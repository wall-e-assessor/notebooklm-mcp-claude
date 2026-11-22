<#
.SYNOPSIS
  Instala o servidor MCP do NotebookLM (notebooklm-py) para o Claude Code e o Claude Desktop no Windows.

.DESCRIPTION
  Cria um Python e um ambiente proprios numa pasta fixa do perfil (fora do AppData), instala o
  pacote notebooklm-py numa versao travada, faz o login no Google (so na primeira vez) e registra
  o servidor no Claude Code e no Claude Desktop apontando direto para o executavel, sem uvx.

  Nenhuma credencial sai do computador: o login fica em %USERPROFILE%\.notebooklm.

  Autor: @pro.hudsontravassos. Licenca MIT.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\install.ps1
#>
[CmdletBinding()]
param(
    [string]$Version = "0.8.6",
    [string]$InstallDir = (Join-Path $env:USERPROFILE ".notebooklm-py"),
    [string]$ServerName = "notebooklm",
    [ValidateSet("chrome", "msedge", "chromium")]
    [string]$Browser = "chrome",
    [switch]$SkipLogin,
    [switch]$SkipClaudeCode,
    [switch]$SkipDesktop,
    [switch]$SkipTest
)

$ErrorActionPreference = "Stop"
$ScriptsDir = Join-Path $PSScriptRoot "scripts"
$Venv = Join-Path $InstallDir ".venv"
$VenvPython = Join-Path $Venv "Scripts\python.exe"
$ServerExe = Join-Path $Venv "Scripts\notebooklm-mcp.exe"
$CliExe = Join-Path $Venv "Scripts\notebooklm.exe"

function Write-Step([string]$Text) { Write-Host ""; Write-Host "==> $Text" -ForegroundColor Cyan }
function Write-Ok([string]$Text) { Write-Host "    $Text" -ForegroundColor Green }
function Write-Note([string]$Text) { Write-Host "    $Text" -ForegroundColor Yellow }

function Invoke-Checked([string]$Exe, [string[]]$Arguments) {
    & $Exe @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Falhou: $Exe $($Arguments -join ' ') (codigo $LASTEXITCODE)" }
}

function Get-DesktopConfigPaths {
    # O Claude Desktop instalado pela Microsoft Store (MSIX) guarda a configuracao fora do
    # %APPDATA%\Claude. Procura nos tres lugares conhecidos e devolve os que existem.
    $found = @()
    $dataRoot = Join-Path $env:LOCALAPPDATA "Claude-Data"
    if (Test-Path $dataRoot) {
        $found += Get-ChildItem $dataRoot -Directory -ErrorAction SilentlyContinue |
            ForEach-Object { Join-Path $_.FullName "claude_desktop_config.json" } |
            Where-Object { Test-Path $_ }
    }
    $packages = Join-Path $env:LOCALAPPDATA "Packages"
    if (Test-Path $packages) {
        $found += Get-ChildItem $packages -Directory -Filter "Claude_*" -ErrorAction SilentlyContinue |
            ForEach-Object { Join-Path $_.FullName "LocalCache\Roaming\Claude\claude_desktop_config.json" } |
            Where-Object { Test-Path $_ }
    }
    $classic = Join-Path $env:APPDATA "Claude\claude_desktop_config.json"
    if (Test-Path $classic) { $found += $classic }
    if ($found.Count -eq 0 -and (Test-Path (Join-Path $env:APPDATA "Claude"))) { $found += $classic }
    return $found | Select-Object -Unique
}

# 1. Pre-requisitos
Write-Step "Conferindo o uv"
if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
    throw "O uv nao foi encontrado. Instale com: winget install astral-sh.uv   (depois abra um terminal novo)"
}
Write-Ok (uv --version)

# 2. Python proprio, fora do AppData
Write-Step "Instalando o Python 3.12 em $InstallDir\python"
New-Item -ItemType Directory -Force $InstallDir | Out-Null
Invoke-Checked "uv" @("python", "install", "3.12", "--install-dir", (Join-Path $InstallDir "python"), "--no-bin")
$BasePython = Get-ChildItem (Join-Path $InstallDir "python") -Recurse -Filter python.exe |
    Where-Object { $_.DirectoryName -notmatch "\\Scripts$" } | Select-Object -First 1 -ExpandProperty FullName
if (-not $BasePython) { throw "Python nao encontrado em $InstallDir\python" }
Write-Ok $BasePython

# 3. Ambiente e pacote
Write-Step "Instalando notebooklm-py $Version"
$installed = $null
if (Test-Path $VenvPython) {
    $installed = (& $VenvPython -I -c "import importlib.metadata as m; print(m.version('notebooklm-py'))" 2>$null | Out-String).Trim()
}
if ($installed -eq $Version) {
    Write-Ok "Versao $Version ja instalada; ambiente mantido."
} else {
    # O Windows trava os executaveis em uso: fecha servidores abertos a partir desta pasta.
    $running = @(Get-Process | Where-Object { $_.Path -and $_.Path.StartsWith($InstallDir, [StringComparison]::OrdinalIgnoreCase) })
    if ($running.Count -gt 0) {
        Write-Note "Encerrando $($running.Count) processo(s) do servidor em uso para atualizar os arquivos."
        $running | ForEach-Object { Stop-Process -Id $_.Id -Force -Confirm:$false }
        Start-Sleep -Seconds 2
    }
    if (-not (Test-Path $VenvPython)) {
        Invoke-Checked "uv" @("venv", $Venv, "--python", $BasePython)
    }
    Invoke-Checked "uv" @("pip", "install", "--python", $VenvPython, "--compile-bytecode", "notebooklm-py[mcp,browser]==$Version")
}
Write-Ok (& $CliExe --version)

# 4. Login (so se ainda nao houver sessao valida)
Write-Step "Conferindo o login no NotebookLM"
$authOk = $false
try {
    $auth = (& $CliExe auth check --json 2>$null | Out-String) | ConvertFrom-Json
    $authOk = ($auth.status -eq "ok")
} catch { $authOk = $false }
if ($authOk) {
    Write-Ok "Sessao valida encontrada; login nao repetido."
} elseif ($SkipLogin) {
    Write-Note "Sem sessao valida. Rode depois: & '$CliExe' login --browser $Browser"
} else {
    Write-Note "Uma janela do navegador vai abrir. Entre com a conta Google dos seus notebooks (prazo: 5 min)."
    Invoke-Checked $CliExe @("login", "--browser", $Browser, "--browser-timeout", "300")
}

# 5. Claude Code
if (-not $SkipClaudeCode) {
    Write-Step "Registrando no Claude Code"
    if (Get-Command claude -ErrorAction SilentlyContinue) {
        & claude mcp remove $ServerName -s user 2>$null | Out-Null
        Invoke-Checked "claude" @("mcp", "add", $ServerName, "--scope", "user", "--", $ServerExe)
        $settings = Join-Path $env:USERPROFILE ".claude\settings.json"
        Invoke-Checked $VenvPython @("-I", (Join-Path $ScriptsDir "claude_config.py"), "settings-add", $settings, $ServerName)
    } else {
        Write-Note "Comando 'claude' nao encontrado; Claude Code pulado."
    }
}

# 6. Claude Desktop (chat e Cowork)
if (-not $SkipDesktop) {
    Write-Step "Registrando no Claude Desktop"
    $configs = @(Get-DesktopConfigPaths)
    if ($configs.Count -eq 0) {
        Write-Note "Configuracao do Claude Desktop nao encontrada. Abra o Desktop uma vez e rode o instalador de novo."
    }
    foreach ($cfg in $configs) {
        Invoke-Checked $VenvPython @("-I", (Join-Path $ScriptsDir "claude_config.py"), "desktop-add", $cfg, $ServerName, $ServerExe)
    }
}

# 7. Teste
if (-not $SkipTest) {
    Write-Step "Testando o servidor como o Claude o inicia"
    Invoke-Checked $VenvPython @("-I", (Join-Path $ScriptsDir "mcp_probe.py"), $ServerExe)
}

Write-Step "Pronto"
Write-Ok "Abra uma sessao nova do Claude Code e reinicie o Claude Desktop (feche pela bandeja do sistema)."
Write-Ok "Servidor: $ServerName  ->  $ServerExe"
