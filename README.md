# Intent Capture

Intent Capture is a lightweight native macOS utility for effortless screenshot, OCR, and color-picking workflows. It is built to stay out of the way: live quietly in the menu bar, launch actions instantly from hotkeys or the mouse middle button, and finish common capture tasks without opening a heavy editor.

Intent Capture 是一个轻量级 macOS 原生效率工具，用于无感、便捷地完成截图、OCR 文字识别和取色。它安静常驻菜单栏，通过快捷键或鼠标中键快速触发，不打开笨重编辑器也能完成常用捕获动作。

> Status: macOS version is usable as an early open-source build. A Windows version exists on another machine and may be organized later.
>
> 状态：macOS 版本目前是可用的早期开源版本。Windows 版本在另一台电脑上，之后可以再整理成双端项目。

## Features / 功能

- Effortless by default: stays in the menu bar and only appears when you call it
- Fast and convenient: trigger actions with global hotkeys, the action panel, or the mouse middle button
- Lightweight native app: focused on capture, OCR, and color picking without a bulky editing workflow
- Compact action panel for choosing the next task quickly
- Screenshot region to clipboard
- Screenshot region to file
- Screenshot region to file and clipboard
- OCR selected region and copy recognized text
- Pick screen color and copy HEX/RGB values
- Configurable default action, save folder, color format, and hotkeys
- Optional middle-click trigger: short press runs the latest action, long press opens the action panel
- In-app toast messages without relying on macOS notification permission

- 默认无感：常驻菜单栏，不主动打扰，需要时才出现
- 快速便捷：支持全局快捷键、动作面板和鼠标中键触发
- 原生轻量：专注截图、OCR 和取色，不做笨重复杂的编辑器流程
- 紧凑动作面板，快速选择下一步操作
- 框选区域截图并复制
- 框选区域截图并保存
- 框选区域截图，保存并复制
- 框选区域 OCR，并复制识别文字
- 屏幕取色，并复制 HEX/RGB 色值
- 可设置默认动作、保存目录、色值格式和快捷键
- 可选鼠标中键触发：短按执行最近动作，长按打开动作面板
- 应用内轻量提示，不依赖 macOS 系统通知权限

## Requirements / 环境要求

- Apple Silicon Mac
- macOS 13 or later
- Xcode Command Line Tools

Install Command Line Tools:

```bash
xcode-select --install
```

## Build / 构建

Typecheck only:

```bash
bash scripts/verify-macos.sh
```

Build `.app` and `.dmg`:

```bash
bash scripts/package-macos.sh
```

Output:

```text
release/IntentCapture-mac-arm64.dmg
```

Local run helper:

```bash
chmod +x script/build_and_run.sh
./script/build_and_run.sh --verify
```

Note: `script/build_and_run.sh` is a local development helper. It rebuilds the app and replaces `/Applications/IntentCapture.app`.

注意：`script/build_and_run.sh` 是本机开发脚本，会重新构建并替换 `/Applications/IntentCapture.app`。

## Permissions / 权限

Screenshot, OCR, and color picking require Screen Recording permission:

```text
System Settings -> Privacy & Security -> Screen Recording
```

Middle-click global listening requires Accessibility permission:

```text
System Settings -> Privacy & Security -> Accessibility
```

截图、OCR 和取色需要屏幕录制权限：

```text
系统设置 -> 隐私与安全性 -> 屏幕录制
```

鼠标中键全局监听需要辅助功能权限：

```text
系统设置 -> 隐私与安全性 -> 辅助功能
```

## Distribution / 分发

The package script can create a DMG that users can download and install by dragging `IntentCapture.app` into Applications.

```bash
bash scripts/package-macos.sh
```

By default, the app is signed with an ad-hoc identity. That is enough for local testing, but public distribution on macOS should use an Apple Developer ID certificate and notarization to reduce Gatekeeper warnings.

默认脚本使用 ad-hoc 签名，适合本机测试。公开分发给其他 macOS 用户时，建议使用 Apple Developer ID 证书签名并公证，减少 Gatekeeper 拦截。

Build with a Developer ID certificate:

```bash
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" bash scripts/package-macos.sh
```

Notarize:

```bash
export APPLE_ID="you@example.com"
export APPLE_TEAM_ID="TEAMID"
export APPLE_APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"
bash scripts/notarize-macos.sh
```

Do not commit Apple ID credentials or app-specific passwords.

不要把 Apple ID、团队 ID 之外的敏感凭据或 app-specific password 提交到仓库。

## Roadmap / 计划

- Publish signed and notarized macOS releases
- Organize the Windows version into the same public project
- Consider a shared bilingual documentation site after both platforms are stable

- 发布签名并公证的 macOS 安装包
- 后续把 Windows 版本整理进同一个公开项目
- 双端稳定后，再考虑做中英双语文档页

## License / 许可证

MIT License. See [LICENSE](LICENSE).
