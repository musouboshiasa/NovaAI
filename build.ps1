<#
 星枢 AI · 命令行构建脚本
 用法： .\build.ps1 [-Clean] [-Release]
 产出： entry\build\default\outputs\default\entry-default-unsigned.hap
#>
param(
  [switch]$Clean,
  [switch]$Release
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$ide  = 'D:\Program Files\Huawei\DevEco Studio'
$tc   = Join-Path (Split-Path $root -Parent) 'toolchain'

if (-not (Test-Path $ide)) { throw "未找到 DevEco Studio: $ide" }
if (-not (Test-Path (Join-Path $tc 'bin\hvigorw.bat'))) {
  Write-Host '未找到已打补丁的 hvigor 工具链，正在生成…' -ForegroundColor Yellow
  node (Join-Path $tc 'patch-hvigor.mjs')
}

$env:NODE_HOME       = Join-Path $ide 'tools\node'
$env:DEVECO_SDK_HOME = Join-Path $ide 'sdk'
$env:Path            = $env:NODE_HOME + ';' + $env:Path

$tasks = @()
if ($Clean) { $tasks += 'clean' }
$tasks += 'assembleHap'
$mode = if ($Release) { 'release' } else { 'debug' }

Write-Host ('构建任务: ' + ($tasks -join ' ') + '   (buildMode=' + $mode + ')') -ForegroundColor Cyan

& (Join-Path $tc 'bin\hvigorw.bat') @tasks --mode module -p product=default -p buildMode=$mode --no-daemon
if ($LASTEXITCODE -ne 0) { throw ('构建失败（exit=' + $LASTEXITCODE + '）') }

$hap = Join-Path $root 'entry\build\default\outputs\default\entry-default-unsigned.hap'
if (Test-Path $hap) {
  $size = [math]::Round((Get-Item $hap).Length / 1KB, 1)
  Write-Host ''
  Write-Host '构建成功：' -ForegroundColor Green
  Write-Host ('  ' + $hap + '  (' + $size + ' KB)')
} else {
  Write-Host '构建结束，但未找到 HAP 产物' -ForegroundColor Yellow
}
