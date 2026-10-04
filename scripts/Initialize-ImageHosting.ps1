#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$Owner = '',
    [string]$Repo = 'ImageHosting-nobYoQ',
    [string]$Branch = 'main',
    [string]$ImagePath = 'images/',
    [ValidateSet('github', 'jsdelivr')][string]$Delivery = 'github',
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'ImageHosting.psm1') -Force

$config = [ordered]@{
    schemaVersion = 1
    owner = $Owner
    repo = $Repo
    branch = $Branch
    imagePath = $ImagePath.Replace('\', '/').TrimEnd('/') + '/'
    delivery = $Delivery.ToLowerInvariant()
}
Assert-HostingConfig -Config $config
$root = [System.IO.Path]::GetFullPath($ProjectRoot)
$local = Join-Path $root '.local'
$null = New-Item -ItemType Directory -Path $root, $local, (Join-Path $root $config.imagePath) -Force
$config | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $root 'image-hosting.json') -Encoding utf8NoBOM
$picgo = Get-PicGoConfig -Config $config
$picgo | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $local 'picgo.generated.json') -Encoding utf8NoBOM

$repository = '{0}/{1}' -f $Owner, $Repo
$cdnBase = 'https://cdn.jsdelivr.net/gh/{0}@{1}' -f $repository, $Branch
$domainText = if ($Delivery -eq 'jsdelivr') { $cdnBase } else { '留空（GitHub 原始链接）' }
$fields = @(
    '# 你的 PicGo 配置',
    '',
    '打开 PicGo → 图床设置 → GitHub，按下表填写，保存并设为默认图床。',
    '',
    '| PicGo 字段 | 填写内容 |',
    '| --- | --- |',
    "| 设定仓库名 | $repository |",
    "| 设定分支名 | $Branch |",
    '| 设定 Token | 仅在 PicGo 内粘贴你创建的 Token |',
    "| 指定存储路径 | $($config.imagePath) |",
    "| 设定自定义域名 | $domainText |",
    '',
    "jsDelivr 可选域名：$cdnBase",
    '域名不要加图片目录或末尾斜杠。启用前查看 docs/使用指南.md 中的用途限制。',
    '',
    '生成的 JSON 仅供核对字段，不是 PicGo GUI 的整份配置；不要覆盖 PicGo 的 data.json。',
    '本脚本不会创建远程仓库、修改 PicGo、保存 Token 或推送 Git 提交。'
)
$fields | Set-Content -LiteralPath (Join-Path $local 'picgo-settings.md') -Encoding utf8NoBOM
Write-Host "配置已生成：$repository（$Branch，$Delivery）"
Write-Host "PicGo 填写表：$(Join-Path $local 'picgo-settings.md')"
Write-Host '下一步：按照 docs/使用指南.md 创建公开仓库、发布项目，再在 PicGo 中填写 Token。'
