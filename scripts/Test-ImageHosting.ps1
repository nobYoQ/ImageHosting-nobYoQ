#Requires -Version 7.0
[CmdletBinding()]
param(
    [switch]$Online,
    [string]$Path = 'images/example.svg',
    [string]$ConfigPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'image-hosting.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'ImageHosting.psm1') -Force
$config = Read-HostingConfig -Path $ConfigPath
$root = Split-Path -Parent ([System.IO.Path]::GetFullPath($ConfigPath))
$count = Test-LocalImages -Directory (Join-Path $root $config.imagePath)
$links = Get-HostingLinks -Config $config -Path $Path
Write-Host "本地检查通过：配置有效，$count 个图片文件的类型和大小符合本项目要求。"

if (-not $Online) {
    Write-Host '尚未检查远程仓库和上传权限。首次推送后添加 -Online 检查公开访问，再用 PicGo 实际上传一张图片。'
    return
}

function Invoke-PublicCheck {
    param([string]$Uri, [string]$Label, [string]$Method = 'Head')
    try {
        $response = Invoke-WebRequest -Uri $Uri -Method $Method -TimeoutSec 15 -SkipHttpErrorCheck -Headers @{
            'User-Agent' = 'ImageHosting-PublicCheck'
        }
    }
    catch { throw "$Label 请求失败：请检查当前网络、DNS 或代理设置。" }
    if ([int]$response.StatusCode -ne 200) {
        $hint = switch ([int]$response.StatusCode) {
            404 { '检查仓库是否公开、分支是否已创建、文件是否已推送，以及路径大小写；CDN 也可能尚未更新。' }
            403 { '可能触发匿名 API 限流或服务限制；这不能证明 PicGo Token 有效或无效。' }
            429 { '请求过于频繁，请稍后重试。' }
            default { '请检查服务状态或稍后重试。' }
        }
        throw "$Label 返回 HTTP $($response.StatusCode)。$hint"
    }
    Write-Host "$Label：HTTP 200"
    return $response
}

$api = 'https://api.github.com/repos/{0}/{1}' -f $config.owner, $config.repo
$repositoryResponse = Invoke-PublicCheck -Uri $api -Label '公开仓库' -Method Get
$repository = $repositoryResponse.Content | ConvertFrom-Json
if ($repository.private -ne $false) { throw '此方案需要公开仓库。' }
$null = Invoke-PublicCheck -Uri "$api/branches/$($config.branch)" -Label '目标分支' -Method Get
$raw = Invoke-PublicCheck -Uri $links.Raw -Label 'GitHub 原始图片'
if (($raw.Headers['Content-Type'] -join ';') -notmatch '^image/') { throw '原始链接没有返回图片 Content-Type，请核对文件内容和路径。' }
if ($config.delivery -eq 'jsdelivr') {
    $cdn = Invoke-PublicCheck -Uri $links.JsDelivr -Label 'jsDelivr 图片'
    if (($cdn.Headers['Content-Type'] -join ';') -notmatch '^image/') { throw 'jsDelivr 没有返回图片 Content-Type，请核对文件或等待缓存更新。' }
}
Write-Host '公开访问检查通过。此检查不读取 Token；上传权限仍需通过 PicGo 的一次真实上传确认。'
