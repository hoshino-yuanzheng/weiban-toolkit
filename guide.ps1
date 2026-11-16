# ============================================================
#  引导脚本 ---- 双击「① 双击开始.bat」就会跑到这里
#  面向电脑操作不熟的用户：一步步提示，缺什么补什么
# ============================================================

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'lib\common.ps1')

$PY_DOWNLOAD_URL = 'https://www.python.org/ftp/python/3.12.7/python-3.12.7-amd64.exe'

function Pause-Any {
    param([string]$Text = '按回车键继续')
    Write-Host ""
    Write-Host "  $Text ..." -ForegroundColor DarkGray -NoNewline
    $null = Read-Host
}

function Pause-Enter {
    Write-Host ""
    Write-Host "  按回车键返回菜单 ..." -ForegroundColor DarkGray -NoNewline
    $null = Read-Host
}

function Stop-Exit {
    param([string]$Message)
    Write-Host ""
    Write-Host "  $Message" -ForegroundColor Red
    Write-Host ""
    Pause-Any '按回车键关闭'
    exit 1
}

# ---------- 欢迎 ----------
Write-Banner '安全微伴刷课工具 · 使用引导'
Write-Host "  本工具仅用于个人学习，刷课属于违反平台规定的行为。" -ForegroundColor DarkGray
Write-Host "  使用后果由使用者自行承担。" -ForegroundColor DarkGray

$root = Get-ToolRoot

# 可移动盘提示
try {
    $drive = New-Object System.IO.DriveInfo((Split-Path $root -Qualifier) + '\')
    if ($drive.DriveType -eq 'Removable') {
        Write-Host ""
        Write-Host "  检测到程序在可移动磁盘（U盘/移动硬盘）上。" -ForegroundColor Yellow
        Write-Host "  可以继续使用，但运行速度会慢一些；" -ForegroundColor DarkGray
        Write-Host "  想快一点可以把整个文件夹复制到电脑本地（如 D:\）再运行。" -ForegroundColor DarkGray
    }
} catch { }

# ============================================================
#  第一步：Python
# ============================================================
function Step-Python {
    Write-Section '第 1 步：检查 Python'

    while ($true) {
        $py = Test-PythonDetail
        if ($py.Ok) {
            Write-Result -Item 'Python' -Level 'ok' -Detail "$($py.Version)"
            return $true
        }

        Write-Result -Item 'Python' -Level 'fail' -Detail '没找到（或版本太旧）'
        Write-Host ""
        Write-Host "  这个工具需要 Python 才能运行。有两种方式：" -ForegroundColor White
        Write-Host "    [1] 自动下载安装（推荐，约 25MB，需要联网）" -ForegroundColor Cyan
        Write-Host "    [2] 我自己去官网下载安装" -ForegroundColor Cyan
        Write-Host "    [0] 退出" -ForegroundColor DarkGray
        Write-Host ""
        $choice = Read-Host "  请输入 1 / 2 / 0"

        if ($choice -eq '0') { Stop-Exit '已退出。' }

        if ($choice -eq '1') {
            $exe = $null

            # 优先用包里自带的安装程序（离线可用，不需要网络）
            $bundled = Join-Path (Join-Path (Get-ToolRoot) 'files') 'python-3.12.7-amd64.exe'
            if (Test-Path $bundled) {
                $exe = $bundled
                Write-Host ""
                Write-Host "  使用包里自带的 Python 安装包（无需联网）。" -ForegroundColor Green
            } else {
                $dir = Join-Path (Get-RuntimeDir) 'installer'
                New-Item -ItemType Directory -Force -Path $dir | Out-Null
                $exe = Join-Path $dir 'python-setup.exe'
                Write-Host ""
                Write-Host "  正在下载 Python 安装包，请稍候（约 25MB）..." -ForegroundColor DarkGray
                try {
                    $old = $ProgressPreference
                    $ProgressPreference = 'Continue'
                    Invoke-WebRequest -Uri $PY_DOWNLOAD_URL -OutFile $exe -UseBasicParsing -TimeoutSec 300
                    $ProgressPreference = $old
                    Write-Host "  下载完成，正在启动安装程序..." -ForegroundColor Green
                } catch {
                    Write-Host "  下载失败：$($_.Exception.Message)" -ForegroundColor Red
                    Write-Host "  请改用方式 [2] 手动安装。" -ForegroundColor Yellow
                    continue
                }
            }

            Write-Host ""
            Write-Host "  [!] 安装窗口会出现，请等待它自己装完（约 1-2 分钟）。" -ForegroundColor Yellow
            Write-Host "    如果弹出「是否允许此应用更改设备」，请点【是】。" -ForegroundColor Yellow
            Write-Host ""
            try {
                Start-Process -FilePath $exe -ArgumentList '/passive InstallAllUsers=0 PrependPath=1 Include_test=0 Include_launcher=1' -Wait
            } catch {
                Write-Host "  安装程序启动失败：$($_.Exception.Message)" -ForegroundColor Red
                continue
            }
            Write-Host ""
            Write-Host "  安装结束，重新检测..." -ForegroundColor Green
            Start-Sleep -Seconds 2
            continue
        }

        # 方式 2：手动
        Write-Host ""
        Write-Host "  即将打开 Python 官网下载页。" -ForegroundColor White
        Write-Host "  1) 下载页面里点黄色的【Download Python 3.x.x】按钮" -ForegroundColor Yellow
        Write-Host "  2) 运行安装包，**第一页最下面的「Add python.exe to PATH」一定要勾上**" -ForegroundColor Yellow
        Write-Host "  3) 点 Install Now，装完回来按回车" -ForegroundColor Yellow
        Write-Host ""
        try { Start-Process 'https://www.python.org/downloads/' } catch { }
        Pause-Any '装完后按回车重新检测'
    }
}

# ============================================================
#  第二步：浏览器
# ============================================================
function Step-Browser {
    Write-Section '第 2 步：检查浏览器'
    $b = Find-Browser
    if ($b) {
        Write-Result -Item '浏览器' -Level 'ok' -Detail (Split-Path $b -Leaf)
        return $true
    }

    Write-Result -Item '浏览器' -Level 'fail' -Detail '没找到 Chrome / Edge'
    Write-Host ""
    Write-Host "  程序的验证码识别需要用到 Chrome 内核的浏览器。" -ForegroundColor White
    Write-Host "  建议安装 Google Chrome（免费）：" -ForegroundColor White
    try { Start-Process 'https://www.google.cn/chrome/' } catch { }
    Write-Host ""
    Write-Host "  装好后回来按回车继续。" -ForegroundColor Yellow
    Pause-Any
    return ((Find-Browser) -ne $null)
}

# ============================================================
#  第三步：部署
# ============================================================
function Step-Deploy {
    Write-Section '第 3 步：安装程序文件'
    Write-Host "  正在自动配置，请耐心等待..." -ForegroundColor DarkGray
    Write-Host ""

    $script = Join-Path $PSScriptRoot 'deploy.ps1'
    & $script
    return ($LASTEXITCODE -eq 0 -or (Test-Path (Get-VenvPython)))
}

# ============================================================
#  第四步：账号
# ============================================================
function Step-Account {
    Write-Section '第 4 步：填写账号'

    $cfg = Get-ConfigPath
    if (-not (Test-Path $cfg)) {
        Write-Result -Item '配置文件' -Level 'fail' -Detail '还没生成，先完成第 3 步'
        return $false
    }

    while ($true) {
        $raw = Get-Content $cfg -Raw -Encoding UTF8
        $mt = [regex]::Match($raw, 'tenant_name\s*=\s*"([^"]*)"')
        $mu = [regex]::Match($raw, '(?m)^username\s*=\s*"([^"]*)"')
        $filled = ($mt.Success -and $mt.Groups[1].Value -and $mu.Success -and $mu.Groups[1].Value)

        if ($filled) {
            Write-Result -Item '账号' -Level 'ok' -Detail "$($mt.Groups[1].Value) / $($mu.Groups[1].Value)"
            return $true
        }

        Write-Result -Item '账号' -Level 'warn' -Detail '还没填写'
        Write-Host ""
        Write-Host "  接下来会用记事本打开配置文件，请填这三行：" -ForegroundColor White
        Write-Host ""
        Write-Host '      tenant_name = "你的学校全称"' -ForegroundColor Cyan
        Write-Host '      username    = "你的学号"' -ForegroundColor Cyan
        Write-Host '      password    = "你的密码"' -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  注意：" -ForegroundColor Yellow
        Write-Host "    · 学校全称要和登录页下拉框里显示的**一字不差**" -ForegroundColor DarkGray
        Write-Host "    · 引号要保留，只改引号里面的内容" -ForegroundColor DarkGray
        Write-Host "    · 保存（Ctrl+S）后关掉记事本，再回来按回车" -ForegroundColor DarkGray
        Write-Host ""
        Pause-Any '按回车打开记事本'

        try { Start-Process notepad.exe -ArgumentList "`"$cfg`"" -Wait } catch { }

        Write-Host ""
        Write-Host "  正在重新检查..." -ForegroundColor DarkGray
    }
}

# ============================================================
#  主流程
# ============================================================
$venvPy = Get-VenvPython

# 不能只看 venv 在不在：venv 建好但依赖没装（中途失败）时，也必须重走部署流程，
# 否则直接进菜单，一开跑就报 ModuleNotFoundError。
$needSetup = $true
if (Test-Path $venvPy) {
    $eapChk = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & $venvPy -c "import nodriver,cv2,numpy,requests,pyaes,loguru" 2>$null | Out-Null
    $depOk = $LASTEXITCODE
    $ErrorActionPreference = $eapChk
    if ($depOk -eq 0) { $needSetup = $false }
}
$firstRun = $needSetup

# ---------- 启动前体检 ----------
Write-Section '启动前环境检测'
# 每次都完整检测：网络不通时刷课必然失败，早发现比跑到一半再报错强
$pf = Show-Preflight (Invoke-Preflight)
if (-not $pf.Ready) {
    Write-Host ""
    Write-Host "  有 $($pf.Fails) 项不满足，可能导致安装或运行失败。" -ForegroundColor Yellow
    Pause-Any '按回车继续（想先修复可 Ctrl+C 退出）'
}

if ($firstRun) {
    Write-Host ""
    Write-Host "  检测到这是第一次使用，将引导你完成安装（大约 3-5 分钟）。" -ForegroundColor Cyan
    Write-Host ""
    Pause-Any

    $okPy = Step-Python
    if (-not $okPy) { Stop-Exit 'Python 没装好，无法继续。' }

    $okB = Step-Browser
    if (-not $okB) {
        Write-Host ""
        Write-Host "  没有浏览器会导致验证码无法自动识别。" -ForegroundColor Yellow
        Write-Host "  可以先用 Chrome 装好再回来，或者继续（部分课程可能会失败）。" -ForegroundColor Yellow
        Pause-Any '按回车继续'
    }

    $okDep = Step-Deploy
    if (-not $okDep) { Stop-Exit '程序安装失败，请把上面的报错截图求助。' }

    $null = Step-Account

    Write-Host ""
    Write-Host "  准备完成！" -ForegroundColor Green
    Pause-Any
}

# ---------- 菜单 ----------
while ($true) {
    Write-Banner '主菜单'

    $cfg = Get-ConfigPath
    $filled = $false
    if (Test-Path $cfg) {
        $raw = Get-Content $cfg -Raw -Encoding UTF8
        $mt = [regex]::Match($raw, 'tenant_name\s*=\s*"([^"]*)"')
        if ($mt.Success -and $mt.Groups[1].Value) { $filled = $true; $school = $mt.Groups[1].Value }
    }
    if ($filled) {
        Write-Host "  当前学校：$school" -ForegroundColor DarkGray
    } else {
        Write-Host "  当前学校：未填写（请先选 5 填账号）" -ForegroundColor Yellow
    }
    Write-Host ""

    Write-Host "  [1] 开始刷课" -ForegroundColor Cyan
    Write-Host "  [2] 查看进度（打开浏览器）" -ForegroundColor Cyan
    Write-Host "  [3] 导出学习清单（Excel）" -ForegroundColor Cyan
    Write-Host "  [4] 环境检查" -ForegroundColor Cyan
    Write-Host "  [5] 修改账号 / 重新安装" -ForegroundColor Cyan
    Write-Host "  [0] 退出" -ForegroundColor DarkGray
    Write-Host ""

    $choice = Read-Host "  请输入序号"

    switch ($choice) {
        '1' {
            if (-not $filled) {
                Write-Host ""
                Write-Host "  还没填账号，请先选 5。" -ForegroundColor Yellow
                Pause-Enter
                continue
            }
            Write-Host ""
            & (Join-Path $PSScriptRoot 'start.ps1')
            Pause-Enter
        }
        '2' {
            & (Join-Path $PSScriptRoot 'progress.ps1')
            Pause-Enter
        }
        '3' {
            & (Join-Path $PSScriptRoot 'export.ps1')
            Pause-Enter
        }
        '4' {
            Write-Banner '环境检测'
            # 完整检测：系统、磁盘、路径、代理、网络、Python、浏览器、运行状态
            $pf2 = Show-Preflight (Invoke-Preflight)
            Write-Host ""
            if ($pf2.Ready) {
                Write-Host "  一切正常，可以放心使用。" -ForegroundColor Green
            } else {
                Write-Host "  有 $($pf2.Fails) 项阻塞，按上面的提示处理后重跑。" -ForegroundColor Yellow
                Write-Host "  括号里的 -> 后面就是修复建议。" -ForegroundColor DarkGray
            }
            Pause-Enter
        }
        '5' {
            Write-Banner '修改账号 / 重新安装'
            Write-Host "  [1] 只改账号（用记事本打开配置文件）" -ForegroundColor Cyan
            Write-Host "  [2] 重新安装程序（依赖坏了时用，不会丢进度）" -ForegroundColor Cyan
            Write-Host "  [0] 返回" -ForegroundColor DarkGray
            Write-Host ""
            $c2 = Read-Host "  请输入序号"
            if ($c2 -eq '1') {
                try { Start-Process notepad.exe -ArgumentList "`"$(Get-ConfigPath)`"" -Wait } catch { }
            } elseif ($c2 -eq '2') {
                $venvDir = Join-Path (Get-RuntimeDir) '.venv'
                if (Test-Path $venvDir) {
                    Write-Host "  正在删除旧环境..." -ForegroundColor DarkGray
                    Remove-Item $venvDir -Recurse -Force -ErrorAction SilentlyContinue
                }
                $null = Step-Deploy
                $null = Step-Account
            }
            Pause-Enter
        }
        '0' {
            Write-Host ""
            Write-Host "  已退出。" -ForegroundColor DarkGray
            break
        }
        default {
            Write-Host "  输入无效，请重新选择。" -ForegroundColor Yellow
            Start-Sleep -Seconds 1
        }
    }
}
