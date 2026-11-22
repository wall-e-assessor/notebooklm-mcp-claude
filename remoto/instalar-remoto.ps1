<#
.SYNOPSIS
  Publica o servidor MCP do NotebookLM na internet (modo remoto), para usar no claude.ai,
  no app do celular e no Claude Code de qualquer computador.

.DESCRIPTION
  Rodar no computador que fica ligado 24 h. O script:
    1. instala o servidor (install.ps1 da pasta acima) e o extra "headless";
    2. faz o login com token mestre numa conta Google, no perfil "remoto";
    3. gera o token de acesso (Claude Code/Desktop) e a senha do conector (claude.ai);
    4. cria a tarefa agendada que mantem o servidor no ar a cada logon;
    5. publica o endereco https pelo Tailscale Funnel (sem dominio, sem porta aberta);
    6. testa o endereco publico e grava as instrucoes de conexao em CONEXAO.txt.

  Segredos ficam em %USERPROFILE%\.notebooklm-py\remoto (acesso so do seu usuario) e no
  perfil do login em %USERPROFILE%\.notebooklm\profiles\remoto. Nada disso vai para o Git.

  Pre-requisitos no painel do Tailscale (uma vez): MagicDNS, HTTPS Certificates e o
  atributo "funnel" na politica. Veja remoto\README.md.

  Autor: @pro.hudsontravassos. Licenca MIT.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\remoto\instalar-remoto.ps1 -Account conta@gmail.com
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Account,
    [string]$InstallDir = (Join-Path $env:USERPROFILE ".notebooklm-py"),
    [string]$Perfil = "remoto",
    [int]$Port = 9420,
    [string]$TaskName = "NotebookLM MCP remoto",
    [switch]$SkipLogin,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path $PSScriptRoot -Parent
$RemoteDir = Join-Path $InstallDir "remoto"
$Venv = Join-Path $InstallDir ".venv"
$VenvPython = Join-Path $Venv "Scripts\python.exe"
$ServerExe = Join-Path $Venv "Scripts\notebooklm-mcp.exe"
$CliExe = Join-Path $Venv "Scripts\notebooklm.exe"
$SecretsFile = Join-Path $RemoteDir "segredos.json"

function Write-Step([string]$Text) { Write-Host ""; Write-Host "==> $Text" -ForegroundColor Cyan }
function Write-Ok([string]$Text) { Write-Host "    $Text" -ForegroundColor Green }
function Write-Note([string]$Text) { Write-Host "    $Text" -ForegroundColor Yellow }
function Invoke-Checked([string]$Exe, [string[]]$Arguments) {
    & $Exe @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Falhou: $Exe $($Arguments -join ' ') (codigo $LASTEXITCODE)" }
}
function New-Secret([int]$Bytes = 32) {
    $buf = New-Object byte[] $Bytes
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($buf)
    return ([Convert]::ToBase64String($buf)).TrimEnd("=").Replace("+", "-").Replace("/", "_")
}

# 0. Este computador fica ligado 24 h?
Write-Step "Conferindo o computador"
Write-Ok "Nome: $env:COMPUTERNAME"
if (-not $Force) {
    $answer = Read-Host "    Este computador fica ligado 24 h e e o servidor escolhido? (s/n)"
    if ($answer -notmatch "^[sS]") { throw "Instalacao cancelada. Rode no computador que fica ligado 24 h." }
}

# 1. Tailscale
Write-Step "Conferindo o Tailscale"
$ts = Get-Command tailscale -ErrorAction SilentlyContinue
if (-not $ts) {
    $candidate = Join-Path $env:ProgramFiles "Tailscale\tailscale.exe"
    if (Test-Path $candidate) { $ts = $candidate } else { throw "Tailscale nao encontrado. Instale em https://tailscale.com/download e entre na sua conta." }
} else { $ts = $ts.Source }
$status = (& $ts status --json | Out-String) | ConvertFrom-Json
if ($status.BackendState -ne "Running") { throw "O Tailscale nao esta conectado (estado: $($status.BackendState)). Abra o Tailscale e entre na conta." }
$DnsName = $status.Self.DNSName.TrimEnd(".")
if (-not $DnsName) { throw "Sem nome DNS no Tailscale. Ative o MagicDNS no painel (DNS)." }
$BaseUrl = "https://$DnsName"
Write-Ok "Endereco publico: $BaseUrl"

# 2. Servidor + extra headless
Write-Step "Instalando o servidor"
& (Join-Path $RepoRoot "install.ps1") -InstallDir $InstallDir -SkipLogin -SkipClaudeCode -SkipDesktop -SkipTest
$version = (& $VenvPython -I -c "import importlib.metadata as m; print(m.version('notebooklm-py'))" | Out-String).Trim()
Invoke-Checked "uv" @("pip", "install", "--python", $VenvPython, "--compile-bytecode", "notebooklm-py[mcp,browser,headless]==$version")

# 3. Login com token mestre (perfil separado)
Write-Step "Login com token mestre na conta $Account (perfil '$Perfil')"
if ($SkipLogin) {
    Write-Note "Login pulado. Para fazer depois: & '$CliExe' --profile $Perfil login --master-token --account $Account"
} else {
    Write-Note "Uma janela do navegador vai abrir. Entre com $Account."
    Invoke-Checked $CliExe @("--profile", $Perfil, "login", "--master-token", "--account", $Account)
}

# 4. Segredos (gerados uma vez; mantidos se ja existirem)
Write-Step "Gerando token de acesso e senha do conector"
New-Item -ItemType Directory -Force $RemoteDir | Out-Null
if (Test-Path $SecretsFile) {
    $secrets = Get-Content $SecretsFile -Raw | ConvertFrom-Json
    Write-Ok "Segredos existentes mantidos."
} else {
    $secrets = [pscustomobject]@{ bearer_token = (New-Secret 32); oauth_password = (New-Secret 24) }
}
$secrets = [pscustomobject]@{
    bearer_token   = $secrets.bearer_token
    oauth_password = $secrets.oauth_password
    base_url       = $BaseUrl
    profile        = $Perfil
    port           = $Port
    server_exe     = $ServerExe
    account        = $Account
}
$secrets | ConvertTo-Json | Set-Content -Encoding UTF8 $SecretsFile
Copy-Item (Join-Path $PSScriptRoot "iniciar-servidor.ps1") (Join-Path $RemoteDir "iniciar-servidor.ps1") -Force
# Pasta acessivel so pelo usuario atual (sem heranca de permissoes)
& icacls $RemoteDir /inheritance:r /grant:r "$($env:USERNAME):(OI)(CI)F" | Out-Null
Write-Ok "Segredos em $SecretsFile (acesso so de $env:USERNAME)"

# 5. Tarefa agendada: sobe o servidor a cada logon e o mantem no ar
Write-Step "Criando a tarefa agendada '$TaskName'"
$launcher = Join-Path $RemoteDir "iniciar-servidor.ps1"
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$launcher`""
$trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
    -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings `
    -Description "Servidor MCP do NotebookLM em modo remoto (notebooklm-mcp-claude, @pro.hudsontravassos)" -Force | Out-Null
Get-Process | Where-Object { $_.Path -eq $ServerExe } | ForEach-Object { Stop-Process -Id $_.Id -Force -Confirm:$false }
Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
Start-ScheduledTask -TaskName $TaskName
Write-Ok "Tarefa criada e iniciada."

# 6. Tailscale Funnel: https publico -> 127.0.0.1:porta
Write-Step "Publicando pelo Tailscale Funnel"
Invoke-Checked $ts @("funnel", "--bg", "$Port")
Write-Ok "Funnel ativo: $BaseUrl -> 127.0.0.1:$Port"

# 7. Teste pelo endereco publico
Write-Step "Testando o endereco publico (ate 3 min)"
$ok = $false
for ($i = 0; $i -lt 18 -and -not $ok; $i++) {
    Start-Sleep -Seconds 10
    try {
        $meta = Invoke-RestMethod -Uri "$BaseUrl/.well-known/oauth-authorization-server" -TimeoutSec 15
        if ($meta.issuer.TrimEnd("/") -eq $BaseUrl) { $ok = $true }
    } catch { }
}
if ($ok) {
    Write-Ok "OAuth respondendo em $BaseUrl"
    & $VenvPython -I (Join-Path $RepoRoot "scripts\remote_probe.py") "$BaseUrl/mcp" $secrets.bearer_token
} else {
    Write-Note "O endereco publico nao respondeu. Confira os pre-requisitos do Tailscale e o log em $RemoteDir\servidor.log"
}

# 8. Instrucoes de conexao (ficam na pasta protegida)
$howto = @"
NotebookLM MCP remoto - dados de conexao (NAO compartilhe este arquivo)

claude.ai (navegador e app do celular):
  Configuracoes > Conectores > Adicionar conector personalizado
  URL: $BaseUrl/mcp
  Deixe as opcoes avancadas em branco. Na pagina de senha, use:
  $($secrets.oauth_password)

Claude Code em qualquer computador:
  claude mcp add --transport http --scope user notebooklm-remoto $BaseUrl/mcp --header "Authorization: Bearer $($secrets.bearer_token)"

Conta Google servida: $Account (perfil $Perfil)
"@
$howto | Set-Content -Encoding UTF8 (Join-Path $RemoteDir "CONEXAO.txt")

Write-Step "Pronto"
Write-Ok "Instrucoes de conexao em $RemoteDir\CONEXAO.txt"
Write-Ok "O servidor sobe sozinho a cada logon deste usuario. Configure o Windows para entrar automaticamente se o PC reiniciar sem ninguem."
