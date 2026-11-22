<#
.SYNOPSIS
  Tira o servidor MCP do NotebookLM do ar (modo remoto).

.DESCRIPTION
  Remove a tarefa agendada, desliga o Tailscale Funnel e encerra o servidor. Com
  -ApagarSegredos apaga tambem o token, a senha e o perfil do login remoto, o que
  invalida os conectores ja cadastrados.

  Autor: @pro.hudsontravassos. Licenca MIT.
#>
[CmdletBinding()]
param(
    [string]$InstallDir = (Join-Path $env:USERPROFILE ".notebooklm-py"),
    [string]$Perfil = "remoto",
    [string]$TaskName = "NotebookLM MCP remoto",
    [switch]$ApagarSegredos
)

$RemoteDir = Join-Path $InstallDir "remoto"

if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "Tarefa '$TaskName' removida."
}

$ts = Get-Command tailscale -ErrorAction SilentlyContinue
if ($ts) { & $ts.Source funnel reset 2>$null; Write-Host "Tailscale Funnel desligado." }

Get-CimInstance Win32_Process |
    Where-Object { $_.CommandLine -and $_.CommandLine -like "*notebooklm-mcp*--transport http*" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -Confirm:$false }
Get-CimInstance Win32_Process |
    Where-Object { $_.CommandLine -and $_.CommandLine -like "*iniciar-servidor.ps1*" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -Confirm:$false }
Write-Host "Servidor remoto encerrado."

if ($ApagarSegredos) {
    if (Test-Path $RemoteDir) { Remove-Item $RemoteDir -Recurse -Force -Confirm:$false; Write-Host "Segredos apagados: $RemoteDir" }
    $profileDir = Join-Path $env:USERPROFILE ".notebooklm\profiles\$Perfil"
    if (Test-Path $profileDir) { Remove-Item $profileDir -Recurse -Force -Confirm:$false; Write-Host "Login remoto apagado: $profileDir" }
    $oauthDir = Join-Path $env:USERPROFILE ".notebooklm\oauth"
    if (Test-Path $oauthDir) { Remove-Item $oauthDir -Recurse -Force -Confirm:$false; Write-Host "Estado OAuth apagado: $oauthDir" }
    Write-Host "Revogue tambem o acesso na conta Google: myaccount.google.com > Seguranca > Seus dispositivos."
} else {
    Write-Host "Segredos mantidos em $RemoteDir (use -ApagarSegredos para apagar)."
}
