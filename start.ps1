# ============================================================
#  开始刷课 ---- 启动前自动做一次环境检查，然后运行
#  用法：.\start.ps1
#        .\start.ps1 -ExamMode true      # 同时做考试
#        .\start.ps1 -StudyMode force    # 强制重刷已完成课程
# ============================================================

param(
    [ValidateSet('false', 'true', 'force')][string]$StudyMode = 'true',
    [ValidateSet('false', 'true', 'perfect', 'force')][string]$ExamMode = 'false',
    [switch]$SkipCheck
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\common.ps1')

Write-Banner '安全微伴刷课'

# ---------- 启动前检查 ----------
if (-not $SkipCheck) {
    Write-Section '启动前检查'
    $rt = Show-RuntimeReport
    $fails = @($rt.Items | Where-Object { $_.Level -eq 'fail' })
    if ($fails.Count -gt 0) {
        Write-Host ""
        Write-Host "  有 $($fails.Count) 项阻塞问题，先运行 .\deploy.ps1 或修好再试。" -ForegroundColor Red
        Write-Host "  确认要强行启动可加 -SkipCheck 参数。" -ForegroundColor DarkGray
        exit 1
    }
}

# ---------- 环境变量 ----------
$root    = Get-ToolRoot
$runtime = Get-RuntimeDir
$venvPy  = Get-VenvPython
$entry   = Join-Path (Get-SrcDir) 'main.py'
$dataDir = Get-DataDir

# 必须用环境变量传数据目录：client.py 在 import 时就读取 WB_DATA_DIR，
# 只传 --data-dir 会让题库去程序目录找，导致「题库为空、课后题随机作答」。
$env:WB_DATA_DIR      = $dataDir
$env:PYTHONIOENCODING = 'utf-8'
$tmpDir = Join-Path $runtime 'tmp'
New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null
$env:TEMP = $tmpDir
$env:TMP  = $tmpDir

$browser = Find-Browser

# ---------- 启动 ----------
Write-Section '运行参数'
$studyDesc = @{
    'false' = 'false（只考试，不学习）'
    'true'  = 'true（学习未完成课程，学够即停）'
    'force' = 'force（全部重刷，不设上限）'
}
$examDesc = @{
    'false'   = 'false（跳过考试）'
    'true'    = 'true（及格即可）'
    'perfect' = 'perfect（冲满分）'
    'force'   = 'force（已及格也重考）'
}
Write-Result -Item '学习模式' -Level 'info' -Detail $studyDesc[$StudyMode]
Write-Result -Item '考试模式' -Level 'info' -Detail $examDesc[$ExamMode]
Write-Result -Item '数据目录' -Level 'info' -Detail $dataDir
Write-Result -Item '日志目录' -Level 'info' -Detail (Get-LogDir)
Write-Host ""

$argList = @($entry, '--non-interactive', '--study-mode', $StudyMode, '--exam-mode', $ExamMode)
if ($browser) { $argList += @('--browser-path', $browser) }

Write-Host "  Ctrl+C 可随时中断，已完成的课程服务端会记住。" -ForegroundColor DarkGray
Write-Host ""
Start-Sleep -Milliseconds 600

$started = Get-Date
# PS 5.1：刷课程序会往 stderr 输出日志，Stop 模式会把正常输出当成致命错误而中断
$eapRun = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
& $venvPy @argList
$code = $LASTEXITCODE
$ErrorActionPreference = $eapRun
$span = (Get-Date) - $started

Write-Banner ''
Write-Host ("  运行结束，耗时 {0:hh\:mm\:ss}，退出码 {1}" -f $span, $code) -ForegroundColor Cyan
$logDir = Get-LogDir
if (Test-Path $logDir) {
    $latest = Get-ChildItem $logDir -Recurse -Filter 'weban-*.log' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latest) {
        Write-Host "  最新日志：$($latest.FullName)" -ForegroundColor Gray
        Write-Host "  看进度：.\progress.ps1    导出清单：.\export.ps1" -ForegroundColor Gray
    }
}
Write-Host ""
