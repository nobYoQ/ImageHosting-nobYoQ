#Requires -Version 7.0
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$scripts = Join-Path $root 'scripts'
Import-Module (Join-Path $scripts 'ImageHosting.psm1') -Force
$script:passed = 0

function Assert-Equal {
    param($Actual, $Expected, [string]$Label)
    if ($Actual -cne $Expected) { throw "失败：$Label。实际值：$Actual；预期值：$Expected" }
    $script:passed++
}

function Assert-Throws {
    param([scriptblock]$Action, [string]$Pattern, [string]$Label)
    $caught = $null
    try { $null = & $Action } catch { $caught = $_.Exception.Message }
    if ($null -eq $caught -or $caught -notmatch $Pattern) { throw "失败：$Label，未收到预期错误。" }
    $script:passed++
}

# Parse every maintained PowerShell file before executing behavior tests.
foreach ($folder in @($scripts, $PSScriptRoot)) {
    foreach ($file in Get-ChildItem -LiteralPath $folder -File) {
        if ($file.Extension -notin @('.ps1', '.psm1')) { continue }
        $parseTokens = $null
        $parseErrors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$parseTokens, [ref]$parseErrors)
        Assert-Equal $parseErrors.Count 0 "语法：$($file.Name)"
    }
}

$config = [ordered]@{
    schemaVersion = 1
    owner = 'example-user'
    repo = 'image-hosting'
    branch = 'main'
    imagePath = 'images/'
    delivery = 'github'
}
$links = Get-HostingLinks -Config $config -Path 'images/example.svg'
Assert-Equal $links.Raw 'https://raw.githubusercontent.com/example-user/image-hosting/main/images/example.svg' 'Raw 链接'
Assert-Equal $links.Url $links.Raw '默认使用 Raw'
Assert-Equal $links.JsDelivr 'https://cdn.jsdelivr.net/gh/example-user/image-hosting@main/images/example.svg' 'CDN 分支链接'
Assert-Equal $links.GitHub 'https://github.com/example-user/image-hosting/blob/main/images/example.svg' 'GitHub 预览链接'
Assert-Equal $links.Markdown ('![图片]({0})' -f $links.Raw) 'Markdown 链接'

$links = Get-HostingLinks -Config $config -Path 'images\截图 01#50%(a).png' -Alt '图[1] "说明" & <b>'
Assert-Equal $links.Path 'images/截图 01#50%(a).png' 'Windows 分隔符'
Assert-Equal $links.Raw 'https://raw.githubusercontent.com/example-user/image-hosting/main/images/%E6%88%AA%E5%9B%BE%2001%2350%25%28a%29.png' '中文和 URL 特殊字符'
Assert-Equal $links.Markdown.StartsWith('![图\[1\] "说明" & <b>](') $true 'Markdown 替代文本转义'
Assert-Equal $links.Html.Contains('&quot;说明&quot; &amp; &lt;b&gt;') $true 'HTML 替代文本转义'

$picgo = Get-PicGoConfig -Config $config
Assert-Equal $picgo.picBed.github.customUrl '' 'Raw 模式不设置自定义域名'
Assert-Equal $picgo.picBed.github.token '' 'Token 始终为空'
$config.delivery = 'jsdelivr'
$picgo = Get-PicGoConfig -Config $config
Assert-Equal $picgo.picBed.github.customUrl 'https://cdn.jsdelivr.net/gh/example-user/image-hosting@main' 'PicGo 自定义域名不含图片目录'
Assert-Equal $picgo.picBed.github.path 'images/' 'PicGo 存储路径有末尾斜杠'
Assert-Equal (Get-HostingLinks -Config $config -Path 'images/a.png').Url 'https://cdn.jsdelivr.net/gh/example-user/image-hosting@main/images/a.png' 'CDN 模式默认链接'

foreach ($badPath in @('../a.png', '/images/a.png', 'images//a.png', 'images/./a.png', 'images/../a.png', 'C:\a.png', 'https://example.com/a.png', '', 'images/')) {
    Assert-Throws { Get-HostingLinks -Config $config -Path $badPath } '相对|路径|目录' '拒绝非仓库相对路径'
}
foreach ($badBranch in @('feature/images', 'main..old', 'main.lock', 'main.', 'main@2', 'main name')) {
    $config.branch = $badBranch
    Assert-Throws { Assert-HostingConfig -Config $config } '分支' '拒绝不支持的分支'
}
$config.branch = 'main'
$config.owner = 'YOUR_GITHUB_USERNAME'
Assert-Throws { Assert-HostingConfig -Config $config } '尚未配置' '占位用户名不能生成假链接'
$config.owner = 'example-user'
$config['unexpectedField'] = 'sample'
Assert-Throws { Assert-HostingConfig -Config $config } '只包含' '拒绝公开配置的额外字段'
$config.Remove('unexpectedField')
$config.imagePath = '../outside/'
Assert-Throws { Assert-HostingConfig -Config $config } '图片目录' '拒绝目录穿越'
$config.imagePath = 'images/'

# All temporary fixtures live under the project's ignored .local directory.
$testRoot = Join-Path $root ('.local/tests/{0}' -f [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $testRoot -Force
$fixtureConfig = Join-Path $testRoot 'image-hosting.json'
& (Join-Path $scripts 'Initialize-ImageHosting.ps1') -Owner 'example-user' -Repo 'image-hosting' -Delivery jsdelivr -ProjectRoot $testRoot
$generated = Read-HostingConfig -Path $fixtureConfig
Assert-Equal $generated.delivery 'jsdelivr' '初始化写入选择的链接类型'
$generatedPicgo = Get-Content -LiteralPath (Join-Path $testRoot '.local/picgo.generated.json') -Encoding utf8 -Raw | ConvertFrom-Json
Assert-Equal $generatedPicgo.picBed.github.token '' '生成的 JSON 没有凭据'
Assert-Equal $generatedPicgo.picBed.github.customUrl 'https://cdn.jsdelivr.net/gh/example-user/image-hosting@main' '生成的 JSON 域名'
Assert-Equal (Test-Path -LiteralPath (Join-Path $testRoot '.local/picgo-settings.md')) $true '生成 PicGo 中文填写表'
$bytes = [System.IO.File]::ReadAllBytes($fixtureConfig)
Assert-Equal ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) $false '生成配置使用 UTF-8 无 BOM'

$imageFolder = Join-Path $testRoot 'images'
Copy-Item -LiteralPath (Join-Path $root 'images/example.svg') -Destination $imageFolder
Assert-Equal (Test-LocalImages -Directory $imageFolder) 1 '示例图片通过本地检查'
& (Join-Path $scripts 'Test-ImageHosting.ps1') -ConfigPath $fixtureConfig
Assert-Equal (& (Join-Path $scripts 'Get-ImageLink.ps1') -ConfigPath $fixtureConfig -Path 'images/example.svg' -Format JsDelivr) 'https://cdn.jsdelivr.net/gh/example-user/image-hosting@main/images/example.svg' '命令行图片链接输出'
Assert-Throws { & (Join-Path $scripts 'Initialize-ImageHosting.ps1') -ProjectRoot $testRoot } '尚未配置' '缺少用户名时失败且不提示交互输入'

$emptyImage = Join-Path $imageFolder 'empty.png'
[System.IO.File]::WriteAllBytes($emptyImage, [byte[]]@())
Assert-Throws { Test-LocalImages -Directory $imageFolder } '为空' '拒绝空图片'
Remove-Item -LiteralPath $emptyImage
$largeImage = Join-Path $imageFolder 'large.png'
$stream = [System.IO.File]::Create($largeImage)
try { $stream.SetLength(20000000) } finally { $stream.Dispose() }
Assert-Throws { Test-LocalImages -Directory $imageFolder } '20 MB' '拒绝达到大小上限的文件'
Remove-Item -LiteralPath $largeImage
$badFile = Join-Path $imageFolder 'readme.txt'
[System.IO.File]::WriteAllText($badFile, 'fixture', [System.Text.UTF8Encoding]::new($false))
Assert-Throws { Test-LocalImages -Directory $imageFolder } '文件类型' '拒绝非图片扩展名'
Remove-Item -LiteralPath $badFile

# Simulate public HTTP responses: no network and no real GitHub credentials.
$httpState = [pscustomobject]@{
    Mode = 'ok'
    Calls = [System.Collections.Generic.List[string]]::new()
}
function Invoke-WebRequest {
    param($Uri, $Method, $TimeoutSec, [switch]$SkipHttpErrorCheck, $Headers)
    $httpState.Calls.Add([string]$Uri)
    $status = if ($httpState.Mode -eq '404') { 404 } elseif ($httpState.Mode -eq '403') { 403 } else { 200 }
    if ($httpState.Mode -eq 'network') { throw 'Simulated network failure' }
    $content = if ($httpState.Mode -eq 'private') { '{"private":true}' } else { '{"private":false}' }
    $contentType = if ($httpState.Mode -eq 'html') { 'text/html' } else { 'image/svg+xml' }
    return [pscustomobject]@{ StatusCode = $status; Content = $content; Headers = @{ 'Content-Type' = $contentType } }
}

& (Join-Path $scripts 'Test-ImageHosting.ps1') -Online -ConfigPath $fixtureConfig
Assert-Equal $httpState.Calls.Count 4 'CDN 模式检查仓库、分支、Raw、CDN'
$httpState.Mode = '404'
Assert-Throws { & (Join-Path $scripts 'Test-ImageHosting.ps1') -Online -ConfigPath $fixtureConfig } 'HTTP 404' '未发布文件返回失败'
$httpState.Mode = '403'
Assert-Throws { & (Join-Path $scripts 'Test-ImageHosting.ps1') -Online -ConfigPath $fixtureConfig } 'HTTP 403' '匿名限流不会报告成功'
$httpState.Mode = 'private'
Assert-Throws { & (Join-Path $scripts 'Test-ImageHosting.ps1') -Online -ConfigPath $fixtureConfig } '公开仓库' '拒绝私有仓库'
$httpState.Mode = 'html'
Assert-Throws { & (Join-Path $scripts 'Test-ImageHosting.ps1') -Online -ConfigPath $fixtureConfig } 'Content-Type' 'HTTP 200 HTML 不算图片成功'
$httpState.Mode = 'network'
Assert-Throws { & (Join-Path $scripts 'Test-ImageHosting.ps1') -Online -ConfigPath $fixtureConfig } '请求失败' '网络错误报告失败'

# Regenerating configuration changes only generated settings and keeps images.
& (Join-Path $scripts 'Initialize-ImageHosting.ps1') -Owner 'example-user' -Repo 'image-hosting' -Delivery github -ProjectRoot $testRoot
Assert-Equal (Test-Path -LiteralPath (Join-Path $imageFolder 'example.svg')) $true '重新初始化保留图片'
$regenerated = Get-Content -LiteralPath (Join-Path $testRoot '.local/picgo.generated.json') -Encoding utf8 -Raw | ConvertFrom-Json
Assert-Equal $regenerated.picBed.github.customUrl '' '切回 Raw 清空生成的自定义域名'
$httpState.Mode = 'ok'
$httpState.Calls.Clear()
& (Join-Path $scripts 'Test-ImageHosting.ps1') -Online -ConfigPath $fixtureConfig
Assert-Equal $httpState.Calls.Count 3 'Raw 模式不请求 CDN'

Write-Host "通过 $script:passed 项断言。网络响应为模拟数据，尚未验证你的远程仓库或 PicGo 上传。"
Write-Host "测试文件位于已忽略的目录：$testRoot"
