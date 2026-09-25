# Guitar Tuner

用 Swift + SwiftUI 写的吉他调音器，一套代码同时支持 **iOS 17+** 和 **macOS 14+**。

- **音频采集**：`AVAudioEngine` + `AVAudioInputNode`，实时 tap，无锁环形缓冲，DSP 全部在后台队列跑。
- **输入模式**：`Microphone`（70 Hz–1 kHz 带通）与 `Pickup`（400 Hz 低通），滤波参数会跟着调弦预设自动放宽，不会把低音弦或尤克里里高音弦滤掉。
- **音高识别**：NSDF（归一化平方差）+ MPM 峰值挑选的自相关算法，抛物线插值到亚采样精度，对"二次谐波比基频还强"的拾音器信号不会误判成高八度。
- **抗抖动**：绝对 RMS 门限 + 自适应噪声地板（跟着房间噪声走）+ 中值滤波 + 短时保持。
- **34 组调音预设 + 半音阶**：Drop D 系列、开放调弦、DADGAD、巴里通、7/8 弦、贝斯、尤克里里、曼陀铃等（见下）。
- **和弦模式**：46 个常用指法（开放/横按/七和弦/挂留/加九/强力和弦）+ 和弦识别与质量判定（大三、小三、七、挂留、加九…）+ 逐弦反馈的练习模式。
- **频谱视图**：vDSP FFT，对数频率轴，并标出当前基频与泛音——输入滤波器到底做了什么，一眼就能看出来。
- **调音辅助**：自动/锁定单弦、迟滞判定、A4 参考音高 415–466 Hz、稳定性曲线。
- **浅色界面**：白底，白天放在谱架上也看得清（界面固定 light，不跟随系统深色）。
- **应用图标**：按 App 自己的仪表盘设计用代码画出来（蓝底 / 刻度弧 / 指针 / 绿色准音区），macOS `.icns` 与 iOS AppIcon 由同一套脚本生成。
- **参考音与节拍器**：可播放单弦参考音、整和弦、整段进行的示范；节拍器带 19 组拍号（含 5/8 3+2、7/8 2+2+3、9/8 2+2+2+3、10/8 3+3+2+2 等奇数拍分组）、重音、细分和 Tap tempo。
- **练习与进度**：8 条和弦进行跟练（每条都能换 12 个调）（I–V–vi–IV、12 小节布鲁斯、ii–V–I、卡农…）自动打分，加上每根弦的历史漂移统计。
- **设置会保存**：输入模式、调弦预设、参考音高、容差、capo、输入设备、节拍器参数、练习和弦与进行都会记住。
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

跑自检（6439 项，覆盖音名/音分换算、35 组预设、门限、检测精度、稳定器、环形缓冲、目标匹配、滤波配置、FFT 频谱、46 个和弦指法、和弦质量判定与练习反馈）：

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

门限 = `max(地板 × 3, 下限)`，地板自适应估计环境噪声，规则是**只有接近"最近最低电平"的帧才能把它抬高**：

- 出现更低电平（房间变安静、弦衰减到尾音、两次拨弦之间的空档）→ 地板快速下落。
- 稳定且接近安静基准的电平（房间确实变吵了）→ 地板缓慢上升。
- 拨弦（又响、起音又常常是宽频无音高）→ **不允许抬高地板**。

最后一条是关键。早期版本用的是"没测到音高就跟随当前 RMS"，于是每次拨弦的起音都会把地板顶上去：几十帧就撞到上限，门限随即高于琴声本身，表现就是"刚打开能调，连续拨几下之后就不活跃了"。现在拨弦只能通过衰减尾音把估计值拉**低**，方向始终是对的。当前门限画在电平条上，能直接看出它和信号的关系。

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
- 弦停下来之后**保持 1.5 s**；保持期间指针和读数会变淡，提示这是"最后一次读数"而不是实时测量（"响度够但不够周期"的帧只保持一半时间）。
- 清晰度有迟滞：**开始**跟踪需要 NSDF ≥ 0.5，**维持**跟踪只需要 ≥ 0.3。衰减中的弦因此不会在清晰度刚跌破阈值的那一瞬间就从表盘上消失。
- 自动匹配最近的目标弦，但带 12 音分迟滞，靠近两弦中点时不会来回跳；也可以直接锁定某一根弦。

### 泛音锁（低音弦的经典陷阱）

低音弦的基频在麦克风里往往偏弱，最强的成分常常是它的 **2 次泛音**。E2 = 82.4 Hz，2 次泛音是 164.8 Hz（E3）——而 164.8 Hz 距离标准调弦里最近的 D3 只差 200 音分，距离 E2 差 1200 音分。于是一个"诚实的"匹配器会自信地告诉你"你在弹 D3"，实际你在调 6 弦。

处理方式：

1. **直接匹配明显不对时尝试泛音解释**：把测到的频率按 2、3、4… 分频，看是否存在某根弦能让结果落在 ±25 音分以内；只有在明显优于直接匹配时才采用，并在界面上标注成 `2nd harmonic`，让你知道读的是泛音而不是基频。
2. **锁定弦时无条件折算**：锁定 6 弦后，247.2 Hz（既是空弦 B 弦，也是低音 E 的 3 次泛音）会被正确地算作 E2。
3. **不拿"当前跟踪的弦"当借口**：否则你调完 E 弦接着弹 B 弦时，会被报成"E2 准了"。247.2 Hz 这种"既是一根空弦又是一个泛音"的情况在自动模式下会如实报成 B3——想区分就锁定弦（调音页面目标弦那一排点一下）。
- 半音阶（Chromatic）模式下目标是最接近的十二平均律音，不限于预设弦。

## 和弦模式

第二页是**和弦指法与质量检测 + 练习**。调音和和弦共用一个音频引擎，切页不会中断麦克风。

### 指法库

`ChordLibrary.guitar` 手工写了 46 个常用指法（`frets` 按 6→1 弦排列，`nil` 表示不弹）：

| 类别 | 内容 |
| --- | --- |
| 大三/小三 | C G D A E F B♭ B · Am Em Dm Bm F♯m Cm Gm Fm |
| 七和弦 | C7 D7 E7 G7 A7 B7 F7 · Cmaj7 Dmaj7 Emaj7 Fmaj7 Gmaj7 Amaj7 · Am7 Em7 Dm7 Bm7 Gm7 |
| 挂留/加音/六和弦 | Csus4 Dsus4 Asus2 Asus4 Esus4 Cadd9 C6 Bm7♭5 |
| 强力和弦 | E5 A5 D5 G5 |

每张图都画成指板图：圆点=按弦品、○=空弦、×=不弹、底下一行是该弦实际发出的音名。练习模式下每个圆点会随检测结果变绿/变橙（表示"这个音听到了 / 没听到"）。

### 和弦识别是怎么做的

单音识别用的自相关在这里不适用（和弦没有单一基频），所以走频谱路线，但有三个坑，都是靠检查发现的：

1. **谐波不能当新音**。E 的三次谐波正好落在 B 上（十二度），如果把频谱能量直接折叠成 12 个音级，任何纯大三和弦都会读成 maj7（C 和弦里 E 的泛音被当成 B）。所以每个音的强度 = **基频强度 × 谐波列完整度**：真音的基频和它的 2/3/4/5 次谐波同时存在；单纯泄漏来的峰没有自己的谐波列。
2. **不能用能量求和比较音级**。开放 E 和弦根音在 3 根弦上响、三度只在 1 根弦上响，求和会让三度看起来"基本缺失"，于是每个三和弦都被自己的强力和弦抢答。改成取**同名音里的最大值**。
3. **模板匹配不能只看覆盖**。余弦相似度会让两音的强力和弦模板永远"最贴合"，所以改成：**加权覆盖率 − 无法解释的能量惩罚**（多出来的音要解释）。再加两条先验：有歧义时优先更简单的和弦（七和弦要有明确证据），以及用最低音打破"同一组音"的歧义（C6 与 Am7、Asus2 与 Esus4 音符完全相同，靠贝斯音区分）。

低音区还有个物理限制：48 kHz 下 8192 点 FFT 的 bin 间隔是 5.9 Hz，而 82 Hz 附近的半音只隔 4.9 Hz——**FFT 根本分不开低音区的半音**。所以频率用插值精确取值，再用谐波列完整度排除泄漏。

### 练习反馈

- 实时显示：识别到的和弦名 + 置信度、12 个音级的强度条（目标和弦需要的音用绿色标出）。
- 和弦体检：缺哪个音（`missing`）、哪个音太弱（`weak`）、多出什么音（`unexpected`）、完成度百分比。缺音最常见的原因是某根弦没响或被手指闷住了。
- 指板图逐弦染色，直接看到是哪根弦的问题。
- 单弦精度请切回 Tuner 页并锁定那根弦（那里用的是自相关，精度到音分）。

### 已知限制

- 识别基于固定十二平均律网格，整体失谐超过约 ±20 音分会开始影响质量判断；请先用 Tuner 页调准。
- 只覆盖"根音在最低音"的常用指法，斜杠和弦（C/G、D/F♯）会按原位和弦或转位和弦识别。
- 同时按下但完全不发声的弦无法被检测到（麦克风只听到声音）。

## 精度与验证

## 参考音、节拍器与练习

App 现在有四个页面：**Tuner · Chords · Metronome · Practice**，右上角齿轮是设置。全部共用同一个音频引擎，切页不会中断麦克风。

### 播放为什么安全

音频图改成了 `输入 → EQ → 分析 mixer（音量 0）→ 主 mixer → 输出`，`播放节点 → 主 mixer`。tap 挂在 EQ 之后、静音 mixer 之前，所以：

- 播放参考音或节拍器时，麦克风**永远不会**被送到扬声器（不会有啸叫回路）；
- 调音、频谱、和弦识别在播放期间照常工作。

播放用 `AVAudioPlayerNode` + 预渲染 buffer，而不是带渲染回调的音源节点——渲染回调需要在音频线程上放 Swift 闭包，正是之前闪退的那类问题。节拍器的精度来自 `scheduleBuffer(at:)` 的采样点，主线程定时器只负责提前排期，抖动不影响节拍。

### 参考音

- 单弦参考音：点按 Tuner 页目标弦旁的播放键，或设置里的 capo 之后跟着变。
- 整和弦示范：Chords 页的选项里可以听目标和弦应该是什么声音。
- 整段进行示范：Practice 页的 "Hear it" 按当前速度弹一遍进行。

音色是合成的（基频 + 5 个泛音 + 指数衰减），不是纯正弦——纯正弦更难跟唱/跟调。

### 节拍器

19 组拍号，奇数拍都带常用分组：5/8 有 3+2 和 2+3，7/8 有 2+2+3 / 3+2+2 / 2+3+2，9/8 有 3+3+3 和 2+2+2+3，10/8 有 3+3+2+2 和 2+3+2+3，11/8 是 3+3+3+2，12/8 是 4×3。重音落在小节头和每个分组的头拍上；可以再开细分（2 = 八分、3 = 三连音）。速度按拍号分母计数（7/8 的 120 就是每分钟 120 个八分音符），支持 Tap tempo、±1 微调和滑杆。视觉脉冲由最后一次排期的点击时间外推，和声音对齐。

### 进行练习

8 条进行：I–V–vi–IV、I–vi–IV–V、ii–V–I、Andalusian、12 小节布鲁斯、卡农、vi–IV–I–V、I–♭VII–IV。开始后节拍器计时，App 在每小节里用和弦识别打分：换和弦后留一拍宽限再判（手指要时间移动），一条进行的每个和弦都会记录"对/错"、给出准确率、连对数和整段得分，和弦条会按结果染色。跑完自动停表。

**进行用罗马数字定义，可以换调**：12 个大调 + 12 个小调随便选，和弦会自动重算。例如 I–V–vi–IV 在 C 是 C–G–Am–F，在 G 是 G–D–Em–C，在 A 是 A–E–F♯m–D，在 B♭ 是 B♭–F–Gm–E♭。12 小节布鲁斯在 E 就是 E7–A7–B7。同一条进行在 12 个调里轮着练，是标准的练习方式。

换调后的和弦不是查表查出来的，而是用**可移动把位**生成的（E/A 型大横按、Em/Am 型小横按、E7/A7、Emaj7/Amaj7、Em7/Am7、E5/A5、Esus4/Asus4、Asus2），并自动选最靠近琴颈的把位——所以 B 大三会给出 A 型 2 品横按，而不是 E 型 7 品；F 大三给出 1 品横按；C 大三给出 A 型 3 品。生成的把位会和手写指法库交叉核对（同一和弦必须发出同一组音）。

### 调音历史

每秒记录一次稳定读数（不是 20 Hz 全记），存成 JSON 放在 App 的 Application Support 目录。Practice 页按弦汇总平均偏差、准音比例、样本数，并在某根弦长期偏低/偏高或很少调准时给出提示——那通常说明是琴本身在漂，而不是你的耳朵。

### 设置

输入设备（CoreAudio 设备列表，切换会重启引擎因为硬件格式变了）、capo 0–12（目标和弦/目标弦整体上移，标签自动变成实际发声的音）、参考音高 415–466、准音窗口 1–15 音分、历史记录开关与清除。所有设置写入 `UserDefaults`（JSON），滑杆改动会合并到 400 ms 后写一次。

`swift run GuitarTunerChecks` 当前 6439 项全绿，关键阈值：

| 检查 | 阈值 |
| --- | --- |
| 标准调弦六根弦（正弦） | ≤ 5 音分 |
| 失谐 18 音分的低音 E | ≤ 3 音分 |
| 二次谐波为基频 2.6 倍的信号 | ≤ 15 音分，且不得报高八度 |
| 明亮音色（高次谐波很强） | ≤ 10 音分 |
| 白噪声 / 静音 / 门限以下噪声 | 必须返回无音高 |
| 门限与自适应噪声地板 | 单调性、边界、回落方向 |
| 环形缓冲 | 顺序、环绕、跨边界读取 |
| 自适应门限 | 拨弦起音不得抬高门限；连续 8 次拨弦后最后一次仍能检出；响铃期间 ≥85% 的帧有读数 |
| 频谱 | 峰值频率精度、对数轴映射、显示范围随调弦收紧（贝斯上看得见 B0） |
| 预设库 | 35 组结构合法性 + 著名调弦逐音核对（Drop C、Open E、DADGAD、Nashville、8 弦 F♯…） |
| 泛音锁 | E2 的 2 次泛音读成 E2（而非 D3）并标注；A2 同理；真的 D3 / 偏高 12 音分 / 偏低 120 音分的 E2 都不被误折算；两弦之间的音不被伪装成泛音；锁定弦时 3 次泛音归该弦 |
| 和弦指法库 | 46 个指法：弦数、定义音齐备、和弦构成核对（开放 C = C3 E3 G3 C4 E4 等） |
| 和弦识别 | 46/46 指法识别正确；18 组质量判定（大三/小三/七/maj7/m7/m7♭5/6/add9/sus2/sus4/5）；噪声不得给出高置信度；±20 音分仍识别正确 |
| 练习反馈 | 干净和弦判为正确；闷掉 3 弦报"缺 G"；加入 F♯ 报"多出 F♯"；弹错和弦不得判对；逐弦判定全绿 |
| 设置持久化 | 存取往返、缺省值、越界/未知值的兜底（参考音高、容差、capo、速度、音量、未知预设/进行/和弦 ID） |
| Capo | 目标整体上移、弦位标签保持、频率范围跟随、锁定弦与 capo 组合、和弦名称随 capo 变换 |
| 节拍器 | 19 组拍号分组自洽；7/8 (2+2+3)、9/8 (2+2+2+3)、10/8 (3+3+2+2) 的重音落点；细分拍；拍号分母计速；换拍号重启小节 |
| 音色合成 | 缓冲区长度/无 NaN/不削波/自然衰减/首尾无爆音；超过 Nyquist 的泛音被跳过；0 Hz 与零时长返回空；和弦混音电平 |
| 进行练习 | 7 条进行的和弦都存在；对的得分、错的扣分、静音算漏；起拍宽限；跑完整段给出完成、准确率与连对；重置与切换 |
| 进行换调 | 8 条进行 × 24 个调全部能解析；I–V–vi–IV 在 C/G/A/B♭ 的和弦名逐个核对；布鲁斯在 E、Andalusian 在 A 小调、ii–V–I 在 F、I–♭VII–IV 在 D；生成的把位必须落在琴颈内、至少响 4 根弦、含根音、定义音齐备，并与手写指法库音级一致 |
| 调音历史 | 写入/读取往返、上限裁剪保留最新、按弦平均与准音比例、时间窗过滤、一秒节流、长期偏差提示、清空 |

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
