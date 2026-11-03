# PSD Mirror

在真实 iPhone 上原生全屏预览 PSD。支持读取已保存的 PSD，也支持通过 Photoshop 插件预览尚未保存的修改。预览界面使用 SwiftUI + UIKit，不依赖 Safari、WebView 或云服务。

## 三个程序的分工

| 程序 | 作用 |
| --- | --- |
| iPhone 应用 PSD Mirror | **显示端**：从 Mac 接收预览，提供全屏、缩放、拖动和横竖屏 |
| Mac 应用 PSD Mirror | **管理与转发端**：读取已保存 PSD 或接收插件画面，通过局域网提供给手机 |
| Photoshop 插件 PSD Mirror | **实时画面采集端**：从当前 PSD 读取包含未保存修改的合成画面，交给 Mac 应用 |

只看已保存 PSD：`PSD 文件 → Mac 应用 → iPhone 应用`。

预览未保存修改：`Photoshop → 插件 → 本机自动连接 → Mac 应用 → iPhone 应用`。

## 文档导航

1. [三者职责与数据流](README/01-三者职责与数据流.md)：先弄清楚三个程序各自负责什么。
2. [日常使用](README/02-日常使用.md)：启动、连接、全屏操作、跟随切换和常见问题。
3. [从零接入与 AI 操作指南](README/03-从零接入与AI操作指南.md)：让另一位使用者或 AI 在新机器上完成自己的账号登录、构建、签名、安装和实时预览验证。
4. [开发与通信协议](README/04-开发与通信协议.md)：目录、工程生成、数据结构、传输边界和集成测试。
5. [GitHub 提交准备](README/05-GitHub提交准备.md)：应提交与忽略的内容、个人信息检查及所有者操作说明。

## 从源码开始

需要完整 Xcode 和 Python 3。原生应用最低运行环境为 macOS 14 / iOS 17；实时模式还需要 Photoshop 25.0 / 2024 或以上和 Adobe 官方 UXP 开发工具。构建工具版本应与目标系统兼容。

```sh
# Mac 与模拟器不需要配置个人 iPhone 开发签名。
zsh Scripts/build.sh mac
zsh Scripts/build.sh simulator

# 真机安装前，复制模板并填写自己的 Team ID 和唯一 Bundle ID。
cp -n Config/Signing.local.xcconfig.example Config/Signing.local.xcconfig
# 编辑 Config/Signing.local.xcconfig，在 Xcode 登录自己的 Apple Account。
zsh Scripts/build.sh ios
```

共享工程不包含个人开发团队；本地签名配置被 Git 忽略。新使用者必须使用自己的 Apple 账号和证书，不应复用作者的签名产物。完整安装、手机信任和插件加载步骤见接入指南。

构建后，双击 `启动Mac端.command`，在手机 PSD Mirror 点击「扫码连接」，扫描电脑窗口中的二维码，自动连接并显示 PSD 列表，点选文件后进入全屏预览。手机不再显示附近 Mac 列表、地址输入框或配对码输入框。需要实时模式时，用 Adobe UXP Developer Tool 加载 `PhotoshopPlugin/manifest.json`，打开插件面板即可自动连接同机的 Mac 应用，无需选择连接文件夹或填写本地路径。

## 范围与运行数据

当前预览整张 PSD 合成画面，支持适应、铺满、1:1 和原生全屏；不提供图层编辑、可点击原型、PSB、单独选择多画板、USB 图像传输或互联网远程预览。

Mac 默认端口为 `48765`，连接地址和当次配对凭据封装在二维码中，Mac 重启后重新扫码。当前使用带配对码的局域网 HTTP，未实现 TLS，应在可信局域网使用。项目不要求开启 SMB 文件共享。

`build/`、下载工具、签名产物、预览缓存、真实设计稿和本地个人配置不提交到 Git。没有这些产物的新克隆应按照文档重新构建，并用 Adobe 官方工具加载插件。`加载Photoshop插件.command` 仅作为已准备好本机旧版 CLI 环境时的快捷方式，不是通用依赖安装器。
