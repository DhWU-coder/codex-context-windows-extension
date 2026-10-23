#!/usr/bin/env bash

set -euo pipefail

readonly astra_model="gpt-6-astra"
readonly astra_context_window="350000"
readonly default_context_window="272000"
readonly compact_percent="95"

print_usage() {
  printf '用法：bash %s（无需参数）\n' "$0" >&2
}

fail() {
  printf '错误：%s\n' "$1" >&2
  exit 1
}

if [[ "$#" -ne 0 ]]; then
  print_usage
  exit 2
fi

command -v jq >/dev/null 2>&1 || fail "未找到 jq，请先安装 jq"

# 沿用通用脚本的目录规则，脚本可以在仓库中直接运行。
[[ -n "${CODEX_HOME:-}" || -n "${HOME:-}" ]] \
  || fail "未设置 HOME，请通过 CODEX_HOME 指定 Codex 配置目录"
readonly codex_directory="${CODEX_HOME:-${HOME}/.codex}"
[[ -d "${codex_directory}" ]] || fail "找不到 Codex 配置目录：${codex_directory}"

readonly input_file="${codex_directory}/models_cache.json"
readonly output_file="${codex_directory}/model-catalog-astra-350k.json"
[[ -f "${input_file}" ]] || fail "找不到输入文件：${input_file}"

# 本次运行只读取一次缓存，后续校验和生成均使用同一份内容。
input_snapshot="$(< "${input_file}")" || fail "读取输入文件失败：${input_file}"
readonly input_snapshot

# 先校验模型标识和窗口字段，避免生成无法按模型区分的目录。
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

# 精确设置窗口和百分之九十五的压缩阈值，最大窗口沿用通用脚本的保留规则。
if ! jq \
  --arg astra_model "${astra_model}" \
  --argjson astra_context_window "${astra_context_window}" \
  --argjson default_context_window "${default_context_window}" \
  --argjson compact_percent "${compact_percent}" '
  .models |= map(
    .context_window = (
      if .slug == $astra_model
      then $astra_context_window
      else $default_context_window
      end
    )
    | .auto_compact_token_limit = (.context_window * $compact_percent / 100 | floor)
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
