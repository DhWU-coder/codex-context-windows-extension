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

## Astra 350k 专用目录

运行专用脚本，无需传入参数：

```bash
bash astra_model_context_window_350k.sh
```

脚本沿用相同的目录定位规则，从 `CODEX_HOME` 或默认的 `~/.codex/` 读取 `models_cache.json`，生成 `model-catalog-astra-350k.json`。

| 模型 | `context_window` | `auto_compact_token_limit` |
| --- | ---: | ---: |
| `gpt-6-astra`（精确匹配 `slug`） | 350000 | 332500 |
| 其他模型 | 272000 | 258400 |

窗口值和压缩阈值均精确覆盖原值，压缩阈值为窗口值的 95%。`max_context_window` 延续通用脚本的规则：至少为对应窗口值的两倍，原值更大时保留。其余字段和模型顺序保持原样。缓存中必须存在 `gpt-6-astra`，缺少时明确报错。

脚本仅生成 JSON，保留源缓存和 `config.toml`。生成成功后，在 `config.toml` 顶层手动指定实际输出文件的绝对路径，例如：

```toml
model_catalog_json = "/absolute/path/to/model-catalog-astra-350k.json"
```

如果已有顶层 `model_context_window` 或 `model_auto_compact_token_limit`，需自行移除或注释这些全局覆盖项，让各模型使用目录中的值。修改目录引用后重启 Codex。目录加载方式参见 [Codex 官方说明](https://learn.chatgpt.com/docs/enterprise/roll-out-a-gateway#distribute-a-local-catalog)。

## 自定义 Astra 上下文窗口

使用可传参的专用脚本设置 Astra 的窗口大小：

```bash
bash astra_model_context_window.sh 350000
```

- `gpt-6-astra`：`context_window` 精确设置为参数值，`auto_compact_token_limit` 使用整数运算计算 `floor(参数 × 95 / 100)`。
- 其他模型：固定为 `context_window = 272000`、`auto_compact_token_limit = 258400`。

输出文件名为 `model-catalog-astra-<参数/1000>k.json`，其中除以 `1000` 的结果向下取整；实际窗口值保留完整参数。例如，`350000` 和 `350001` 都生成 `model-catalog-astra-350k.json`，但各自的 Astra 窗口值分别为 `350000` 和 `350001`，压缩阈值均为 `332500`。同名文件会被覆盖，传入 `350000` 时与固定 350k 脚本使用相同的输出路径。

参数要求与通用脚本一致：必须是不带前导零的正整数，最大为 `4503599627370495`。目录定位、最大窗口处理、字段保留和配置引用方式与固定 350k 脚本一致。

## 仓库文件

- `generate-model-catalog.sh`：模型目录生成脚本。
- `astra_model_context_window_350k.sh`：生成 Astra 350k、其他模型 272k 的专用目录，并设置对应的自动压缩阈值。
- `astra_model_context_window.sh`：通过参数设置 Astra 窗口及向下取整的 95% 压缩阈值，其他模型保持 272k 和 258400。
- `.gitignore`：忽略编辑器文件、虚拟环境、个人配置、模型缓存及生成结果。
- `.gitattributes`：保证 Bash 脚本使用 LF 换行。

本地缓存、认证信息与生成结果不应提交到仓库。
