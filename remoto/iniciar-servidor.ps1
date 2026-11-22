<#
.SYNOPSIS
  Mantem o servidor MCP do NotebookLM no ar em modo remoto (HTTP), reiniciando se cair.

.DESCRIPTION
  Chamado pela tarefa agendada "NotebookLM MCP remoto". Le os segredos de
  segredos.json (mesma pasta), escuta so em 127.0.0.1 e deixa o Tailscale Funnel
  publicar o endereco https. Log em servidor.log (mesma pasta).

  Autor: @pro.hudsontravassos. Licenca MIT.
#>
$ErrorActionPreference = "Stop"
$Here = $PSScriptRoot
$Secrets = Get-Content (Join-Path $Here "segredos.json") -Raw | ConvertFrom-Json
$Exe = $Secrets.server_exe
$Log = Join-Path $Here "servidor.log"

$env:NOTEBOOKLM_MCP_TOKEN = $Secrets.bearer_token
$env:NOTEBOOKLM_MCP_OAUTH_PASSWORD = $Secrets.oauth_password
$env:NOTEBOOKLM_MCP_OAUTH_BASE_URL = $Secrets.base_url
$env:NOTEBOOKLM_MCP_ALLOW_EXTERNAL_BIND = "1"
$env:PYTHONIOENCODING = "utf-8"

while ($true) {
    if ((Test-Path $Log) -and ((Get-Item $Log).Length -gt 5MB)) {
        Move-Item $Log "$Log.1" -Force
    }
    Add-Content $Log "$(Get-Date -Format s) iniciando servidor (perfil $($Secrets.profile), porta $($Secrets.port))"
    # cmd /c redireciona stdout e stderr do executavel sem as quebras do PowerShell 5.1
    $line = "`"$Exe`" --profile $($Secrets.profile) --transport http --host 127.0.0.1 --port $($Secrets.port) --log-level INFO >> `"$Log`" 2>&1"
    cmd.exe /d /c $line
    Add-Content $Log "$(Get-Date -Format s) servidor encerrou (codigo $LASTEXITCODE); reinicio em 15 s"
    Start-Sleep -Seconds 15
}
