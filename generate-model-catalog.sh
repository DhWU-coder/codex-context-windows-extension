#!/usr/bin/env bash

set -euo pipefail

readonly maximum_safe_target="4503599627370495"

print_usage() {
  printf '用法：bash %s <context_window>\n' "$0" >&2
}

fail() {
  printf '错误：%s\n' "$1" >&2
  exit 1
}

is_greater_than_safe_limit() {
  local value="$1"

  if (( ${#value} > ${#maximum_safe_target} )); then
    return 0
  fi

  if (( ${#value} < ${#maximum_safe_target} )); then
    return 1
  fi

  [[ "${value}" > "${maximum_safe_target}" ]]
}

if [[ "$#" -ne 1 ]]; then
  print_usage
  exit 2
fi

readonly target_context_window="$1"

if [[ ! "${target_context_window}" =~ ^[1-9][0-9]*$ ]]; then
  fail "context_window 必须是不带前导零的正整数"
fi

# 限制在 jq 能精确表示的整数范围内，同时保证乘以 2 后仍是安全整数。
if is_greater_than_safe_limit "${target_context_window}"; then
  fail "context_window 不能大于 ${maximum_safe_target}"
fi

command -v jq >/dev/null 2>&1 || fail "未找到 jq，请先安装 jq"

# 优先使用自定义 Codex 目录，未设置时使用当前用户的 ~/.codex。
[[ -n "${CODEX_HOME:-}" || -n "${HOME:-}" ]] \
  || fail "未设置 HOME，请通过 CODEX_HOME 指定 Codex 配置目录"
readonly codex_directory="${CODEX_HOME:-${HOME}/.codex}"
[[ -d "${codex_directory}" ]] || fail "找不到 Codex 配置目录：${codex_directory}"

# 输入缓存和生成结果均放在 Codex 配置目录，与脚本位置无关。
readonly input_file="${codex_directory}/models_cache.json"
[[ -f "${input_file}" ]] || fail "找不到输入文件：${input_file}"

readonly target_max_context_window=$((target_context_window * 2))
readonly context_window_in_thousands=$((target_context_window / 1000))
readonly output_file="${codex_directory}/model-catalog-${context_window_in_thousands}k.json"

# 在更新前验证输入结构，避免字符串等异常值参与数字比较。
if ! jq -e '
  type == "object"
  and (.models | type == "array")
  and all(.models[];
    type == "object"
    and (.context_window | type == "number")
    and (.max_context_window | type == "number")
  )
' "${input_file}" >/dev/null; then
  fail "输入文件结构无效：models 必须是数组，且每个模型的上下文字段必须是数字"
fi

temporary_file="$(mktemp "${output_file}.tmp.XXXXXX")" \
  || fail "无法创建临时输出文件"

cleanup() {
  # 仅清理尚未完成替换的临时文件，不触碰已有目标文件。
  if [[ -n "${temporary_file:-}" && -f "${temporary_file}" ]]; then
    rm -f "${temporary_file}"
  fi
}

trap cleanup EXIT
trap 'exit 1' HUP INT TERM

if ! jq \
  --argjson target_context_window "${target_context_window}" \
  --argjson target_max_context_window "${target_max_context_window}" '
  .models |= map(
    .context_window = (
      if .context_window < $target_context_window
      then $target_context_window
      else .context_window
      end
    )
    | .max_context_window = (
      if .max_context_window < $target_max_context_window
      then $target_max_context_window
      else .max_context_window
      end
    )
  )
' "${input_file}" > "${temporary_file}"; then
  fail "生成模型目录失败"
fi

# 同一目录内移动可原子替换目标文件，已存在时直接覆盖。
mv -f "${temporary_file}" "${output_file}"
temporary_file=""
trap - EXIT HUP INT TERM

printf '已生成：%s\n' "${output_file}"
