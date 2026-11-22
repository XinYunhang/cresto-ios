# PROGRESS

> **（11-22）** 塔罗与运势模块已整体下线。第 4 Tab 现为 DeepSeek 峰谷与余额监控页。

## 1. DeepSeek 模块文件

- `Cresto/Views/DeepSeekMonitorView.swift`：第 4 Tab 主页（峰谷卡 + 余额卡 + 错误态 + 手动刷新）
- `Cresto/Services/TariffClock.swift`：`TariffRules`（时段常量表）/ `TariffPeriod`（峰/谷 + 徽章配色）/ `TariffClock`（北京时间判定 + 下次切换计算）
- `Cresto/Services/DeepSeekService.swift`：actor，官方 `GET /user/balance`（Bearer），字符串余额转 Double，错误分型（noKey / 401 / 429 / 5xx / 网络 / 结构）
- `Cresto/Services/KeychainService.swift`：API Key 存取（`ThisDeviceOnly`，service = `com.xinyunhang.cresto.deepseek`）
- `Cresto/Views/SettingsView.swift`：「DeepSeek」分组（SecureField + 保存 / 删除 / 测试连接 + 定价页链接）

峰谷规则（官方定价文档，2026 现行版）：工作日 9–12 / 14–18 峰顶（北京时间）；其余时段 + 周末全天谷价；峰价 = 谷价 × 2。官方改版只改 `TariffRules` 一张表。

## 2. 数据流

```swift
// Key（永不进 UserDefaults / 日志 / 快照导出）
KeychainService.save(_:) / load() / delete()

// 余额（数值是字符串 "5.10"，Double(str) 失败一律显示「—」，严禁强解）
DeepSeekService.shared.fetchBalance() -> BalanceInfo { currency, total?, granted?, toppedUp? }

// 峰谷（纯本地时钟，零 API 调用）
TariffClock.moment(now:) -> TariffMoment { period, isWeekend, secondsUntilSwitch, nextPeriod }
```

## 3. 下一轮（按 Obsidian 07 笔记 §3）

- 轮询 + 余额差值累计消耗：`@Model DeepSeekDay(dateKey, cost)` + lastBalance/lastCheck，前台 Timer 60–300s（做成设置项），窗口 210 天
- 热力图复用 `Theme.HeatScale`，阈值 p40/p75/p99 在数据变化时缓存，渲染只查表
- 服务健康滑动窗口（429/5xx 占比 >30% 标红并降频轮询），与峰谷徽章分开

## 4. 全局样式

文件：`Cresto/DesignSystem/Theme.swift`（未变动）：内容实心磨砂块、卡片无描边无投影、`cardCorner 20 / screenPadding 18 / cardGap 10`。

- 底栏：系统 `UISegmentedControl`，58pt（`GlassTabBar.swift`），Tabs = 概览 / 待办 / 课表 / API（`AppTab`）
- 右下角悬浮锚点：52pt 正圆 FAB，trailing 20 / bottom 80（底栏正上方 16pt），课表页已用（`TimetableView.addButton`），待办添加键与主页交互球复用同一坐标
- 徽章等状态件允许低饱和功能性配色（谷 = 青绿、峰 = 琥珀，`TariffPeriod.bg/fg`），内容区仍黑白
