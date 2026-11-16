# ============================================================
#  公共函数库（被其它 ps1 dot-source 引用，不单独运行）
#  兼容 Windows PowerShell 5.1 与 PowerShell 7+
# ============================================================

$script:ToolRoot = Split-Path -Parent $PSScriptRoot

function Get-ToolRoot { return $script:ToolRoot }

# ---------- 输出 ----------

function Write-Banner {
    param([string]$Text)
    Write-Host ""
    Write-Host ("=" * 58) -ForegroundColor DarkCyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host ("=" * 58) -ForegroundColor DarkCyan
}

function Write-Section {
    param([string]$Text)
    Write-Host ""
    Write-Host "-- $Text " -ForegroundColor Cyan -NoNewline
    Write-Host ("-" * [Math]::Max(0, 52 - $Text.Length)) -ForegroundColor DarkCyan
}

function Write-Result {
    param(
        [string]$Item,
        [ValidateSet('ok', 'warn', 'fail', 'info')][string]$Level = 'info',
        [string]$Detail = '',
        [string]$Fix = ''
    )
    $mark = '[ ]'; $color = 'Gray'
    switch ($Level) {
        'ok'   { $mark = '[OK]'; $color = 'Green' }
        'warn' { $mark = '[! ]'; $color = 'Yellow' }
        'fail' { $mark = '[X ]'; $color = 'Red' }
        'info' { $mark = '[-]'; $color = 'DarkGray' }
    }
    Write-Host "  $mark " -ForegroundColor $color -NoNewline
    Write-Host $Item -ForegroundColor White -NoNewline
    if ($Detail) { Write-Host "  $Detail" -ForegroundColor DarkGray } else { Write-Host "" }
    if ($Fix) { Write-Host "        -> $Fix" -ForegroundColor Yellow }
}

# ---------- 路径 ----------

function Get-RuntimeDir   { return (Join-Path (Get-ToolRoot) 'runtime') }
function Get-VenvPython   { return (Join-Path (Get-RuntimeDir) '.venv\Scripts\python.exe') }
function Get-SrcDir       { return (Join-Path (Get-RuntimeDir) 'src') }
function Get-DataDir      { return (Join-Path (Get-RuntimeDir) 'data') }
function Get-LogDir       { return (Join-Path (Get-DataDir) 'logs') }
function Get-ConfigPath   { return (Join-Path (Get-DataDir) 'config.toml') }

# ---------- 检测：Python ----------

function Find-Python {
    <#
      返回一个满足 >=3.11 的 python.exe 绝对路径；找不到返回 $null。
      优先 py 启动器（Windows 官方安装方式），其次 PATH 里的 python。
    #>
    $candidates = @()

    # 1) py 启动器最高版本
    $py = Get-Command py -ErrorAction SilentlyContinue
    if ($py) {
        foreach ($v in @('-3.13', '-3.12', '-3.11')) {
            try {
                $out = & py $v -c "import sys;print(sys.executable)" 2>$null
                if ($LASTEXITCODE -eq 0 -and $out) { $candidates += $out.Trim() }
            } catch { }
        }
    }

    # 2) PATH
    $p = Get-Command python -ErrorAction SilentlyContinue
    if ($p) { $candidates += $p.Source }

    # 3) 常见安装位置
    foreach ($v in @('313', '312', '311')) {
        foreach ($base in @("$env:LOCALAPPDATA\Programs\Python\Python$v", "C:\Python$v")) {
            $exe = Join-Path $base 'python.exe'
            if (Test-Path $exe) { $candidates += $exe }
        }
    }

    foreach ($c in ($candidates | Select-Object -Unique)) {
        if (-not (Test-Path $c)) { continue }
        try {
            $ver = & $c -c "import sys;print('%d.%d'%sys.version_info[:2])" 2>$null
            if ($LASTEXITCODE -eq 0 -and $ver) {
                $parts = $ver.Split('.')
                $major = [int]$parts[0]; $minor = [int]$parts[1]
                if ($major -eq 3 -and $minor -ge 10 -and $minor -le 13) { return $c }
            }
        } catch { }
    }
    return $null
}

function Test-PythonDetail {
    <# 返回 @{Path=..;Version=..;Ok=bool} #>
    $exe = Find-Python
    if (-not $exe) { return @{ Path = $null; Version = $null; Ok = $false } }
    $ver = (& $exe -c "import sys;print(sys.version.split()[0])" 2>$null)
    return @{ Path = $exe; Version = "$ver".Trim(); Ok = $true }
}

# ---------- 检测：浏览器 ----------

function Find-Browser {
    $paths = @(
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
        "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
        "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe"
    )
    foreach ($p in $paths) { if (Test-Path $p) { return $p } }
    return $null
}

# ---------- 检测：网络 ----------

function Test-Url {
    param([string]$Url, [int]$TimeoutSec = 8)
    try {
        $req = [System.Net.WebRequest]::Create($Url)
        $req.Method = 'HEAD'
        $req.Timeout = $TimeoutSec * 1000
        $req.Proxy = $null
        $resp = $req.GetResponse()
        $code = [int]$resp.StatusCode
        $resp.Close()
        return ($code -ge 200 -and $code -lt 400)
    } catch {
        return $false
    }
}

# ---------- 检测：端口 ----------

function Test-PortFree {
    param([int]$Port)
    try {
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
        $listener.Start(); $listener.Stop()
        return $true
    } catch { return $false }
}

# ---------- 检测：磁盘 ----------

function Get-FreeGB {
    param([string]$Path)
    try {
        $root = [System.IO.Path]::GetPathRoot((Resolve-Path $Path -ErrorAction SilentlyContinue))
        if (-not $root) { $root = 'C:\' }
        $d = New-Object System.IO.DriveInfo($root)
        return [Math]::Round($d.AvailableFreeSpace / 1GB, 1)
    } catch { return -1 }
}

# ---------- 检测：运行环境 ----------

function Test-Runtime {
    <# 返回 @{Ready=bool; Items=@()} 供自检与启动共用 #>
    $items = @()

    $py = Test-PythonDetail
    if ($py.Ok) {
        $items += @{ Name = 'Python'; Level = 'ok'; Detail = "$($py.Version)  $($py.Path)" }
    } else {
        $items += @{ Name = 'Python'; Level = 'fail'; Detail = '需要 3.11 / 3.12 / 3.13'; Fix = '安装 Python 3.12（python.org），安装时勾选 Add to PATH' }
    }

    $venv = Get-VenvPython
    if (Test-Path $venv) {
        # PS 5.1 下原生命令写 stderr 会被当成终止错误，探测时必须临时放宽
        $eapProbe = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $probeVenv = & $venv -c "print('VENV-OK')" 2>$null
        $venvCode = $LASTEXITCODE
        $ErrorActionPreference = $eapProbe

        if ($venvCode -eq 0 -and "$probeVenv" -match 'VENV-OK') {
            $items += @{ Name = '虚拟环境'; Level = 'ok'; Detail = $venv }
            # 关键依赖是否齐全
            $eapProbe2 = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            & $venv -c "import nodriver,cv2,numpy,requests,pyaes,loguru" 2>$null | Out-Null
            $depCode = $LASTEXITCODE
            $ErrorActionPreference = $eapProbe2

            if ($depCode -eq 0) {
                $items += @{ Name = '依赖包'; Level = 'ok'; Detail = 'nodriver / opencv / numpy / requests / pyaes / loguru' }
            } else {
                $items += @{ Name = '依赖包'; Level = 'fail'; Detail = '缺少依赖'; Fix = '运行 .\deploy.ps1' }
            }
        } else {
            $items += @{ Name = '虚拟环境'; Level = 'fail'; Detail = '已失效（换电脑后会这样）'; Fix = '运行 .\deploy.ps1，会自动重建' }
        }
    } else {
        $items += @{ Name = '虚拟环境'; Level = 'fail'; Detail = '尚未创建'; Fix = '运行 .\deploy.ps1' }
    }

    $src = Get-SrcDir
    $need = @('main.py', 'client.py', 'api.py', 'captcha.py', 'captcha_model.onnx')
    $missing = @($need | Where-Object { -not (Test-Path (Join-Path $src $_)) })
    if ((Test-Path $src) -and ($missing.Count -eq 0)) {
        $items += @{ Name = '程序源码'; Level = 'ok'; Detail = $src }
    } else {
        $items += @{ Name = '程序源码'; Level = 'fail'; Detail = "缺少: $($missing -join ', ')"; Fix = '运行 .\deploy.ps1' }
    }

    $browser = Find-Browser
    if ($browser) {
        $items += @{ Name = '浏览器'; Level = 'ok'; Detail = $browser }
    } else {
        $items += @{ Name = '浏览器'; Level = 'fail'; Detail = '未找到 Chrome / Edge'; Fix = '安装 Chrome 后重试（验证码识别依赖它）' }
    }

    $cfg = Get-ConfigPath
    if (-not (Test-Path $cfg)) {
        $items += @{ Name = '账号配置'; Level = 'fail'; Detail = 'config.toml 不存在'; Fix = '运行 .\deploy.ps1 会生成模板' }
    } else {
        $raw = Get-Content $cfg -Raw -Encoding UTF8
        $m = [regex]::Match($raw, 'tenant_name\s*=\s*"([^"]*)"')
        $u = [regex]::Match($raw, '(?m)^username\s*=\s*"([^"]*)"')
        if ($m.Success -and $m.Groups[1].Value -and $u.Success -and $u.Groups[1].Value) {
            $items += @{ Name = '账号配置'; Level = 'ok'; Detail = "已填写：$($m.Groups[1].Value) / $($u.Groups[1].Value)" }
        } else {
            $items += @{ Name = '账号配置'; Level = 'warn'; Detail = '尚未填写学校/学号'; Fix = "编辑 $cfg 填写 tenant_name / username / password" }
        }
    }

    $ans = Join-Path (Get-DataDir) 'answer\answer.json'
    if (Test-Path $ans) {
        $kb = [Math]::Round((Get-Item $ans).Length / 1KB, 0)
        $items += @{ Name = '题库'; Level = 'ok'; Detail = "$kb KB" }
    } else {
        $items += @{ Name = '题库'; Level = 'warn'; Detail = '未找到，课后习题会随机作答'; Fix = '运行 .\deploy.ps1' }
    }

    $free = Get-FreeGB (Get-ToolRoot)
    if ($free -ge 1) {
        $items += @{ Name = '磁盘空间'; Level = 'ok'; Detail = "$free GB 可用" }
    } else {
        $items += @{ Name = '磁盘空间'; Level = 'fail'; Detail = "$free GB"; Fix = '清理磁盘，至少保留 1GB' }
    }

    $ready = (@($items | Where-Object { $_.Level -eq 'fail' })).Count -eq 0
    return @{ Ready = $ready; Items = $items }
}

function Show-RuntimeReport {
    param($Runtime = $null)
    if (-not $Runtime) { $Runtime = Test-Runtime }
    foreach ($i in $Runtime.Items) {
        Write-Result -Item $i.Name -Level $i.Level -Detail $i.Detail -Fix $i.Fix
    }
    return $Runtime
}


# ============================================================
#  启动前体检（比 Test-Runtime 更全面，供引导脚本使用）
# ============================================================

function Get-SystemProxy {
    <# 返回系统代理地址；未启用返回 $null #>
    try {
        $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
        $reg = Get-ItemProperty -Path $key -ErrorAction Stop
        if ($reg.ProxyEnable -eq 1) {
            if ($reg.ProxyServer) { return "$($reg.ProxyServer)" }
            return '已启用（自动配置）'
        }
        return $null
    } catch { return $null }
}

function Test-UrlLatency {
    param([string]$Url, [int]$TimeoutSec = 8)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $ok = Test-Url -Url $Url -TimeoutSec $TimeoutSec
    $sw.Stop()
    return @{ Ok = $ok; Ms = [int]$sw.ElapsedMilliseconds }
}

function Invoke-Preflight {
    <# 启动前全面体检，返回 @{Items; Ready; Fails}
       注意：所有外部程序调用都已做 stderr 保护，PS5.1 下不会中断 #>
    param([switch]$SkipNetwork)

    $items = @()
    $root = Get-ToolRoot

    # 1. 操作系统
    $osName = ''
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $osName = ($os.Caption -replace 'Microsoft\s*', '').Trim()
    } catch {
        $osName = [Environment]::OSVersion.VersionString
    }
    $arch = '32 位'
    if ([Environment]::Is64BitOperatingSystem) { $arch = '64 位' }
    $items += @{ Name = '操作系统'; Level = 'ok'; Detail = "$osName（$arch）"; Fix = '' }

    # 2. PowerShell 版本
    $psv = $PSVersionTable.PSVersion
    $psLevel = 'ok'
    $psFix = ''
    if ($psv.Major -lt 5) {
        $psLevel = 'warn'
        $psFix = '版本偏低，建议在 Windows 10 / 11 上使用'
    }
    $items += @{ Name = 'PowerShell'; Level = $psLevel; Detail = "$psv"; Fix = $psFix }

    # 3. 磁盘空间
    $free = Get-FreeGB $root
    if ($free -lt 0) {
        $items += @{ Name = '磁盘空间'; Level = 'warn'; Detail = '读取失败'; Fix = '' }
    } elseif ($free -lt 1.5) {
        $items += @{ Name = '磁盘空间'; Level = 'fail'; Detail = "$free GB 可用"; Fix = '至少需要 1.5 GB（Python 环境 + 依赖包）' }
    } else {
        $items += @{ Name = '磁盘空间'; Level = 'ok'; Detail = "$free GB 可用"; Fix = '' }
    }

    # 4. 路径是否含中文
    if ($root -match '[^\x00-\x7F]') {
        $items += @{ Name = '程序路径'; Level = 'warn'; Detail = '含中文'; Fix = '不影响使用；若遇到莫名其妙的错误，可改放到纯英文路径' }
    } else {
        $items += @{ Name = '程序路径'; Level = 'ok'; Detail = $root; Fix = '' }
    }

    # 5. 是否在可移动磁盘
    try {
        $driveRoot = (Split-Path $root -Qualifier) + '\'
        $di = New-Object System.IO.DriveInfo($driveRoot)
        if ($di.DriveType -eq 'Removable') {
            $items += @{ Name = '运行位置'; Level = 'warn'; Detail = '可移动磁盘'; Fix = '可以运行但较慢，建议先复制到本地磁盘' }
        }
    } catch { }

    # 6. 系统代理
    $proxy = Get-SystemProxy
    if ($proxy) {
        $items += @{ Name = '系统代理'; Level = 'warn'; Detail = $proxy; Fix = '代理可能导致 SSL 报错，遇到连接失败先关闭代理' }
    } else {
        $items += @{ Name = '系统代理'; Level = 'ok'; Detail = '未启用'; Fix = '' }
    }

    # 7. 网络连通性
    if (-not $SkipNetwork) {
        $t1 = Test-UrlLatency -Url 'https://weiban.mycourse.cn/index.html' -TimeoutSec 6
        if ($t1.Ok) {
            $items += @{ Name = '平台连通'; Level = 'ok'; Detail = "weiban.mycourse.cn（$($t1.Ms) ms）"; Fix = '' }
        } else {
            $items += @{ Name = '平台连通'; Level = 'fail'; Detail = '无法访问'; Fix = '检查网络 / 校园网认证 / 关闭代理后重试' }
        }

        $t2 = Test-UrlLatency -Url 'https://pypi.tuna.tsinghua.edu.cn/simple/' -TimeoutSec 6
        if ($t2.Ok) {
            $items += @{ Name = '依赖源'; Level = 'ok'; Detail = "清华镜像（$($t2.Ms) ms）"; Fix = '' }
        } else {
            $items += @{ Name = '依赖源'; Level = 'warn'; Detail = '镜像不可达'; Fix = '首次部署会失败，换个网络再试' }
        }
    }

    # 8. Python
    $py = Test-PythonDetail
    if ($py.Ok) {
        $items += @{ Name = 'Python'; Level = 'ok'; Detail = $py.Version; Fix = '' }
    } else {
        $items += @{ Name = 'Python'; Level = 'warn'; Detail = '未安装'; Fix = '不用手动准备，首次使用会引导安装' }
    }

    # 9. 浏览器
    $br = Find-Browser
    if ($br) {
        $items += @{ Name = '浏览器'; Level = 'ok'; Detail = (Split-Path $br -Leaf); Fix = '' }
    } else {
        $items += @{ Name = '浏览器'; Level = 'fail'; Detail = '未找到 Chrome / Edge'; Fix = '验证码自动识别需要它，请先安装 Chrome' }
    }

    # 10. 是否有程序正在占用
    $busy = @()
    try {
        $busy = @(Get-Process -Name python,WeBan -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$root*" })
    } catch { }
    if ($busy.Count -gt 0) {
        $items += @{ Name = '运行状态'; Level = 'warn'; Detail = "已有程序在跑（PID $($busy.Id -join ',')）"; Fix = '等它跑完，或到任务管理器结束 python.exe' }
    }

    $fails = @($items | Where-Object { $_.Level -eq 'fail' })
    return @{ Items = $items; Ready = ($fails.Count -eq 0); Fails = $fails.Count }
}

function Show-Preflight {
    param($Result = $null)
    if (-not $Result) { $Result = Invoke-Preflight }
    foreach ($i in $Result.Items) {
        Write-Result -Item $i.Name -Level $i.Level -Detail $i.Detail -Fix $i.Fix
    }
    return $Result
}