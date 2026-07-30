$ErrorActionPreference = 'Stop'

$TaskName = 'AutologinTransferRdpSession'
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$TransferScript = Join-Path $ScriptDir 'transfer_rdp_session.ps1'

if (-not (Test-Path $TransferScript)) {
    throw "No se encontró $TransferScript"
}

$currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principalCheck = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
if (-not $principalCheck.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Ejecuta este instalador desde PowerShell como administrador.'
}

$escapedScript = $TransferScript.Replace('"', '\"')
$action = New-ScheduledTaskAction `
    -Execute 'powershell.exe' `
    -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$escapedScript`""

$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$principal = New-ScheduledTaskPrincipal `
    -UserId $env:USERNAME `
    -LogonType Interactive `
    -RunLevel Highest

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 5) `
    -MultipleInstances IgnoreNew

$task = New-ScheduledTask `
    -Action $action `
    -Trigger $trigger `
    -Principal $principal `
    -Settings $settings `
    -Description 'Transfiere una sesión RDP autorizada a consola e inicia Steam.'

Register-ScheduledTask -TaskName $TaskName -InputObject $task -Force | Out-Null

Write-Host "Tarea instalada: $TaskName"
Write-Host "Se ejecutará al iniciar sesión el usuario $env:USERNAME con privilegios elevados."
Write-Host "Script: $TransferScript"
