<#
.SYNOPSIS
  Remove o servidor MCP do NotebookLM instalado pelo install.ps1.

.DESCRIPTION
  Tira o registro do Claude Code e do Claude Desktop, remove as permissoes de leitura do
  settings.json e apaga a pasta da instalacao. O login salvo (%USERPROFILE%\.notebooklm)
  so e apagado com -RemoveLogin.

  Autor: @pro.hudsontravassos. Licenca MIT.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\uninstall.ps1 -RemoveLogin
#>
[CmdletBinding()]
param(
    [string]$InstallDir = (Join-Path $env:USERPROFILE ".notebooklm-py"),
    [string]$ServerName = "notebooklm",
    [switch]$RemoveLogin
)

$ErrorActionPreference = "Stop"
$ScriptsDir = Join-Path $PSScriptRoot "scripts"
$VenvPython = Join-Path $InstallDir ".venv\Scripts\python.exe"
$Helper = Join-Path $ScriptsDir "claude_config.py"

if (Get-Command claude -ErrorAction SilentlyContinue) {
    & claude mcp remove $ServerName -s user 2>$null | Out-Null
    Write-Host "Claude Code: registro '$ServerName' removido."
}

if (Test-Path $VenvPython) {
    & $VenvPython -I $Helper settings-remove (Join-Path $env:USERPROFILE ".claude\settings.json") $ServerName
    $configs = @()
    $dataRoot = Join-Path $env:LOCALAPPDATA "Claude-Data"
    if (Test-Path $dataRoot) {
        $configs += Get-ChildItem $dataRoot -Directory | ForEach-Object { Join-Path $_.FullName "claude_desktop_config.json" }
    }
    $packages = Join-Path $env:LOCALAPPDATA "Packages"
    if (Test-Path $packages) {
        $configs += Get-ChildItem $packages -Directory -Filter "Claude_*" | ForEach-Object { Join-Path $_.FullName "LocalCache\Roaming\Claude\claude_desktop_config.json" }
    }
    $configs += Join-Path $env:APPDATA "Claude\claude_desktop_config.json"
    foreach ($cfg in ($configs | Where-Object { Test-Path $_ })) {
        & $VenvPython -I $Helper desktop-remove $cfg $ServerName
    }
}

# Encerra servidores abertos a partir da pasta, para liberar os arquivos
Get-Process | Where-Object { $_.Path -and $_.Path.StartsWith($InstallDir, [StringComparison]::OrdinalIgnoreCase) } |
    ForEach-Object { Stop-Process -Id $_.Id -Force -Confirm:$false }

if (Test-Path $InstallDir) {
    Remove-Item $InstallDir -Recurse -Force -Confirm:$false
    Write-Host "Pasta removida: $InstallDir"
}

$loginDir = Join-Path $env:USERPROFILE ".notebooklm"
if ($RemoveLogin -and (Test-Path $loginDir)) {
    Remove-Item $loginDir -Recurse -Force -Confirm:$false
    Write-Host "Login salvo removido: $loginDir"
} elseif (Test-Path $loginDir) {
    Write-Host "Login mantido em $loginDir (use -RemoveLogin para apagar)."
}

Write-Host "Pronto. Reinicie o Claude Desktop e abra uma sessao nova do Claude Code."
