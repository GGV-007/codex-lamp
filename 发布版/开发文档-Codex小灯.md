# Codex小灯 · 开发文档

> 菜单栏小灯：看着 Codex 干活。
> 与「WB小灯」同一套灯语规则，读的是 Codex 的会话日志。
>
> **版本**：**V1.5**（2026-10-28）—— **真修「换完提示音重启会丢」**：app 的 Bundle ID 叫 `local.codex.light`，代码却用同名 `initWithSuiteName:` 建 suite，macOS 直接忽略（"own bundle identifier as suite name does not work"），偏好只在进程内存里、从不落盘；改用 `standardUserDefaults`（与 WB小灯 V2.6 同源同病同修，已在 .app 里实测验证）。｜V1.4（2026-10-27）—— 菜单「重启 / 退出」**配上图标**：重启=循环箭头（arrow.triangle.2.circlepath）、退出=方框叉（xmark.square），SF Symbols 13pt Medium，与 WB小灯 同款同尺寸。｜V1.3（2026-10-27）—— ①第二行整行换成「**工作中 · 已忙 X 分 X 秒**」（文字白、两个数字绿，复用的就是驱动 C 灯闪的那个忙碌时长参数）；原来「最近活动：X小时X分X秒前」这一行**彻底删除**（前台菜单、后台计算都不再保留）；②**修提示音偏好不落盘**（换完音重启会丢，详见 1.1）。｜V1.2（2026-10-27）：「最近活动」行状态词去掉。｜V1.1（2026-10-27）：菜单宽度统一 314、状态词去闪烁。｜V1.0：当前任务第一行绿字 15 半粗。｜V0.9：分隔线。｜V0.8：菜单 0% 黄呼吸。｜V0.6：真实用量。｜**文档整理**：W｜2026-10-12
> **源码**：`源码/Codex小灯.m`（单文件 975 行）｜**产物**：`发布版/Codex小灯.app`（版本 1.5）
> **作者**：Codex（原始实现）｜**本版文档**：W 实测审查后编写，含三项待修问题

---

## 0. 结论先行

一句话：**方向对、当前判定准，但有 3 处必修。**

我这个版本做的事情是「拿真实日志把它判定的逻辑重放一遍」，而不是只看代码。测的时候 Codex 正好在另一个窗口干活，日志正在实时写入 —— 属于活体测试。

| 项 | 结论 |
|----|------|
| 数据源是否真实可用 | ✅ `~/.codex/sessions/` 实时落盘，mtime 与末事件差 **0.0 秒** |
| 时间戳格式是否匹配 | ✅ 实测 `2026-10-12T04:30:33.817Z`，与代码 formatter 完全一致 |
| 「已完成」信号是否存在 | ✅ `task_complete` 152 次、`AgentMessage` final 相位 158 次 |
| 当前时刻判定 | ✅ 判「忙碌中」正确（依据：最新回合 function_call，末事件 1 秒） |
| 误红风险 | ❌ **回合内 30~180 秒的事件间隔有 343 次** → 每次都会误红 |
| 打断是否立刻红 | ❌ `turn_aborted` 7 次，代码没认这个事件 |
| 能否自证 | ❌ 无 `--selftest` / `--replay` / `--state` |

**三项必修（未授权改动，等拍板）**：

1. `kUnfinishedTurnTimeout` 30 秒 → 放宽到 180 秒（与文件级兜底拉齐），消掉 343 次误红
2. 认 `turn_aborted` → 打断立刻红，而不是等 30 秒兜底
3. 补 `--selftest`（断言）+ `--replay`（真实日志重放）+ `--state`（一行状态），把「判定对不对」变成可验证的事

**本版已做（2026-10-12，刚哥点名要的）**：**干完活响一声「叮」**——灯从绿转红时播提示音，菜单里可开可关、可换音（16 个候选）。三项必修仍未动。详见第 2.4 节。

---

## 1. 灯语规则

| 状态栏 | 含义 | 触发 |
|--------|------|------|
| 绿色加粗 **C**，闪烁 | **忙** —— Codex 正在干活 | 最新回合有「未完成」信号 |
| 红色加粗 **C**，常亮 | **闲** —— 待命 | 已交付 / 日志超 180 秒未更新 |
| 红色加粗 **C**，常亮 | **离线** —— Codex 没开 | 日志不更新（天然对齐，无需专门判断） |

点一下 **C** 展开面板：

```
当前任务：抖音发布辅助平台         ← V1.0：第一行，整行绿字 15 半粗（大一号）
工作中 · 已忙 3 分 12 秒            ← V1.3：整行替换掉「最近活动」（与 WB 同款）；文字白、两个数字绿；闲=「闲置中」
────────────────────────
5小时剩余：91% · 20 分钟后重置   ← V0.6：真实用量；V0.8：数字为 0% 时黄色呼吸（与菜单栏 C 同频同相）
本周剩余：96% · 4 天 17 小时后重置
────────────────────────
测试网速                          ← V0.6 追加：默认浏览器打开 fast.com 测速（刚哥定：不显示网址）
打开 Codex
更换提示音 ▸                      ← 子菜单：开关 + 16 个音源（点音名即试听并设为当前）
────────────────────────
重启 Codex 小灯 🔄                ← V0.5 新增：拉起新实例后退出旧实例；V1.4 配「循环箭头」图标
退出 Codex小灯 ⊠                  ← V1.4 配「方框叉」图标（两行图标同 13pt，与 WB 同款）
```

> **V0.4 变更（刚哥指定）**：菜单只保留以上 5 项。删掉了「动作」「依据」两行状态、
> 「最近 Codex 项目」列表和「演示忙碌 30 秒」演示模式。「退出」条目名同步改成 app 现名。
> **V0.6 变更（2026-10-17）**：新增 Codex 真实用量（5 小时剩余 / 本周剩余），详见 2.5；
> 同日追加（刚哥指定）：栏序对调——最近活动/当前任务第一栏、用量第二栏；刷新 300 秒 → 60 秒（主动拉取，分钟级刚好）；
> 「最近活动」状态词染色：进行中=绿色并跟随菜单栏 C 同步闪烁，已完成=红色常亮（renderDetailLine，与 C 同一套灯语色）。
> 同日追加：菜单新增「测试网速」，点击用默认浏览器打开 fast.com，菜单上不显示网址（openFastCom:）。
> **2026-10-22 追加**：菜单栏 C 旁边直接挂剩余额度，格式 **`C 46% 20:22 / 91%`**——
> ①5 小时剩余 → ②该窗口的重置时间点（本地时钟 HH:mm，取 `reset_at`，退回「当前 + reset_after_seconds」）→ ③斜杠后=本周剩余。
> 各自独立染色：≥10% 绿、<10% 红（重置时间与前一个百分比同色）；百分比不闪烁（C 照常闪）。
> 用量未拿到前只显示 C。实现：`fiveHourLeft` / `weekLeft` / `fiveHourReset` + `renderStatusTitle` 拼接富文本，
> 状态项长度改为自适应（-1），否则会被 24pt 定宽截断。本周那个额度不显示重置时间，只给 5 小时窗口配。
> 百分比数字（91% / 96%）用绿色突出，其余文字保持黑白层级。
> **V0.7 变更（2026-10-25，刚哥指定）**：5 小时额度耗尽（0%）时，菜单栏的「0%」变成**黄色呼吸**——
> systemYellow + alpha 按余弦 0.25↔1.0 平滑往复，周期 2.6 秒（`kBreathTick=0.05s` 每帧重画，
> `updateBreathTimer` 挂在每秒巡检 `updateState` 里：0% 开呼吸、回到有量关掉并恢复常亮）。
> 只染百分比本身；重置时间点保持红色常亮、`/本周%` 不参与；与忙闲绿闪（0.55s 硬切）完全独立。
> 实测采样：alpha 0.56→0.34→0.25（谷）→0.34→0.58→1.00（峰），黄色 R=1.00 G=0.84 B=0.00。
> **V1.0 变更（2026-10-26，刚哥指定）**：面板前两行对调——「当前任务」第一行、整行绿色 15 半粗（比常规行大一号，文本框加高防截字）；
> 「最近活动：X小时X分X秒前 · 状态」放第二行，样式不动（12 常规灰字，状态词仍绿闪/红常亮）。
> 探针实测：第 0 行=「当前任务：…」15.0 号绿字，第 1 行=「最近活动：…」12.0 号。

> **V1.3 变更（2026-10-27，刚哥指定）**：第二行「最近活动：X小时X分X秒前」**整行删掉**（刚哥定：没意义），
> 换成与 WB 小灯同款的「**工作中 · 已忙 X 分 X 秒**」——文字 `labelColor`（白）、两个数字 `systemGreenColor`（绿）。
> 数据来源就是**原本驱动 C 灯闪烁的那个忙碌时长**：新增 `@property NSTimeInterval busySince`，
> 在「闲 → 忙」的边沿记下当前时间戳，「忙 → 闲」的那一刻清零；`renderDetailLine` 里现算 `now - busySince`；
> 闲着时这一行直接写「闲置中」（白字，不参与染色）。连带删除：原来的 `detailAgeText` 拼接、
> 菜单占位文案改成「闲置中」、`detailField.textColor` 默认 `labelColor`。前后台都不再留「最近活动」这四个字。

### 1.3 V1.5：真修「换完提示音重启会丢」（2026-10-28，与 WB小灯 V2.6 同源）

| 项 | 内容 |
|----|------|
| 现象 | 菜单里换好提示音 / 开关提示音，重启 app 又变回默认音 |
| 真根因 | Bundle ID（`local.codex.light`）与 suite 名**同名**，macOS 告警后**忽略该 suite**：`Using your own bundle identifier as an NSUserDefaults suite name does not make sense and will not work.` 返回的实例不落盘 |
| 为什么 V1.3 没修到 | V1.3 的自测跑的是裸二进制（无 Bundle ID），suite 正常 → 一直 PASS；真实 `.app` 里才是坏的 |
| 修法 | `soundPrefs` 改用 `[NSUserDefaults standardUserDefaults]` |
| 验证 | 在 `Codex小灯.app` 内跑自测、并用 `defaults` 外部写入后由 app 内二进制读回验证（与 WB 同法，见 WB 文档 0.9） |

### 1.2 V1.4：菜单「重启 / 退出」加图标（2026-10-27 刚哥指定）

| 项 | 做法 |
|----|------|
| 重启 | `NSImage imageWithSystemSymbolName:@"arrow.triangle.2.circlepath"`（循环箭头），13pt Medium |
| 退出 | `xmark.square`（方框叉），同 13pt，两行图标位对齐 |
| 说明 | SF Symbols 系统自带，无需素材；`if (sym)` 判空防老系统没有该符号；template 渲染自动适配深浅色 |
| 同步 | WB小灯 退出项的图标源码里此前一直缺失（只有重启写了），V2.4 一并补上——两灯菜单尾部现在完全同款 |

### 1.1 V1.3 顺手修：提示音偏好不落盘（换完音重启会丢）

| 项 | 内容 |
|----|------|
| 现象 | 菜单里换好提示音、开关提示音，重启 app 后又变回默认（「叮」） |
| 根因 | `soundPrefs` **每次调用都新建一个** `NSUserDefaults`（`initWithSuiteName:`），写完从不 `synchronize`，退出进程时改动还在内存里，没送到 cfprefsd 就随进程没了 |
| 修法 | ① `soundPrefs` 改成 `dispatch_once` 进程内单例；② `saveSoundPrefs` 结尾加 `[d synchronize]`（立刻落盘，不等系统异步 flush） |
| 影响面 | 与 WB小灯 同源同款（V2.3 同步修掉） |

> **V0.8 变更（2026-10-26，刚哥指定）**：点开菜单后，「5小时剩余：**0%**」这一行的 **0% 也要黄色呼吸**。
> 实现：新增 `lastFiveLine` / `lastWeekLine` 缓存菜单两行的原文；原来的 `setUsageField:` 拆成
> `renderUsageLines` + `renderUsageField:text:baseColor:breathing:`（先按数字区间染绿/红，breathing=YES 时数字改用
> `systemYellow` 且 alpha 取当前 `breathAlpha`）；`tickBreath` 里除 `renderStatusTitle` 再加一次 `renderUsageLines`。
> 于是菜单与菜单栏**共用同一个呼吸帧**（同一个 `breathTimer`、同一个 `breathAlpha`）——同频同相，不会各亮各的。
> **关键坑**：启动头 1 秒文案还没生成时 `lastFiveLine` 为 nil，直接建 attributed string 会抛
> `NSConcreteMutableAttributedString initWithString:attributes: nil value`，每帧抛异常 → 呼吸帧停摆、alpha 卡死在 0.92。
> 已加 nil 保护（`if (self.lastFiveLine)`）；修复后实测采样 alpha 0.62→0.29→0.29→0.58→1.00，与 `breathAlpha` 逐帧一致。
> 本周那一行 `breathing=NO` 不参与呼吸；文字部分仍用 `labelColor` / `secondaryLabelColor` 保持黑白层级。
> **V0.5 变更（2026-10-17 追加）**：删掉「显示当前日志」按钮（刚哥指定，无意义）。
> **V0.5 变更**：在「退出」上方新增「重启 Codex 小灯」。实现：
> `NSWorkspaceOpenConfiguration.createsNewApplicationInstance = YES` 先拉起一个**新实例**，
> 再 `terminate` 退出当前实例 —— 必须设 YES，否则系统认为「已在运行」不会开新的，等效于退出。
> 已实测：旧实例存活时该调用能成功拉起第二个实例（2026-10-17）。
> **2026-10-25 修一个真 bug**：原来发起启动后**立刻** `terminate`，而启动请求是异步的，进程一死请求被掐掉，
> 表现就是"点了重启没反应"。改为在 `completionHandler` 里确认新实例已拉起后，再延迟 0.6 秒退出；
> 若 NSWorkspace 失败则用 `/usr/bin/open -n` 兜底。实测：PID 8156 退出 → 新实例 8166 拉起。

闪烁实现：切换 alpha（100% ↔ 22%），不换字，避免菜单栏宽度跳动 —— 与 WB小灯 同一手法。

---

## 2. 判定原理：Codex 的「干活信号」在哪

数据源只有一个：

```
~/.codex/sessions/<年>/<月>/<日>/rollout-<时间戳>-<uuid>.jsonl
```

按日期分层，当前本机 118 个文件；单个会话文件是**逐事件追加**的，实测有 13883 行、**511.7 MB**。日志实时落盘（mtime ≈ 末事件时间）。

### 2.1 事件类型（实测分布，取本机最大的一个会话文件）

| type | 有 turn_id | 无 turn_id | 说明 |
|------|-----------|-----------|------|
| `response_item` | 5668 | — | 模型输出：`reasoning` / `function_call` / `message` |
| `event_msg` | 4477 | 1842 | 状态机事件：`item_completed` / `task_started` / `task_complete` / `token_count` / `turn_aborted` |
| `token_usage_record` | 1627 | — | 计费 |
| `turn_context` | 178 | — | 回合上下文 |
| `compacted` | — | 18 | 会话压缩 |
| `world_state` / `session_meta` | — | 49 / 1 | 与忙闲无关 |

`turn_id` 的取值位置（代码里已实现）：`payload.turn_id`，兜底 `payload.internal_chat_message_metadata_passthrough.turn_id`。

### 2.2 判定逻辑（源码 `latestSubstantiveStateFrom:`）

```
1) 从日志尾部 512KB 里，从后往前找第一个带 turn_id 的事件 → 得到「最新回合」
2) 扫这个回合内的所有事件，累计三个标志：
     hasTaskComplete  ← event_msg.task_complete
     hasFinal         ← response_item.message(assistant, phase=final/final_answer)
                        event_msg.item_completed.item(AgentMessage, phase=final)
     hasBusySignal    ← response_item.function_call / reasoning / message(user)
                        event_msg.item_completed.item(UserMessage | CommandExecution | Reasoning)
3) 判定：
     hasTaskComplete || hasFinal            → 闲
     hasBusySignal && 末事件年龄 > 30 秒     → 闲（兜底停闪）   ← 问题在这
     hasBusySignal                          → 忙
     都不成立                                → 回退：文件 3 秒内被写过 → 忙，否则闲
4) 前置兜底：整个日志文件 180 秒没更新过 → 直接判闲
```

**「依据」字段就是 `stateReason`**，面板上直接显示它是凭什么判的（如「最新回合 CommandExecution」）—— 这一点做得好，别的人类看灯只能猜，它能告诉你原因。

### 2.3 与 WB小灯 的对照

| | WB小灯 | Codex小灯 |
|---|--------|-----------|
| 数据源 | `~/.workbuddy/projects/*.jsonl` | `~/.codex/sessions/**/rollout-*.jsonl` |
| 判据粒度 | 末条「实质事件」是否走完回合 | 最新 turn 内的信号聚合 |
| 判闲信号 | `message(assistant, completed)` | `task_complete` / `AgentMessage final` |
| 记账事件干扰 | `file-history-snapshot` / `ai-title`（需跳过） | `token_count`（代码已跳过 ✅） |
| 打断 | `Interrupted by user` → 立刻红 | `turn_aborted` → **未处理** ❌ |
| 自测 | 46 项断言 + `--replay` | **无** ❌ |
| 架构 | 通用二进制（arm64 + x86_64） | **仅 arm64**（Intel Mac 跑不了） |

### 2.4 完成提示音（V0.3 新增，V0.4 保留）

**触发条件**：灯从**绿 → 红**的那一次翻转（`wasBusy && !busy`），也就是「这一轮活干完了」。
不在启动时响、不在一直闲着时响、不在变绿时响。

实现要点（源码 `playCompletionSound` / `toggleSound:` / `selectSound:`）：

| 要点 | 做法 | 为什么 |
|------|------|--------|
| 只在「绿→红」响 | 在 `updateState` 里比对新旧 `busy` | 只有这个翻转代表「活干完了」，其余都不该打扰 |
| 声音必须被持有 | `@property (strong) NSSound *player` | 局部变量会被 ARC 提前释放 → 只响半声或干脆不响，这是最容易踩的坑 |
| 防抖 | `kMinSoundGap = 2 秒` | 判定抖动（兜底窗口、打断、连续两轮）时不至于连响成噪音 |
| 持久化 | `NSUserDefaults`，suite = `local.codex.light` | app 和裸二进制两种启动方式都能记住设置 |
| 音源自动发现 | 扫 `/System/Library/Sounds`、`/Library/Sounds`、`~/Library/Sounds` | 不用硬编码清单；自己往 `~/Library/Sounds` 丢个音频就自动出现在菜单里 |

菜单长这样：

```
更换提示音 ▸
    ✓ 提示音：开启（点一下关闭）
    ────────────
    系统提示音
      Basso / Blow / Bottle / Frog / Funk / Glass / Hero / Morse
      Ping / Pop / Purr / Sosumi / Submarine / Tink(✓ 默认)
    自定义（~/Library/Sounds）
      codex-alert-codex-notification
      codex-notification
    ────────────
    试听当前提示音
```

- **点任意一个音名 = 立刻试听 + 设为当前音**（自动把提示音打开，符合直觉）
- 默认音是系统自带的 **Tink**（就是那声「叮」）；本机 `~/Library/Sounds` 里还有 Codex 自己的两个通知音，也在列表里
- 设置在哪？`~/Library/Preferences/local.codex.light.plist`（想复位就删掉它）

**实测验证方式**（不靠肉眼看灯）：把源码复制一份做插桩版，用环境变量把 home 指到隔离目录、造一个假会话，记录状态翻转与 `[NSSound play]` 的真实返回值：

| 用例 | 场景 | 结果 |
|------|------|------|
| A | 造一个刚写入的假会话（先绿 3 秒后转红） | `busy 1 -> 0` 同一秒 `SOUND play=1`（Tink）✅ |
| B | 提示音设为关闭 | 翻转照常发生，但 `SOUND suppressed`，**0 次响声** ✅ |
| C | 只有 2 小时前的旧日志（一直闲） | 全程无翻转、**0 次响声**（启动不误响）✅ |
| D | 真实 home 下扫音源 | **16 个**（系统 14 + Codex 自定义 2）✅ |

---

### 2.5 Codex 真实用量（V0.6 新增）

**要解决的问题**：Codex 的 5 小时窗口和本周额度，肉眼只能靠猜。这一版直接在菜单最上面显示真实剩余百分比。

**数据从哪来**（实测确认，非猜）：

| 项 | 值 |
|----|----|
| 接口 | `GET https://chatgpt.com/backend-api/wham/usage` |
| 认证 | `Authorization: Bearer <access_token>`（读 `~/.codex/auth.json`，**只读不改写**） |
| 账号头 | `chatgpt-account-id: <account_id>` |
| 返回字段 | `rate_limit.primary_window.used_percent`（5 小时窗口，18000 秒）<br>`rate_limit.secondary_window.used_percent`（本周，604800 秒） |
| 重置时间 | 同级的 `reset_after_seconds` / `reset_at` |

菜单显示的是**剩余**百分比（`100 - used_percent`），并带上下次重置时间：

```
5小时剩余：91% · 15 分钟后重置
本周剩余：96% · 4 天 17 小时后重置
```

**配色（2026-10-17 刚哥定）**：只有百分比数字（含 `%`）用系统绿色（`systemGreenColor`），
其余文字保持原来的黑白层级 —— 用 `NSMutableAttributedString` 只给数字段上色，实现见 `setUsageField:text:baseColor:`。

**几个刻意的设计**：

| 设计 | 做法 | 原因 |
|------|------|------|
| 只读凭据 | 只读 `~/.codex/auth.json`，从不写回 | 自己刷新 token 会与 Codex 抢登录态，可能把你踢下线 |
| 失败不编数 | 首次失败显示「用量：暂不可用」；已有数据后失败**保留上次结果** | 显示 0% 或 100% 都是误导 |
| 登录过期 | 显示「登录已过期 · 打开 Codex 刷新后自动恢复」 | Codex 自己会刷新 token，等它写回即可 |
| 刷新频率 | **60 秒一次**（容差 5 秒；2026-10-17 刚哥定，原 300 秒） | 接口是**主动拉取**不是推送；分钟级变化（14 分 → 13 分）一分钟一拉刚好 |
| 不阻塞 UI | `NSURLSession` 异步 + 主线程回写 | 断网时菜单不会卡住 |

**实测记录（2026-10-17 21:28）**：

- 走系统代理（`127.0.0.1:12334`）请求成功，HTTP 200；
- 真实返回：5 小时窗口 `used_percent=9`（剩余 91%，1225 秒后重置）、本周 `used_percent=4`（剩余 96%，410350 秒后重置）；
- app 内 `NSURLSession` 实跑输出：`[usage] 5小时剩余：91% · 15 分钟后重置 | 本周剩余：96% · 4 天 17 小时后重置` ✅

> 注意：WorkBuddy 沙箱里的 `HTTP(S)_PROXY` 指向 65530（不可用），app 运行在系统环境，走的是系统代理设置，不受影响。

---

## 3. 完整源码（源码/Codex小灯.m）

> 下面是 V1.2 的完整源码，共 949 行，单文件、零依赖。
> `lastFiveLine` / `lastWeekLine` + `renderUsageLines` + `renderUsageField:...breathing:`，`tickBreath` 同步重画菜单两行。
> 其余逻辑未改动。

```objc
#import <Cocoa/Cocoa.h>

static const NSTimeInterval kPollInterval = 1.0;
static const NSTimeInterval kBlinkInterval = 0.55;
static const NSTimeInterval kStaleBusyWindow = 180.0;
static const NSTimeInterval kUnfinishedTurnTimeout = 30.0;
static const NSTimeInterval kMinSoundGap = 2.0;   // 两声「叮」之间至少隔这么久，防止判定抖动时连响
static const NSTimeInterval kBreathTick = 0.05;   // 黄色呼吸的步进（50ms 一帧，肉眼平滑）
static const NSTimeInterval kBreathPeriod = 2.6;  // 呼吸一个明→暗→明周期（秒），"慢慢"呼吸

@interface AppDelegate : NSObject <NSApplicationDelegate, NSMenuDelegate>
@property (strong) NSStatusItem *item;
@property (strong) NSMenu *menu;
@property (strong) NSTextField *detailField;
@property (strong) NSTextField *taskField;
// ---- Codex 真实用量（5小时窗口 / 本周）----
@property (strong) NSTextField *usageFiveField;
@property (strong) NSTextField *usageWeekField;
@property (copy)   NSString *lastFiveLine;    // 最近一次菜单用量文案（呼吸帧重画用）
@property (copy)   NSString *lastWeekLine;
@property (strong) NSTimer *usageTimer;
@property (nonatomic) BOOL usageFetching;
@property (nonatomic) NSTimeInterval usageFetchedAt;
@property (nonatomic) NSInteger fiveHourLeft;   // 5小时剩余百分比，-1 = 还没拿到数据
@property (nonatomic) NSInteger weekLeft;       // 本周（5天）剩余百分比，-1 = 还没拿到数据
@property (copy) NSString *fiveHourReset;       // 5小时窗口重置时间点（本地 HH:mm），如 22:00
@property (strong) NSTimer *pollTimer;
@property (strong) NSTimer *blinkTimer;
@property (strong) NSTimer *breathTimer;          // 5小时额度耗尽（0%）时的黄色呼吸定时器
@property (nonatomic) CFAbsoluteTime breathStart; // 呼吸起点，用于算当前 alpha
@property (nonatomic) BOOL busy;
@property (nonatomic) BOOL blinkOn;
@property (nonatomic) NSTimeInterval lastActivity;
@property (copy) NSString *lastSessionPath;
@property (copy) NSString *currentTitle;
@property (copy) NSString *lastActionText;
@property (copy) NSString *stateReason;
@property (nonatomic) NSTimeInterval busySince;   // 本次变忙的时刻（V1.3：「已忙 X 分 X 秒」用）
// ---- 干完活提示音 ----
@property (nonatomic) BOOL soundEnabled;
@property (copy) NSString *soundPath;
@property (nonatomic) NSTimeInterval lastSoundAt;
@property (strong) NSSound *player;                       // 必须持有，否则声音会被提前释放
@property (strong) NSMenuItem *soundToggleItem;
@property (strong) NSMutableArray<NSMenuItem *> *soundChoiceItems;
- (void)loadSoundPrefs;
- (void)saveSoundPrefs;
- (NSString *)defaultSoundPath;
- (NSArray<NSDictionary<NSString *, NSString *> *> *)availableSounds;
- (void)refreshSoundMenuItems;
- (void)playCompletionSound;
- (void)toggleSound:(id)sender;
- (void)selectSound:(id)sender;
- (void)previewSound:(id)sender;
// ---- Codex 用量 ----
- (void)fetchUsage;
- (void)applyUsage:(NSDictionary *)json;
- (NSString *)formatResetAfter:(NSNumber *)secs;
- (NSString *)resetClockFrom:(NSDictionary *)window;
- (void)setUsageLine:(NSString *)five week:(NSString *)week;
- (void)renderUsageLines;   // 菜单用量两行重画（0% 时由呼吸帧驱动，黄字忽明忽暗）
- (void)renderUsageField:(NSTextField *)field text:(NSString *)text baseColor:(NSColor *)baseColor breathing:(BOOL)breath;
- (void)renderDetailLine;
- (void)startUsageTimer;
- (void)updateBreathTimer;   // 5小时额度=0 → 黄色呼吸开/关
- (CGFloat)breathAlpha;      // 当前呼吸亮度 0.25~1.0
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    self.blinkOn = YES;
    [self loadSoundPrefs];

    // NSStatusItemVariableLength(-1)：宽度随内容自适应，挂上百分比后不会截断
    self.item = [[NSStatusBar systemStatusBar] statusItemWithLength:-1.0];
    self.fiveHourLeft = -1;   // -1 = 用量还没拿到，菜单栏先只显示 C
    self.weekLeft = -1;

    self.menu = [[NSMenu alloc] initWithTitle:@"Codex小灯"];
    self.menu.delegate = self;
    // V1.0 改版（2026-10-26 刚哥指定）：「当前任务」提为第一行、整行绿字大一号；「最近活动」第二行原样式
    [self.menu addItem:[self fieldItemWithTitle:@"当前任务：未检测" assign:^(NSTextField *field) {
        self.taskField = field;
    }]];
    [self.menu addItem:[self fieldItemWithTitle:@"闲置中" assign:^(NSTextField *field) {
        self.detailField = field;
    }]];
    // 任务行：15 半粗 + 绿色（比常规菜单行大一号），框加高防截字
    self.taskField.font = [NSFont systemFontOfSize:15 weight:NSFontWeightSemibold];
    self.taskField.textColor = [NSColor systemGreenColor];
    self.taskField.frame = NSMakeRect(16, 1, 314 - 16 - 14, 22);
    // 状态行（V1.3）：与其他行同字号（13 半粗），文字白、数字绿由 renderDetailLine 逐段染色
    self.detailField.textColor = [NSColor labelColor];
    [self.menu addItem:[NSMenuItem separatorItem]];

    [self.menu addItem:[self fieldItemWithTitle:@"5小时剩余：--" assign:^(NSTextField *field) {
        self.usageFiveField = field;
    }]];
    [self.menu addItem:[self fieldItemWithTitle:@"本周剩余：--" assign:^(NSTextField *field) {
        self.usageWeekField = field;
    }]];
    self.usageFiveField.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
    self.usageWeekField.font = [NSFont systemFontOfSize:12];
    self.usageFiveField.textColor = [NSColor labelColor];
    self.usageWeekField.textColor = [NSColor secondaryLabelColor];
    [self.menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *fastCom = [[NSMenuItem alloc] initWithTitle:@"测试网速" action:@selector(openFastCom:) keyEquivalent:@""];
    fastCom.target = self;
    [self.menu addItem:fastCom];

    NSMenuItem *openCodex = [[NSMenuItem alloc] initWithTitle:@"打开 Codex" action:@selector(openCodex:) keyEquivalent:@""];
    openCodex.target = self;
    [self.menu addItem:openCodex];

    // ---- 完成提示音：绿变红时「叮」一声，可开关、可换音 ----
    NSMenuItem *soundRoot = [[NSMenuItem alloc] initWithTitle:@"更换提示音" action:nil keyEquivalent:@""];
    NSMenu *soundMenu = [[NSMenu alloc] initWithTitle:@"更换提示音"];

    self.soundToggleItem = [[NSMenuItem alloc] initWithTitle:@"提示音：开启"
                                                      action:@selector(toggleSound:)
                                               keyEquivalent:@""];
    self.soundToggleItem.target = self;
    [soundMenu addItem:self.soundToggleItem];
    [soundMenu addItem:[NSMenuItem separatorItem]];

    self.soundChoiceItems = [NSMutableArray array];
    NSString *lastGroup = nil;
    for (NSDictionary<NSString *, NSString *> *s in [self availableSounds]) {
        NSString *group = s[@"group"];
        if (![group isEqualToString:lastGroup ?: @""]) {
            NSMenuItem *h = [[NSMenuItem alloc] initWithTitle:group action:nil keyEquivalent:@""];
            h.enabled = NO;
            [soundMenu addItem:h];
            lastGroup = group;
        }
        NSMenuItem *it = [[NSMenuItem alloc] initWithTitle:s[@"name"]
                                                    action:@selector(selectSound:)
                                             keyEquivalent:@""];
        it.target = self;
        it.representedObject = s[@"path"];
        [self.soundChoiceItems addObject:it];
        [soundMenu addItem:it];
    }
    [soundMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *preview = [[NSMenuItem alloc] initWithTitle:@"试听当前提示音"
                                                     action:@selector(previewSound:)
                                              keyEquivalent:@""];
    preview.target = self;
    [soundMenu addItem:preview];

    soundRoot.submenu = soundMenu;
    [self.menu addItem:soundRoot];
    [self refreshSoundMenuItems];

    // 分隔线：把「重启 / 退出」这类 app 操作和上面的功能项隔开（2026-10-26 刚哥指定，与 WB小灯 一致）
    [self.menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *restart = [[NSMenuItem alloc] initWithTitle:@"重启 Codex 小灯" action:@selector(restartApp:) keyEquivalent:@""];
    restart.target = self;
    // V1.4：左侧配「循环箭头」图标（与 WB小灯 同款同尺寸），和「退出」的图标位对齐（2026-10-27 刚哥指定）
    NSImage *restartSym = [NSImage imageWithSystemSymbolName:@"arrow.triangle.2.circlepath"
                                      accessibilityDescription:@"重启"];
    if (restartSym) {
        restart.image = [restartSym imageWithSymbolConfiguration:
            [NSImageSymbolConfiguration configurationWithPointSize:13 weight:NSFontWeightMedium]];
    }
    [self.menu addItem:restart];

    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"退出 Codex小灯" action:@selector(quit:) keyEquivalent:@"q"];
    quit.target = self;
    // V1.4：退出配「方框叉」图标（xmark.square），与重启同一尺寸（2026-10-27 刚哥指定）
    NSImage *quitSym = [NSImage imageWithSystemSymbolName:@"xmark.square"
                                   accessibilityDescription:@"退出"];
    if (quitSym) {
        quit.image = [quitSym imageWithSymbolConfiguration:
            [NSImageSymbolConfiguration configurationWithPointSize:13 weight:NSFontWeightMedium]];
    }
    [self.menu addItem:quit];

    self.item.menu = self.menu;

    self.pollTimer = [NSTimer scheduledTimerWithTimeInterval:kPollInterval target:self selector:@selector(updateState) userInfo:nil repeats:YES];
    [self updateState];
    [self startUsageTimer];
}

- (NSMenuItem *)fieldItemWithTitle:(NSString *)title assign:(void (^)(NSTextField *field))assign {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
    // 外层容器负责留白：左侧 16pt（与原生菜单文字对齐）、右侧 12pt；整体比旧版 300pt 窄
    NSView *box = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 314, 24)];   // V1.1：与 WB小灯 菜单同宽 314（刚哥定：按宽的统一）
    NSTextField *field = [NSTextField labelWithString:title];
    field.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
    field.lineBreakMode = NSLineBreakByTruncatingTail;      // 任务名过长截断，不再硬裁半截字
    field.frame = NSMakeRect(16, 4, 314 - 16 - 14, 17);
    [box addSubview:field];
    item.view = box;
    assign(field);
    return item;
}

- (NSArray<NSString *> *)recentSessionFiles {
    NSMutableArray<NSString *> *files = [NSMutableArray array];
    NSString *root = [NSHomeDirectory() stringByAppendingPathComponent:@".codex/sessions"];
    NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtPath:root];
    for (NSString *relative in enumerator) {
        if ([relative.pathExtension isEqualToString:@"jsonl"]) {
            [files addObject:[root stringByAppendingPathComponent:relative]];
        }
    }
    [files sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        NSDictionary *aa = [[NSFileManager defaultManager] attributesOfItemAtPath:a error:nil];
        NSDictionary *bb = [[NSFileManager defaultManager] attributesOfItemAtPath:b error:nil];
        NSDate *da = aa[NSFileModificationDate];
        NSDate *db = bb[NSFileModificationDate];
        return [db compare:da];
    }];
    if (files.count > 12) {
        return [files subarrayWithRange:NSMakeRange(0, 12)];
    }
    return files;
}

- (void)updateState {
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    NSTimeInterval latest = 0;
    NSString *latestPath = nil;

    for (NSString *path in [self recentSessionFiles]) {
        NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
        NSDate *date = attrs[NSFileModificationDate];
        NSTimeInterval t = date.timeIntervalSince1970;
        if (t > latest) {
            latest = t;
            latestPath = path;
        }
    }

    self.lastActivity = latest;
    self.lastSessionPath = latestPath ?: @"";
    BOOL wasBusy = self.busy;
    BOOL sessionBusy = [self sessionAppearsBusy:self.lastSessionPath now:now];
    self.busy = sessionBusy;

    if (self.busy && !wasBusy) { [self startBlink]; self.busySince = now; }   // V1.3：记下"这次忙了多久"
    if (!self.busy) {
        [self stopBlink];
        self.blinkOn = YES;
        self.busySince = 0;
    }
    if (wasBusy && !self.busy) [self playCompletionSound];   // 绿 → 红：活干完了，叮一声
    [self updateBreathTimer];   // 0% → 黄色呼吸开；回到有量 → 关（挂巡检，比只挂拉取那一刻稳）
    [self renderStatusTitle];

    [self updateCurrentTitleAndAction];

    [self renderDetailLine];   // V1.3：状态行「工作中 · 已忙 X 分 X 秒」，每秒刷新

    self.taskField.stringValue = [NSString stringWithFormat:@"当前任务：%@", self.currentTitle ?: @"未检测"];
}

- (BOOL)sessionAppearsBusy:(NSString *)path now:(NSTimeInterval)now {
    if (!path.length) return NO;
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    NSDate *date = attrs[NSFileModificationDate];
    if (!date) {
        self.stateReason = @"无日志文件";
        return NO;
    }
    NSTimeInterval fileAge = now - date.timeIntervalSince1970;
    if (fileAge > kStaleBusyWindow) {
        self.stateReason = [NSString stringWithFormat:@"日志 %.0f 秒未更新，按闲置", fileAge];
        return NO;
    }

    NSString *state = [self latestSubstantiveStateFrom:path];
    if ([state isEqualToString:@"idle"]) return NO;
    if ([state isEqualToString:@"busy"]) return YES;

    // If the tail cannot be parsed, fall back to a very short write window, not the old 45 seconds.
    return now - date.timeIntervalSince1970 < 3.0;
}

- (NSString *)latestSubstantiveStateFrom:(NSString *)path {
    NSArray<NSDictionary *> *events = [self tailEventObjectsFrom:path bytes:524288];
    NSString *latestTurn = nil;
    for (NSDictionary *obj in [events reverseObjectEnumerator]) {
        latestTurn = [self turnIDForEvent:obj];
        if (latestTurn.length) break;
    }

    if (latestTurn.length) {
        BOOL hasFinal = NO;
        BOOL hasTaskComplete = NO;
        BOOL hasBusySignal = NO;
        NSString *lastKnownReason = @"最新回合无明确事件";
        NSTimeInterval now = [NSDate date].timeIntervalSince1970;
        NSTimeInterval lastTurnAge = 999999.0;
        for (NSDictionary *obj in events) {
            NSString *turnID = [self turnIDForEvent:obj];
            if (![turnID isEqualToString:latestTurn]) continue;
            lastTurnAge = [self ageOfEvent:obj now:now];

            NSString *type = obj[@"type"];
            NSDictionary *payload = [obj[@"payload"] isKindOfClass:NSDictionary.class] ? obj[@"payload"] : nil;
            NSString *ptype = payload[@"type"];
            NSString *phase = payload[@"phase"];

            if ([type isEqualToString:@"response_item"]) {
                if ([ptype isEqualToString:@"function_call"] || [ptype isEqualToString:@"reasoning"]) {
                    hasBusySignal = YES;
                    lastKnownReason = [NSString stringWithFormat:@"最新回合 %@", ptype];
                }
                if ([ptype isEqualToString:@"message"]) {
                    NSString *role = payload[@"role"];
                    if ([role isEqualToString:@"user"]) {
                        hasBusySignal = YES;
                        lastKnownReason = @"最新回合收到用户消息";
                    }
                    if ([role isEqualToString:@"assistant"] && [self isFinalPhase:phase]) {
                        hasFinal = YES;
                        lastKnownReason = [NSString stringWithFormat:@"最新回合 assistant %@", phase];
                    }
                }
            }

            if ([type isEqualToString:@"event_msg"]) {
                NSString *etype = payload[@"type"];
                if ([etype isEqualToString:@"task_complete"]) {
                    hasTaskComplete = YES;
                    lastKnownReason = @"最新回合 task_complete";
                }
                NSDictionary *item = [payload[@"item"] isKindOfClass:NSDictionary.class] ? payload[@"item"] : nil;
                NSString *itemType = item[@"type"];
                NSString *itemPhase = item[@"phase"];
                if ([itemType isEqualToString:@"UserMessage"] ||
                    [itemType isEqualToString:@"CommandExecution"] ||
                    [itemType isEqualToString:@"Reasoning"]) {
                    hasBusySignal = YES;
                    lastKnownReason = [NSString stringWithFormat:@"最新回合 %@", itemType];
                }
                if ([itemType isEqualToString:@"AgentMessage"] && [self isFinalPhase:itemPhase]) {
                    hasFinal = YES;
                    lastKnownReason = [NSString stringWithFormat:@"最新回合 AgentMessage %@", itemPhase];
                }
            }
        }
        if (hasTaskComplete || hasFinal) {
            self.stateReason = lastKnownReason;
            return @"idle";
        }
        if (hasBusySignal && lastTurnAge > kUnfinishedTurnTimeout) {
            self.stateReason = [NSString stringWithFormat:@"最新回合 %.0f 秒无明确完成，兜底停闪", lastTurnAge];
            return @"idle";
        }
        if (hasBusySignal) {
            self.stateReason = lastKnownReason;
            return @"busy";
        }
    }

    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    for (NSDictionary *obj in [events reverseObjectEnumerator]) {
        NSString *type = obj[@"type"];
        NSDictionary *payload = [obj[@"payload"] isKindOfClass:NSDictionary.class] ? obj[@"payload"] : nil;
        NSString *ptype = payload[@"type"];
        NSString *phase = payload[@"phase"];

        if ([type isEqualToString:@"response_item"]) {
            if ([ptype isEqualToString:@"function_call"] || [ptype isEqualToString:@"reasoning"]) {
                self.stateReason = [NSString stringWithFormat:@"尾部 %@", ptype];
                return @"busy";
            }
            if ([ptype isEqualToString:@"message"]) {
                NSString *role = payload[@"role"];
                if ([role isEqualToString:@"user"]) {
                    self.stateReason = @"尾部 user message";
                    return @"busy";
                }
                if ([role isEqualToString:@"assistant"]) {
                    self.stateReason = [NSString stringWithFormat:@"尾部 assistant %@", phase ?: @""];
                    return [self isFinalPhase:phase] ? @"idle" : @"busy";
                }
            }
        }

        if ([type isEqualToString:@"event_msg"]) {
            NSString *etype = payload[@"type"];
            if ([etype isEqualToString:@"token_count"]) continue;
            if ([etype isEqualToString:@"task_complete"]) {
                self.stateReason = @"尾部 task_complete";
                return @"idle";
            }
            if ([etype isEqualToString:@"item_completed"]) {
                NSDictionary *item = [payload[@"item"] isKindOfClass:NSDictionary.class] ? payload[@"item"] : nil;
                NSString *itemType = item[@"type"];
                NSString *itemPhase = item[@"phase"];
                if ([itemType isEqualToString:@"AgentMessage"]) {
                    self.stateReason = [NSString stringWithFormat:@"尾部 AgentMessage %@", itemPhase ?: @""];
                    return [self isFinalPhase:itemPhase] ? @"idle" : @"busy";
                }
                if ([itemType isEqualToString:@"CommandExecution"] || [itemType isEqualToString:@"Reasoning"]) {
                    NSString *status = item[@"status"];
                    NSTimeInterval age = [self ageOfEvent:obj now:now];
                    self.stateReason = [NSString stringWithFormat:@"尾部 %@ %@ %.0f 秒", itemType, status ?: @"", age];
                    if ([status isEqualToString:@"completed"] && age > 3.0) return @"idle";
                    return @"busy";
                }
            }
        }
    }
    return @"unknown";
}

- (BOOL)isFinalPhase:(NSString *)phase {
    return [phase isEqualToString:@"final"] || [phase isEqualToString:@"final_answer"];
}

- (NSString *)turnIDForEvent:(NSDictionary *)event {
    NSDictionary *payload = [event[@"payload"] isKindOfClass:NSDictionary.class] ? event[@"payload"] : nil;
    NSString *turnID = payload[@"turn_id"];
    if (turnID.length) return turnID;
    NSDictionary *meta = [payload[@"internal_chat_message_metadata_passthrough"] isKindOfClass:NSDictionary.class]
        ? payload[@"internal_chat_message_metadata_passthrough"]
        : nil;
    turnID = meta[@"turn_id"];
    return turnID.length ? turnID : @"";
}

- (NSTimeInterval)ageOfEvent:(NSDictionary *)event now:(NSTimeInterval)now {
    NSString *timestamp = event[@"timestamp"];
    if (!timestamp.length) return 999999.0;
    NSDateFormatter *fmt = [NSDateFormatter new];
    fmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    fmt.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    fmt.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'";
    NSDate *date = [fmt dateFromString:timestamp];
    if (!date) {
        fmt.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
        date = [fmt dateFromString:timestamp];
    }
    if (!date) return 999999.0;
    return MAX(0, now - date.timeIntervalSince1970);
}

// ================= 完成提示音（绿变红时「叮」一声）=================

- (NSUserDefaults *)soundPrefs {
    // V1.5 真修（2026-10-28 与 WB小灯 V2.6 同源同病）：
    // app 的 Bundle ID 就叫 local.codex.light，再用同名的 initWithSuiteName 会被系统忽略
    // （"own bundle identifier as suite name does not work"）→ 返回的实例不落盘，换完音重启就丢。
    // 改用 standardUserDefaults（写 ~/Library/Preferences/local.codex.light.plist），两个 app 天然隔离。
    return [NSUserDefaults standardUserDefaults];
}

- (void)loadSoundPrefs {
    NSUserDefaults *d = [self soundPrefs];
    self.soundEnabled = ([d objectForKey:@"SoundEnabled"] == nil) ? YES : [d boolForKey:@"SoundEnabled"];
    NSString *p = [d stringForKey:@"SoundPath"];
    self.soundPath = p.length ? p : [self defaultSoundPath];
}

- (void)saveSoundPrefs {
    NSUserDefaults *d = [self soundPrefs];
    [d setBool:self.soundEnabled forKey:@"SoundEnabled"];
    [d setObject:(self.soundPath ?: @"") forKey:@"SoundPath"];
    [d synchronize];   // V1.3：立刻落盘，别等系统的异步 flush
}

- (NSString *)defaultSoundPath {
    // 默认就是那声「叮」；万一系统里没有，退回列表第一个
    NSString *tink = @"/System/Library/Sounds/Tink.aiff";
    if ([[NSFileManager defaultManager] fileExistsAtPath:tink]) return tink;
    NSDictionary<NSString *, NSString *> *first = [self availableSounds].firstObject;
    return first[@"path"] ?: @"";
}

- (NSArray<NSDictionary<NSString *, NSString *> *> *)availableSounds {
    NSArray<NSArray<NSString *> *> *dirs = @[
        @[@"系统提示音", @"/System/Library/Sounds"],
        @[@"其他提示音", @"/Library/Sounds"],
        @[@"自定义（~/Library/Sounds）", [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Sounds"]],
    ];
    NSArray<NSString *> *exts = @[@"aiff", @"aif", @"wav", @"caf", @"m4a", @"mp3"];
    NSMutableArray<NSDictionary<NSString *, NSString *> *> *out = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSArray<NSString *> *pair in dirs) {
        NSString *group = pair[0];
        NSString *dir = pair[1];
        NSArray<NSString *> *names = [fm contentsOfDirectoryAtPath:dir error:nil];
        for (NSString *n in [names sortedArrayUsingSelector:@selector(localizedStandardCompare:)]) {
            if ([n hasPrefix:@"."]) continue;
            if (![exts containsObject:n.pathExtension.lowercaseString]) continue;
            NSString *base = n.stringByDeletingPathExtension;
            if ([seen containsObject:base]) continue;      // 同名只留第一个（系统音优先）
            [seen addObject:base];
            [out addObject:@{@"name": base,
                             @"path": [dir stringByAppendingPathComponent:n],
                             @"group": group}];
        }
    }
    return out;
}

- (void)refreshSoundMenuItems {
    self.soundToggleItem.title = self.soundEnabled ? @"提示音：开启（点一下关闭）"
                                                   : @"提示音：关闭（点一下开启）";
    self.soundToggleItem.state = self.soundEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    NSString *cur = self.soundPath ?: @"";
    for (NSMenuItem *it in self.soundChoiceItems) {
        id rep = it.representedObject;
        NSString *p = [rep isKindOfClass:[NSString class]] ? rep : @"";
        it.state = [p isEqualToString:cur] ? NSControlStateValueOn : NSControlStateValueOff;
    }
}

- (void)playCompletionSound {
    if (!self.soundEnabled || !self.soundPath.length) return;
    if (![[NSFileManager defaultManager] fileExistsAtPath:self.soundPath]) return;
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    if (self.lastSoundAt > 0 && now - self.lastSoundAt < kMinSoundGap) return;  // 防抖，避免连响
    self.lastSoundAt = now;
    NSSound *s = [[NSSound alloc] initWithContentsOfFile:self.soundPath byReference:YES];
    if (!s) return;
    self.player = s;              // 必须持有，否则声音会被提前释放（只响半声或干脆不响）
    [s play];
}

- (void)toggleSound:(id)sender {
    self.soundEnabled = !self.soundEnabled;
    [self saveSoundPrefs];
    [self refreshSoundMenuItems];
    if (self.soundEnabled) {
        self.lastSoundAt = 0;     // 开启时立刻响一声，马上知道听不听得到
        [self playCompletionSound];
    }
}

- (void)selectSound:(id)sender {
    if (![sender isKindOfClass:[NSMenuItem class]]) return;
    id rep = [(NSMenuItem *)sender representedObject];
    if (![rep isKindOfClass:[NSString class]] || ![(NSString *)rep length]) return;
    self.soundPath = rep;
    self.soundEnabled = YES;       // 选了音就等于要开，符合直觉
    [self saveSoundPrefs];
    [self refreshSoundMenuItems];
    self.lastSoundAt = 0;
    [self playCompletionSound];    // 点一下即试听
}

- (void)previewSound:(id)sender {
    BOOL keep = self.soundEnabled;
    self.soundEnabled = YES;
    self.lastSoundAt = 0;
    [self playCompletionSound];
    self.soundEnabled = keep;
}

// ================= Codex 真实用量（5 小时窗口 / 本周）=================
// 数据源：GET https://chatgpt.com/backend-api/wham/usage
// 凭据：只读 ~/.codex/auth.json（不改写，避免影响 Codex 自身登录态）

- (void)startUsageTimer {
    [self fetchUsage];
    // 60 秒一拉：这个接口是「我主动拉取」不是推送，分钟级变化（14 分 → 13 分）一分钟一次刚好
    self.usageTimer = [NSTimer scheduledTimerWithTimeInterval:60.0
                                                       target:self
                                                     selector:@selector(fetchUsage)
                                                     userInfo:nil
                                                      repeats:YES];
    self.usageTimer.tolerance = 5.0;
}

- (void)fetchUsage {
    if (self.usageFetching) return;
    self.usageFetching = YES;

    NSString *authPath = [NSHomeDirectory() stringByAppendingPathComponent:@".codex/auth.json"];
    NSData *data = [NSData dataWithContentsOfFile:authPath];
    NSDictionary *auth = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    NSDictionary *tokens = [auth[@"tokens"] isKindOfClass:NSDictionary.class] ? auth[@"tokens"] : nil;
    NSString *token = tokens[@"access_token"];
    NSString *account = tokens[@"account_id"];
    if (!token.length) {
        self.usageFetching = NO;
        [self setUsageLine:@"用量：未登录 Codex" week:@"登录后自动显示"];
        return;
    }

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:
        [NSURL URLWithString:@"https://chatgpt.com/backend-api/wham/usage"]];
    req.timeoutInterval = 15.0;
    [req setValue:[@"Bearer " stringByAppendingString:token] forHTTPHeaderField:@"Authorization"];
    if (account.length) [req setValue:account forHTTPHeaderField:@"chatgpt-account-id"];
    [req setValue:@"codex-cli/0.163.0" forHTTPHeaderField:@"User-Agent"];
    [req setValue:@"application/json" forHTTPHeaderField:@"Accept"];

    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req
        completionHandler:^(NSData *body, NSURLResponse *resp, NSError *err) {
            NSInteger code = [resp isKindOfClass:NSHTTPURLResponse.class]
                ? [(NSHTTPURLResponse *)resp statusCode] : 0;
            NSDictionary *json = body.length
                ? [NSJSONSerialization JSONObjectWithData:body options:0 error:nil] : nil;
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) self = weakSelf;
                if (!self) return;
                self.usageFetching = NO;
                if (code == 200 && [json isKindOfClass:NSDictionary.class]) {
                    [self applyUsage:json];
                } else if (code == 401) {
                    [self setUsageLine:@"用量：登录已过期" week:@"打开 Codex 刷新后自动恢复"];
                } else if (self.usageFetchedAt <= 0) {
                    // 首次就失败：如实说不可用，不编数字
                    [self setUsageLine:@"用量：暂不可用" week:@"网络恢复后自动重试"];
                }
                // 已有真实数据时网络失败：保留上次结果，不显示假 0
            });
        }];
    [task resume];
}

- (void)applyUsage:(NSDictionary *)json {
    NSDictionary *rl = [json[@"rate_limit"] isKindOfClass:NSDictionary.class] ? json[@"rate_limit"] : nil;
    NSDictionary *primary = [rl[@"primary_window"] isKindOfClass:NSDictionary.class] ? rl[@"primary_window"] : nil;
    NSDictionary *secondary = [rl[@"secondary_window"] isKindOfClass:NSDictionary.class] ? rl[@"secondary_window"] : nil;

    NSString *five = @"5小时剩余：--";
    NSString *week = @"本周剩余：--";
    if (primary) {
        NSInteger used = [primary[@"used_percent"] integerValue];
        NSInteger left = MAX(0, MIN(100, 100 - used));
        self.fiveHourLeft = left;   // 同步到菜单栏 C 旁边（renderStatusTitle 读取）
        self.fiveHourReset = [self resetClockFrom:primary];   // 重置时间点，如 22:00
        five = [NSString stringWithFormat:@"5小时剩余：%ld%% · %@",
                (long)left, [self formatResetAfter:primary[@"reset_after_seconds"]]];
    }
    if (secondary) {
        NSInteger used = [secondary[@"used_percent"] integerValue];
        NSInteger left = MAX(0, MIN(100, 100 - used));
        self.weekLeft = left;   // 同步到菜单栏 C 旁边
        week = [NSString stringWithFormat:@"本周剩余：%ld%% · %@",
                (long)left, [self formatResetAfter:secondary[@"reset_after_seconds"]]];
    }
    self.usageFetchedAt = [NSDate date].timeIntervalSince1970;
    [self setUsageLine:five week:week];
}

// 5 小时窗口的重置时间点，换算成本地时钟 HH:mm；取不到就退回「当前时间 + 剩余秒数」
- (NSString *)resetClockFrom:(NSDictionary *)window {
    NSNumber *resetAt = [window[@"reset_at"] isKindOfClass:NSNumber.class] ? window[@"reset_at"] : nil;
    NSNumber *after = [window[@"reset_after_seconds"] isKindOfClass:NSNumber.class] ? window[@"reset_after_seconds"] : nil;
    NSDate *date = nil;
    if (resetAt && resetAt.doubleValue > 0) {
        date = [NSDate dateWithTimeIntervalSince1970:resetAt.doubleValue];
    } else if (after) {
        date = [NSDate dateWithTimeIntervalSinceNow:after.doubleValue];
    }
    if (!date) return @"";
    NSDateFormatter *fmt = [NSDateFormatter new];
    fmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    fmt.timeZone = [NSTimeZone localTimeZone];
    fmt.dateFormat = @"HH:mm";
    return [fmt stringFromDate:date];
}

- (NSString *)formatResetAfter:(NSNumber *)secs {
    NSInteger s = [secs isKindOfClass:NSNumber.class] ? secs.integerValue : 0;
    if (s <= 0) return @"即将重置";
    if (s >= 86400) return [NSString stringWithFormat:@"%ld 天 %ld 小时后重置", (long)(s / 86400), (long)((s % 86400) / 3600)];
    if (s >= 3600) return [NSString stringWithFormat:@"%ld 小时 %ld 分后重置", (long)(s / 3600), (long)((s % 3600) / 60)];
    return [NSString stringWithFormat:@"%ld 分钟后重置", (long)MAX(1, (s + 59) / 60)];
}

- (void)setUsageLine:(NSString *)five week:(NSString *)week {
    self.lastFiveLine = five;
    self.lastWeekLine = week;
    [self renderUsageLines];
    if (getenv("CODEX_LIGHT_DEBUG")) NSLog(@"[usage] %@ | %@", five, week);
}

// 菜单用量两行：百分比染色；5 小时行在 0% 时黄色呼吸（与菜单栏 C 同一个呼吸帧）
// 文案还没生成（启动头几秒）时直接跳过，不能拿 nil 建 attributed string
- (void)renderUsageLines {
    if (self.lastFiveLine) [self renderUsageField:self.usageFiveField text:self.lastFiveLine
                                        baseColor:[NSColor labelColor] breathing:(self.fiveHourLeft == 0)];
    if (self.lastWeekLine) [self renderUsageField:self.usageWeekField text:self.lastWeekLine
                                        baseColor:[NSColor secondaryLabelColor] breathing:NO];   // 本周不参与呼吸
}

// 只把百分比数字（含 %）染色：平时绿色；breathing=YES（5小时=0%）时黄色并按呼吸亮度忽明忽暗，
// 其余文字保持原来的黑白层级（2026-10-26 刚哥指定：菜单里的 0% 也要呼吸）
- (void)renderUsageField:(NSTextField *)field text:(NSString *)text baseColor:(NSColor *)baseColor breathing:(BOOL)breath {
    NSMutableAttributedString *a = [[NSMutableAttributedString alloc] initWithString:text
        attributes:@{NSFontAttributeName: field.font, NSForegroundColorAttributeName: baseColor}];
    NSRange pct = [text rangeOfString:@"%"];
    if (pct.location != NSNotFound) {
        NSUInteger start = pct.location;
        while (start > 0) {
            unichar c = [text characterAtIndex:start - 1];
            if (c >= '0' && c <= '9') start--; else break;
        }
        NSRange numberRange = NSMakeRange(start, pct.location - start + 1);
        NSColor *numColor = [NSColor systemGreenColor];
        if (breath) numColor = [[NSColor systemYellowColor] colorWithAlphaComponent:[self breathAlpha]];
        [a addAttribute:NSForegroundColorAttributeName value:numColor range:numberRange];
    }
    field.attributedStringValue = a;
}

- (void)startBlink {
    if (self.blinkTimer) return;
    self.blinkTimer = [NSTimer timerWithTimeInterval:kBlinkInterval target:self selector:@selector(tickBlink) userInfo:nil repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:self.blinkTimer forMode:NSRunLoopCommonModes];
}

- (void)stopBlink {
    [self.blinkTimer invalidate];
    self.blinkTimer = nil;
}

- (void)tickBlink {
    self.blinkOn = !self.blinkOn;
    [self renderStatusTitle];
    // V1.1：状态词不闪了，不用跟着闪烁帧重画这一行
}

// ===== 5小时额度耗尽（0%）→ 黄色呼吸（2026-10-25 刚哥定） =====
// 只作用于菜单栏的「0%」两个字：黄色、alpha 按余弦 0.25↔1.0 缓慢往复（周期 2.6s），
// 与忙闲绿闪（0.55s 硬切）完全独立；重置时间点和 /本周% 不参与。

// 0% 才需要呼吸；有量了就停掉并恢复常亮
- (void)updateBreathTimer {
    BOOL need = (self.fiveHourLeft == 0);
    if (need && !self.breathTimer) {
        self.breathStart = CFAbsoluteTimeGetCurrent();
        self.breathTimer = [NSTimer timerWithTimeInterval:kBreathTick target:self
                                                 selector:@selector(tickBreath) userInfo:nil repeats:YES];
        [[NSRunLoop mainRunLoop] addTimer:self.breathTimer forMode:NSRunLoopCommonModes];
    } else if (!need && self.breathTimer) {
        [self.breathTimer invalidate];
        self.breathTimer = nil;
        [self renderStatusTitle];   // 停呼吸后立刻按常亮色重画，不留暗帧
    }
}

- (void)tickBreath {
    [self renderStatusTitle];   // renderStatusTitle 内部读 breathAlpha，0% 时每帧重画
    [self renderUsageLines];    // 菜单里「5小时剩余：0%」的黄字同步呼吸（2026-10-26 刚哥指定）
}

// 当前呼吸亮度：cos 从 1 → -1 → 1，映射到 0.25 ~ 1.0，起止都是全亮，明暗过渡平滑
- (CGFloat)breathAlpha {
    if (!self.breathTimer) return 1.0;
    CGFloat t = fmod(CFAbsoluteTimeGetCurrent() - self.breathStart, kBreathPeriod) / kBreathPeriod;
    return 0.25 + 0.75 * (0.5 - 0.5 * cos(2.0 * M_PI * t));
}

// 状态行：V1.3（2026-10-27 刚哥定）——参考 WB小灯 面板：忙时「工作中 · 已忙 X 分 X 秒」
// （文字白、只有时长的两个数字绿），闲时「闲置中」；原「最近活动：…前」整行废弃（前后台都去掉）
- (void)renderDetailLine {
    if (!self.busy) {
        self.detailField.attributedStringValue = [[NSAttributedString alloc]
            initWithString:@"闲置中"
                attributes:@{NSFontAttributeName: self.detailField.font,
                             NSForegroundColorAttributeName: [NSColor labelColor]}];
        return;
    }
    NSTimeInterval secs = [NSDate date].timeIntervalSince1970 - self.busySince;
    long mins = (long)floor(secs / 60), ss = (long)fmod(secs, 60);
    NSString *pre = @"工作中 · 已忙 ", *m1 = @" 分 ", *m2 = @" 秒";
    NSMutableAttributedString *a = [[NSMutableAttributedString alloc]
        initWithString:[NSString stringWithFormat:@"%@%ld%@%ld%@", pre, mins, m1, ss, m2]
            attributes:@{NSFontAttributeName: self.detailField.font,
                         NSForegroundColorAttributeName: [NSColor labelColor]}];
    NSString *ms = [NSString stringWithFormat:@"%ld", mins], *xs = [NSString stringWithFormat:@"%ld", ss];
    [a addAttribute:NSForegroundColorAttributeName value:[NSColor systemGreenColor]
              range:NSMakeRange(pre.length, ms.length)];
    [a addAttribute:NSForegroundColorAttributeName value:[NSColor systemGreenColor]
              range:NSMakeRange(pre.length + ms.length + m1.length, xs.length)];
    self.detailField.attributedStringValue = a;
}

- (void)renderStatusTitle {
    NSColor *base = self.busy ? [NSColor colorWithCalibratedRed:0.24 green:0.95 blue:0.42 alpha:1.0]
                              : [NSColor colorWithCalibratedRed:1.0 green:0.28 blue:0.24 alpha:1.0];
    NSColor *color = (self.busy && !self.blinkOn) ? [base colorWithAlphaComponent:0.22] : base;
    NSMutableAttributedString *title = [[NSMutableAttributedString alloc] initWithString:@"C"];
    NSRange all = NSMakeRange(0, title.length);
    [title addAttribute:NSFontAttributeName value:[NSFont systemFontOfSize:15 weight:NSFontWeightHeavy] range:all];
    [title addAttribute:NSForegroundColorAttributeName value:color range:all];
    // C 旁边挂剩余额度：`C 46% 22:00 / 80%` ——
    // 5小时剩余 + 它的重置时间点（本地时钟），斜杠后=本周剩余；
    // 各自独立染色：≥10% 绿、<10% 红；0% 黄色呼吸；百分比本身不随忙闲闪（2026-10-22/25 刚哥定）
    NSFont *pctFont = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
    if (self.fiveHourLeft >= 0) {
        NSColor *fiveColor = self.fiveHourLeft < 10
            ? [NSColor colorWithCalibratedRed:1.0 green:0.30 blue:0.28 alpha:1.0]
            : [NSColor colorWithCalibratedRed:0.30 green:0.95 blue:0.45 alpha:1.0];
        // 5小时额度耗尽（0%）特例：百分比染成黄色并按呼吸亮度忽明忽暗（updateBreathTimer 驱动）；
        // 重置时间点仍保持红色常亮，不受呼吸影响（2026-10-25 刚哥定）
        NSColor *pctColor = fiveColor;
        if (self.fiveHourLeft == 0)
            pctColor = [[NSColor systemYellowColor] colorWithAlphaComponent:[self breathAlpha]];
        NSString *pct = [NSString stringWithFormat:@" %ld%%", (long)self.fiveHourLeft];
        NSRange r1 = NSMakeRange(title.length, pct.length);
        [title appendAttributedString:[[NSAttributedString alloc] initWithString:pct]];
        [title addAttribute:NSFontAttributeName value:pctFont range:r1];
        [title addAttribute:NSForegroundColorAttributeName value:pctColor range:r1];

        if (self.fiveHourReset.length) {
            NSString *reset = [NSString stringWithFormat:@" %@", self.fiveHourReset];
            NSRange r2 = NSMakeRange(title.length, reset.length);
            [title appendAttributedString:[[NSAttributedString alloc] initWithString:reset]];
            [title addAttribute:NSFontAttributeName value:pctFont range:r2];
            [title addAttribute:NSForegroundColorAttributeName value:fiveColor range:r2];
        }
    }
    if (self.weekLeft >= 0) {
        NSColor *weekColor = self.weekLeft < 10
            ? [NSColor colorWithCalibratedRed:1.0 green:0.30 blue:0.28 alpha:1.0]
            : [NSColor colorWithCalibratedRed:0.30 green:0.95 blue:0.45 alpha:1.0];
        NSString *weekPiece = [NSString stringWithFormat:@" / %ld%%", (long)self.weekLeft];
        NSRange r3 = NSMakeRange(title.length, weekPiece.length);
        [title appendAttributedString:[[NSAttributedString alloc] initWithString:weekPiece]];
        [title addAttribute:NSFontAttributeName value:pctFont range:r3];
        [title addAttribute:NSForegroundColorAttributeName value:weekColor range:r3];
    }
    self.item.button.image = nil;
    self.item.button.attributedTitle = title;
    self.item.button.toolTip = self.busy ? @"Codex 正在干活" : @"Codex 闲置";
}

- (NSString *)sessionIDFromPath:(NSString *)path {
    NSString *name = path.lastPathComponent.stringByDeletingPathExtension;
    NSRange r = [name rangeOfString:@"rollout-" options:0];
    if (r.location != NSNotFound && name.length > 44) {
        NSString *tail = [name substringFromIndex:MAX((NSUInteger)0, name.length - 36)];
        if ([tail containsString:@"-"]) return tail;
    }
    return @"";
}

- (NSArray<NSDictionary *> *)sessionIndexEntries {
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@".codex/session_index.jsonl"];
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    if (!text.length) return @[];
    NSMutableArray<NSDictionary *> *entries = [NSMutableArray array];
    NSArray<NSString *> *lines = [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    NSInteger start = MAX(0, (NSInteger)lines.count - 300);
    for (NSInteger i = start; i < (NSInteger)lines.count; i++) {
        NSString *line = lines[i];
        if (!line.length) continue;
        NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([obj isKindOfClass:NSDictionary.class]) [entries addObject:obj];
    }
    return entries;
}

- (void)updateCurrentTitleAndAction {
    NSString *sid = [self sessionIDFromPath:self.lastSessionPath ?: @""];
    self.currentTitle = sid.length ? sid : @"未检测";
    for (NSDictionary *entry in [self.sessionIndexEntries reverseObjectEnumerator]) {
        if ([entry[@"id"] isEqualToString:sid]) {
            NSString *title = entry[@"thread_name"];
            if (title.length) self.currentTitle = title;
            break;
        }
    }
    self.lastActionText = [self latestActionTextFrom:self.lastSessionPath];
}

- (NSString *)latestActionTextFrom:(NSString *)path {
    if (!path.length) return @"等待中";
    NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:path];
    if (!fh) return @"等待中";
    unsigned long long size = [fh seekToEndOfFile];
    unsigned long long offset = size > 65536 ? size - 65536 : 0;
    [fh seekToFileOffset:offset];
    NSData *data = [fh readDataToEndOfFile];
    NSString *tail = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSArray<NSString *> *lines = [tail componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    for (NSInteger i = (NSInteger)lines.count - 1; i >= 0; i--) {
        NSString *line = lines[i];
        if (!line.length || ![line hasPrefix:@"{"]) continue;
        NSDictionary *obj = [NSJSONSerialization JSONObjectWithData:[line dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        if (![obj isKindOfClass:NSDictionary.class]) continue;
        NSString *type = obj[@"type"];
        NSDictionary *payload = [obj[@"payload"] isKindOfClass:NSDictionary.class] ? obj[@"payload"] : nil;
        NSString *ptype = payload[@"type"];
        NSString *name = payload[@"name"];
        if ([ptype isEqualToString:@"function_call"] || [type isEqualToString:@"function_call"]) {
            return name.length ? [NSString stringWithFormat:@"调用工具 %@", name] : @"调用工具";
        }
        if ([ptype isEqualToString:@"message"]) return @"正在回复 / 已回复";
        if ([type isEqualToString:@"event_msg"]) return @"状态更新";
        if ([type isEqualToString:@"response_item"]) return @"生成内容";
    }
    return @"等待中";
}

- (NSArray<NSDictionary *> *)tailEventObjectsFrom:(NSString *)path bytes:(unsigned long long)bytes {
    NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:path];
    if (!fh) return @[];
    unsigned long long size = [fh seekToEndOfFile];
    unsigned long long offset = size > bytes ? size - bytes : 0;
    [fh seekToFileOffset:offset];
    NSData *data = [fh readDataToEndOfFile];
    NSString *tail = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!tail.length) return @[];
    NSMutableArray<NSDictionary *> *events = [NSMutableArray array];
    NSArray<NSString *> *lines = [tail componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    for (NSString *line in lines) {
        if (!line.length || ![line hasPrefix:@"{"]) continue;
        NSDictionary *obj = [NSJSONSerialization JSONObjectWithData:[line dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        if ([obj isKindOfClass:NSDictionary.class]) [events addObject:obj];
    }
    return events;
}

- (void)openFastCom:(id)sender {
    // fast.com：Netflix 的测速页，交给默认浏览器打开
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://fast.com"]];
}

- (void)openCodex:(id)sender {
    [[NSWorkspace sharedWorkspace] launchApplication:@"Codex"];
}

- (void)quit:(id)sender {
    [NSApp terminate:nil];
}

// 重启自己：先以「新实例」方式把本 app 再拉起一份，等它真起来了再退出当前实例
// 两个关键点：
// 1) createsNewApplicationInstance 必须设 YES —— 否则系统看到"已在运行"就不会开新的，等效于退出
// 2) 不能在发起启动后立刻 terminate —— 启动请求是异步的，进程一死请求被掐掉，表现就是"点了没反应"。
//    必须在 completionHandler 里确认新实例已拉起，再延迟一点点退出（2026-10-25 修）
- (void)restartApp:(id)sender {
    NSURL *selfURL = [NSURL fileURLWithPath:[[NSBundle mainBundle] bundlePath]];
    NSWorkspaceOpenConfiguration *conf = [NSWorkspaceOpenConfiguration configuration];
    conf.createsNewApplicationInstance = YES;
    [[NSWorkspace sharedWorkspace] openApplicationAtURL:selfURL
                                          configuration:conf
                                      completionHandler:^(NSRunningApplication *app, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error || !app) {
                // 兜底：走 open -n 拉新实例
                NSTask *task = [[NSTask alloc] init];
                task.launchPath = @"/usr/bin/open";
                task.arguments = @[@"-n", selfURL.path];
                [task launch];
            }
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                [NSApp terminate:nil];
            });
        });
    }];
}

@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        AppDelegate *delegate = [AppDelegate new];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}

```

---

## 4. 编译 / 打包 / 调参

### 编译

```bash
cd ~/Documents/Work/大AI开发/Codex小灯
clang -fobjc-arc -framework Cocoa -o Codex小灯 源码/Codex小灯.m

# 要给别人用（Intel 也能跑），加 -arch：
clang -fobjc-arc -framework Cocoa -arch arm64 -arch x86_64 -o Codex小灯 源码/Codex小灯.m
lipo -info Codex小灯     # 期望输出 x86_64 arm64
```

### 打成 App

```bash
mkdir -p "Codex小灯.app/Contents/MacOS" "Codex小灯.app/Contents/Resources"
cp Codex小灯 "Codex小灯.app/Contents/MacOS/Codex小灯"
cp 源码/Resources/*.png "Codex小灯.app/Contents/Resources/"
codesign --force --deep -s - "Codex小灯.app"
xattr -cr "Codex小灯.app"      # 清隔离标记，见第 4.1
open "Codex小灯.app"
```

`Info.plist` 关键项（当前值）：`CFBundleIdentifier = local.codex.light`、
`CFBundleShortVersionString = 0.5`、`LSUIElement = true`（不占 Dock）。

### 4.1 发给别人用（交付前必看）

App 是 ad-hoc 自签名（`Signature=adhoc, linker-signed`），没有公证。别人从微信/浏览器收到后会被打上隔离标记，**双击一定被拦**。

**顺序不能反 —— 必须先删隔离标记，再双击**（这条在 WB小灯 上实测过，可复现）：

| 操作顺序 | 结果 |
|---------|------|
| 先 `xattr -cr "Codex小灯.app"`，再双击 | ✅ 正常打开 |
| 先双击（被拦一次）→ 再 `xattr -cr` | ❌ 报 `Operation not permitted`，删不掉、仍打不开 |

补救：把这份 .app 删掉，从 zip 重新解压一份干净的，再走「先删标记」；
或走 系统设置 → 隐私与安全性 →「仍要打开」。

给使用者的口令（可直接转发）：

> 解压后**先别双击**。开「终端」，敲 `xattr -cr `（cr 后有一个空格），把 Codex小灯拖进终端窗口，回车。
> 然后再双击，菜单栏出 C 即可。若已双击被拦：删掉它，重新解压一份再做这步。

### 4.2 可调参数（源码顶部）

| 参数 | 当前值 | 作用 | 建议 |
|------|--------|------|------|
| `kPollInterval` | 1.0 秒 | 状态巡检间隔 | 保持 |
| `kBlinkInterval` | 0.55 秒 | 绿灯闪烁半周期 | 保持 |
| `kStaleBusyWindow` | 180 秒 | 日志多久没更新算「整个会话闲着」 | 保持 |
| `kUnfinishedTurnTimeout` | 30 秒 | 回合内多久没新事件就停闪 | **建议 180**（见第 6 节） |
| `kMinSoundGap` | 2 秒 | 两声提示音之间至少隔多久 | 嫌吵调大，嫌慢调小 |

---

## 5. 怎么自证（当前是缺口）

WB小灯 的教训：**没有自测的判定逻辑 = 不可信**。它现在只能靠肉眼盯灯，没法回答「它到底准不准」。

建议补三个模式（WB小灯 已有，可直接照搬思路）：

| 模式 | 作用 |
|------|------|
| `--selftest` | 一组断言：数据源可读、turn_id 能取到、时间戳能解析、各判定分支（忙/闲/兜底/打断）、文案。返回失败数，不弹窗 |
| `--replay` | 读真实日志全量重放，逐行算灯色 → 输出「交付事件 N 次，正确判红 N 次，假绿 0 次」 |
| `--state` | 打一行当前状态（在线/忙/依据/末事件年龄），方便采样与写进日志 |

补上之后，任何改动的效果都能用数字说话，而不是「我觉得现在不闪了」。

---

## 6. 已知问题与修复建议（W 实测，2026-10-12）

### ① 30 秒兜底太激进 → 会误红（必修）

`kUnfinishedTurnTimeout = 30` 意味着：回合内只要 30 秒没有新事件，灯就转红。但 Codex 长思考、跑长命令时，事件间隔经常超过 30 秒。

实测（本机最大会话 13883 行）：

```
回合内相邻事件间隔 30~180 秒：343 次   ← 每一次都会「明明在干活却闪红」
回合内相邻事件间隔 >180 秒  ：121 次   ← 由文件级 180 秒兜底接管，红灯合理
```

**修法**：把 `kUnfinishedTurnTimeout` 提到 180 秒；或者更稳的做法 —— 保留 30 秒用于「无 busy 信号」的场景，只要回合内存在 `busy` 信号就交给文件级 180 秒兜底。

### ② 打断（`turn_aborted`）没处理（必修）

日志里有 `turn_aborted` 事件（本机 7 次），是用户按 ESC 打断。当前代码不认识它，打断后回合内不再出现 `task_complete`，只能等 30 秒兜底才转红 → **多绿 30 秒**。

**修法**：识别 `event_msg.turn_aborted` → 立即判闲（WB小灯 对 `Interrupted by user` 就是这么做的，效果是「打断即红」）。

### ③ `task_started` 没当忙信号（建议）

日志里 `task_started` 出现 161 次。它是「回合正式开始」的明确信号，长命令从发起到第一次输出之间可能很久 —— 认它可以让绿灯**更早亮起来**，而不是等第一个 `function_call` 落盘。

### ④ 性能与退化风险（已知边界，暂不必修）

- 每秒对 `~/.codex/sessions` 做**全树枚举 + 按 mtime 排序**。当前 118 个文件无所谓；一年后文件上千，会有可见开销。建议改成「只扫最近 2 天目录」或按 mtime 缓存。
- 每秒读两次日志尾部（512KB 判定 + 64KB 取动作文案）。本机最大文件 511.7 MB 时，512KB 只覆盖**约 13 行**，极端情况下尾部不足以凑出回合信息 → 判定退回「文件 3 秒内写过」的兜底。结果通常仍正确，但面板「依据」会显示得比较粗糙。
- `NSFileHandle` 未显式 `closeFile`（依赖 ARC 回收）。每秒创建两个句柄，不致命，但不够干净。

### ⑤ 交付面

- 二进制**仅 arm64** → Intel Mac 打不开。要给别人就编通用二进制（见 4.1）。
- 无「首次打开必读」随包说明 → 别人双击被拦时无从下手。建议照 WB小灯 的做法，打包时在 app 旁边放一份说明 txt。

---

## 7. 踩坑 / 实测记录

| # | 项 | 结论 |
|---|----|------|
| 1 | 时间戳格式 | 实测 `2026-10-12T04:30:33.817Z`（UTC + 毫秒），与 `yyyy-MM-dd'T'HH:mm:ss.SSS'Z'` 完全匹配。**若 Codex 改格式，`ageOfEvent` 会返回 999999 → 直接误判闲**，建议加一条格式断言 |
| 2 | `turn_id` 位置 | 在 `payload.turn_id`，部分事件藏在 `payload.internal_chat_message_metadata_passthrough.turn_id`。实测两类都存在，代码两处都读了 ✅ |
| 3 | 记账类事件 | `token_count` 高频写入且无 turn_id，代码在尾部回退分支里 `continue` 跳过 ✅ 处理正确 |
| 4 | 完成信号 | `task_complete`（152 次）与 `AgentMessage` final（158 次）两个信号互为备份，不会出现「判不出完成 → 灯不灭」 |
| 5 | 落盘实时性 | mtime 与末事件时间差 **0.0 秒**，不存在异步批量落盘的滞后问题（WB小灯 那套日志是异步的，Codex 这个不是） |
| 6 | 打断 | `turn_aborted` 存在但未处理 → 见第 6 节 ② |
| 7 | 大文件 | 单会话 511.7 MB，尾部窗口只盖 13 行 → 见第 6 节 ④ |
| 8 | 目录结构 | `sessions/<年>/<月>/<日>/rollout-*.jsonl`，按日期分层 —— 枚举时要能处理深目录（代码用了 `enumeratorAtPath`，✅） |
| 9 | **`NSSound` 没持有住** | 提示音只响半声、或者干脆不响 | `NSSound` 必须是 `strong` 属性。局部变量在方法返回后被 ARC 释放，声音会跟着断 —— 新增提示音时最容易踩 |
| 10 | **判定抖动会连响** | 兜底窗口、打断、连续两轮完工时绿红来回翻 | 加 `kMinSoundGap = 2 秒` 防抖（实测用例 B/C 已覆盖关闭与空闲两种不该响的情况） |
| 11 | 音源清单不该硬编码 | 想换音得改代码 | 扫描 `/System/Library/Sounds`、`/Library/Sounds`、`~/Library/Sounds` 三个目录，往哪个目录丢音频都会自动出现在菜单里 |

---

## 8. 目录与产物

```
Codex小灯/
├── 开发文档-Codex小灯.md        ← 本文件
├── README.md                    ← 原始简短说明
├── 源码/
│   ├── Codex小灯.m              ← 单文件源码（962 行）
│   └── Resources/               ← 早期头像帧（当前 C 字母版不依赖：pet_busy_*.png / pet_idle_gray.png）
├── pet-check/
│   └── current-ggv-spritesheet.png   ← 宠物形象精灵图（2026-10-10，制作中）
└── 发布版/
    ├── Codex小灯.app            ← 双击即用（arm64，版本 1.0）
    ├── Codex小灯                ← 编译出的裸二进制
    ├── 开发文档-Codex小灯.md     ← 与 app 放一起的这一份
    └── Codex小灯-发布版.zip      ← 打包（app + 文档）
```

运行状态：app 正在运行（`发布版/Codex小灯.app`）；源码时间 09-13 21:42、二进制 09-13 21:46 → **app 是当前源码编的，没有落后**。

---

## 9. 后续可选增强

| 想做的事 | 思路 |
|---------|------|
| 换成宠物形象 | `pet-check/current-ggv-spritesheet.png` 已在做精灵图；改为按状态切帧渲染（忙=跑动帧、闲=静帧），替掉现在的 C 字母 |
| 今日活跃统计 | 在 `updateState` 里累计 busy 时长，写 `NSUserDefaults`，面板显示「今天忙了 N 分钟」 |
| 多会话并行 | 现在只盯「最近修改的那个会话」。若同时开多个 Codex 窗口，可改为「任一活跃即忙」，并把当前任务显示成多行 |
| 与 WB小灯 合并 | 两个灯同一套逻辑，可抽成「宿主适配层」：换数据源适配器即可支持 Codex / WorkBuddy / 其他 agent，一个 app 两行图标 |

---

_文档整理：W（WorkBuddy）｜2026-10-12 ｜ 源码作者：Codex_
_本版为「实测审查版」：第 0 / 6 / 7 节的三项必修与实测数据由 W 独立验证得出，尚未改动源码。_
