# GitHub 提交准备

本项目的整理工作仅准备本地文件。创建仓库、选择公开或私有、设置远程地址、提交和推送，由项目所有者自行进行。

## 建议提交的内容

提交 `iOS/`、`Mac/`、`Shared/`、`PhotoshopPlugin/` 的源码与图标、`Scripts/`、`Tests/`、`README/`、根目录 `README.md`、`.gitignore`、两个 `.command` 启动脚本，以及可共享的 `PSDMirror.xcodeproj` 工程和 schemes。

`Config/Signing.xcconfig` 与 `Config/Signing.local.xcconfig.example` 也要提交。它们使其他开发者能从模板配置自己的团队，不依赖作者电脑。

## 已忽略的内容

| 类别 | 对应内容 | 原因 |
| --- | --- | --- |
| 构建和缓存 | `build/`、`DerivedData/`、`dist/`、应用包、IPA、归档、调试符号、CCX | 可重新生成，可能包含个人签名、机器路径或预览 |
| 下载的依赖 | `node_modules/`、`.npm/`；本机下载工具也在 `build/` | 新机器自行安装官方工具，不上传整个运行环境 |
| 个人 Xcode 配置 | `xcuserdata/`、用户界面状态与源码管理个人状态 | 避免账号和本机状态污染共享工程 |
| 本地签名配置 | `Config/*.local.xcconfig` | 保存本人的 Team 与 Bundle ID，模板仍保留 |
| 凭据与证书 | `.env` 系列、证书、私钥、签名描述文件等 | 不能作为项目源码分发；`.env.example` 可共享 |
| UXP 与预览运行数据 | `.uxprc`、`PhotoshopBridge/`、`psdmirror-frame.json` | 含本机加载会话，或旧版文件夹中转遗留的设计预览；当前版本不再通过文件夹传输 |
| 私人设计稿 | `*.psd`、`*.psb` | 防止把当前工作素材误传；测试程序会自行生成样本 |
| 系统和编辑器临时文件 | `.DS_Store`、`.idea/`、`.vscode/`、日志和临时文件 | 与可复现源码无关 |

`.gitignore` 不会删除这些本地文件，所以当前安装、开发工具和个人配置仍可使用。项目正常构建所需的 PNG 图标和其他源码资源没有被全局忽略。

## 所有者操作前的检查

创建 Git 仓库后、提交前，可以由所有者执行以下只读检查：

```sh
git status --short --ignored
git check-ignore -v --no-index build/ Config/Signing.local.xcconfig PhotoshopPlugin/.uxprc
git diff --cached --name-only
git diff --cached
```

确认暂存区没有 `build/`、本地签名配置、真实 PSD、账号导出、日志、预览图或证书。重点检查共享工程是否被 Xcode 手动写入私人 Team，以及文档是否混入真实邮箱、设备标识、当前配对码或用户绝对路径。

如果文件曾经被 Git 跟踪，新增 `.gitignore` 不会自动停止跟踪。可由所有者按实际路径使用 `git rm --cached`（文件）或 `git rm -r --cached`（目录）从索引移除，保留磁盘文件，再检查暂存区。只移除确认不应提交的具体路径，不必重建整个索引。

如果敏感凭据已经公开推送，单独忽略或删除当前版本不能清除历史；应首先撤销/轮换真实凭据，再处理历史。本地 Team ID 或 Bundle ID 不是私钥，不要与证书私钥和账号密码混为一谈。

## 新使用者从仓库获得什么

获得可生成和构建的源码、共享工程、配置模板和文档。不会获得已签名 iPhone 安装包、作者的 Apple/Adobe 账号、本机 CLI 下载包、预览缓存或私人 PSD。

让新的 AI 直接阅读 [从零接入与 AI 操作指南](03-从零接入与AI操作指南.md)，并告诉它实际克隆目录、目标设备和需要的预览方式。账号登录和签名仍由新使用者自己的环境提供。

公开仓库前还应由所有者确认代码及图标的使用权，并自行选择合适的开源许可证。当前没有替所有者选择或添加许可证；上传 GitHub 与授予开源许可是不同事项。
