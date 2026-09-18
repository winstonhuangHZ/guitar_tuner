# Guitar Tuner

用 Swift + SwiftUI 写的吉他调音器，一套代码同时支持 **iOS 17+** 和 **macOS 14+**。

- **音频采集**：`AVAudioEngine` + `AVAudioInputNode`，实时 tap，无锁环形缓冲，DSP 全部在后台队列跑。
- **输入模式**：`Microphone`（70 Hz–1 kHz 带通）与 `Pickup`（400 Hz 低通），滤波参数会跟着调弦预设自动放宽，不会把低音弦或尤克里里高音弦滤掉。
- **音高识别**：NSDF（归一化平方差）+ MPM 峰值挑选的自相关算法，抛物线插值到亚采样精度，对"二次谐波比基频还强"的拾音器信号不会误判成高八度。
- **抗抖动**：绝对 RMS 门限 + 自适应噪声地板（跟着房间噪声走）+ 中值滤波 + 短时保持。
- **调音辅助**：自动/锁定单弦、迟滞判定、A4 参考音高 415–466 Hz、常用预设（标准/Drop D/E♭/Open G/Open D/DADGAD/4 弦与 5 弦贝斯/尤克里里/半音阶）。
- **零第三方依赖**。

## 快速开始

macOS 直接跑（需要 macOS 14+ 与 Swift 6 工具链）：

```bash
swift run GuitarTunerMac
```

打成真正的 `.app`（macOS 才会用 App 自己的名字弹麦克风授权，并且授权能稳定保留）：

```bash
./Scripts/make-macos-app.sh
open build/GuitarTuner.app
```

跑 DSP 自检（162 项，覆盖音名/音分换算、预设、门限、检测精度、稳定器、环形缓冲、目标匹配、滤波配置）：

```bash
swift run GuitarTunerChecks
```

> 为什么不是 `swift test`：XCTest 与 swift-testing 只随**完整 Xcode** 提供，本机目前只有 Command Line Tools（`xcodebuild` 指向 `/Library/Developer/CommandLineTools`），`swift test` 无法编译。所以验证套件写成了可执行的纯 Swift 检查程序，CLT 环境下也能真跑。

## iOS

iOS 需要一个 App target，SwiftPM 本身不能产出 iOS 应用包。两种方式：

**手动（推荐，三步）**

1. Xcode → File → New → Project → iOS App，Interface 选 SwiftUI，Language 选 Swift，删掉自动生成的 `ContentView.swift` 与 `XxxApp.swift`。
2. File → Add Package Dependencies… → Add Local… → 选中本仓库根目录，把 `GuitarTunerUI`（会带上 `GuitarTunerKit`）加到 target。
3. 把 `Platforms/iOS/GuitarTuneriOSApp.swift` 拖进 target，并在 target 的 Info 里加一条 `NSMicrophoneUsageDescription`（可直接照抄 `Platforms/iOS/Info.plist`）。

**XcodeGen**

```bash
brew install xcodegen
cd Platforms/iOS && xcodegen generate && open GuitarTuner.xcodeproj
```

## 目录结构

```
Sources/
  GuitarTunerKit/            纯逻辑：DSP + 音频，可单独测试
    Analysis/                NoteMath · TuningPreset · PitchDetector · PitchStabilizer
                             SignalMetrics · TunerEvaluator · TunerReading
    Audio/                   AudioInputMode/AnalysisProfile · AudioSampleRingBuffer
                             AnalysisPipeline · TunerController · MicrophonePermission
  GuitarTunerUI/             iOS/macOS 共用 SwiftUI 界面
  GuitarTunerMac/            macOS App 入口（swift run 可直接跑）
  GuitarTunerChecks/         可执行的验证套件
Platforms/
  iOS/                       iOS App 入口 + Info.plist + 可选 project.yml
  macOS/                     打包用 Info.plist
Scripts/make-macos-app.sh    生成 .app bundle
```

## 信号链

```
AVAudioEngine.inputNode → AVAudioUnitEQ（高通 + 低通）→ tap(2048 帧)
                                                            ↓ 无锁环形缓冲（音频线程只 try-lock）
                                        20 Hz 分析队列 ←────┘
                                              ↓
        RMS / 自适应噪声门限 → NSDF(MPM) → 中值+保持 → 目标弦匹配 → @Observable
                                              ↓
                                     SwiftUI（指针 / 电平 / 稳定性曲线）
```

- 输入节点从不接到扬声器（`mainMixerNode.outputVolume = 0`），不会有啸叫回路；tap 装在 EQ 之后的节点上，所以送到识别算法的是**滤波后**的信号。
- 采样率、通道数、耳机插拔等变化由 `AVAudioEngineConfigurationChange` 监听后自动重建音频图。

## DSP 细节

### 输入模式与滤波器

| 模式 | 高通 | 低通 | 目的 |
| --- | --- | --- | --- |
| Microphone | 70 Hz | 1 kHz | 滤掉空调、桌面震动、人声等环境噪声 |
| Pickup | 60 Hz | 400 Hz | 压掉过强的高次谐波，让基频在自相关里胜出 |

两档都不是写死的：`AnalysisProfile` 会按当前调弦把参数放到安全位置——低音贝斯 B0（30.9 Hz）的基频不会被高通切掉（高通降到 25 Hz），尤克里里 A4（440 Hz）不会被 400 Hz 低通吃掉（低通抬到 550 Hz）。识别搜索范围同样随预设调整（例如标准调弦 55–1318 Hz）。

### 能量门限

门限 = `max(噪声地板 × 3, 下限)`。噪声地板用非对称速率自适应：门限关闭时快速跟随房间噪声（attack 0.05），有信号时极慢回落（release 0.0008），所以持续音期间门限不会抖动。当前门限会画在电平条上，玩家能直接看出"信号是不是被门限挡住了"。

### 音高检测（NSDF + MPM）

对每个延迟 τ 计算归一化平方差：

```
NSDF(τ) = 2 · Σ x[j]·x[j+τ] / Σ (x[j]² + x[j+τ]²)      ∈ [-1, 1]
```

相比原始自相关多了一步能量归一化：峰值高度直接就是"清晰度"，可以用一个统一阈值判断信号是否可信，不会因为音量大小而漂移。

峰值挑选用 McLeod 的 MPM 思路，两个关键点都在代码里：

1. **峰必须是"闭合正区间"的最高点**——两侧都要有负值把它包起来。少了这个约束，噪声在 NSDF 上叠出的涟漪会被误当成周期（开发中正是这条检查抓到了这个 bug）。
2. **不取最高峰**：最高峰常常是真实周期的 2 倍或 3 倍。MPM 取"沿 lag 增大方向，第一个达到最高峰 85% 的峰"。

最后用抛物线插值把峰值位置细化到亚采样级，再换算成频率。

### 稳定器与目标匹配

- 中值滤波（5 帧）去掉孤立跳变；频率跳变超过 250 音分直接清空窗口（换弦时不拖泥带水）。
- 弦衰减到门限以下后保持 0.35 s；"响度够但不够周期"的帧只保持一半时间。
- 自动匹配最近的目标弦，但带 12 音分迟滞，靠近两弦中点时不会来回跳；也可以直接锁定某一根弦。
- 半音阶（Chromatic）模式下目标是最接近的十二平均律音，不限于预设弦。

## 精度与验证

`swift run GuitarTunerChecks` 当前 162 项全绿，关键阈值：

| 检查 | 阈值 |
| --- | --- |
| 标准调弦六根弦（正弦） | ≤ 5 音分 |
| 失谐 18 音分的低音 E | ≤ 3 音分 |
| 二次谐波为基频 2.6 倍的信号 | ≤ 15 音分，且不得报高八度 |
| 明亮音色（高次谐波很强） | ≤ 10 音分 |
| 白噪声 / 静音 / 门限以下噪声 | 必须返回无音高 |
| 门限与自适应噪声地板 | 单调性、边界、回落方向 |
| 环形缓冲 | 顺序、环绕、跨边界读取 |

## 已知限制

- 只在 macOS 上编译与运行验证过。iOS 目标本机没有 Xcode 与 iOS SDK，无法编译，也无法在真机验证麦克风链路——`Platforms/iOS` 下的代码用的是标准 API（`AVAudioSession(.record, .measurement)`、`AVAudioApplication.requestRecordPermission`），但请以真机结果为准。
- 单音识别：同时拨多根弦（和弦）时不适用，需要 FFT/多基频估计。
- 没有录音、没有联网，音频只在内存里分析。

## 受限环境下构建

如果 `swift build` 报 `sandbox-exec: sandbox_apply: Operation not permitted`（外层沙箱/CI 里 SwiftPM 无法再套一层沙箱），加：

```bash
swift build --disable-sandbox
# 或者给脚本设：GUITAR_TUNER_DISABLE_SWIFTPM_SANDBOX=1 ./Scripts/make-macos-app.sh
```

如果报 clang module cache 不可写：

```bash
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/guitar-tuner-module-cache"
```
