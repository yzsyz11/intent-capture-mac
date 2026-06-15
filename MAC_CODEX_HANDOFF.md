# Intent Capture Mac Handoff

这是从 Windows 机器上先搭好的 macOS Swift/AppKit 版本。请在 Apple Silicon Mac 上继续，不要直接重写项目。

## 目标

打出可安装的 Apple Silicon macOS 安装包：

```text
release/IntentCapture-mac-arm64.dmg
```

并验证安装后能启动、状态栏可用、快捷键/中键交互可用、截图/OCR/取色主流程可跑。

## 当前实现

- Swift + AppKit 状态栏 App
- 动作面板
- 设置窗口
- 区域截图复制
- 区域截图保存
- 区域截图保存并复制
- OCR 识别并复制
- 取色并复制
- 全局快捷键
- 中键短按执行最近动作
- 中键长按打开动作面板
- `.app` 和 `.dmg` 打包脚本
- Developer ID 公证脚本骨架

## 在 Mac 上优先执行

```bash
cd macos/IntentCaptureMac
chmod +x script/build_and_run.sh
bash scripts/verify-macos.sh
```

如果有 Swift 编译错误，先修编译错误，不要改产品方向。

编译检查通过后：

```bash
bash scripts/package-macos.sh
bash scripts/check-package.sh
```

启动验证：

```bash
./script/build_and_run.sh --verify
```

目标输出：

```text
release/IntentCapture-mac-arm64.dmg
```

## 需要重点验证

- App 能打开，并出现在 macOS 状态栏
- 状态栏菜单能打开动作面板和设置
- 默认动作快捷键能执行最近动作
- 动作面板快捷键能打开动作面板
- 中键短按执行最近动作
- 中键长按打开动作面板
- 截图复制能进入区域选择并复制到剪贴板
- 截图保存能写入保存目录
- OCR 能识别区域文字并复制
- 取色能复制 HEX/RGB 色值
- 屏幕录制权限缺失时有可理解提示
- 辅助功能权限缺失时中键监听提示合理

## 权限

截图、OCR、取色需要屏幕录制权限：

```text
系统设置 -> 隐私与安全性 -> 屏幕录制
```

中键监听需要辅助功能权限：

```text
系统设置 -> 隐私与安全性 -> 辅助功能
```

## 当前限制

这个工程是在 Windows 上准备的，尚未在 macOS 上实际运行 `swiftc/codesign/hdiutil`。不要认为 DMG 已经完成，必须在 Mac 上重新编译、打包、启动验证。

脚本默认使用 ad-hoc 签名，适合自己本机测试。如果要发给别人安装，需要 Developer ID 签名和公证：

```bash
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" bash scripts/package-macos.sh
bash scripts/notarize-macos.sh
```

## 不要做的事

- 不要重写成 Electron
- 不要把第一版做成复杂截图编辑器
- 不要加入云同步或复杂历史索引
- 不要把中键当唯一入口，快捷键必须保留
