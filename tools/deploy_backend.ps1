# ============================================================
#  稳雷达后端 · 部署 / 升级（目标：C:\nva\nva_backend，端口 80）
#
#  用法：远程桌面进服务器 → 管理员 PowerShell → 整段粘贴执行
#
#  做四件事：
#    1. 保留 devices.json（手机 token 不失效，避免 APP 报 401）
#    2. 干掉占着 80 端口的旧进程
#    3. 解压 nva_v6.zip 到 C:\nva
#    4. 建 NVA-Radar 计划任务（SYSTEM 权限、开机自启、崩溃自动重启）+ 自检
# ============================================================
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

$Dest = 'C:\nva'
$App  = Join-Path $Dest 'nva_backend'
$Port = 80

function Say($m, $c = 'Cyan') { Write-Host $m -ForegroundColor $c }

# ---------- 0. 找 zip ----------
$zip = $null
$cands = @(
    (Join-Path $Dest 'nva_v6.zip'),
    'C:\nva_v6.zip',
    "C:\Users\Administrator\Desktop\nva_v6.zip",
    "\\tsclient\C\Users\Administrator\Desktop\nva_v6.zip",
    "\\tsclient\C\nva_v6.zip"
)
foreach ($c in $cands) { if (Test-Path $c) { $zip = $c; break } }
if (-not $zip) {
    Say "[X] 没找到 nva_v6.zip。把桌面那份 nva_v6.zip 拷到服务器的 C:\ 根目录再跑一次。" Red
    Say "    已经试过的位置：" Yellow
    $cands | ForEach-Object { "      $_" }
    exit 1
}
Say "[0] 使用安装包: $zip" Green

# ---------- 1. 备份 devices.json（保住手机 token） ----------
$devBackup = $null
$devPath = Join-Path $App 'devices.json'
if (Test-Path $devPath) {
    $devBackup = Join-Path $Dest ('devices_backup_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.json')
    Copy-Item $devPath $devBackup -Force
    Say "[1] 已备份 devices.json -> $devBackup" Green
} else {
    Say "[1] 没有旧的 devices.json（首次部署）" Yellow
}

# ---------- 2. 干掉占 80 的进程 ----------
Say "[2] 检查 80 端口占用..."
$lines = netstat -ano | Select-String ":$Port\s+.*LISTENING"
foreach ($l in $lines) {
    $t = $l.Line.Trim()
    $pid80 = ($t -split '\s+')[-1]
    Say "    $t"
    if ($pid80 -and $pid80 -ne '0') {
        $pr = Get-Process -Id $pid80 -ErrorAction SilentlyContinue
        if ($pr) { Say ("    杀掉: " + $pr.ProcessName + " (PID $pid80)") Yellow }
        Stop-Process -Id $pid80 -Force -ErrorAction SilentlyContinue
    }
}
# 停掉同名旧服务/旧任务
Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'nva|replica|radar' } | ForEach-Object {
    Say ("    停服务: " + $_.Name) Yellow
    Stop-Service $_.Name -Force -ErrorAction SilentlyContinue
    Set-Service $_.Name -StartupType Disabled -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 2

# ---------- 3. 备份旧目录 + 解压 ----------
if (Test-Path $App) {
    $bak = 'nva_backend_bak_' + (Get-Date -Format 'HHmmss')
    try {
        Rename-Item $App (Join-Path $Dest $bak) -ErrorAction Stop
        Say "[3] 旧版本已备份为 $bak" Green
    } catch {
        Say ("[3] 旧目录占用，改名为 .old: " + $_.Exception.Message) Yellow
        Rename-Item $App ($App + '_old') -ErrorAction SilentlyContinue
    }
}
Say "[3] 解压中（35MB，十几秒）..."
Expand-Archive -Path $zip -DestinationPath $Dest -Force
if (Test-Path (Join-Path $App 'server.py')) {
    Say "[3] 解压完成，server.py 就位" Green
} else {
    Say "[X] 解压失败：没找到 server.py" Red
    exit 1
}

# ---------- 4. 恢复 devices.json ----------
if ($devBackup -and (Test-Path $devBackup)) {
    Copy-Item $devBackup (Join-Path $App 'devices.json') -Force
    Say "[4] devices.json 已恢复（手机 token 继续有效，不会 401）" Green
}

# ---------- 5. 解释器 ----------
$py = Join-Path $App 'runtime\python.exe'
if (Test-Path $py) {
    Say ("[5] 自带运行时: " + (& $py -c "import sys,numpy;print('Python '+sys.version.split()[0]+' numpy '+numpy.__version__)" 2>&1)) Green
} else {
    Say "[5] 没找到自带 runtime\python.exe，改用系统 python" Yellow
    $py = (Get-Command python -ErrorAction SilentlyContinue).Source
    if (-not $py) { Say "[X] 系统也没 python，装不了" Red; exit 1 }
}

# ---------- 6. 防火墙 ----------
netsh advfirewall firewall delete rule name="NVA-80" 2>$null | Out-Null
netsh advfirewall firewall add rule name="NVA-80" dir=in action=allow protocol=TCP localport=$Port | Out-Null
Remove-NetFirewallRule -DisplayName "NVA-80" -ErrorAction SilentlyContinue
New-NetFirewallRule -Name "NVA-80" -DisplayName "NVA-80" -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort $Port -ErrorAction SilentlyContinue | Out-Null
Say "[6] 防火墙已放行 TCP $Port" Green

# ---------- 7. run_service.bat（崩溃自动重启） ----------
$bat = "@echo off`r`ncd /d `"$App`"`r`n:loop`r`necho [%%date%% %%time%%] start >> nva.log`r`nruntime\python.exe server.py --host 0.0.0.0 --port $Port >> nva.log 2>&1`r`necho [%%date%% %%time%%] exited, restart in 3s >> nva.log`r`ntimeout /t 3 /nobreak >nul`r`ngoto loop"
Set-Content -Path (Join-Path $App 'run_service.bat') -Value $bat -Encoding ASCII
Say "[7] run_service.bat 已写入" Green

# ---------- 8. 计划任务 ----------
schtasks /delete /tn "NVA-Radar" /f 2>$null | Out-Null
schtasks /create /tn "NVA-Radar" /tr "`"$App\run_service.bat`"" /sc onstart /delay 0000:20 /ru SYSTEM /rl HIGHEST /f | Out-Null
schtasks /run /tn "NVA-Radar" | Out-String
Say "[8] NVA-Radar 计划任务已注册并启动（SYSTEM 权限，关掉窗口也不会停）" Green

Say "    等 20 秒让解析器冷启动..."
Start-Sleep -Seconds 20

# ---------- 9. 自检 ----------
Say "[9] 自检：" Green
try {
    $r = Invoke-WebRequest -UseBasicParsing ("http://127.0.0.1:{0}/api/device/ping" -f $Port) -TimeoutSec 10
    Write-Host ("    /api/device/ping -> " + $r.StatusCode + " " + $r.Content)
} catch { Write-Host ("    /api/device/ping 失败: " + $_.Exception.Message) -ForegroundColor Red }

$hc = Join-Path $App 'tools\healthcheck.py'
if (Test-Path $hc) {
    Write-Host "    ---- healthcheck ----"
    & $py $hc ("http://127.0.0.1:{0}" -f $Port) 2>&1 | Out-String
}

Write-Host "    ---- 80 端口监听 ----"
(netstat -ano | Select-String ":$Port\s+.*LISTENING" | ForEach-Object { "    " + $_.Line.Trim() })

Write-Host "    ---- nva.log 尾部 ----"
Get-Content (Join-Path $App 'nva.log') -Tail 10 -ErrorAction SilentlyContinue

Write-Host ""
Say "完成。外网验证地址：" Green
Write-Host "    http://120.26.174.238/api/device/ping"
Write-Host "    http://120.26.174.238/radar/"
