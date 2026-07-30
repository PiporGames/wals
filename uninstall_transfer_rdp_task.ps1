$ErrorActionPreference = 'Stop'

$TaskName = 'AutologinTransferRdpSession'

$currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principalCheck = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
if (-not $principalCheck.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Ejecuta este desinstalador desde PowerShell como administrador.'
}

$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($task) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "Tarea desinstalada: $TaskName"
}
else {
    Write-Host "La tarea no existe: $TaskName"
}
