# ============================================================
#  导出学习清单 ---- 从日志还原课程列表，生成 xlsx
#  用法：.\export.ps1
#        .\export.ps1 -OutDirs "D:\我的清单.xlsx"
# ============================================================

param(
    [string]$OutFile = ''
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\common.ps1')

Write-Banner '安全微伴刷课 · 导出学习清单'

$venvPy = Get-VenvPython
$script = Join-Path (Get-ToolRoot) 'files\export_list.py'
$logDir = Get-LogDir

if (-not (Test-Path $venvPy)) {
    Write-Host "  没找到虚拟环境，先运行 .\deploy.ps1" -ForegroundColor Red
    exit 1
}
if (-not (Test-Path $logDir)) {
    Write-Host "  没有日志可解析，先跑一次刷课。" -ForegroundColor Yellow
    exit 1
}

if (-not $OutFile) {
    $stamp = Get-Date -Format 'yyyy-MM-dd'
    $OutFile = Join-Path ([Environment]::GetFolderPath('Desktop')) "安全微伴学习清单_$stamp.xlsx"
}

Write-Host "  日志目录：$logDir" -ForegroundColor Gray
Write-Host "  输出文件：$OutFile" -ForegroundColor Gray
Write-Host ""

$eapExport = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
& $venvPy $script --logs $logDir --out $OutFile
$code = $LASTEXITCODE
$ErrorActionPreference = $eapExport
if ($code -eq 0 -and (Test-Path $OutFile)) {
    Write-Host ""
    Write-Host "  已生成：$OutFile" -ForegroundColor Green
    try { Start-Process $OutFile } catch { }
} else {
    Write-Host "  导出失败，退出码 $code" -ForegroundColor Red
}
Write-Host ""
