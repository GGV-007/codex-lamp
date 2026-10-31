# Codex小灯 · 开发需求说明（V0.6）

> 一个 macOS 菜单栏小工具：一眼看出 Codex 是否在干活，以及额度还剩多少。
> 交付物：单文件 Objective-C 源码 + 可直接运行的 .app。零第三方依赖。

---

## 1. 一句话目标

在菜单栏常驻一个图标，同时表达三件事：**Codex 此刻忙不忙**、**5 小时额度剩多少**、**本周额度剩多少**。

## 2. 技术约束

- Objective-C **单文件**（约 800～900 行），ARC + Cocoa，零依赖
- 编译：`clang -fobjc-arc -framework Cocoa -o Codex小灯 Codex小灯.m`
- 打包：`.app`，bundle id `local.codex.light`，`LSUIElement=true`（无 Dock 图标），ad-hoc 签名

## 3. 菜单栏图标

**显示格式：`C 46% 20:22 / 91%`**

| 元素 | 含义 | 颜色 |
|------|------|------|
| `C` | 状态灯 | 忙=绿 `(0.24,0.95,0.42)` 闪烁（alpha 100%↔22%，0.55 秒）；闲=红 `(1.0,0.28,0.24)` 常亮 |
| `46%` | 5 小时额度剩余 | ≥10% 绿 `(0.30,0.95,0.45)`，<10% 红 `(1.0,0.30,0.28)` |
| `20:22` | 该窗口重置时间点 | 本地时区 `HH:mm`，与左侧百分比同色 |
| `/ 91%` | 本周额度剩余 | 独立按同规则染色 |

- 百分比**不闪烁**；数据未获取成功前只显示 `C`，不显示占位值
- 状态项宽度必须自适应（`statusItemWithLength:-1.0`），否则被 24pt 定宽截断；部分 SDK 无 `NSStatusItemVariableLength` 宏，直接写 `-1.0`

## 4. 忙闲判定（读 Codex 会话日志）

- 数据源：`~/.codex/sessions/<年>/<月>/<日>/rollout-*.jsonl`，取 mtime 最新文件，每秒轮询
- 文件 180 秒未更新 → **闲**
- 否则解析尾部 512KB，按 `payload.turn_id` 取**最新回合**判定：
  - 有 `task_complete`，或 `assistant`/`AgentMessage` 且 phase 为 `final` → **闲**
  - 有 `function_call` / `reasoning` / 用户消息 / `CommandExecution` → **忙**
  - 最新回合超 30 秒无完成信号 → 兜底判**闲**
- 事件行分两种：`response_item`（payload.type = message / function_call / reasoning）与 `event_msg`（payload.type = task_complete / token_count / item_completed…），其中 `token_count` 跳过

## 5. 菜单结构（顺序与文案固定）

```
最近活动：0小时0分17秒前 · 进行中      ← 时间固定「X小时X分X秒」；前缀灰字；状态词：进行中=绿且与 C 同步闪烁，已完成=红常亮
当前任务：<任务名>                     ← 取自 ~/.codex/session_index.jsonl 尾部 300 行按会话 id 匹配 thread_name
────────────
5小时剩余：46% · 2小时45分后重置        ← 12pt 半粗，百分比数字绿色
本周剩余：91% · 4天23小时后重置         ← 12pt 灰字，百分比数字绿色
────────────
测试网速                              ← 默认浏览器打开 https://fast.com（菜单不显示网址）
打开 Codex
更换提示音 ▸                          ← 见下
重启 Codex 小灯                       ← 见下
退出 Codex小灯                        ← ⌘Q
```

**「更换提示音」子菜单**：开关项（勾选态同步）→ 分组音源列表（`/System/Library/Sounds`、`/Library/Sounds`、`~/Library/Sounds`；扩展名 aiff/aif/wav/caf/m4a/mp3；按基名去重，系统目录优先）→ `试听当前提示音`。**点任意音名 = 立即试听并设为当前音**。默认音 `/System/Library/Sounds/Tink.aiff`，设置存 `NSUserDefaults` suite `local.codex.light`。

**「重启」**：`NSWorkspaceOpenConfiguration.createsNewApplicationInstance = YES` 先拉新实例，再 `terminate` 旧实例。不设 YES 系统认为已在运行，结果等于只退出。

## 6. 完成提示音

仅在状态**绿→红翻转**时响一声（启动不响、一直闲不响、变绿不响）。`NSSound` 必须用强属性持有，否则提前释放只响半声；两次响声间隔 ≥2 秒防抖。

## 7. 用量接口（外部查不到，照此实现）

- `GET https://chatgpt.com/backend-api/wham/usage`
- 请求头：`Authorization: Bearer <access_token>`、`chatgpt-account-id: <account_id>`、`User-Agent: codex-cli/0.163.0`
- 凭据**只读** `~/.codex/auth.json` 的 `tokens.access_token`、`tokens.account_id`；**绝不写回、绝不自行刷新 token**（会与 Codex 抢登录态，导致用户被踢下线）。token 由 Codex 自己续，续完读到的即为新值
- 返回字段：`rate_limit.primary_window.{used_percent,reset_after_seconds,reset_at}`（5 小时窗口 = 18000 秒）、`rate_limit.secondary_window.*`（本周 = 604800 秒）
- 界面一律显示**剩余 = 100 − used_percent**
- **60 秒主动拉取一次**（接口无推送），启动即拉一次
- 异常处理：首次失败显示「用量：暂不可用」；已有数据后失败**保留上次真实值**（宁旧勿假）；HTTP 401 显示「登录已过期，打开 Codex 后自动恢复」

## 8. 验收标准

1. 菜单栏数字与 Codex 官方面板的剩余用量一致
2. Codex 干活时 `C` 绿闪、菜单「进行中」绿字同闪；干完瞬间转红常亮、「已完成」红字、响一声
3. 断网时数字不清零、不显示假值；token 过期给出明确提示
4. 提示音可关可选，选中即试听；重启能真实拉起新实例
5. 单文件源码，一条 clang 命令编译通过，零依赖
