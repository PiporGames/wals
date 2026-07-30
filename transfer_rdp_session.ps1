$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$AllowedClientAddresses = @(
    '192.168.1.10'
)
$RdpPort = 3389
$SteamCommand = 'steam://open/bigpicture'

$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$LogFile = Join-Path $ScriptDir 'transfer_rdp_session.log'

function Write-Log {
    param([string]$Message)

    $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
    Write-Host $line
}

function Write-CommandStart {
    param([string]$Command)

    Write-Log "CMD> $Command"
}

function Write-CommandOutput {
    param(
        [string]$CommandName,
        [object]$Output
    )

    if ($null -eq $Output) {
        Write-Log "$CommandName output: <sin salida>"
        return
    }

    $hadOutput = $false
    foreach ($line in $Output) {
        $hadOutput = $true
        Write-Log "$CommandName output: $line"
    }

    if (-not $hadOutput) {
        Write-Log "$CommandName output: <sin salida>"
    }
}

function Normalize-RemoteAddress {
    param([string]$Address)

    if (-not $Address) { return '' }
    return ($Address -replace '%.*$', '').ToLowerInvariant()
}

function Test-AllowedRemoteAddress {
    param([string]$Address)

    $normalizedAddress = Normalize-RemoteAddress $Address
    foreach ($allowedAddress in $AllowedClientAddresses) {
        if ($normalizedAddress -eq (Normalize-RemoteAddress $allowedAddress)) {
            return $true
        }
    }

    return $false
}

function Get-RdpClientConnection {
    Write-Log "Buscando conexión RDP establecida hacia puerto local $RdpPort"
    Write-Log "Direcciones cliente permitidas: $($AllowedClientAddresses -join ', ')"

    try {
        Write-CommandStart "Get-NetTCPConnection -LocalPort $RdpPort -State Established"
        $allConnections = Get-NetTCPConnection -LocalPort $RdpPort -State Established -ErrorAction SilentlyContinue
        if ($allConnections) {
            foreach ($connection in $allConnections) {
                Write-Log "Get-NetTCPConnection output: LocalAddress=$($connection.LocalAddress) LocalPort=$($connection.LocalPort) RemoteAddress=$($connection.RemoteAddress) RemotePort=$($connection.RemotePort) State=$($connection.State) OwningProcess=$($connection.OwningProcess)"
            }
        }
        else {
            Write-CommandOutput 'Get-NetTCPConnection' '<sin conexiones RDP establecidas>'
        }

        Write-CommandStart "Where-Object RemoteAddress in allowed list"
        $connections = $allConnections | Where-Object { Test-AllowedRemoteAddress $_.RemoteAddress }

        if ($connections) {
            foreach ($connection in $connections) {
                Write-Log "Where-Object output: Conexión RDP permitida RemoteAddress=$($connection.RemoteAddress) NormalizedRemoteAddress=$(Normalize-RemoteAddress $connection.RemoteAddress) RemotePort=$($connection.RemotePort) OwningProcess=$($connection.OwningProcess)"
            }
            return $true
        }

        Write-CommandOutput 'Where-Object' '<sin conexiones coincidentes>'
    }
    catch {
        Write-Log "Error consultando Get-NetTCPConnection: $($_.Exception.Message)"
    }

    Write-Log 'No hay conexión RDP establecida desde una dirección permitida'
    return $false
}

function Get-CurrentUserRdpSessionId {
    $currentUser = $env:USERNAME
    Write-Log "Buscando sesión RDP activa para usuario: $currentUser"

    try {
        Write-CommandStart 'quser'
        $output = quser 2>&1
        Write-CommandOutput 'quser' $output

        foreach ($line in ($output | Select-Object -Skip 1)) {
            $cleanLine = ($line -replace '^\s*>', '').Trim()
            if (-not $cleanLine) { continue }

            $parts = $cleanLine -split '\s+'
            if ($parts.Count -lt 4) { continue }

            $username = $parts[0]
            $sessionName = $parts[1]
            $sessionId = $null
            $state = $null

            if ($parts[2] -match '^\d+$') {
                $sessionId = $parts[2]
                $state = $parts[3]
            }
            elseif ($parts[1] -match '^\d+$') {
                $sessionId = $parts[1]
                $state = $parts[2]
                $sessionName = ''
            }

            $isActive = $state -ieq 'Active' -or $state -ieq 'Activo'

            if ($username -ieq $currentUser -and $sessionName -like 'rdp-tcp*' -and $sessionId -and $isActive) {
                Write-Log "Sesión RDP activa encontrada: User=$username SessionName=$sessionName SessionId=$sessionId State=$state"
                return $sessionId
            }
        }
    }
    catch {
        Write-Log "Error consultando quser: $($_.Exception.Message)"
    }

    Write-Log "No se encontró sesión RDP activa para $currentUser"
    return $null
}

function Start-Steam {
    Write-Log "Iniciando Steam: $SteamCommand"

    try {
        Write-CommandStart "Start-Process $SteamCommand"
        Start-Process $SteamCommand
        Write-Log "Steam iniciado"
    }
    catch {
        Write-Log "Error iniciando Steam: $($_.Exception.Message)"
    }
}

Write-Log '=== Inicio transfer_rdp_session.ps1 ==='
Write-Log "Usuario=$env:USERNAME Equipo=$env:COMPUTERNAME ScriptDir=$ScriptDir"

if (-not (Get-RdpClientConnection)) {
    Write-Log 'Saliendo sin acción: la conexión RDP no proviene de la IP permitida'
    Write-Log '=== Fin transfer_rdp_session.ps1 ==='
    exit 0
}

$sessionId = Get-CurrentUserRdpSessionId
if (-not $sessionId) {
    Write-Log 'Saliendo sin acción: no hay sesión RDP activa transferible'
    Write-Log '=== Fin transfer_rdp_session.ps1 ==='
    exit 1
}

Write-Log "Ejecutando transferencia: tscon $sessionId /dest:console"
try {
    Write-CommandStart "tscon $sessionId /DEST:console"
    $tsconOutput = tscon $sessionId /DEST:console 2>&1
    Write-CommandOutput 'tscon' $tsconOutput
    Write-Log "tscon finalizado con exit code $LASTEXITCODE"

    if ($LASTEXITCODE -eq 0) {
        Start-Steam
    }
    else {
        Write-Log 'No se inicia Steam porque tscon falló'
        Write-Log '=== Fin transfer_rdp_session.ps1 ==='
        exit 1
    }
}
catch {
    Write-Log "Error ejecutando tscon: $($_.Exception.Message)"
    Write-Log '=== Fin transfer_rdp_session.ps1 ==='
    exit 1
}

Write-Log '=== Fin transfer_rdp_session.ps1 ==='
