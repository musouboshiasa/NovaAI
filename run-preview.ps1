<#
 本地运行（不需要任何设备）：用 DevEco Studio 打开工程，
 然后在 Index.ets 里点击右上角 Previewer，即可在 PC 上直接渲染运行。
#>
param([switch]$NoOpen)

$root = $PSScriptRoot
$ide  = 'D:\Program Files\Huawei\DevEco Studio\bin\devecostudio64.exe'

Write-Host '星枢 AI · 本地运行' -ForegroundColor Cyan
Write-Host ''
Write-Host '步骤：'
Write-Host '  1. DevEco Studio 打开工程后，等待 Sync 完成'
Write-Host '  2. 打开 entry/src/main/ets/pages/Index.ets'
Write-Host '  3. 点击编辑器右上角的 Previewer 图标'
Write-Host '  4. 首次使用请在「设置 → 服务商与 API Key」里填入 DeepSeek API Key'
Write-Host ''
Write-Host 'Previewer 完全运行在本机：不需要模拟器、不需要真机、不需要签名。' -ForegroundColor Green
Write-Host ''

if (-not $NoOpen) {
  if (Test-Path $ide) {
    Write-Host '正在打开 DevEco Studio…'
    Start-Process $ide -ArgumentList $root
  } else {
    Write-Host ('未找到 DevEco Studio: ' + $ide) -ForegroundColor Yellow
  }
}
