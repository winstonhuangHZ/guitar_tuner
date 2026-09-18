# Guitar Tuner

用 Swift + SwiftUI 写的吉他调音器，一套代码同时支持 **iOS 17+** 和 **macOS 14+**。

- **音频采集**：`AVAudioEngine` + `AVAudioInputNode`，实时 tap，无锁环形缓冲，DSP 全部在后台队列跑。
- **输入模式**：`Microphone`（70 Hz–1 kHz 带通）与 `Pickup`（400 Hz 低通），滤波参数会跟着调弦预设自动放宽，不会把低音弦或尤克里里高音弦滤掉。
- **音高识别**：NSDF（归一化平方差）+ MPM 峰值挑选的自相关算法，抛物线插值到亚采样精度，对"二次谐波比基频还强"的拾音器信号不会误判成高八度。
- **抗抖动**：绝对 RMS 门限 + 自适应噪声地板（跟着房间噪声走）+ 中值滤波 + 短时保持。
- **34 组调音预设 + 半音阶**：Drop D 系列、开放调弦、DADGAD、巴里通、7/8 弦、贝斯、尤克里里、曼陀铃等（见下）。
- **频谱视图**：vDSP FFT，对数频率轴，并标出当前基频与泛音——输入滤波器到底做了什么，一眼就能看出来。
- **调音辅助**：自动/锁定单弦、迟滞判定、A4 参考音高 415–466 Hz、稳定性曲线。
- **浅色界面**：白底，白天放在谱架上也看得清（界面固定 light，不跟随系统深色）。
- **应用图标**：按 App 自己的仪表盘设计用代码画出来（蓝底 / 刻度弧 / 指针 / 绿色准音区），macOS `.icns` 与 iOS AppIcon 由同一套脚本生成。
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

跑 DSP 自检（419 项，覆盖音名/音分换算、35 组预设、门限、检测精度、稳定器、环形缓冲、目标匹配、滤波配置、FFT 频谱）：

```bash
swift run GuitarTunerChecks
```

> 为什么不是 `swift test`：XCTest 与 swift-testing 只随**完整 Xcode** 提供，本机目前只有 Command Line Tools（`xcodebuild` 指向 `/Library/Developer/CommandLineTools`），`swift test` 无法编译。所以验证套件写成了可执行的纯 Swift 检查程序，CLT 环境下也能真跑。

## 调音预设

| 分类 | 预设 |
| --- | --- |
| 通用 | Chromatic（半音阶，自动跟随最近的十二平均律音） |
| 吉他（6 弦） | Standard E · Drop D · Double Drop D · Drop C♯ · Drop C · Drop B · Drop A · Open D · Open G · Open E · Open A · Open C · DADGAD · DADDAD · All Fourths · Nashville（high-strung）· E♭ Standard（降半音）· D Standard（降全音）· C Standard · Baritone（B 标准） |
| 扩展音域 | 7 弦 B Standard · 7 弦 Drop A · 8 弦 F♯ Standard |
| 贝斯 | 4 弦 · Drop D · 5 弦 · 6 弦 |
| 尤克里里 | C（re-entrant）· Low G · Baritone（DGBE） |
| 其他 | Mandolin（GDAE）· 5 弦班卓（Open G）· Lap Steel C6 · Tenor Guitar（CGDA） |

每根弦都带位置标签（例如 `E2 · 6th string`），可以自动匹配，也可以锁定某根弦单独调。频率范围按实际目标频率计算，不依赖排列顺序——尤克里里的 G 弦比 C 弦高，班卓的 5 弦是最高音的 drone 弦，都不会算错。

## App 图标

图标不是一张静态图片，而是由脚本按 App 自己的仪表盘设计画出来的（蓝底、刻度弧、白色指针、绿色准音区）：

```bash
swift Scripts/make-app-icons.swift    # 重新生成（改颜色/几何后重跑即可）
swift Scripts/verify-app-icon.swift   # 取样校验：透明留白、指针、准音区、icns 结构、32 px 可读性
```

生成物：

| 路径 | 用途 |
| --- | --- |
| `Resources/AppIcon.icns` | macOS 图标，`Scripts/make-macos-app.sh` 会复制进 `GuitarTuner.app/Contents/Resources/` |
| `Resources/AppIcon.iconset/` | 中间产物（16–1024 px），方便手动微调或交给设计师 |
| `Platforms/iOS/Assets.xcassets/AppIcon.appiconset/` | iOS 的 1024 px 图标（不带 alpha，iOS 不接受透明通道） |

两点注意：Dock 里显示图标的前提是从 `.app` 启动——`swift run` 的裸可执行文件没有 bundle，用的是终端的图标；另外 macOS 会缓存图标，换图后如果还是旧的，把 app 挪一下或者 `killall Dock`。

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
Resources/AppIcon.icns       生成的 macOS 图标（.iconset 为中间产物）
Scripts/make-macos-app.sh    生成 .app bundle
Scripts/make-app-icons.swift 生成两端的应用图标
Scripts/verify-app-icon.swift 图标取样校验
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

`swift run GuitarTunerChecks` 当前 419 项全绿，关键阈值：

| 检查 | 阈值 |
| --- | --- |
| 标准调弦六根弦（正弦） | ≤ 5 音分 |
| 失谐 18 音分的低音 E | ≤ 3 音分 |
| 二次谐波为基频 2.6 倍的信号 | ≤ 15 音分，且不得报高八度 |
| 明亮音色（高次谐波很强） | ≤ 10 音分 |
| 白噪声 / 静音 / 门限以下噪声 | 必须返回无音高 |
| 门限与自适应噪声地板 | 单调性、边界、回落方向 |
| 环形缓冲 | 顺序、环绕、跨边界读取 |
| 频谱 | 峰值频率精度、对数轴映射、显示范围随调弦收紧（贝斯上看得见 B0） |
| 预设库 | 35 组结构合法性 + 著名调弦逐音核对（Drop C、Open E、DADGAD、Nashville、8 弦 F♯…） |

## 排查

**同意麦克风权限后立刻闪退（每次打开都闪退）**

崩溃报告里是这么一行：

```
closure #1 in TunerController.startEngine()   ← 麦克风 tap 回调
swift_task_isCurrentExecutorWithFlagsImpl -> dispatch_assert_queue_fail
EXC_BAD_INSTRUCTION (SIGILL)
```

原因：在 `@MainActor` 方法里写的闭包，如果传给的是**没有标 `@Sendable` 的 Objective-C block 类型**，就会继承主 actor 隔离；`AVAudioNodeTapBlock` / `AVAudioSourceNodeRenderBlock` 恰好都没标。AVFAudio 在实时线程上调用它时，Swift 6 运行时的主 actor 断言直接 trap。这也是之前一直卡在 "waiting" 时没有暴露出来的原因——引擎压根没启动到那一步。

修法是把这类闭包放到 `nonisolated` 函数里创建（`TunerController.makeTapHandler`）。这条约束现在有守卫脚本，改完音频图跑一下就能发现回归：

```bash
swift build && ./Scripts/verify-audio-callbacks.sh
```

它会反汇编产物，确认所有接收 `AVAudioPCMBuffer` 的回调里都不含主 actor 断言（修复前 tap 的 partial apply thunk 里就有）。

顺带一提：重新构建会改变 ad-hoc 签名，macOS 的麦克风授权是按签名记录的。如果更新后第一次运行拿不到音频，去「系统设置 → 隐私与安全性 → 麦克风」把 Guitar Tuner 的开关关掉再打开；实在不行用 `tccutil reset Microphone com.example.guitartuner` 清掉这条记录重新授权。

想确认音频到底有没有进来，可以用 trace 模式启动：

```bash
GUITAR_TUNER_TRACE=/tmp/tuner.log open -a build/GuitarTuner.app
```

日志里会写明权限状态、引擎采样率、以及分析循环每 100 帧的 RMS / 清晰度 / 测到的频率。

**授权之后一直停在 "waiting"**

启动流程原先会一直 `await` 系统授权回调。macOS 对"归属不到具体 App"的进程（典型是用 `swift run` 直接跑的裸可执行文件）可能永远不回调，界面就卡在等待授权。现在的处理：

1. 授权请求改成轮询 + 8 秒超时：用户一点"允许"，约 200 ms 内就继续；即使超时也不会把 UI 卡住。
2. 不再用授权状态阻断启动：只要不是明确的 `.denied`，就直接尝试启动音频引擎，由引擎给出真实结论。
3. 引擎已运行但 2.5 秒内一帧数据都没到，会显示提示并说明原因（多半就是上面那个归属问题）。
4. 出错横幅带 **Try again** 和 **Open microphone settings**（macOS 会直接跳到"隐私与安全性 → 麦克风"）。

最省事的做法仍然是打成 App bundle，让 macOS 用 "Guitar Tuner" 自己的身份弹授权：

```bash
./Scripts/make-macos-app.sh && open build/GuitarTuner.app
```

**一点声音都没有**：确认系统输入设备选的是你要用的那个麦克风；电平条上的白色竖线是当前 RMS 门限，信号不越过它就不会参与识别（把琴靠近麦克风，或让环境安静一些）。

## 已知限制

- 只在 macOS 上编译与运行验证过。iOS 目标本机没有 Xcode 与 iOS SDK，无法编译，也无法在真机验证麦克风链路——`Platforms/iOS` 下的代码用的是标准 API（`AVAudioSession(.record, .measurement)`、`AVAudioApplication.requestRecordPermission`），但请以真机结果为准。
- 单音识别：同时拨多根弦（和弦）时不适用，需要 FFT/多基频估计。
- 没有录音、没有联网，音频只在内存里分析。
- 界面固定浅色，不跟随系统深色外观。

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
