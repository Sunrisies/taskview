# 任务视图（TaskView）

类 Windows「任务视图」（Win+Tab）的 macOS 多任务窗口管理器：全局快捷键 ⌥Tab 唤起全屏覆盖层，以缩略图网格展示当前桌面空间的所有窗口，方向键 / 鼠标选择，回车聚焦。

## 功能

- **⌥Tab 唤起/关闭**任务视图（默认全局快捷键，可在设置中修改）
- 缩略图网格展示当前空间全部窗口（按前后顺序排列）
- **方向键**选择（左右循环、上下按行）、**回车/空格**打开、**Esc** 关闭
- **鼠标悬停**即选中，**单击**直接打开；点击空白处关闭
- 卡片右上角 **×** 关闭目标窗口；网格焦点下 **⌘⌫** 关闭所选窗口，需要辅助功能权限
- 菜单栏图标：打开任务视图 / 设置 / 权限设置 / 退出
- 菜单栏“关于任务视图…”：查看版本、构建渠道、构建时间与运行位置，并复制信息用于反馈；设置页也显示这些信息
- 原生设置页：快捷键录制与恢复默认、开机自启、悬停选择、背景压暗、缩略图清晰度
- 窗口较多时网格支持滚动，键盘选择自动滚动到目标卡片
- 标题 / 应用名搜索，支持中文、多关键词；⌘F 聚焦搜索，Esc 先清空再关闭
- 所有显示器 / 当前显示器筛选，以及按应用分组；可在任务视图内切换并保存
- 仅为可见卡片加载缩略图，滚动时释放离开视口的图片，最多四路并发
- 首次运行引导「屏幕录制」权限

## 下载安装（普通用户）

到 [GitHub Releases](https://github.com/Sunrisies/taskview/releases) 下载 ZIP 或 DMG，将 `TaskView.app` 拖入“应用程序”后打开。无需拉取源码、安装 Xcode / Python 或导入证书。

当前支持 **macOS 14+、Apple Silicon（M 系列芯片）**。Beta 下载包未经过 Apple 公证，首次打开可能需要在系统“隐私与安全性”中确认；屏幕录制和辅助功能权限仍需由用户授予。

- [详细安装、升级与卸载说明](Docs/安装说明.md)
- [隐私说明](Docs/隐私说明.md)
- [维护者打包和 GitHub 发布步骤](Docs/发布说明.md)

发布附件由维护者生成并上传，本仓库中的源码目录不是可直接运行的安装包。

## 开发环境

- macOS 14.0+，当前默认生成 arm64 应用。
- Xcode 15 或更新的命令行工具，Swift 5.9+。
- Python 3，用于测试、采样和发布脚本。

## 构建与运行

```bash
bash Scripts/install_local_signer.sh # 开发者首次生成 / 安装自己的固定证书（已安装时无需重复）
./Scripts/make_app.sh          # release 构建 → build/TaskView.app
./Scripts/make_app.sh debug    # debug 构建
open build/TaskView.app        # 启动（菜单栏出现图标）
bash Scripts/test.sh          # 加载取消、设置保存、自启状态、窗口匹配测试
bash Scripts/test.sh --ui     # 另加设置控件、快捷键替换、网格布局与导航测试
```

调试参数：

```bash
open build/TaskView.app --args --show   # 启动后 1 秒自动弹出任务视图
open build/TaskView.app --args --settings # 启动后打开设置
```

## 权限（必读）

应用需要两项系统权限，首次启动会自动请求：

| 权限 | 用途 | 授予位置 |
| --- | --- | --- |
| 屏幕录制 | 读取窗口列表、生成缩略图 | 系统设置 → 隐私与安全性 → 屏幕录制 |
| 辅助功能 | 聚焦到指定窗口（精确 raise） | 系统设置 → 隐私与安全性 → 辅助功能 |

授权后需**退出并重新打开**应用。菜单栏图标 →「屏幕录制权限…」可直达设置页。

> 构建必须使用证书签名，默认身份为 `TaskView Local Signer`，不会回退到 ad-hoc 签名。签名失败时保留之前的应用。签名材料位于被 Git 忽略的 `Scripts/signing/`；新克隆的安装脚本会生成自己的本地证书和私钥，再导入登录钥匙串。仅用于开发，不是 Apple Developer ID；下载版用户不要运行这个脚本。也可用 `TASKVIEW_SIGNING_IDENTITY='Developer ID Application: …' ./Scripts/make_app.sh` 指定已有身份。改用证书签名后，需要为新身份重新授权一次；后续仍需保持应用路径与签名身份一致。

## 使用

1. 按 **⌥Tab**（Option + Tab）打开任务视图
2. 方向键或鼠标选择窗口，**回车/单击**聚焦
3. 再按已设置的快捷键关闭；**Esc** 有搜索内容时先清空，再按一次关闭。
4. 直接输入文字或按 **⌘F** 搜索标题 / 应用名。搜索框内 **↑ ↓** 选择结果、**回车** 打开；左右箭头移动输入光标，空格用于分隔关键词。
5. 顶部切换显示器范围或勾选「按应用分组」，对应设置自动保存。当前显示器以此次打开时鼠标所在屏幕为准，跨屏窗口只要与该屏相交就会显示。

关闭窗口时会先收起任务视图，激活目标应用并请求它执行原生关闭按钮动作；未保存内容由目标应用显示保存 / 取消确认。关闭请求成功不代表窗口已经关闭，也不会自动重新弹出任务视图。搜索框中的 ⌘⌫ 保留原生文本编辑行为。

窗口列表加载期间再次按 **⌥Tab** 可取消打开。切换到其他应用时，覆盖层自动关闭。若快捷键注册失败，启动时会提示，仍可通过菜单栏打开。

## 设置

点击菜单栏图标 →「设置…」打开设置窗口。

- **快捷键**：点击当前组合并按下新组合，需包含 Command、Option 或 Control；Esc 取消。注册失败不保存修改，恢复默认也会检查是否被占用。
- **开机自启**：使用系统登录项服务，在登录 macOS 后启动菜单栏应用。开关显示系统真实状态，若显示等待批准，点击「打开系统登录项设置…」完成批准。建议先把 `TaskView.app` 放到固定位置，再开启。
- **显示与操作**：默认窗口范围、应用分组、悬停选择、背景压暗程度、480 / 960 / 1440 像素的缩略图清晰度。自动保存，下次打开任务视图生效；任务视图顶部也能立即切换范围和分组。
- **权限**：显示屏幕录制和辅助功能授权状态，支持跳转系统设置。返回应用时刷新状态。
- 若系统里已授权而应用仍显示未授权，点击「重新检查权限」，通过实际窗口读取接口验证。设置页同时显示当前应用路径，便于确认系统授权的是同一份应用。

快捷键与显示选项保存在应用的 UserDefaults 中；自启状态由系统管理。首次请求权限后，不会在每次登录时重复请求；可随时通过设置页授予权限。

## 实现说明

| 模块 | 职责 |
| --- | --- |
| `GlobalHotKey` | Carbon `RegisterEventHotKey` 全局热键 |
| `WindowList` | `SCShareableContent` 枚举当前空间 layer-0 窗口 |
| `ThumbnailService` | `SCScreenshotManager.captureImage` 单窗口截图 |
| `ThumbnailLoader` | 可见卡片截图调度、并发限制、视口图片淘汰 |
| `WindowQuery` | 标题 / 应用名搜索、显示器筛选和稳定分组 |
| `FocusController` | `NSRunningApplication.activate` + AX raise（标题/几何匹配） |
| `OverlayController` | 覆盖层窗口生命周期、缩略图并发抓取 |
| `OverlayContentView` | 可滚动网格布局、键盘导航和空列表提示 |
| `AppSettings` | 快捷键与显示参数保存、加载和校验 |
| `SettingsWindowController` | AppKit 设置页、快捷键录制、权限状态 |
| `LoginItemController` | 系统登录项注册、取消与真实状态刷新 |
| `WindowMatcher` | 按标题与几何信息选择唯一匹配窗口；关闭使用更严格匹配 |
| `WindowCloseService` | 辅助功能关闭按钮动作、权限 / 按钮错误处理及 AXValue 几何解码 |

技术要点：

- 覆盖层为无边框 `NSWindow`（`canBecomeKey`），层级 `screenSaver`，`moveToActiveSpace + fullScreenAuxiliary`；在不同 Space / 全屏应用下的显示行为需实机验证
- 背景 = `NSVisualEffectView`（fullScreenUI）+ 黑色压暗层
- 窗口标题与缩略图均依赖「屏幕录制」权限；未授权时显示设置引导弹窗，其他读取错误单独提示
- 最多四个窗口截图同时进行，快速开关时也等待旧截图实际返回再释放并发槽位；只保留可见卡片的图片
- 筛选、分组和截图回调均保留原始窗口索引，避免搜索后选错窗口或显示错图

测试不修改真实登录项，也不改用户的已保存设置。自启开启 / 关闭 / 待批准 / 失败分支通过替代服务验证；快捷键替换测试使用替代注册服务，真实系统注册需在正常启动的应用中验证。UI 测试生成 `build/tests/settings-preview.png`。

## 已知限制

- 仅管理**当前桌面空间**的窗口（与系统 Stage Manager/Spaces 行为一致）；跨空间窗口不出现在网格中
- 不含虚拟桌面（Space）的创建/切换——macOS 公开 API 不支持创建桌面
- 「辅助功能」未授权时退化为「激活该 App」，不保证精确 raise 到目标窗口
- 构建脚本当前仅生成 Apple Silicon（arm64）版本
- 首次更换签名身份后可能需重新授予权限；本地自签名版本未进行公证

## 开发文档与性能

- [逐文件开发说明](Docs/开发说明.md)：源码、脚本、证书、测试及生成文件的用途和模块关系。
- [常驻性能与后续计划](Docs/性能与后续计划.md)：空闲与截图阶段的负担、内存估算、实测方法、已知限制和功能建议。

Release 默认关闭文件诊断日志。需要排查时，先退出已有实例，再运行 `open build/TaskView.app --args --debug-log`；Debug 构建默认开启。日志位于 `~/Library/Application Support/TaskView/debug.log`，每个文件上限 1 MiB，仅保留一份备份。

本机空闲采样（需要 Python 3 和可读取进程统计的 macOS 终端）：

```bash
python3 Scripts/profile_idle.py --duration 60 --interval 5
```

当前没有取得小时级常驻性能实测，代码分析与像素内存估算不代表实测结果。

## 生成下载版（维护者）

```bash
python3 Scripts/package_release.py             # 编译、证书签名、生成 Beta ZIP 和 DMG
python3 Scripts/package_release.py --zip-only  # 只生成 ZIP
bash Scripts/publish_github.sh                # 提交源码、推送仓库并发布现有 Beta 附件
```

产物位于 `dist/TaskView-版本-beta.构建号-架构/`，含下载文件、SHA-256 校验值、发布元数据及发布说明。只有应用和用户文档进入下载包；签名验证失败时不会生成新的发布目录。具体步骤见 [发布说明](Docs/发布说明.md)。
