# 衣橱穿搭（OutfitApp）

个人自用的 iOS 衣服搭配 App：把自己已有的衣物录进本地衣橱，按当天气温与场合，用本地规则从已有衣物里组 1–3 套，并记录每天穿了什么。

全程零费用：免费 Xcode + SwiftUI + SwiftData + 本机存储，不接任何付费服务，不上架 App Store，不上传任何照片或数据。

---

## 1. 现在能做什么（P0 六项）

| 功能 | 入口 | 说明 |
| --- | --- | --- |
| 衣物库 | 衣橱 | 拍照或从相册添加，按品类、主色、季节、厚度、场合打标签，可编辑、归档、删除 |
| 每日推荐 | 今日 | 手动输入气温 + 选场合，从在用衣物里组套，每套给可解释理由，1–3 套一页，可换一套 |
| 手动组套 | 搭配 → 我的搭配 | 自己挑衣物保存成套，可命名、收藏、一键设为今日穿搭 |
| 今日穿搭记录 | 今日 / 日历与我的 | 一天一条，可改；按日历回看、补备注 |
| 灵感收藏 | 搭配 → 灵感收藏 | 手动存图 + 一句可借鉴点 + 关联自有衣物；可从灵感提炼成推荐规则 |
| 数据导出恢复 | 日历与我的 → 我的 | 一键导出 JSON + 图片为单个 zip；导入先校验再替换 |

不做：商城、社交、关注点赞、付费识别、付费订阅、自动抓取小红书/杂志内容、Android 版、多设备同步。

---

## 2. 环境要求

| 项 | 要求 |
| --- | --- |
| Mac | macOS 13.5 及以上（Xcode 15）；macOS 14.5 及以上（Xcode 16） |
| Xcode | **Xcode 15 或更新**（工程用 SwiftData，需要 iOS 17 SDK） |
| iPhone | **iOS 17.0 及以上**（本工程部署目标为 iOS 17.0） |
| 签名 | 免费 Apple ID 即可，个人签名有效期通常约 7 天，到期需连 Mac 重签 |

> 如果你的 iPhone 停在 iOS 16，本工程装不上。此时需要把存储层从 SwiftData 换成 Core Data 并下调部署目标，属于阶段 0 的选型变更，必须先登记再改（见 `PROGRESS.md` 附录B）。

---

## 3. 在 Xcode 里编译与运行

1. 双击打开 `OutfitApp.xcodeproj`。
2. 选中左上角 Target **OutfitApp** → **Signing & Capabilities**：
   - **Team** 选你的 Apple ID（Personal Team）；
   - 如果提示 Bundle ID 冲突，把 **Bundle Identifier** 改成唯一值，例如 `com.yourname.outfitapp`。
3. 连上 iPhone（首次需在手机上「信任此电脑」），在顶部设备选择里选你的手机，点 Run。
4. 首次启动若提示「未受信任的开发者」：iPhone 设置 → 通用 → VPN 与设备管理 → 选中你的 Apple ID → 信任。

命令行编译（可选）：

```bash
xcodebuild -project OutfitApp.xcodeproj \
  -scheme OutfitApp \
  -destination 'generic/platform=iOS' \
  -configuration Debug \
  build
```

只需要模拟器验证时，把 `-destination` 换成 `'platform=iOS Simulator,name=iPhone 16'`。模拟器没有相机，照片只能从相册选。

---

## 4. 使用流程

1. **先录衣物**：衣橱 → 右上 `+` → 拍照/相册 → 填名称、品类、主色、季节、厚度、场合。按 `docs/02-拍照与字段规范.md` 拍，一套 5 件就能开始试。
2. **每天早上**：今日 → 调气温 → 选场合 → 「生成今日推荐」→ 看理由 → 「记今日穿搭」。
3. **自己搭配**：搭配 → 我的搭配 → `+` → 勾选至少 2 件 → 命名保存；之后可一键设为今日穿搭。
4. **存灵感**：搭配 → 灵感收藏 → `+` → 存图 + 写一句能照着穿的要点 + 关联 1 件自有衣物；用久了再从灵感「提炼为规则」。
5. **备份**：日历与我的 → 我的 → 导出备份。备份落在 App 的 `Documents/Backups`，可在「文件」App → 我的 iPhone → 衣橱穿搭 里拷出。

---

## 5. 数据与隐私

- 数据库：SwiftData，存在 App 沙盒内；
- 图片：`Application Support/Images/`，数据库只存文件名；
- 备份：`Documents/Backups/衣橱备份-yyyyMMdd-HHmm.zip`，内含 `backup.json` + `images/`；
- 不发起任何网络请求，不写任何密钥、账号、API Key；
- `.gitignore` 已排除 `xcuserdata`、备份 zip、证书等，个人数据不会进仓库。

---

## 6. 零费用边界

| 项 | 做法 | 费用 |
| --- | --- | --- |
| 开发工具 | 免费 Xcode | 0 |
| 存储 | 本机 SwiftData + 沙盒文件 | 0 |
| 天气 | 手动输入气温，不接天气 API | 0 |
| 推荐 | 本地规则打分，无模型调用 | 0 |
| 签名 | 免费 Apple ID 个人签名（约 7 天有效） | 0 |
| 第三方库 | 无。zip 读写自己实现，只用 Foundation / UIKit / SwiftUI | 0 |

---

## 7. 工程结构

```
OutfitApp.xcodeproj
OutfitApp/
├── App/            入口与四页导航
├── Models/         SwiftData 模型 + 五组标签词表
├── Services/       图片存储、规则推荐引擎、备份导入导出、极简 zip
├── Views/
│   ├── Today/      今日
│   ├── Wardrobe/   衣橱、衣物表单、衣物详情
│   ├── Outfits/    搭配、灵感
│   ├── History/    日历
│   ├── Settings/   规则、词表、备份
│   └── Components/ 通用组件
└── Resources/      Assets（AppIcon、AccentColor）
docs/               阶段规范与手册
PROGRESS.md         按规划书逐项进度
```

---

## 8. 已知限制

- 免费个人签名约 7 天到期，到期 App 打不开，需连 Mac 重新 Run 一次；数据不丢，**重装前先导出备份**。
- 推荐是「排除 → 完整性 → 打分」的规则结果，不是造型AI；规则权重写在 `Services/RecommendationEngine.swift`，可解释、可调。
- 温度靠手动输入，不会自动跟随天气。
- 衣物照片手动拍摄，不做自动抠图（避免引入付费能力）。
