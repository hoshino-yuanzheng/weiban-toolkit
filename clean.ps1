# ============================================================
#  分享前清理 ---- 删掉自己的账号、日志、虚拟环境
#  做成「可分享的干净包」
# ============================================================

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\common.ps1')

Write-Banner '分享前清理'

$runtime = Get-RuntimeDir
$data    = Get-DataDir
$venvDir = Join-Path $runtime '.venv'
$cfg     = Get-ConfigPath
$logs    = Get-LogDir
$inst    = Join-Path $runtime 'installer'

# 先看有没有程序在跑，避免删到一半被占用
$running = Get-Process -Name python -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -like "$runtime*" }
if ($running) {
    Write-Host "  检测到刷课程序正在运行（PID: $($running.Id -join ', ')）。" -ForegroundColor Yellow
    Write-Host "  请先关掉那个窗口再运行本脚本。" -ForegroundColor Yellow
    Write-Host ""
    Read-Host "  按回车退出"
    exit 1
}

Write-Host "  将要删除以下内容：" -ForegroundColor White
Write-Host ""

$sizeTotal = 0
$plan = @()

if (Test-Path $cfg) {
    $plan += @{ Path = $cfg; Desc = '账号密码（config.toml）' }
    $sizeTotal += (Get-Item $cfg).Length
}
if (Test-Path $logs) {
    $logSize = (Get-ChildItem $logs -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    if ($logSize) { $sizeTotal += $logSize }
    $plan += @{ Path = $logs; Desc = "学习日志（$( [Math]::Round([double]$logSize/1KB,0) ) KB）" }
}
if (Test-Path $venvDir) {
    $venvSize = (Get-ChildItem $venvDir -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    if ($venvSize) { $sizeTotal += $venvSize }
    $plan += @{ Path = $venvDir; Desc = "虚拟环境（$( [Math]::Round([double]$venvSize/1MB,0) ) MB，换电脑本来也要重建）" }
}
if (Test-Path $inst) {
    $plan += @{ Path = $inst; Desc = 'Python 安装包缓存' }
}

if ($plan.Count -eq 0) {
    Write-Host "  没有需要清理的内容，这个包已经是干净的。" -ForegroundColor Green
    Write-Host ""
    Read-Host "  按回车退出"
    exit 0
}

foreach ($p in $plan) {
    Write-Host "    · $($p.Desc)" -ForegroundColor DarkGray
}
Write-Host ""
Write-Host "  保留：程序源码、题库、说明文档、脚本。" -ForegroundColor Gray
Write-Host ""
$ans = Read-Host "  确认清理吗？输入 y 回车继续，其它键取消"

if ($ans -ne 'y' -and $ans -ne 'Y') {
    Write-Host ""
    Write-Host "  已取消，什么都没删。" -ForegroundColor Yellow
    Read-Host "  按回车退出"
    exit 0
}

Write-Host ""
foreach ($p in $plan) {
    $target = $p.Path
    if (-not (Test-Path $target)) { continue }

    $ok = $false
    try {
        Remove-Item $target -Recurse -Force -ErrorAction Stop
        $ok = $true
    } catch {
        # 被占用时改名挪走，避免阻塞
        try {
            $alt = "$target._del_$(Get-Date -Format 'HHmmss')"
            Rename-Item $target $alt -ErrorAction Stop
            Remove-Item $alt -Recurse -Force -ErrorAction SilentlyContinue
            $ok = $true
        } catch { }
    }
    if ($ok) {
        Write-Host "    [OK] 已删除 $($p.Desc)" -ForegroundColor Green
    } else {
        Write-Host "    [X ] 删除失败 $($p.Desc)（文件被占用，重启电脑后再试）" -ForegroundColor Red
    }
}

# 确保 runtime 骨架还在
foreach ($d in @($runtime, (Join-Path $data 'logs'), (Join-Path $data 'answer'))) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
}

Write-Host ""
Write-Host "  清理完成。" -ForegroundColor Green
Write-Host "  现在可以把整个文件夹压缩发给别人了。" -ForegroundColor Cyan
Write-Host "  对方解压后双击「① 双击开始.bat」即可。" -ForegroundColor Cyan
Write-Host ""
Read-Host "  按回车退出"
