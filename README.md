# Codex 上下文窗口配置辅助脚本

根据本地 `models_cache.json` 生成调整过上下文窗口数值的模型目录文件，便于进行 Codex 本地配置实验。

## 依赖

- Bash
- `jq`
- 本地已有的 `models_cache.json`，其中 `models` 为数组，每个模型的 `context_window` 和 `max_context_window` 均为数字

## 使用方法

在本仓库目录直接运行脚本，传入目标上下文窗口大小：

```bash
bash generate-model-catalog.sh 400000
```

脚本按以下规则定位 Codex 配置目录：

1. 环境变量 `CODEX_HOME` 非空时使用该目录。
2. 否则使用当前用户主目录下的 `~/.codex/`。

默认从 `~/.codex/models_cache.json` 读取缓存，并生成 `~/.codex/model-catalog-400k.json`。脚本可以放在任意位置，输入缓存和生成结果均位于选定的 Codex 配置目录。

如果使用自定义目录，可通过环境变量指定，建议使用绝对路径：

```bash
CODEX_HOME="/path/to/codex" bash generate-model-catalog.sh 400000
```

选定目录必须已经存在，并包含 `models_cache.json`；缺少目录或缓存时，错误消息会列出对应路径。相对路径形式的 `CODEX_HOME` 按运行命令时的当前目录解析。

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
