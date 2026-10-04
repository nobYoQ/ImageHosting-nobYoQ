#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-HostingConfig {
    param([System.Collections.IDictionary]$Config)

    $fields = @('schemaVersion', 'owner', 'repo', 'branch', 'imagePath', 'delivery')
    if ($null -eq $Config -or $Config.Count -ne $fields.Count) {
        throw '配置必须只包含 schemaVersion、owner、repo、branch、imagePath、delivery；不要加入 Token。'
    }
    foreach ($field in $fields) {
        if (-not $Config.Contains($field)) { throw "配置缺少字段：$field" }
        if ($field -ne 'schemaVersion' -and $Config[$field] -isnot [string]) {
            throw "配置字段必须是字符串：$field"
        }
    }
    if ($Config.schemaVersion -ne 1) { throw '不支持此配置版本。' }
    if ($Config.owner -eq 'YOUR_GITHUB_USERNAME' -or [string]::IsNullOrWhiteSpace($Config.owner)) {
        throw '尚未配置 GitHub 用户名。请先执行 scripts/Initialize-ImageHosting.ps1 -Owner 你的GitHub用户名。'
    }
    if ($Config.owner -cnotmatch '^[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?$' -or $Config.owner.Contains('--')) {
        throw 'GitHub 用户名格式不正确。只填写用户名，不要填写邮箱、网址或 Token。'
    }
    if ($Config.repo -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$' -or $Config.repo.EndsWith('.git')) {
        throw '仓库名只支持字母、数字、点、下划线和短横线；不要附加 .git。'
    }
    # 使用不含斜杠的简单分支名，避免 PicGo、Raw 与 CDN 对 ref 的解析差异。
    if ($Config.branch -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or
        $Config.branch.Contains('..') -or $Config.branch.EndsWith('.') -or $Config.branch.EndsWith('.lock')) {
        throw '请使用 main、master 等简单分支名；不支持斜杠、空格、.. 或 .lock 后缀。'
    }
    if ($Config.imagePath -cnotmatch '^(?:[A-Za-z0-9][A-Za-z0-9_-]*/)+$') {
        throw '图片目录应为 images/ 或 assets/images/；只使用字母、数字、短横线、下划线，并以 / 结尾。'
    }
    if ($Config.delivery -cnotin @('github', 'jsdelivr')) {
        throw 'delivery 必须为 github 或 jsdelivr。'
    }
}

function Read-HostingConfig {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw '找不到 image-hosting.json，请先运行初始化脚本。' }
    try {
        $config = Get-Content -LiteralPath $Path -Encoding utf8 -Raw | ConvertFrom-Json -AsHashtable
    }
    catch { throw '配置不是有效的 JSON。请重新运行初始化脚本；不要在配置中加入 Token。' }
    if ($config -isnot [System.Collections.IDictionary]) { throw '配置必须是 JSON 对象。' }
    Assert-HostingConfig -Config $config
    return $config
}

function ConvertTo-RepositoryPath {
    param([string]$Path)

    $normalized = $Path.Replace('\', '/')
    if ([string]::IsNullOrWhiteSpace($normalized) -or $normalized -match '[:\x00-\x1f\x7f]') {
        throw '请提供仓库内的相对文件路径，例如 images/example.svg，不要输入磁盘路径或网址。'
    }
    foreach ($segment in $normalized.Split('/')) {
        if ($segment -in @('', '.', '..')) { throw '文件路径不能包含空目录、. 或 ..，也不能以 / 开头或结尾。' }
    }
    return $normalized
}

function Get-HostingLinks {
    param(
        [System.Collections.IDictionary]$Config,
        [string]$Path,
        [string]$Alt = '图片'
    )

    Assert-HostingConfig -Config $Config
    $relative = ConvertTo-RepositoryPath -Path $Path
    $encoded = ($relative.Split('/') | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/'
    $repository = '{0}/{1}' -f $Config.owner, $Config.repo
    $cdn = 'https://cdn.jsdelivr.net/gh/{0}@{1}/{2}' -f $repository, $Config.branch, $encoded
    $raw = 'https://raw.githubusercontent.com/{0}/{1}/{2}' -f $repository, $Config.branch, $encoded
    $url = if ($Config.delivery -eq 'jsdelivr') { $cdn } else { $raw }
    $plainAlt = $Alt -replace '[\r\n]', ' '
    $markdownAlt = $plainAlt.Replace('\', '\\').Replace('[', '\[').Replace(']', '\]')
    $htmlAlt = [System.Net.WebUtility]::HtmlEncode($plainAlt)
    return [pscustomobject][ordered]@{
        Path = $relative
        Url = $url
        JsDelivr = $cdn
        Raw = $raw
        GitHub = 'https://github.com/{0}/blob/{1}/{2}' -f $repository, $Config.branch, $encoded
        Markdown = '![{0}]({1})' -f $markdownAlt, $url
        Html = '<img src="{0}" alt="{1}" />' -f $url, $htmlAlt
    }
}

function Get-PicGoConfig {
    param([System.Collections.IDictionary]$Config)

    Assert-HostingConfig -Config $Config
    $repository = '{0}/{1}' -f $Config.owner, $Config.repo
    $customUrl = if ($Config.delivery -eq 'jsdelivr') {
        'https://cdn.jsdelivr.net/gh/{0}@{1}' -f $repository, $Config.branch
    } else { '' }
    return [ordered]@{
        picBed = [ordered]@{
            current = 'github'
            uploader = 'github'
            github = [ordered]@{
                repo = $repository
                branch = $Config.branch
                token = ''
                path = $Config.imagePath
                customUrl = $customUrl
            }
        }
    }
}

function Test-LocalImages {
    param([string]$Directory)

    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) { throw '图片目录不存在，请运行初始化脚本。' }
    $extensions = @('.png', '.jpg', '.jpeg', '.gif', '.webp', '.avif', '.svg', '.ico', '.bmp')
    $count = 0
    foreach ($file in Get-ChildItem -LiteralPath $Directory -File -Recurse -Force) {
        if ($file.Name -eq '.gitkeep') { continue }
        if ($file.Extension.ToLowerInvariant() -notin $extensions) {
            throw "图片目录包含不支持的文件类型：$($file.Name)。请转换为 PNG、JPG、WebP 等图片。"
        }
        if ($file.Length -eq 0) { throw "图片文件为空：$($file.Name)" }
        # 本项目使用十进制 20 MB 的保守阈值，避免上传后被 CDN 拒绝。
        if ($file.Length -ge 20000000) { throw "图片必须小于 20 MB：$($file.Name)" }
        $count++
    }
    return $count
}

Export-ModuleMember -Function Assert-HostingConfig, Read-HostingConfig, ConvertTo-RepositoryPath, Get-HostingLinks, Get-PicGoConfig, Test-LocalImages
