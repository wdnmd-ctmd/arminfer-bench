# AGENTS.md

本文件给参赛 AI/协作者提供项目导航。**事实来源(Source of Truth)为 `.trae/specs/bootstrap-arm-infer-bench/spec.md`**;本文件与其保持一致,如有冲突以 spec 为准。

## 项目目标

用 KleidiAI 微内核重构 llama.cpp,做一套开源、纯 GitHub Actions Arm64 runner(`ubuntu-24.04-arm`)可复现的「Arm64 LLM 推理优化 + 一键基准」工具包,产出多档构建 × 多量化的消融对照数据 + 静态看板 + 可复用优化配方。

**参赛背景**:Arm Create: AI Optimization Challenge(Cloud AI 赛道,截止 2026-08-15)。算力只用 GitHub Actions 免费 Arm64 Runner,不依赖本地硬件。

## 本轮范围

**W1 = T0 + T1**。T0 仓库脚手架(本批);T1 基线 CI(bench.yml,arm64,naive 档冒烟)。事实来源:`.trae/specs/bootstrap-arm-infer-bench/spec.md`。T2–T6 为后续阶段,本轮不执行。

## 目录结构

```
/LICENSE                      Apache-2.0 全文(版权行 Copyright 2026 wdnmd-ctmd)
/README.md                    三段式:Overview / Functionality / Setup
/AGENTS.md                    项目目标、目录、Arm64 构建运行验证说明、五档定义
/.gitignore                   忽略 third_party/llama.cpp 与其 build/ 等
/.gitattributes               强制 LF 行尾(shell/yml 跨平台)
/scripts/run_bench.sh         一键:构建→下载模型→基准→输出 JSON  (T4)
/scripts/build_variant.sh     按档位参数化构建 llama.cpp            (T2)
/scripts/fetch_llamacpp.sh    浅拉固定 commit 的 llama.cpp 到 third_party/ (T1 本轮)
/.github/workflows/bench.yml  arm64 CI 工作流(concurrency + 路径限定 + action 固定版本) (T1 本轮)
/results/                     基准 JSON 输出(含 .gitkeep)
/dashboard/                   静态看板占位(含 .gitkeep)          (T4)
/third_party/llama.cpp        运行时浅拉(gitignored),其下 build/ 也 gitignored
```

## 五档构建定义表

逐因子拆开 i8mm 指令、llama.cpp 自带 ARM 重排、KleidiAI 微内核三个优化的净贡献:

| 档位 | ARM arch | 重排(repack) | KleidiAI | 含义 |
|------|----------|--------------|----------|------|
| naive | armv8-a | OFF | OFF | 真·未优化基线 |
| norepack | armv9-a+dotprod+i8mm+sve2 | OFF | OFF | 只吃 i8mm 指令 |
| repack | 同上 | ON | OFF | llama.cpp 自带 ARM 重排 |
| kleidiai_only | 同上 | OFF | ON | 纯 KleidiAI(隔离) |
| kleidiai | 同上 | ON | ON | 两者全开(真实部署) |

> 注:R3 完整矩阵在 T2 实现;本轮 T1 仅落地 `naive` 档作为冒烟基线。

## 构建关键参数

- `-DGGML_NATIVE=OFF`
- `-DGGML_CPU_ARM_ARCH=armv9-a+dotprod+i8mm+sve2`(KleidiAI cmake 靠字面 `+dotprod` token 选内核,**必须显式补 `+dotprod`**)
- `-DGGML_CPU_KLEIDIAI=ON/OFF`
- `-DGGML_CPU_REPACK=ON/OFF`(默认 ON;naive 档 OFF,见下节)
- 用 `ccache` 跨档共享 llama/ggml 核心目标,编译时间砍半。

> 本轮 T1 naive 档:`-DGGML_NATIVE=OFF -DGGML_CPU_ARM_ARCH=armv8-a -DGGML_CPU_KLEIDIAI=OFF -DGGML_CPU_REPACK=OFF`,作为真·未优化基线。

## repack 真实关闭机制(T1.6 已核对)

**pinned commit**:`fabde3bf5136940eb03821aa2490e2360093965b`(release b9728,2026-06-19)。事实来源见 spec.md「naive 档"关闭自带 repack"」节。

已在该 commit 上核对:repack 由 cmake option `GGML_CPU_REPACK` 控制(定义于 `ggml/CMakeLists.txt:120`),描述 "ggml: use runtime weight conversion of Q4_0 to Q4_X_X",**默认 ON**。

- **关闭方式**:`-DGGML_CPU_REPACK=OFF`(纯 build-time cmake flag,**无运行时 env var 覆盖**)。
- **源码归属**:`repack.cpp`/`repack.h` 在 `ggml-cpu/` 顶层 + ARM 专属 `ggml-cpu/arch/arm/repack.cpp`;运行时门控 Q4_0→Q4_X_X 在线重排。
- **naive 档构建参数**:`-DGGML_NATIVE=OFF -DGGML_CPU_ARM_ARCH=armv8-a -DGGML_CPU_KLEIDIAI=OFF -DGGML_CPU_REPACK=OFF`。
- **诚实标注**:`repack.cpp` 仍被编译进二进制(单档构建 `GGML_CPU_SOURCES` 无条件包含),`GGML_CPU_REPACK=OFF` 时运行时不做重排;naive 仍含 NEON。
- 候选 `GGML_CPU_AARCH64` **不存在**;运行时 env var / 版本默认行为均非关闭途径。

## naive 诚实标注

`naive` 为 **armv8-a 基础基线**,构建参数为 `-DGGML_NATIVE=OFF -DGGML_CPU_ARM_ARCH=armv8-a -DGGML_CPU_KLEIDIAI=OFF -DGGML_CPU_REPACK=OFF`。

**naive 仍含 NEON,无法完全关闭**。naive 的目标是「尽可能未优化的 armv8-a NEON 基础基线」,而非「零 SIMD 纯标量」。所谓"未优化"指不开 i8mm、不开 KleidiAI 微内核、关闭 ARM 重排;NEON 本身是 armv8-a ABI 的一部分,编译器与 llama.cpp 默认即会产出 NEON 指令,不具备干净的 build-time 关闭开关。

## Arm64 构建运行验证说明

### CPU 特性自证

aarch64 读 CPU 特性要解析 `/proc/cpuinfo` 的 **`Features` 字段**(不是 x86 的 `flags`):

- `dotprod` 在其中叫 **`asimddp`**
- `i8mm` 字面即 `i8mm`
- `sve2` 字面即 `sve2`

bench job 启动构建/基准前,日志中必须打印解析出的 `Features` 字段,并明确标注 `asimddp`/`i8mm`/`sve2` 是否存在。

### TTFT 取数

TTFT 用 `llama-bench` 的 prompt-processing(prefill)吞吐推算,**不要用 `llama-cli` 的 `--timing`**(部分 commit 上无效且交互模式会挂死)。公式:`ttft_ms = pp_n / prefill_tok_s × 1000`,`pp_n = 512`(即 `-p` 值)。

### GGUF 文件名与分片

- **HF 文件名全小写**:HuggingFace 上 GGUF 文件名全小写(形如 `qwen2.5-1.5b-instruct-q4_k_m.gguf`),下载路径勿拼错大小写;按仓库真实文件列表动态发现。
- **7B 分片动态发现**:7B 的 GGUF 在 HF 上可能分片,按仓库真实文件列表动态发现并全部下载,首片交给 llama.cpp 自动加载多片。
- **`model_size_mb` 累加分片**:分片场景要累加所有分片,不能只统计首片。
- **`actions/cache` 缓存 GGUF**:避免每次重下。

### 同机对照原则(NF4,项目级不变量)

对照结论的可信度建立在「同机」之上,从 W1 第一条数据起即遵守:

- **同 job 同 runner**:同一组对照(naive vs 各优化档)必须在同一个 GitHub Actions job、同一台 runner 内连续跑完。不同 job/不同 runner 的绝对数字**不可直接对比**,仅作参考。
- **结论只用同机比值**:作品的优化结论只采用「同机 speedup ratio」(如 `decode_tok_s_kleidiai / decode_tok_s_naive`),绝对值仅作参考。
- **runner CPU 型号记录**:`cpu_model` 解析自 `/proc/cpuinfo` 的 `CPU part`/`CPU implementer` 或 `lscpu`(如 Neoverse-N2 / Cobalt-100),写入 JSON 的 `cpu_model`。
- **W1 起即记录**:W1 虽只有 naive 单档,`cpu_model` 也必须从第一条数据开始记录,为后续同机比值提供基准锚点。

## 结果 JSON schema

终版 schema(与 spec 一致,以此为准):

```
variant, quant, model, model_revision, model_sha256, model_size_mb,
bench_args, pp_n, tg_n, reps,
prefill_tok_s, prefill_stddev, decode_tok_s, decode_stddev,
ttft_ms, ttft_formula, peak_mem_mb, peak_mem_source,
n_threads, cpu_model, cpu_features, compiler, llama_commit, runner_os, timestamp
```

字段来源说明:

- `model_revision` / `model_sha256`:GGUF 按 `resolve/<REV>/<file>` 钉死的 revision 与下载后校验的 sha256。
- `pp_n` / `tg_n` / `reps` / `n_threads`:即 `-p 512` / `-n 128` / `-r 5` / `-t 4`,冗余写入便于校验。
- `prefill_stddev` / `decode_stddev`:来自 `llama-bench -r 5` 重复结果;stddev/avg > 10% 在日志告警。
- `ttft_ms` / `ttft_formula`:由 `pp_n / prefill_tok_s × 1000` 推算,公式字符串一并落盘。
- `peak_mem_mb` / `peak_mem_source`:峰值内存与取数来源;主方法 `/usr/bin/time -v` 的 `Maximum resident set size`,`peak_mem_source` 默认 `time_v_maxrss`。
- `cpu_model`:runner 实际 CPU 型号(`/proc/cpuinfo` 的 `CPU part`/`CPU implementer` 或 `lscpu`)。
- `cpu_features`:`/proc/cpuinfo` 的 `Features` 字段(含 `asimddp`/`i8mm`/`sve2` 标注)。
- `compiler`:`cc --version` / `clang --version` 首行。
- `runner_os`:`lsb_release` 或 `/etc/os-release`。
- `llama_commit`:`fetch_llamacpp.sh` 回校的 SHA。

## 后续阶段

- **T2**:五档构建矩阵(`build_variant.sh` + 激活探针自证 KleidiAI/重排是否接管)——实现完整 R3,严格遵守 NF4 同机对照(同 job/同 runner 连续跑完,结论只用 speedup ratio)。
- **T3**:多量化对照(Q4_0/Q4_K_M/Q8_0 + perplexity 质量列)——实现 R4。
- **T4**:一键基准 `run_bench.sh` + 静态看板——实现 R5。
- **T5**:Arm Performix 接入 + 迁移模板 + 优化配方——实现 R6/R7。
- **T6**:三段式 README 终稿 + ≤3min 演示视频脚本——实现 R8 终稿。