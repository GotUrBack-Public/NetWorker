<#
.SYNOPSIS
    NetWorker - modernes PowerShell-Netzwerktool fuer Windows 11.
.DESCRIPTION
    Startet ohne Installation direkt aus einem Git-Clone.
    Erkennt das lokale Netzwerk automatisch und bietet ein nummerisches Menue
    fuer Netzwerkscan, Ping, Geraetezaehlung und Geschwindigkeitsmessung.
    Kompatibel mit Windows PowerShell 5.1 und PowerShell 7.
#>

[CmdletBinding()]
param(
    [switch]$NoLogo
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:NetWorkerVersion = '1.1.0'

function Write-NetWorkerLogo {
    Clear-Host
    if (-not $NoLogo) {
        $line = [string]::new([char]0x2550, 62)
        Write-Host ""
        Write-Host "  $line" -ForegroundColor Cyan
        Write-Host "   _   _      _    __        __            " -ForegroundColor Cyan
        Write-Host "  | \ | | ___| |_  \ \      / /__  _ __ _ _ " -ForegroundColor Green
        Write-Host "  |  \| |/ _ \ __|  \ \ /\ / / _ \| '__| | |" -ForegroundColor Yellow
        Write-Host "  | |\  |  __/ |_    \ V  V / (_) | |  | |_| " -ForegroundColor Magenta
        Write-Host "  |_| \_|\___|\__|    \_/\_/ \___/|_|   \__, |" -ForegroundColor Red
        Write-Host "                                        |___/ " -ForegroundColor DarkGray
        Write-Host "  $line" -ForegroundColor Cyan
        Write-Host "  NetWorker $script:NetWorkerVersion  |  Windows 11 PowerShell  |  no installation" -ForegroundColor DarkGray
        Write-Host ""
    }
}

function Write-NetWorkerMenu {
    Write-Host ""
    Write-Host "  MAIN MENU" -ForegroundColor White
    Write-Host "  ----------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "  [1]  Netzwerk scannen" -ForegroundColor Green
    Write-Host "  [2]  Ping-Test (Gateway, automatisch)" -ForegroundColor Green
    Write-Host "  [3]  Geraete im Netzwerk zaehlen" -ForegroundColor Green
    Write-Host "  [4]  Geschwindigkeit testen" -ForegroundColor Green
    Write-Host "  [5]  Uebersicht / Netzwerk-Info" -ForegroundColor Green
    Write-Host "  [6]  Hilfe" -ForegroundColor Yellow
    Write-Host "  [0]  Beenden" -ForegroundColor Red
    Write-Host "  ----------------------------------------------------------" -ForegroundColor DarkGray
}

function Get-NetWorkerLocalIPv4 {
    $adapter = Get-NetIPConfiguration -ErrorAction SilentlyContinue |
        Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' } |
        Select-Object -First 1

    if (-not $adapter) {
        $adapter = Get-NetIPConfiguration -ErrorAction SilentlyContinue |
            Where-Object { $_.IPv4Address -and $_.NetAdapter.Status -eq 'Up' } |
            Select-Object -First 1
    }

    if (-not $adapter -or -not $adapter.IPv4Address) {
        throw "Keine aktive IPv4-Netzwerkverbindung gefunden."
    }

    $ipv4 = $adapter.IPv4Address.IPAddress
    $prefix = [int]$adapter.IPv4Address.PrefixLength
    $maskValue = [uint32]([Math]::Pow(2, 32) - [Math]::Pow(2, 32 - $prefix))
    $maskBytes = [byte[]]@(
        [byte](($maskValue -shr 24) -band 0xFF),
        [byte](($maskValue -shr 16) -band 0xFF),
        [byte](($maskValue -shr 8) -band 0xFF),
        [byte]($maskValue -band 0xFF)
    )

    $ipBytes = [System.Net.IPAddress]::Parse($ipv4).GetAddressBytes()
    $networkBytes = [byte[]]@(
        [byte]($ipBytes[0] -band $maskBytes[0]),
        [byte]($ipBytes[1] -band $maskBytes[1]),
        [byte]($ipBytes[2] -band $maskBytes[2]),
        [byte]($ipBytes[3] -band $maskBytes[3])
    )
    $network = ([System.Net.IPAddress]::new($networkBytes)).IPAddressToString

    $gateway = $null
    if ($adapter.IPv4DefaultGateway) { $gateway = $adapter.IPv4DefaultGateway.NextHop }

    return [pscustomobject]@{
        InterfaceAlias = $adapter.InterfaceAlias
        IPv4           = $ipv4
        PrefixLength   = $prefix
        Gateway        = $gateway
        Network        = $network
        SubnetMask     = ([System.Net.IPAddress]::new($maskBytes)).IPAddressToString
    }
}

function Get-NetWorkerSubnetRange {
    param(
        [Parameter(Mandatory)] [string]$Network,
        [Parameter(Mandatory)] [int]$PrefixLength
    )

    if ($PrefixLength -lt 16 -or $PrefixLength -gt 30) {
        throw "Subnetze mit /$PrefixLength sind fuer einen schnellen Scan zu gross oder zu klein. Bitte /16 bis /30 verwenden."
    }

    $baseBytes = [System.Net.IPAddress]::Parse($Network).GetAddressBytes()
    $base = [uint32](($baseBytes[0] * 16777216) + ($baseBytes[1] * 65536) + ($baseBytes[2] * 256) + $baseBytes[3])
    $hostCount = [int]([Math]::Pow(2, 32 - $PrefixLength) - 2)
    if ($hostCount -gt 1024) {
        throw "Dieses Subnetz enthaelt zu viele Hosts ($hostCount). Bitte ein kleineres Subnetz verwenden."
    }

    $ips = [System.Collections.Generic.List[string]]::new()
    for ($i = 1; $i -le $hostCount; $i++) {
        $ipValue = $base + $i
        $bytes = [byte[]]@(
            [byte](($ipValue -shr 24) -band 0xFF),
            [byte](($ipValue -shr 16) -band 0xFF),
            [byte](($ipValue -shr 8) -band 0xFF),
            [byte]($ipValue -band 0xFF)
        )
        $ips.Add(([System.Net.IPAddress]::new($bytes)).IPAddressToString)
    }

    return $ips
}

function Test-NetWorkerHost {
    param([Parameter(Mandatory)] [string]$IPAddress)

    $result = Test-Connection -ComputerName $IPAddress -Count 1 -Quiet -ErrorAction SilentlyContinue
    if (-not $result) {
        return $null
    }

    $name = $IPAddress
    try {
        $name = [System.Net.Dns]::GetHostEntry($IPAddress).HostName
    } catch {
        $name = $IPAddress
    }

    return [pscustomobject]@{
        IPAddress = $IPAddress
        Hostname  = $name
        Status    = 'Online'
    }
}

function Invoke-NetWorkerScan {
    Write-Host ""
    Write-Host "  Netzwerk-Scan wird gestartet..." -ForegroundColor Cyan
    $local = Get-NetWorkerLocalIPv4
    Write-Host ("  Gateway: {0} | eigenes Subnetz: {1}/{2}" -f $local.Gateway, $local.Network, $local.PrefixLength) -ForegroundColor DarkGray

    $ips = Get-NetWorkerSubnetRange -Network $local.Network -PrefixLength $local.PrefixLength
    Write-Host ("  Pruefe {0} Adressen (max. 1024)..." -f $ips.Count) -ForegroundColor DarkGray

    $found = foreach ($ip in $ips) {
        $hostInfo = Test-NetWorkerHost -IPAddress $ip
        if ($hostInfo) { $hostInfo }
    }
    $found = @($found)

    if ($found.Count -eq 0) {
        Write-Host "  Keine Geraete gefunden." -ForegroundColor Yellow
    } else {
        Write-Host ""
        Write-Host ("  {0} Geraet(e) gefunden:" -f $found.Count) -ForegroundColor Green
        $found | Format-Table -AutoSize
    }
    Read-Host "  Enter zum Zurueckkehren"
}

function Invoke-NetWorkerPing {
    $local = Get-NetWorkerLocalIPv4
    $target = if ($local.Gateway) { $local.Gateway } else { '8.8.8.8' }
    $count = 4

    Write-Host ""
    Write-Host ("  Ping an {0} (automatisch, {1} Pakete)..." -f $target, $count) -ForegroundColor Cyan

    $pings = @(Test-Connection -ComputerName $target -Count $count -ErrorAction SilentlyContinue)
    $success = @($pings | Where-Object { $_.StatusCode -eq 0 -or $_.Status -eq 'Success' })
    $times = @($success | ForEach-Object {
        if ($null -ne $_.ResponseTime) { [int]$_.ResponseTime } elseif ($null -ne $_.Latency) { [int]$_.Latency }
    })

    $avg = 0; $min = 0; $max = 0
    if ($times.Count -gt 0) {
        $avg = [Math]::Round(($times | Measure-Object -Average).Average, 1)
        $min = ($times | Measure-Object -Minimum).Minimum
        $max = ($times | Measure-Object -Maximum).Maximum
    }
    $denominator = [double]$count
    $loss = [Math]::Round((1 - ($success.Count / $denominator)) * 100, 1)

    $pings | Format-Table -AutoSize
    Write-Host ""
    Write-Host ("  Ergebnis: {0}/{1} erreichbar | Verlust: {2}% | Ping min/avg/max: {3}/{4}/{5} ms" -f $success.Count, $count, $loss, $min, $avg, $max) -ForegroundColor Green
    Read-Host "  Enter zum Zurueckkehren"
}

function Invoke-NetWorkerDeviceCount {
    Write-Host ""
    Write-Host "  Zaehle Geraete im lokalen Subnetz..." -ForegroundColor Cyan
    $local = Get-NetWorkerLocalIPv4
    $ips = Get-NetWorkerSubnetRange -Network $local.Network -PrefixLength $local.PrefixLength
    Write-Host ("  Pruefe {0} Adressen..." -f $ips.Count) -ForegroundColor DarkGray

    $found = foreach ($ip in $ips) {
        $hostInfo = Test-NetWorkerHost -IPAddress $ip
        if ($hostInfo) { $hostInfo }
    }
    $found = @($found)

    Write-Host ""
    Write-Host ("  Gefundene Geraete: {0}" -f $found.Count) -ForegroundColor Green
    if ($found.Count -gt 0) {
        $found | Format-Table IPAddress, Hostname, Status -AutoSize
    }
    Read-Host "  Enter zum Zurueckkehren"
}

function Invoke-NetWorkerSpeedTest {
    Write-Host ""
    Write-Host "  Einfacher Geschwindigkeitstest (automatisch)..." -ForegroundColor Cyan
    Write-Host "  Hinweis: Laedt eine kleine Datei und schaetzt die Download-Geschwindigkeit." -ForegroundColor DarkGray

    $url = 'https://speed.cloudflare.com/__down?bytes=1000000'
    try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 30
        $sw.Stop()
        $bytes = [int64]$response.RawContentLength
        if ($bytes -le 0 -and $response.Content) { $bytes = [int64]$response.Content.Length }
        $seconds = [Math]::Max($sw.Elapsed.TotalSeconds, 0.001)
        $mbps = [Math]::Round(($bytes * 8 / 1MB) / $seconds, 2)

        Write-Host ""
        Write-Host ("  Download: {0} KB in {1:N2}s" -f [Math]::Round($bytes / 1KB, 1), $sw.Elapsed.TotalSeconds) -ForegroundColor White
        Write-Host ("  Geschwindigkeit: {0} Mbit/s" -f $mbps) -ForegroundColor Green
    } catch {
        Write-Host ("  Test fehlgeschlagen: {0}" -f $_.Exception.Message) -ForegroundColor Red
    }
    Read-Host "  Enter zum Zurueckkehren"
}

function Show-NetWorkerOverview {
    $local = Get-NetWorkerLocalIPv4
    $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | Select-Object Name, InterfaceDescription, LinkSpeed, MacAddress
    Write-Host ""
    Write-Host "  Netzwerk-Uebersicht" -ForegroundColor Cyan
    [pscustomobject]@{
        Interface = $local.InterfaceAlias
        IPv4      = $local.IPv4
        Subnetz   = "$($local.Network)/$($local.PrefixLength)"
        Gateway   = $local.Gateway
        Maske     = $local.SubnetMask
    } | Format-List
    if ($adapters) { $adapters | Format-Table -AutoSize }
    Read-Host "  Enter zum Zurueckkehren"
}

function Show-NetWorkerHelp {
    Write-Host ""
    Write-Host "  NetWorker Hilfe" -ForegroundColor Cyan
    Write-Host "  - [1] scannt das lokale IPv4-Subnetz per Ping." -ForegroundColor White
    Write-Host "  - [2] testet automatisch das Gateway mit ICMP-Ping." -ForegroundColor White
    Write-Host "  - [3] zaehlt erreichbare Geraete im Subnetz." -ForegroundColor White
    Write-Host "  - [4] misst eine einfache Download-Geschwindigkeit." -ForegroundColor White
    Write-Host "  - [5] zeigt lokale IP, Gateway, Subnetz und aktive Adapter." -ForegroundColor White
    Write-Host "  - [0] beendet NetWorker." -ForegroundColor White
    Write-Host ""
    Read-Host "  Enter zum Zurueckkehren"
}

function Start-NetWorker {
    do {
        Write-NetWorkerLogo
        Write-NetWorkerMenu
        $choice = Read-Host "  Auswahl"

        switch ($choice) {
            '1' { Invoke-NetWorkerScan }
            '2' { Invoke-NetWorkerPing }
            '3' { Invoke-NetWorkerDeviceCount }
            '4' { Invoke-NetWorkerSpeedTest }
            '5' { Show-NetWorkerOverview }
            '6' { Show-NetWorkerHelp }
            '0' { Write-Host ""; Write-Host "  NetWorker beendet." -ForegroundColor Cyan; return }
            default { Write-Host "  Ungueltige Auswahl." -ForegroundColor Red; Start-Sleep -Milliseconds 600 }
        }
    } while ($true)
}

Start-NetWorker