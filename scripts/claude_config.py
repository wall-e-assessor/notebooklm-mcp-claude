"""Edita os arquivos de configuracao do Claude sem apagar as outras chaves.

Comandos:
  settings-add <settings.json> <prefixo>      tempo de espera + permissoes de leitura
  settings-remove <settings.json> <prefixo>   desfaz o settings-add
  desktop-add <config.json> <nome> <exe>      registra o servidor no Claude Desktop
  desktop-remove <config.json> <nome>         remove o servidor do Claude Desktop

Antes de gravar, guarda uma copia "<arquivo>.bak-AAAAMMDD-HHMMSS".
"""
import json
import os
import shutil
import sys
import time

READ_ONLY_TOOLS = [
    "server_info", "notebook_list", "notebook_describe",
    "source_list", "source_read", "source_wait",
    "chat_ask", "chat_start", "chat_status", "suggest_prompts",
    "studio_list", "studio_status", "research_status", "share_status",
]
TIMEOUT_MS = "120000"


def load(path):
    if not os.path.exists(path):
        return {}
    with open(path, encoding="utf-8-sig") as fh:
        text = fh.read().strip()
    return json.loads(text) if text else {}


def save(path, data):
    if os.path.exists(path):
        shutil.copy2(path, f"{path}.bak-{time.strftime('%Y%m%d-%H%M%S')}")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(data, fh, ensure_ascii=False, indent=2)
        fh.write("\n")


def settings_add(path, prefix):
    cfg = load(path)
    env = cfg.setdefault("env", {})
    if int(env.get("MCP_TIMEOUT", "0") or 0) < int(TIMEOUT_MS):
        env["MCP_TIMEOUT"] = TIMEOUT_MS
    allow = cfg.setdefault("permissions", {}).setdefault("allow", [])
    for tool in READ_ONLY_TOOLS:
        rule = f"mcp__{prefix}__{tool}"
        if rule not in allow:
            allow.append(rule)
    save(path, cfg)
    print(f"settings.json: MCP_TIMEOUT={env['MCP_TIMEOUT']} e {len(READ_ONLY_TOOLS)} permissoes de leitura")


def settings_remove(path, prefix):
    cfg = load(path)
    if not cfg:
        return
    allow = cfg.get("permissions", {}).get("allow", [])
    cfg.get("permissions", {})["allow"] = [r for r in allow if not r.startswith(f"mcp__{prefix}__")]
    save(path, cfg)
    print("settings.json: permissoes do servidor removidas (MCP_TIMEOUT mantido)")


def desktop_add(path, name, exe):
    cfg = load(path)
    cfg.setdefault("mcpServers", {})[name] = {"command": exe, "args": []}
    save(path, cfg)
    print(f"Claude Desktop: servidor '{name}' gravado em {path}")


def desktop_remove(path, name):
    cfg = load(path)
    if cfg.get("mcpServers", {}).pop(name, None) is not None:
        save(path, cfg)
        print(f"Claude Desktop: servidor '{name}' removido de {path}")


def main():
    cmd, args = sys.argv[1], sys.argv[2:]
    {
        "settings-add": settings_add,
        "settings-remove": settings_remove,
        "desktop-add": desktop_add,
        "desktop-remove": desktop_remove,
    }[cmd](*args)


if __name__ == "__main__":
    main()
