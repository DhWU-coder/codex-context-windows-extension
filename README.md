# Codex 上下文窗口配置辅助脚本

根据本地 `models_cache.json` 生成调整过上下文窗口数值的模型目录文件，便于进行 Codex 本地配置实验。

## 依赖

- Bash
- `jq`
- 本地已有的 `models_cache.json`，其中 `models` 为数组，每个模型的 `context_window` 和 `max_context_window` 均为数字

## 使用方法

将 `generate-model-catalog.sh` 放在 `models_cache.json` 所在目录，然后传入目标上下文窗口大小：

```bash
bash generate-model-catalog.sh 400000
```

如果缓存位于 `~/.codex/`，可在本仓库目录执行：

```bash
cp generate-model-catalog.sh ~/.codex/generate-model-catalog.sh
bash ~/.codex/generate-model-catalog.sh 400000
```

此时会生成 `~/.codex/model-catalog-400k.json`。输入路径与输出路径始终以脚本所在目录为准，与运行命令时的当前目录无关。

## 生成规则

对 `models` 数组中的所有模型：

- `context_window` 至少为传入值。
- `max_context_window` 至少为传入值的两倍。
- 原有字段值更大时保留原值，其他字段保持原样。

脚本保留源缓存文件，先写入临时文件，再替换目标文件；同名目标文件会被覆盖。文件名中的 `k` 值由传入值除以 `1000` 后向下取整，因此不同参数可能生成相同文件名。

参数必须是不带前导零的正整数，最大为 `4503599627370495`。缺少参数或参数数量错误时退出码为 `2`；输入无效、缺少依赖或生成失败时以非零状态退出。

生成目录文件后，还需根据所用 Codex 版本完成相应的模型目录配置。调整目录中的数值本身不会改变模型服务端支持的上下文长度。

## 仓库文件

- `generate-model-catalog.sh`：模型目录生成脚本。
- `.gitignore`：忽略编辑器文件、虚拟环境、个人配置、模型缓存及生成结果。
- `.gitattributes`：保证 Bash 脚本使用 LF 换行。

本地缓存、认证信息与生成结果不应提交到仓库。
