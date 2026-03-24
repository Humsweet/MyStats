# MyStats

A lightweight, native macOS menu bar application to monitor Disk and Network usage.

## Features
- **Disk Usage**: Shows free and used disk space in GB (two-row layout).
- **Network Speed**: Shows real-time upload/download speeds, auto-scaling between B/s, KB/s, and MB/s.
- **Minimalist**: Uses native Swift and AppKit for maximum performance and minimum footprint.
- **Settings**: Simple "Launch at Login" option.

## Requirements
- Mac 电脑，系统版本 macOS 13 (Ventura) 或更高

## Installation

这是一个需要从源码编译的项目，按照下面的步骤一步步来就行。

### 1. 下载代码

**方式 A：用 Git Clone（推荐）**

打开「终端」app（在 启动台 → 其他 → 终端，或者用 Spotlight 搜索 "Terminal"），粘贴以下命令并按回车：

```bash
git clone https://github.com/Humsweet/MyStats.git
```

下载完成后进入项目目录：

```bash
cd MyStats
```

**方式 B：下载 ZIP**

1. 点击本页面绿色的 **Code** 按钮 → **Download ZIP**
2. 解压下载的 ZIP 文件
3. 打开「终端」，输入 `cd `（注意 cd 后面有个空格），然后把解压出来的文件夹拖进终端窗口，按回车

### 2. 安装编译工具

在终端中运行：

```bash
xcode-select --install
```

会弹出一个系统对话框，点击「安装」，等待完成即可。如果提示"已经安装"则跳过此步。

### 3. 编译并生成 App

```bash
chmod +x scripts/build_app.sh
./scripts/build_app.sh
```

等待输出 `Done. App is at .../MyStats.app` 表示编译成功。

### 4. 安装

将项目目录下生成的 `MyStats.app` 拖到 `/Applications`（访达侧栏的「应用程序」文件夹），双击打开即可。

> **Note**: 必须放到「应用程序」文件夹中，否则「开机自启」功能会因 macOS 安全限制而无法正常工作。

## Usage
The status bar item displays a compact two-row view:

```
F: 179.89 GB  ● 512 KB/s
U: 300.11 GB  ● 128 KB/s
```

- Top row: Free disk space (F:) + upload speed (red dot indicator)
- Bottom row: Used disk space (U:) + download speed (blue dot indicator)
- Click the item to open the menu.
- Select "Settings" to enable/disable Launch at Login.
- Select "Quit" to exit.

## Technical Details
- Built with Swift 5.9, targeting macOS 13+.
- Uses `getifaddrs` for network monitoring (low-level BSD socket API), excluding loopback interfaces.
- Uses `SMAppService` for modern login item management.
- Updates every 1 second via a `Timer` on the main run loop.
