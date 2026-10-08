# 程序启动台

在 macOS 上打开的全屏应用网格。点击图标启动程序，成功后回到桌面。可以搜索、翻页、放进文件夹、拖拽排序，并调节图标大小。

这不是系统自带的启动台。程序坞里的名字是「程序启动台」。

## 运行环境

macOS 14 或更高版本，以及 Swift 命令行工具。

## 打开

在项目目录执行：

```bash
Scripts/package-app.sh
open MacLaunchpad.app
```

也可以直接运行：

```bash
swift run MacLaunchpad
```

按 Esc 隐藏窗口。按 Command-Q 退出。

## 使用

- 打开后直接打字即可搜索。搜索只过滤当前画面，不改已保存的排列。
- 用鼠标左右拖动整页翻页，松手后吸附到相邻页。触控板左右滑、方向键和底部圆点也可以翻页。
- 在图标上按住约半秒再拖，可以换位。拖到另一个图标中心会建成文件夹。
- 左下角可以调节图标大小，这个大小会记住。图标变大后，一页能放下的数量会减少，并按新容量重新分页。

排列保存在 `~/Library/Application Support/MacLaunchpad/layout.json`。每次打开都会重新扫描本机应用，包括用户应用目录、`/Applications`、`/System/Applications`（含实用工具）以及 Homebrew Cask 安装的应用。

## 测试

```bash
swift test
```
