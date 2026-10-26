# ============================================================
#  wg_server_setup.ps1 —— WireGuard 服务端一键配置（管理员运行）
#  前提：已装 WireGuard for Windows + Npcap；nva-server.conf 已填好
# ============================================================
$ErrorActionPreference = "Stop"
$wgDir  = "C:\nva\wg"
$conf   = Join-Path $wgDir "nva-server.conf"
$wgNet  = "10.66.0.0/24"
$wgPort = 51820

if (-not (Test-Path $conf)) {
    Write-Host "[!] 找不到 $conf ，先按模板填好配置" -ForegroundColor Red
    Read-Host "按回车退出"; exit 1
}

Write-Host "[1] 注册 WireGuard 隧道服务 ..." -ForegroundColor Cyan
& "C:\Program Files\WireGuard\wireguard.exe" /installtunnelservice $conf | Out-Null
Start-Sleep -Seconds 3

# 找到 WireGuard 创建的接口名（一般和 conf 文件名一致：nva-server）
$alias = (Get-NetIPAddress -AddressPrefix $wgNet -ErrorAction SilentlyContinue | Select-Object -First 1).InterfaceAlias
if (-not $alias) {
    Write-Host "[!] 没找到隧道接口（$wgNet 未生效），检查 conf / 服务状态" -ForegroundColor Red
    & "C:\Program Files\WireGuard\wireguard.exe" /tunnelservice
    Read-Host "按回车退出"; exit 1
}
Write-Host ("    隧道接口: " + $alias) -ForegroundColor Green

Write-Host "[2] 开启 IP 转发（隧道侧 + 出口侧）..." -ForegroundColor Cyan
Set-NetIPInterface -InterfaceAlias $alias -Forwarding Enabled
# 出口网卡 = 有默认网关的那块
$outIf = (Get-NetRoute -DestinationPrefix "0.0.0.0/0" | Sort-Object RouteMetric | Select-Object -First 1).InterfaceAlias
Set-NetIPInterface -InterfaceAlias $outIf -Forwarding Enabled
Write-Host ("    出口网卡: " + $outIf) -ForegroundColor Green

# 系统级 IP 路由开关
$reg = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" -Name IPEnableRouter -ErrorAction SilentlyContinue
if (-not $reg -or $reg.IPEnableRouter -ne 1) {
    Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" -Name IPEnableRouter -Value 1
    Write-Host "    [i] 已打开系统 IP 路由开关（重启后永久生效）" -ForegroundColor Yellow
}

Write-Host "[3] 配置 NAT（手机流量经服务器公网出口）..." -ForegroundColor Cyan
if (-not (Get-NetNat -Name "NvaWG" -ErrorAction SilentlyContinue)) {
    New-NetNat -Name "NvaWG" -InternalIPInterfaceAddressPrefix $wgNet | Out-Null
}
Write-Host "    NAT: NvaWG ($wgNet)" -ForegroundColor Green

Write-Host "[4] 防火墙放行 UDP $wgPort ..." -ForegroundColor Cyan
netsh advfirewall firewall delete rule name="NVA-WG" >$null 2>&1
netsh advfirewall firewall add rule name="NVA-WG" dir=in action=allow protocol=UDP localport=$wgPort | Out-Null

Write-Host ""
Write-Host "完成。下一步以管理员运行:" -ForegroundColor Green
Write-Host ("    runtime\python.exe wg_relay.py --iface \"" + $alias + "\"" ) -ForegroundColor Green
Write-Host "（wg_relay.py 会打印房间号和雷达链接）" -ForegroundColor Gray
Read-Host "按回车关闭"
