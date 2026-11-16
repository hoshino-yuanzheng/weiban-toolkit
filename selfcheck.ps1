# ============================================================
#  环境自检 ---- 不做任何修改，只检查并给出修复建议
#  用法：右键「使用 PowerShell 运行」，或 .\selfcheck.ps1
# ============================================================

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'lib\common.ps1')

Write-Banner '安全微伴刷课 · 环境自检'

Write-Section '系统'
$os = (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).Caption
if (-not $os) { $os = [System.Environment]::OSVersion.VersionString }
Write-Result -Item '操作系统' -Level 'info' -Detail $os
Write-Result -Item 'PowerShell' -Level 'info' -Detail "$($PSVersionTable.PSVersion)"
Write-Result -Item '当前时间' -Level 'info' -Detail (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Write-Result -Item '工具包位置' -Level 'info' -Detail (Get-ToolRoot)

Write-Section '运行环境'
$rt = Show-RuntimeReport

Write-Section '网络连通性'
$targets = @(
    @{ Name = '安全教育平台'; Url = 'https://weiban.mycourse.cn/index.html'; Must = $true },
    @{ Name = 'GitHub 镜像'; Url = 'https://gh-proxy.com'; Must = $false },
    @{ Name = 'PyPI 镜像'; Url = 'https://pypi.tuna.tsinghua.edu.cn/simple/'; Must = $false }
)
$netFail = @()
foreach ($t in $targets) {
    $ok = Test-Url -Url $t.Url -TimeoutSec 8
    if ($ok) {
        Write-Result -Item $t.Name -Level 'ok' -Detail $t.Url
    } elseif ($t.Must) {
        Write-Result -Item $t.Name -Level 'fail' -Detail $t.Url -Fix '检查网络/校园网认证，平台必须能访问'
        $netFail += $t.Name
    } else {
        Write-Result -Item $t.Name -Level 'warn' -Detail "$($t.Url)（仅部署时需要）"
    }
}

Write-Section '端口'
if (Test-PortFree 8899) {
    Write-Result -Item '进度页端口 8899' -Level 'ok' -Detail '空闲'
} else {
    Write-Result -Item '进度页端口 8899' -Level 'warn' -Detail '被占用' -Fix '关掉占用程序，或用 .\progress.ps1 -Port 其他端口'
}

# ---------- 总结 ----------
Write-Banner ''
$failCount = (@($rt.Items | Where-Object { $_.Level -eq 'fail' })).Count + $netFail.Count
$warnCount = (@($rt.Items | Where-Object { $_.Level -eq 'warn' })).Count

if ($failCount -eq 0) {
    Write-Host "  环境就绪，可以开跑。" -ForegroundColor Green
    if ($warnCount -gt 0) {
        Write-Host "  有 $warnCount 项提醒，不影响运行（题库缺失会导致课后题随机作答）。" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "  下一步：.\start.ps1" -ForegroundColor Cyan
} else {
    Write-Host "  有 $failCount 项阻塞问题，先修好再跑。" -ForegroundColor Red
    Write-Host "  多数问题执行 .\deploy.ps1 即可自动解决。" -ForegroundColor Yellow
}
Write-Host ""
