# Modo remoto: NotebookLM no Claude em qualquer lugar

O modo local (`install.ps1`) só atende o computador onde foi instalado. O modo remoto publica o servidor na internet a partir de um computador que fica ligado 24 h. A partir daí ele atende:

| Onde | Como conecta |
|---|---|
| claude.ai no navegador | Conector personalizado, com senha |
| App do Claude no celular | O mesmo conector do claude.ai |
| Claude Code em qualquer computador | `claude mcp add --transport http`, com token |
| Claude Desktop em qualquer computador | Conector do claude.ai, que aparece no Desktop da mesma conta |

O endereço público vem do **Tailscale Funnel**, sem domínio próprio, sem porta aberta no roteador e sem certificado para cuidar. O servidor escuta só em `127.0.0.1` e o Tailscale entrega o tráfego a ele.

## Antes de começar

1. **Computador 24 h.** Escolha a máquina que fica ligada e configure o Windows para entrar sozinho no usuário depois de reiniciar. A tarefa agendada sobe o servidor no logon.
2. **Tailscale instalado e conectado** nessa máquina: https://tailscale.com/download
3. **No painel do Tailscale** (https://login.tailscale.com/admin), uma vez só:
   - **DNS:** ative o **MagicDNS** e os **HTTPS Certificates**.
   - **Access controls:** acrescente à política o atributo `funnel`:
     ```json
     "nodeAttrs": [{ "target": ["autogroup:member"], "attr": ["funnel"] }]
     ```
4. **Conta Google.** O modo remoto usa um **token mestre**, uma credencial permanente com acesso total à conta. O projeto notebooklm-py recomenda uma **conta Google criada só para isso**, com os notebooks compartilhados com ela como editor. Se o token vazar, só essa conta fica exposta.

## Instalação

Na máquina 24 h, dentro da pasta do repositório:

```powershell
powershell -ExecutionPolicy Bypass -File .\remoto\instalar-remoto.ps1 -Account conta@gmail.com
```

O script:

1. Instala o servidor (o mesmo do modo local) com o extra `headless`.
2. Abre o navegador para o login com token mestre, no perfil `remoto`.
3. Gera um **token de acesso** (Claude Code) e uma **senha** (conector do claude.ai).
4. Cria a tarefa agendada **"NotebookLM MCP remoto"**. Ela sobe o servidor a cada logon e o reinicia se ele cair.
5. Liga o **Tailscale Funnel**, que publica `https://<máquina>.<tailnet>.ts.net`.
6. Testa o endereço público e grava os dados de conexão em `%USERPROFILE%\.notebooklm-py\remoto\CONEXAO.txt`.

O modo local continua funcionando na mesma máquina, com o perfil `default`.

## Conectar

Abra o `CONEXAO.txt` gerado na máquina 24 h. Ele traz o endereço, a senha e o comando prontos.

**claude.ai e celular:** Configurações → Conectores → Adicionar conector personalizado. Use o endereço terminado em `/mcp` e deixe as opções avançadas em branco. O claude.ai abre a página de senha do servidor; digite a senha do `CONEXAO.txt`.

**Claude Code em outro computador:**

```powershell
claude mcp add --transport http --scope user notebooklm-remoto https://<máquina>.<tailnet>.ts.net/mcp --header "Authorization: Bearer <token>"
```

## Segurança

| Ponto | Como fica |
|---|---|
| Acesso ao servidor | Sem token ou senha, o servidor responde 401 |
| Token mestre do Google | Fica só na máquina 24 h e nunca passa pelo túnel |
| Token de acesso e senha | Ficam em `%USERPROFILE%\.notebooklm-py\remoto`, pasta com acesso só do seu usuário |
| Criptografia | O Funnel entrega o tráfego cifrado e o certificado fica na própria máquina |
| Ações destrutivas | Excluir e compartilhar exigem `confirm=true` no próprio servidor |

Cuidados:

- **Não publique** o `CONEXAO.txt`, o `segredos.json` nem a pasta `%USERPROFILE%\.notebooklm`.
- **Trocar a senha** não derruba conectores já autorizados. Para revogar de verdade, rode o desinstalador com `-ApagarSegredos` e instale de novo.
- **Dados sigilosos.** O conteúdo dos notebooks passa pelo servidor e chega ao Claude. Avalie as regras do seu órgão antes de servir notebooks com dados protegidos.
- **API não oficial.** O Google pode mudar a API sem aviso e derrubar o servidor.

## Manutenção

| Tarefa | Comando ou local |
|---|---|
| Ver o log | `%USERPROFILE%\.notebooklm-py\remoto\servidor.log` |
| Reiniciar | `Stop-ScheduledTask "NotebookLM MCP remoto"; Start-ScheduledTask "NotebookLM MCP remoto"` |
| Conferir o Funnel | `tailscale funnel status` |
| Tirar do ar | `powershell -ExecutionPolicy Bypass -File .\remoto\desinstalar-remoto.ps1` |
| Tirar do ar e apagar segredos | acrescente `-ApagarSegredos` |

## Limites

- **Ligado ou fora do ar:** o servidor só responde com a máquina 24 h ligada, com internet e com o usuário logado.
- **Um servidor por conta:** não rode duas cópias com o mesmo token mestre, porque uma invalida a sessão da outra.
- **Arquivos:** pelo modo remoto o conector move texto. Para subir arquivos, use o Google Drive ou o site do NotebookLM.

Autor: **@pro.hudsontravassos**. Licença MIT.
