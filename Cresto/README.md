# Cresto iOS（暂定名）

黑白极简 + iOS 26 液态玻璃。底部玻璃胶囊 + 纯白 FAB，5 个 tab：概览 / 待办 / 课表 / 塔罗 / 时间。

## 现在能真用的

**待办**（SwiftData）
标题、备注、日期 + 具体时间、提醒（准时 / 提前 5·15·30 分钟 / 1 小时 / 1 天）、优先级、重复、标签、子任务。
自动分组逾期/今天/明天/本周/以后/待安排；长按可完成、编辑、删除；重复任务勾完自动生成下一次；本地通知。

**课表**
周视图（行=节次、列=星期，课程块跨行），可切周次，表头高亮今天。
**图片导入**：选课表截图 → Vision 认字 → 「周一…周日」定位列、左侧节次定位行、按坐标落格 → 逐条核对修改 → 入库，同名课自动合并成多个时段。

**塔罗**
22 张大阿尔卡那本地卡面，正逆位各一套关键词和牌义；每日一抽落库（当天重开不变）；牌库页可浏览全部；收牌→洗牌→发牌→3D 翻面。

**今日运势**
`FortuneEngine`：种子 = 生日 + 日期，**同一天刷多少次都一样、断网也一样**，换一天换一套。
生日写在 `Services/FortuneEngine.swift` 的 `birthday`（当前是 2008-06-17）。

**使用时间**
`DailyUsage` 记录本 App 前台秒数（进入前台开始计、退到后台结算、每分钟补记一次）。
热力图等级 = 使用时长（3 小时封顶）55% + 当天待办完成率 45% 的合成。

**快速添加**
FAB 选「今天 / 明天 / 今晚 20:00 / 不设日期」直接加；点「时间、提醒、子任务」原地展开成完整编辑页。课表 tab 下 FAB 变成「添加课程」。

## 在 GitHub 上打包 IPA

仓库里带了 `project.yml`（XcodeGen）和三个 workflow：

- **`Unsigned IPA`**：出未签名 IPA，证书你自己在本地签。**不需要任何 secret**。
  Actions → Unsigned IPA → Run workflow，产物在 Artifacts 里，bundle id 是 `com.nevoit.Cresto`。
- **`Compile check`**：每次 push 自动跑，只验证能不能编译。
- **`Build IPA`**：让 CI 直接出签名版（可选，需要配下面的 secret）。

**如果你要走 CI 签名（可选）**：

**1. 本地把卡面拉下来**（不进仓库，版权原因）：

```bash
bash scripts/fetch_cards.sh
```

**2. 在仓库 Settings → Secrets and variables → Actions 里加这 7 个：**

| Secret | 内容 |
| --- | --- |
| `CERT_P12_BASE64` | `base64 -i cert.p12 \| pbcopy` 的结果 |
| `CERT_PASSWORD` | 导出 p12 时设的密码 |
| `PROFILE_BASE64` | `base64 -i xxx.mobileprovision \| pbcopy` 的结果 |
| `KEYCHAIN_PASSWORD` | 随便一串，CI 里的临时钥匙串 |
| `TEAM_ID` | Apple Developer 的 Team ID（10 位） |
| `BUNDLE_ID` | **必须和 profile 里的 App ID 完全一致** |
| `PROFILE_NAME` | profile 的名字，不是文件名，见下 |

查 profile 名字：

```bash
security cms -D -i xxx.mobileprovision | plutil -extract Name raw -
```

**3. push 到 `main`，或者手动跑一次 workflow。** 产物在 Actions → 这次运行 → Artifacts → `Cresto-ipa`。

几个坑：

- `method` 现在是 `development`，装到真机要求**设备 UDID 已经在 profile 里**。要换 ad-hoc / App Store 就改 `build.yml` 里那两个字符串。
- 免费开发者账号的 profile **7 天过期**，过期后重打一次。
- 签名失败先看 Xcode 里能不能本地跑通，CI 只是把同样的事重复一遍。
- 仓库必须 **public**，私有仓库的 macOS runner 要计费。

## 目录

```
project.yml                           XcodeGen 工程描述
.github/workflows/build.yml           打 IPA 的 workflow
scripts/fetch_cards.sh                拉卡面
Cresto/
  CrestoApp.swift                     容器 + 播种 + 通知权限
  DesignSystem/                       主题 token、液态玻璃底栏
  Models/                             TaskItem / Course / TarotDeck / Usage / AppModels
  Services/                           通知、待办动作、运势引擎、课表 OCR、示例数据
  Views/                              概览 / 待办 / 编辑 / 课表 / 导入 / 塔罗 / 时间
  Resources/Cards/                    22 张卡面（git 忽略）
  docs/ARCHITECTURE.md                数据源、AI、dsh 远程的判断与路线
```

## 还没做

- 重复任务只有「完成后生成下一次」，没有「跳过这次 / 改整个系列」。
- 课表图片识别是启发式的，截图质量差会认错，导入后可能要手改几条。
- 运势只有本地生成，还没接 AI 润色（牌义和运势都是写好的短句）。
- 概览页右上 `terminal` 只有图标（P4 接 dsh 远程）。

## 版权

卡面来自 [tianqiskylord.com/tarot.html](https://tianqiskylord.com/tarot.html)，原站注明「AI 辅助创作 · 非官方 **仅限非商业使用**」，只有大阿尔卡那 22 张。

因此 `.gitignore` 把 `Cresto/Resources/Cards/*.webp` 排除了，公开仓库里只有下载脚本。自己装机用没问题；**别上架、别对外分发**。要换就改 `scripts/fetch_cards.sh` 和目标 slug，代码不用动。

## 视觉参数

| 项 | 值 |
| --- | --- |
| 背景 | `#000000` + 顶部 8.5% 白色柔光 |
| 卡片 | 白 4.5%，1px 白 9% 描边，22 圆角 |
| 文字 | `#FAFAFA` / `#A0A0A0` / `#5C5C5C` |
| 底栏 | 74pt 胶囊，液态玻璃，选中=白 16% |
| FAB | 74pt 纯白圆，黑色加号 |
| 页面边距 / 卡片间距 | 18 / 10 |
