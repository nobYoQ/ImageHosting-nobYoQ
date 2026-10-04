# ImageHosting-nobYoQ

使用 **GitHub 保存图片、PicGo 上传并复制链接** 的个人图片仓库，支持 **jsDelivr** 链接配置。无需服务器、数据库或 GitHub Pages。

**从这里开始：[完整使用指南](docs/使用指南.md)**。

> 截至 2026-10-03 核对的 [jsDelivr 条款第 6 节](https://github.com/jsdelivr/jsdelivr/blob/master/Terms%20of%20Use.md)限制通用文件/媒体托管，并明确列举图床网站。因此默认使用 GitHub 原始链接；jsDelivr 配置作为可选项保留，启用前确认用途符合条款。公开的个人博客或项目图片是否符合要求，应按实际用途核实，不能只凭访问量小就认定可以使用。

当前项目是可配置模板；尚未绑定你的 GitHub 账号、创建远程仓库或完成真实上传。`YOUR_GITHUB_USERNAME` 需要替换，Token 只在本机 PicGo 中填写。

## 你需要做的事

1. 在 GitHub 创建公开的空仓库，建议名称 `ImageHosting-nobYoQ`。
2. 在项目根目录用 PowerShell 7 运行以下命令，将用户名换成你的真实 GitHub 用户名：

   ```powershell
   .\scripts\Initialize-ImageHosting.ps1 -Owner '你的GitHub用户名'
   ```

3. 按指南把本项目首次推送到 `main`，让远程分支和示例图片存在。
4. 创建仅有此仓库 `Contents: Read and write` 权限的 fine-grained Token。
5. 安装 PicGo，按生成的 `.local/picgo-settings.md` 填写 GitHub 图床，粘贴 Token，设为默认图床。
6. 上传一张测试图片，打开复制的链接确认可用。

## 已提供的工具

| 文件 | 用途 |
| --- | --- |
| `image-hosting.json` | 可提交的公开配置；不存 Token |
| `scripts/Initialize-ImageHosting.ps1` | 生成公开配置、PicGo 填写表和无凭据 JSON 示例 |
| `scripts/Get-ImageLink.ps1` | 生成当前默认链接、jsDelivr、Raw、Markdown、HTML 链接 |
| `scripts/Test-ImageHosting.ps1` | 本地校验；加 `-Online` 检查公开仓库、分支和图片访问 |
| `config/picgo.github.example.json` | PicGo GitHub 字段参考；Token 为空 |
| `images/example.svg` | 首次发布后的链接测试图片 |
| `tests/Run-Tests.ps1` | 无第三方依赖的本地脚本测试 |

```powershell
# 生成链接；Path 是包含 images/ 的仓库内路径，而不是磁盘路径
.\scripts\Get-ImageLink.ps1 -Path 'images/example.svg' -Format Markdown

# 本地检查（需要先填写真实用户名）
.\scripts\Test-ImageHosting.ps1

# 首次推送以后检查远程公开访问；此命令不会读取 Token
.\scripts\Test-ImageHosting.ps1 -Online

# 离线自测，不需要 GitHub 账号、Token 或网络
.\tests\Run-Tests.ps1
```

如果确认用途符合 jsDelivr 条款，可重新生成配置并在 PicGo 中更新自定义域名：

```powershell
.\scripts\Initialize-ImageHosting.ps1 -Owner '你的GitHub用户名' -Delivery jsdelivr
```

该命令只更新本项目配置和 `.local/` 中的填写表，不会修改 PicGo。曾自定义仓库名、分支或目录时，重新运行需带上相同参数。详见[配置与日常使用](docs/使用指南.md)。
