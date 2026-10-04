#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$Path = 'images/example.svg',
    [string]$Alt = '图片',
    [ValidateSet('All', 'Url', 'Markdown', 'Html', 'JsDelivr', 'Raw', 'GitHub')]
    [string]$Format = 'All',
    [string]$ConfigPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'image-hosting.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'ImageHosting.psm1') -Force
$config = Read-HostingConfig -Path $ConfigPath
$links = Get-HostingLinks -Config $config -Path $Path -Alt $Alt
if ($Format -eq 'All') { $links } else { $links.$Format }
