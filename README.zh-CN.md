[English](README.md)

# MyStats

轻量级 macOS 原生菜单栏应用，实时监控磁盘与网络状态。

## 功能
- **磁盘用量**：双行显示可用空间与已用空间（GB）
- **网络速度**：实时上传/下载速度，自动切换 B/s、KB/s、MB/s 单位
- **极简设计**：纯 Swift + AppKit，性能开销极低
- **开机自启**：支持 Launch at Login

## 系统要求
- macOS 13 (Ventura) 或更高版本
- Xcode Command Line Tools（用于编译）

## 安装

### 方式 A：Git Clone

```bash
git clone https://github.com/Humsweet/MyStats.git
cd MyStats
```

### 方式 B：下载 ZIP

点击本页面绿色的 **Code** 按钮 → **Download ZIP**，解压后在终端中 `cd` 进入该文件夹。

### 编译

如果还没有安装 Xcode Command Line Tools，先运行：

```bash
xcode-select --install
```

系统会弹出安装对话框，点击「安装」等待完成即可。如果提示已安装则跳过。

然后编译：

```bash
chmod +x scripts/build_app.sh
./scripts/build_app.sh
```

看到 `Done. App is at .../MyStats.app` 表示编译成功。

### 运行

将生成的 `MyStats.app` 拖到 `/Applications`（访达侧栏的「应用程序」），双击打开。

> **注意**：必须放在「应用程序」文件夹中，否则「开机自启」功能会因 macOS 安全限制无法正常工作。

## 使用

状态栏会显示一个紧凑的双行视图：

```
F: 179.89 GB  ● 512 KB/s
U: 300.11 GB  ● 128 KB/s
```

- 上行：可用磁盘空间 (F:) + 上传速度（红色圆点）
- 下行：已用磁盘空间 (U:) + 下载速度（蓝色圆点）
- 点击状态栏图标打开菜单
- 选择 "Settings" 开启/关闭开机自启
- 选择 "Quit" 退出

## 技术细节
- 使用 Swift 5.9 构建，目标平台 macOS 13+
- 通过 `getifaddrs`（BSD socket API）监控网络流量，排除回环接口
- 使用 `SMAppService` 管理开机启动项
- 每秒通过 `Timer` 刷新一次数据
