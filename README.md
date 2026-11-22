# notebooklm-mcp-claude

Instalador para **Windows** que conecta o **Google NotebookLM** (hoje chamado Gemini Notebook) ao **Claude Code** e ao **Claude Desktop** (chat e Cowork) por MCP. Com ele, o Claude lista seus notebooks, lê as fontes e faz perguntas ao notebook com citação do trecho de origem.

O servidor MCP vem do projeto [teng-lin/notebooklm-py](https://github.com/teng-lin/notebooklm-py). Este repositório traz a configuração que faz esse servidor ligar de forma estável no Windows, em especial no Claude Desktop.

## Por que este instalador

O instalador oficial do notebooklm-py grava o servidor para abrir com `uvx`. No Windows, testamos e medimos dois problemas:

| Situação | O que acontece |
|---|---|
| **Claude Desktop com `uvx`** | O `uvx` monta o ambiente a cada abertura e confere o pacote na internet. Dentro do Desktop, que roda isolado pelo Windows (MSIX), isso levou cerca de 99 s. O Desktop desiste em 56 s nas sessões do Cowork e do Code e mostra o aviso "Não foi possível iniciar notebooklm". |
| **Claude Code** | Espera 30 s por servidor, por padrão. Num PC de 4 núcleos o servidor leva de 20 a 30 s para ligar, então às vezes cai com `CONNECT_TIMEOUT`. |

O que este instalador faz:

- **Pasta fixa:** instala um Python próprio e o pacote em `%USERPROFILE%\.notebooklm-py`, fora do AppData que o Desktop isola.
- **Versão travada:** fixa a versão do pacote e compila os módulos na instalação, então a abertura não depende da internet.
- **Caminho direto:** registra o servidor no Claude Code e no Claude Desktop apontando para o executável, sem `uvx`. A abertura caiu de cerca de 99 s para cerca de 25 s.
- **Tempo de espera:** sobe para 120 s o limite do Claude Code (`MCP_TIMEOUT`).
- **Permissões:** libera sem pedido de permissão só as 14 ferramentas de leitura. Criar, excluir, adicionar fonte, gerar e compartilhar continuam pedindo confirmação.

## Requisitos

- Windows 10 ou 11
- [uv](https://docs.astral.sh/uv/): `winget install astral-sh.uv`
- Google Chrome (ou Microsoft Edge, com `-Browser msedge`)
- Claude Code e/ou Claude Desktop instalados
- Uma conta Google com acesso ao NotebookLM

## Instalação

Baixe o repositório e rode no PowerShell, dentro da pasta dele:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

Na primeira vez, uma janela do navegador abre para você entrar na conta Google. O instalador salva a sessão sozinho quando detecta o login.

Depois:

1. Abra uma sessão nova do Claude Code.
2. Feche o Claude Desktop pela bandeja do sistema e abra de novo.

### Opções

| Opção | Efeito |
|---|---|
| `-Version 0.8.6` | Versão do notebooklm-py a instalar |
| `-InstallDir <pasta>` | Pasta da instalação (padrão `%USERPROFILE%\.notebooklm-py`) |
| `-ServerName notebooklm` | Nome do servidor no Claude (as ferramentas viram `mcp__notebooklm__*`) |
| `-Browser chrome` | Navegador do login: `chrome`, `msedge` ou `chromium` |
| `-SkipLogin` | Não abre o login |
| `-SkipClaudeCode` / `-SkipDesktop` | Não registra no Code ou no Desktop |
| `-SkipTest` | Não roda o teste final |

Rodar o instalador de novo é seguro: ele mantém o login válido e regrava só o bloco do servidor.

## O que muda no seu computador

| Local | Alteração |
|---|---|
| `%USERPROFILE%\.notebooklm-py\` | Python e pacote do servidor |
| `%USERPROFILE%\.notebooklm\` | Sessão do login no Google (criada pelo notebooklm-py) |
| `%USERPROFILE%\.claude.json` | Servidor registrado no Claude Code, escopo de usuário |
| `%USERPROFILE%\.claude\settings.json` | `MCP_TIMEOUT` de 120 s e permissões das ferramentas de leitura |
| Configuração do Claude Desktop | Bloco `mcpServers.notebooklm`. O instalador procura em `%LOCALAPPDATA%\Claude-Data\*\`, no pacote MSIX e em `%APPDATA%\Claude\` |

Antes de alterar cada `.json`, o instalador guarda uma cópia `.bak-AAAAMMDD-HHMMSS` ao lado do arquivo.

## Teste

O instalador termina com um teste pelo próprio protocolo MCP. Para repetir:

```powershell
& "$env:USERPROFILE\.notebooklm-py\.venv\Scripts\python.exe" -I .\scripts\mcp_probe.py "$env:USERPROFILE\.notebooklm-py\.venv\Scripts\notebooklm-mcp.exe"
```

Saída esperada: tempo do handshake, 38 ferramentas, total de notebooks da conta e `OK`.

## Ferramentas liberadas sem confirmação

`server_info`, `notebook_list`, `notebook_describe`, `source_list`, `source_read`, `source_wait`, `chat_ask`, `chat_start`, `chat_status`, `suggest_prompts`, `studio_list`, `studio_status`, `research_status`, `share_status`.

O `chat_ask` grava cada pergunta no histórico de conversa do notebook, como acontece no site.

## Problemas comuns

| Sintoma | Solução |
|---|---|
| `CONNECT_TIMEOUT` ao abrir o Claude Code | O `MCP_TIMEOUT` só vale em sessão aberta depois da instalação. Abra uma sessão nova. |
| "Não foi possível iniciar notebooklm" no Desktop | Confira se o bloco do Desktop aponta para `notebooklm-mcp.exe` e não para `uvx`. Rode o instalador de novo. |
| Ferramentas respondem `AUTH` | O login expirou. Rode `& "$env:USERPROFILE\.notebooklm-py\.venv\Scripts\notebooklm.exe" login --browser chrome`. O servidor reabre a sessão na chamada seguinte. |
| Conferir o login | `& "$env:USERPROFILE\.notebooklm-py\.venv\Scripts\notebooklm.exe" auth check --test --json` |

## Desinstalar

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
```

Para apagar também a sessão do login, acrescente `-RemoveLogin`. O `MCP_TIMEOUT` fica no `settings.json`, porque outros servidores aproveitam o mesmo limite.

## Segurança

- **Nenhuma credencial neste repositório.** O login fica só no seu computador, em `%USERPROFILE%\.notebooklm\`. Não copie essa pasta para o Git nem para a nuvem: ela dá acesso à sua conta Google.
- **API não oficial.** O notebooklm-py usa APIs internas do Google, sem documentação pública. O Google pode mudar essas APIs sem aviso e quebrar o servidor.
- **Respostas são dado a conferir.** O NotebookLM responde com base nas fontes, mas pode errar. Confira o trecho citado antes de usar a resposta em trabalho importante.

## Créditos

- Servidor MCP e biblioteca: [notebooklm-py](https://github.com/teng-lin/notebooklm-py), de teng-lin, licença MIT.
- Instalador, configuração para Windows e documentação: **@pro.hudsontravassos**.

## Autor

Criado por **@pro.hudsontravassos**.

## Licença

[MIT](./LICENSE)
