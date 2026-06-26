# Fcitx5 macOS WebDAV 自造词同步插件交接文档

更新时间：2026-06-26

## 用户目标

用户在 macOS 小企鹅输入法、Windows、iOS、Android 等多端使用“小码匠/小鹤类 Rime 自造词”能力，希望把 `dynamic_phrases.txt` 通过 WebDAV 同步起来。

核心要求：

1. 不要让手机端推代码或依赖命令行。
2. macOS 小企鹅输入法插件需要内置 WebDAV 配置窗口。
3. 配置窗口里不要要求用户输入具体 `dynamic_phrases.txt` 文件 URL，只输入 WebDAV 目录。
4. 插件自动在该 WebDAV 目录下管理 `dynamic_phrases.txt`。
5. 同步入口暂定为小企鹅菜单手动触发，不做自动后台同步。
6. 用户明确说过：不要单元测试文件。

## 重要路径

原 Rime 配置目录：

```text
/Users/mac/Library/Rime
```

插件开发工作树：

```text
/Users/mac/.config/superpowers/worktrees/Rime/codex-fcitx5-webdav-addon
```

插件源码目录：

```text
/Users/mac/.config/superpowers/worktrees/Rime/codex-fcitx5-webdav-addon/fcitx5-xmjd-webdav
```

已安装插件：

```text
/Users/mac/Library/fcitx5/lib/fcitx5/libxmjdwebdav.so
/Users/mac/Library/fcitx5/share/fcitx5/addon/xmjdwebdav.conf
```

小企鹅/Fcitx5 macOS App：

```text
/Library/Input Methods/Fcitx5.app
```

Fcitx Rime 用户目录：

```text
/Users/mac/.local/share/fcitx5/rime
```

本机小企鹅自造词文件：

```text
/Users/mac/.local/share/fcitx5/rime/dynamic_phrases.txt
```

WebDAV 插件配置文件：

```text
/Users/mac/.config/fcitx5/conf/xmjdwebdav.conf
```

WebDAV 密码存 macOS 钥匙串：

```text
service: com.xmjd.fcitx5.webdav
account: dynamic-phrases
```

Fcitx 运行日志：

```text
/tmp/Fcitx5.log
```

## 当前实现概要

插件名：`xmjdwebdav`

Fcitx5 addon descriptor：

```text
/Users/mac/.config/superpowers/worktrees/Rime/codex-fcitx5-webdav-addon/fcitx5-xmjd-webdav/fcitx5/addon/xmjdwebdav.conf
```

插件类型：Fcitx5 `SharedLibrary` addon。

菜单项：

1. `同步自造词`
2. `自造词 WebDAV 设置…`

设置窗口：Objective-C++ AppKit 实现，文件：

```text
/Users/mac/.config/superpowers/worktrees/Rime/codex-fcitx5-webdav-addon/fcitx5-xmjd-webdav/src/macos_ui.mm
```

同步逻辑：C++ + libcurl，文件：

```text
/Users/mac/.config/superpowers/worktrees/Rime/codex-fcitx5-webdav-addon/fcitx5-xmjd-webdav/src/webdav_sync.cpp
```

Fcitx addon 入口和菜单 action：

```text
/Users/mac/.config/superpowers/worktrees/Rime/codex-fcitx5-webdav-addon/fcitx5-xmjd-webdav/src/addon.cpp
```

## WebDAV URL 规则

用户现在只需要在设置窗口填写 WebDAV 目录，例如：

```text
https://dav.example.com/xmjd/
```

插件同步时自动转成：

```text
https://dav.example.com/xmjd/dynamic_phrases.txt
```

兼容旧写法：如果用户填完整文件地址：

```text
https://dav.example.com/xmjd/dynamic_phrases.txt
```

插件也接受。

校验规则：

- 只接受 `http://` 或 `https://`
- 不允许 URL authority 中带 `@`，避免把账号密码写进 URL
- 不接受 query/hash
- WebDAV 账号和密码由独立输入框填写

## 同步语义

同步时读取：

1. 本机小企鹅 `~/.local/share/fcitx5/rime/dynamic_phrases.txt`
2. WebDAV 远端 `dynamic_phrases.txt`

然后：

- 解析非注释、非空的 `phrase<TAB>code` 行
- 跳过格式无效行
- 按“本地优先、远端补充”的顺序合并去重
- 写回 WebDAV
- 写回本机

WebDAV 远端不存在时，会自动创建 `dynamic_phrases.txt`。

本机文件不存在时，会自动创建本机 `dynamic_phrases.txt`。

冲突处理：

- GET 远端时记录 ETag
- PUT 时带 `If-Match` 或创建时带 `If-None-Match: *`
- HTTP 412 时重试一次
- 上传后写本机前会重新读取本机，避免网络请求期间新增的本地词被覆盖

当前同步是“增量合并”，不是实时同步。删除暂不做强同步；某端删除的词可能被另一端或远端再次合并回来。

## 已做过的验证

构建命令：

```bash
cd /Users/mac/.config/superpowers/worktrees/Rime/codex-fcitx5-webdav-addon/fcitx5-xmjd-webdav
zsh scripts/build_and_install.sh
```

重启 Fcitx5：

```bash
pkill -TERM -x Fcitx5 || true
sleep 2
open -a '/Library/Input Methods/Fcitx5.app'
```

插件加载查询：

```bash
/Library/Input\ Methods/Fcitx5.app/Contents/bin/fcitx5-curl /config/addon/xmjdwebdav
```

预期返回：

```json
{"ERROR":"Addon \"xmjdwebdav\" is not configurable"}
```

这表示 addon 可被 Fcitx 识别/加载，只是没有接入 Fcitx 通用配置 UI；插件使用自己的菜单配置窗口。

状态栏菜单配置：

```text
StatusBar = Menu
```

曾做过本地 Python WebDAV 模拟服务器集成测试，验证 Basic Auth、ETag 冲突重试、合并写回逻辑通过。

## 最近用户反馈与修复进度

用户反馈：

1. 配置窗口能弹，但输入框聚焦不了。
2. 希望把上下文保存到文件，便于 Claude Code 或新对话读取。
3. iOS 模拟器点 WebDAV 同步时报错：`动态自造词文件存在格式错误，请修正后再同步`。

根因定位：

Fcitx5 macOS 自带配置窗口 `ConfigWindowController.swift` 在打开配置窗口前会执行：

```swift
if NSApp.activationPolicy() != .regular {
  NSApp.setActivationPolicy(.regular)
}
window.makeKeyAndOrderFront(nil)
NSApp.activate(ignoringOtherApps: true)
```

我们的插件之前只做了 `activateIgnoringOtherApps` 和窗口置顶，没有把输入法进程从默认 activation policy 切到 `.regular`，所以窗口能显示但 `NSTextField`/`NSSecureTextField` 不能可靠接收键盘事件。

当前已在源码中修改：

```text
/Users/mac/.config/superpowers/worktrees/Rime/codex-fcitx5-webdav-addon/fcitx5-xmjd-webdav/src/macos_ui.mm
```

新增 `AppActivationGuard`：

- 弹窗前把 `NSApp.activationPolicy` 切到 `NSApplicationActivationPolicyRegular`
- 激活 App
- modal 结束后恢复之前的 policy
- 配置窗口打开时把首个输入框 `urlField` 设为 first responder

这个修改已经写入源码，并已重新构建、安装、重启 Fcitx5。验证输出确认插件已加载。

最近一次安装的插件 SHA256：

```text
07b6477218f6c2ef7fbd2f4e99f8fc69c18677270b1a40294a3058cc12d70cfc  /Users/mac/Library/fcitx5/lib/fcitx5/libxmjdwebdav.so
```

## 2026-06-26 iOS 模拟器同步失败定位

模拟器 App Group：

```text
/Users/mac/Library/Developer/CoreSimulator/Devices/FC041AC7-D6A1-41FB-96A8-FDD3432CF139/data/Containers/Shared/AppGroup/1302FE06-76D0-4814-9075-77EAD0C04F8B
```

当前 iOS 保存的 WebDAV 地址：

```text
https://toi.teracloud.jp/dav/
```

根因：

- iOS 新增的 `DynamicPhraseWebDAVConfiguration` 原先要求“完整文件 URL”，不会像 Fcitx5 插件一样把 WebDAV 目录自动补成 `dynamic_phrases.txt`。
- 用户实际保存的是目录 URL，所以 iOS GET 的是 WebDAV 目录。服务端返回目录页/非 TSV 内容后，iOS 严格解析为 `phrase<TAB>code`，于是报“动态自造词文件存在格式错误”。
- 模拟器本地 `UserData/Rime/dynamic_phrases.txt` 是 UTF-8 且每条非注释行都有一个 TAB，不是本次报错的直接原因。

已在 iOS 仓库修复：

```text
/Users/mac/github/xmjd/xmjd/DynamicPhraseWebDAVSync.swift
/Users/mac/github/xmjd/xmjd/DynamicPhraseWebDAVViewController.swift
```

修复内容：

- iOS 同步配置现在接受 WebDAV 目录或完整文件地址。
- 目录地址自动归一化为 `<目录>/dynamic_phrases.txt`。
- 拒绝 `ftp://`、URL 内嵌账号密码、query、fragment。
- UI 文案从“完整文件地址”改为“WebDAV 目录”，并说明兼容完整文件地址。

验证：

```bash
cd /Users/mac/github/xmjd
xcodebuild -project xmjd.xcodeproj -scheme xmjd -configuration Debug \
  -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
```

结果：`** BUILD SUCCEEDED **`。

补充注意：

- `CODE_SIGNING_ALLOWED=NO` 只能用于编译检查，不适合再手动 `simctl install` 到模拟器验证 App Group。
- 用未签名 `.app` 安装后，`FileManager.containerURL(forSecurityApplicationGroupIdentifier:)` 可能无法得到有效 App Group 容器，导致配置/自造词目录表现异常。
- 模拟器验证应使用正常签名构建：

```bash
cd /Users/mac/github/xmjd
xcodebuild -project xmjd.xcodeproj -scheme xmjd -configuration Debug \
  -destination 'platform=iOS Simulator,id=FC041AC7-D6A1-41FB-96A8-FDD3432CF139' build
xcrun simctl install FC041AC7-D6A1-41FB-96A8-FDD3432CF139 \
  /Users/mac/Library/Developer/Xcode/DerivedData/xmjd-grtwrkasaxpdgrdpzlejjhkpxnah/Build/Products/Debug-iphonesimulator/xmjd.app
```

本轮正常签名安装后的当前 App Group：

```text
/Users/mac/Library/Developer/CoreSimulator/Devices/FC041AC7-D6A1-41FB-96A8-FDD3432CF139/data/Containers/Shared/AppGroup/92BE9937-CB4F-4144-83AC-926085C02B25
```

当前模拟器已恢复：

```text
dynamicPhraseWebDavURL = https://toi.teracloud.jp/dav/
dynamicPhraseWebDavUsername = attiv
UserData/Rime/dynamic_phrases.txt = 只有两行合法 header 的空动态词文件
```

最近一次验证命令输出要点：

```text
[100%] Built target xmjdwebdav
Installed xmjdwebdav. Restart Fcitx5, then use its status-bar menu.
{"ERROR":"Addon \"xmjdwebdav\" is not configurable"}
Iaddonmanager.cpp:204] Loaded addon xmjdwebdav
```

## 后续如需重新验证的命令

```bash
cd /Users/mac/.config/superpowers/worktrees/Rime/codex-fcitx5-webdav-addon/fcitx5-xmjd-webdav
zsh scripts/build_and_install.sh
pkill -TERM -x Fcitx5 || true
sleep 2
open -a '/Library/Input Methods/Fcitx5.app'
sleep 3
/Library/Input\ Methods/Fcitx5.app/Contents/bin/fcitx5-curl /config/addon/xmjdwebdav
tail -80 /tmp/Fcitx5.log | grep -E 'Loaded addon xmjdwebdav|xmjdwebdav'
```

手动 UI 验证：

1. 切换到小企鹅输入法。
2. 打开菜单栏小企鹅图标。
3. 点 `自造词 WebDAV 设置…`。
4. 确认窗口弹出后，`WebDAV 目录` 输入框可以聚焦、能输入文字。
5. 填目录地址，例如 `https://dav.example.com/xmjd/`。
6. 填用户名和密码。
7. 保存后点 `同步自造词`。

## Git 状态注意事项

当前插件源码在独立 worktree 里，很多文件是未跟踪状态。AI 之前没有提交 commit。

如果需要继续开发：

```bash
cd /Users/mac/.config/superpowers/worktrees/Rime/codex-fcitx5-webdav-addon
git status --short
```

不要误以为修改已经提交或合并回 `/Users/mac/Library/Rime` 主工作区。

## 给后续 AI 的注意事项

- 用户偏好中文沟通。
- 用户希望高执行力，不希望反复问无意义确认。
- 用户明确说过不要单元测试文件；可以做手动/集成验证。
- 不要把 Fcitx Rime 目录和鼠须管目录做 symlink。之前调研结论：Rime userdb/LevelDB 并发风险，可能损坏用户词库。
- 插件配置必须有 GUI，不能要求用户命令行配置 WebDAV。
- 目前选择的是菜单手动同步，不是每次输入自动同步。


## 2026-06-26 iOS/Android HTTP 412 补充

用户反馈 iOS 同步失败：`其他设备正在同步，请稍后再试`，但实际没有其它设备同步。

定位：该文案是 iOS 对 HTTP 412 Precondition Failed 的笼统映射。412 来源于 WebDAV 条件写入头（`If-Match` 或 `If-None-Match: *`），不一定表示真有其它设备。TeraCloud 这类 WebDAV 服务可能对条件 PUT 支持不完整，尤其首次创建文件时可能拒绝 `If-None-Match: *`。

已修复：

- iOS：`/Users/mac/github/xmjd/xmjd/DynamicPhraseWebDAVSync.swift`
  - 先保留标准条件 PUT 与一次重试。
  - 如果第二次仍 412，则基于第二次重新 GET 的最新远端内容合并后，做一次无条件兼容 PUT。
  - 成功提示会显示“WebDAV 不接受条件写入，已用兼容方式上传”。
  - 失败文案改为“WebDAV 条件写入失败（HTTP 412）…”，不再误导为一定有其它设备。
- iOS UI：`DynamicPhraseWebDAVViewController.swift` 显示条件重试/兼容上传备注。
- Android：`/Users/mac/AndroidStudioProjects/xmjd/app/src/main/java/com/vitta/xmjd/ime/DynamicPhraseWebDavSync.kt`
  - 同步补上目录 URL 自动追加 `dynamic_phrases.txt`。
  - 同步补上 412 兼容 PUT。
  - 同步更新 Compose 设置页文案。

验证：

```bash
cd /Users/mac/github/xmjd
xcodebuild -project xmjd.xcodeproj -scheme xmjd -configuration Debug   -destination 'platform=iOS Simulator,id=FC041AC7-D6A1-41FB-96A8-FDD3432CF139' build
# 结果：BUILD SUCCEEDED

cd /Users/mac/AndroidStudioProjects/xmjd
./gradlew :app:assembleDebug
# 结果：BUILD SUCCESSFUL in 45s
```
