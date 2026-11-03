<#
 星枢 AI · 命令行构建脚本
 用法： .\build.ps1 [-Clean] [-Release]
 产出： entry\build\default\outputs\default\entry-default-unsigned.hap

 直接使用 DevEco Studio 自带的 hvigor，不依赖工程外的任何工具链。
 如需指定别的 IDE 安装位置，设置环境变量 DEVECO_HOME。
#>
param(
  [switch]$Clean,
  [switch]$Release
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$ide  = if ($env:DEVECO_HOME) { $env:DEVECO_HOME } else { 'D:\Program Files\Huawei\DevEco Studio' }

if (-not (Test-Path $ide)) { throw ('未找到 DevEco Studio: ' + $ide + '（可用 DEVECO_HOME 指定）') }

$hvigorw = Join-Path $ide 'tools\hvigor\bin\hvigorw.bat'
if (-not (Test-Path $hvigorw)) { throw ('未找到 hvigorw: ' + $hvigorw) }

$env:NODE_HOME       = Join-Path $ide 'tools\node'
$env:DEVECO_SDK_HOME = Join-Path $ide 'sdk'
$env:Path            = $env:NODE_HOME + ';' + $env:Path

$tasks = @()
if ($Clean) { $tasks += 'clean' }
$tasks += 'assembleHap'
$mode = if ($Release) { 'release' } else { 'debug' }

Write-Host ('构建任务: ' + ($tasks -join ' ') + '   (buildMode=' + $mode + ')') -ForegroundColor Cyan

& $hvigorw @tasks --mode module -p product=default -p buildMode=$mode --no-daemon
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
