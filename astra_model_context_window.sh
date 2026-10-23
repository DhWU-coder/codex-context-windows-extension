#!/usr/bin/env bash

set -euo pipefail

readonly astra_model="gpt-6-astra"
readonly default_context_window="272000"
readonly default_auto_compact_token_limit="258400"
readonly compact_percent="95"
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

readonly astra_context_window="$1"

if [[ ! "${astra_context_window}" =~ ^[1-9][0-9]*$ ]]; then
  fail "context_window 必须是不带前导零的正整数"
fi

# 沿用通用脚本的安全范围，保证最大窗口和压缩阈值的整数计算准确。
if is_greater_than_safe_limit "${astra_context_window}"; then
  fail "context_window 不能大于 ${maximum_safe_target}"
fi

command -v jq >/dev/null 2>&1 || fail "未找到 jq，请先安装 jq"

# 优先使用自定义 Codex 目录，未设置时使用当前用户的 ~/.codex。
[[ -n "${CODEX_HOME:-}" || -n "${HOME:-}" ]] \
  || fail "未设置 HOME，请通过 CODEX_HOME 指定 Codex 配置目录"
readonly codex_directory="${CODEX_HOME:-${HOME}/.codex}"
[[ -d "${codex_directory}" ]] || fail "找不到 Codex 配置目录：${codex_directory}"

# 使用整数运算向下取整，避免大窗口下浮点乘法影响压缩阈值。
readonly astra_auto_compact_token_limit=$((astra_context_window * compact_percent / 100))
readonly context_window_in_thousands=$((astra_context_window / 1000))
readonly input_file="${codex_directory}/models_cache.json"
readonly output_file="${codex_directory}/model-catalog-astra-${context_window_in_thousands}k.json"
[[ -f "${input_file}" ]] || fail "找不到输入文件：${input_file}"

# 本次运行只读取一次缓存，后续校验和生成均使用同一份内容。
input_snapshot="$(< "${input_file}")" || fail "读取输入文件失败：${input_file}"
readonly input_snapshot

# 校验模型标识和窗口字段，确保能按模型准确设置目录。
if ! jq -e '
  type == "object"
  and (.models | type == "array")
  and all(.models[];
    type == "object"
    and (.slug | type == "string")
    and (.context_window | type == "number")
    and (.max_context_window | type == "number")
  )
' <<< "${input_snapshot}" >/dev/null; then
  fail "输入文件结构无效：models 必须是数组，且每个模型必须包含字符串 slug 和数字上下文字段"
fi

if ! jq -e --arg astra_model "${astra_model}" '
  any(.models[]; .slug == $astra_model)
' <<< "${input_snapshot}" >/dev/null; then
  available_models="$(jq -r '[.models[].slug] | join(", ")' <<< "${input_snapshot}")"
  fail "输入缓存中未找到模型：${astra_model}
缓存文件：${input_file}
实际模型列表：${available_models:-（空）}"
fi

temporary_file="$(mktemp "${output_file}.tmp.XXXXXX")" \
  || fail "无法创建临时输出文件"

cleanup() {
  # 失败时仅删除临时输出，保留已有目录文件。
  if [[ -n "${temporary_file:-}" && -f "${temporary_file}" ]]; then
    rm -f "${temporary_file}"
  fi
}

trap cleanup EXIT
trap 'exit 1' HUP INT TERM

# Astra 使用参数及计算出的阈值，其他模型固定为 272000 和 258400。
if ! jq \
  --arg astra_model "${astra_model}" \
  --argjson astra_context_window "${astra_context_window}" \
  --argjson astra_auto_compact_token_limit "${astra_auto_compact_token_limit}" \
  --argjson default_context_window "${default_context_window}" \
  --argjson default_auto_compact_token_limit "${default_auto_compact_token_limit}" '
  .models |= map(
    (
      if .slug == $astra_model
      then .context_window = $astra_context_window
        | .auto_compact_token_limit = $astra_auto_compact_token_limit
      else .context_window = $default_context_window
        | .auto_compact_token_limit = $default_auto_compact_token_limit
      end
    )
    | .max_context_window = ([.max_context_window, (.context_window * 2)] | max)
  )
' <<< "${input_snapshot}" > "${temporary_file}"; then
  fail "生成模型目录失败"
fi

# 在同一目录内原子替换目标文件，保留源缓存和个人配置。
mv -f "${temporary_file}" "${output_file}"
temporary_file=""
trap - EXIT HUP INT TERM

printf '已生成：%s\n' "${output_file}"
