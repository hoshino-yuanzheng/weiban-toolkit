# ============================================================
#  查看进度 ---- 启动本地进度页并打开浏览器
#  用法：.\progress.ps1              默认 8899 端口
#        .\progress.ps1 -Port 9000
#        .\progress.ps1 -NoBrowser   只起服务不开浏览器
# ============================================================

param(
    [int]$Port = 8899,
    [switch]$NoBrowser
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\common.ps1')

Write-Banner '安全微伴刷课 · 进度页'

$venvPy = Get-VenvPython
$script = Join-Path (Get-ToolRoot) 'files\progress_page.py'
$logDir = Get-LogDir

if (-not (Test-Path $venvPy)) {
    Write-Host "  没找到虚拟环境，先运行 .\deploy.ps1" -ForegroundColor Red
    exit 1
}
if (-not (Test-Path $logDir)) {
    Write-Host "  还没跑过刷课，没有日志可显示。" -ForegroundColor Yellow
    Write-Host "  跑一次 .\start.ps1 之后再回来。" -ForegroundColor Yellow
    exit 1
}

# 已有服务在跑？
if (-not (Test-PortFree $Port)) {
    Write-Host "  端口 $Port 已有程序在监听，直接打开页面。" -ForegroundColor Yellow
    Start-Process "http://127.0.0.1:$Port/"
    exit 0
}

$argList = @($script, '--logs', $logDir, '--port', "$Port")
Start-Process -FilePath $venvPy -ArgumentList $argList -WindowStyle Hidden
Start-Sleep -Seconds 2

if (Test-PortFree $Port) {
    Write-Host "  服务没起来，检查 files\progress_page.py 是否存在。" -ForegroundColor Red
    exit 1
}

Write-Host "  已启动：http://127.0.0.1:$Port/" -ForegroundColor Green
Write-Host "  每 3 秒自动刷新，关掉浏览器不影响刷课。" -ForegroundColor Gray

if (-not $NoBrowser) {
    Start-Process "http://127.0.0.1:$Port/"
}
Write-Host ""
