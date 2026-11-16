# ============================================================
#  一键部署 ---- 检测环境、建虚拟环境、装依赖、铺程序文件
#  可重复运行：已完成的步骤会自动跳过
#  用法：右键「使用 PowerShell 运行」，或 .\deploy.ps1
# ============================================================

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\common.ps1')

Write-Banner '安全微伴刷课 · 一键部署'

$root    = Get-ToolRoot
$runtime = Get-RuntimeDir
$src     = Get-SrcDir
$data    = Get-DataDir
$files   = Join-Path $root 'files'

# ---------- 1. 前置检查 ----------
Write-Section '前置检查'

$py = Test-PythonDetail
if (-not $py.Ok) {
    Write-Result -Item 'Python' -Level 'fail' -Detail '未找到 3.11 / 3.12 / 3.13' -Fix '去 python.org 装 Python 3.12，安装时勾选 Add python.exe to PATH，然后重开终端'
    Write-Host "`n部署中止。" -ForegroundColor Red
    exit 1
}
Write-Result -Item 'Python' -Level 'ok' -Detail "$($py.Version)  $($py.Path)"

$browser = Find-Browser
if ($browser) {
    Write-Result -Item '浏览器' -Level 'ok' -Detail $browser
} else {
    Write-Result -Item '浏览器' -Level 'warn' -Detail '未找到 Chrome/Edge' -Fix '验证码自动识别需要它，建议先装 Chrome'
}

if (-not (Test-Path $files)) {
    Write-Result -Item '程序文件' -Level 'fail' -Detail "缺少 files 目录：$files" -Fix '工具包不完整，重新解压'
    exit 1
}

foreach ($d in @($runtime, $src, (Join-Path $data 'answer'), (Join-Path $data 'logs'))) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
}

# ---------- 2. 虚拟环境 ----------
Write-Section '虚拟环境'
$venvPy = Get-VenvPython
$venvDir = Join-Path $runtime '.venv'

# venv 绑死创建时的 Python 路径，从别的电脑拷过来必然失效----这里主动探测并重建
$venvUsable = $false
if (Test-Path $venvPy) {
    # PS 5.1：探测失败时 python 会往 stderr 写内容，会被当成终止错误，必须放宽
    $eapVenv = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $probeVenv = & $venvPy -c "print('VENV-OK')" 2>$null
    $venvProbeCode = $LASTEXITCODE
    $ErrorActionPreference = $eapVenv
    if ($venvProbeCode -eq 0 -and "$probeVenv" -match 'VENV-OK') { $venvUsable = $true }
}

if ($venvUsable) {
    Write-Result -Item '虚拟环境' -Level 'ok' -Detail '已存在，跳过创建'
} else {
    if (Test-Path $venvDir) {
        Write-Result -Item '虚拟环境' -Level 'warn' -Detail '检测到失效环境（通常是换了电脑），正在重建'
        Remove-Item $venvDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Result -Item '虚拟环境' -Level 'info' -Detail '正在创建...'
    & $py.Path -m venv $venvDir
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $venvPy)) {
        Write-Result -Item '虚拟环境' -Level 'fail' -Detail '创建失败'
        exit 1
    }
    Write-Result -Item '虚拟环境' -Level 'ok' -Detail $venvPy
}

# ---------- 3. 程序文件（先铺好，装依赖失败也能恢复） ----------
Write-Section '程序文件'
$copyMap = @{
    'main.py'            = $src
    'client.py'          = $src
    'api.py'             = $src
    'captcha.py'         = $src
    'captcha_model.onnx' = $src
}
foreach ($name in $copyMap.Keys) {
    $from = Join-Path $files $name
    $to   = Join-Path $copyMap[$name] $name
    if (Test-Path $from) {
        Copy-Item $from $to -Force
    } else {
        Write-Result -Item $name -Level 'fail' -Detail "缺少 $from"
    }
}
$ansFrom = Join-Path $files 'answer.json'
$ansTo   = Join-Path $data 'answer\answer.json'
if (Test-Path $ansFrom) {
    Copy-Item $ansFrom $ansTo -Force
}
Write-Result -Item '程序源码' -Level 'ok' -Detail $src
Write-Result -Item '题库' -Level 'ok' -Detail "$([Math]::Round((Get-Item $ansTo).Length/1KB,0)) KB"

# ---------- 4. 配置 ----------
Write-Section '账号配置'
$cfg = Get-ConfigPath
if (Test-Path $cfg) {
    Write-Result -Item 'config.toml' -Level 'ok' -Detail '已存在，保留不覆盖'
} else {
    $tpl = Join-Path $files 'config.example.toml'
    if (Test-Path $tpl) {
        Copy-Item $tpl $cfg -Force
        Write-Result -Item 'config.toml' -Level 'ok' -Detail '已从模板生成'
    } else {
        Write-Result -Item 'config.toml' -Level 'fail' -Detail '模板缺失'
    }
}

# 检查是否已填账号
$raw = Get-Content $cfg -Raw -Encoding UTF8
$mTenant = [regex]::Match($raw, 'tenant_name\s*=\s*"([^"]*)"')
$mUser   = [regex]::Match($raw, '(?m)^username\s*=\s*"([^"]*)"')
if ($mTenant.Success -and $mTenant.Groups[1].Value -and $mUser.Success -and $mUser.Groups[1].Value) {
    Write-Result -Item '账号信息' -Level 'ok' -Detail "$($mTenant.Groups[1].Value) / $($mUser.Groups[1].Value)"
    $needFill = $false
} else {
    Write-Result -Item '账号信息' -Level 'warn' -Detail '尚未填写'
    $needFill = $true
}

# ---------- 5. 依赖（最慢，放最后） ----------
Write-Section '依赖安装'

# PowerShell 5.1 在 ErrorActionPreference=Stop 时会把原生命令写到 stderr 的内容当成
# 终止性错误（NativeCommandError）。新建的 venv 没有依赖，python 必然往 stderr 写
# ModuleNotFoundError，会把脚本直接打断。这里临时放宽，改用 $LASTEXITCODE 判断。
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'

& $venvPy -c "import nodriver,cv2,numpy,requests,pyaes,loguru" 2>$null | Out-Null
$probeExit = $LASTEXITCODE

if ($probeExit -eq 0) {
    Write-Result -Item '依赖包' -Level 'ok' -Detail '已安装，跳过'
} else {
    Write-Host "  正在安装依赖（约 3-8 分钟，取决于网速），请不要关窗口..." -ForegroundColor DarkGray
    $req = Join-Path $files 'requirements.txt'
    $pyMinor = 12
    try { $pyMinor = [int](($py.Version -split '\.')[1]) } catch { }

    if ($pyMinor -lt 11) {
        # websockets 17 要求 >=3.11，3.10 下改用不锁版本的方式让 pip 自选兼容版本
        Write-Host "  Python $($py.Version)：改用兼容模式安装（websockets 自动降级）" -ForegroundColor DarkGray
        $pkgs = @('nodriver', 'opencv-python-headless', 'numpy==1.26.4', 'requests',
                  'pyaes', 'loguru', 'mss', 'openpyxl')
        & $venvPy -m pip install @pkgs -i https://pypi.tuna.tsinghua.edu.cn/simple --quiet 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  清华镜像失败，改用官方源重试（更慢，约 5 分钟）..." -ForegroundColor Yellow
            & $venvPy -m pip install @pkgs --quiet 2>$null | Out-Null
        }
    } else {
        & $venvPy -m pip install -r $req -i https://pypi.tuna.tsinghua.edu.cn/simple --quiet 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  清华镜像失败，改用官方源重试（更慢，约 5 分钟）..." -ForegroundColor Yellow
            & $venvPy -m pip install -r $req --quiet 2>$null | Out-Null
        }
    }

    & $venvPy -c "import nodriver,cv2,numpy,requests,pyaes,loguru" 2>$null | Out-Null
    $probeExit2 = $LASTEXITCODE
    $ErrorActionPreference = $prevEap

    if ($probeExit2 -eq 0) {
        Write-Result -Item '依赖包' -Level 'ok' -Detail '安装完成'
    } else {
        Write-Result -Item '依赖包' -Level 'fail' -Detail '安装失败' -Fix '检查网络后重跑本脚本；或手动执行 runtime\.venv\Scripts\pip.exe install -r files\requirements.txt'
        Write-Host "`n部署中止。" -ForegroundColor Red
        exit 1
    }
}
$ErrorActionPreference = $prevEap

# ---------- 6. 部署后自检 ----------
Write-Section '部署结果'
$rt = Show-RuntimeReport

Write-Banner ''
if ($rt.Ready) {
    Write-Host "  部署完成。" -ForegroundColor Green
} else {
    Write-Host "  部署完成，但仍有阻塞项，看上面的 [X]。`n" -ForegroundColor Yellow
}

if ($needFill) {
    Write-Host "  最后一步：填写账号" -ForegroundColor Cyan
    Write-Host "  用记事本打开：$cfg" -ForegroundColor White
    Write-Host "  把这三行填上（学校全称要和登录页下拉里显示的一字不差）：" -ForegroundColor Gray
    Write-Host '    tenant_name = "广东外语外贸大学"' -ForegroundColor DarkGray
    Write-Host '    username    = "你的学号"' -ForegroundColor DarkGray
    Write-Host '    password    = "你的密码"' -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  填完运行：.\start.ps1" -ForegroundColor Cyan
} else {
    Write-Host "  下一步：.\start.ps1" -ForegroundColor Cyan
}
Write-Host ""
