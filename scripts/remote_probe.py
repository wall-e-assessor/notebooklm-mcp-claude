"""Testa o servidor MCP remoto (HTTP) com o token de acesso.

Uso: python remote_probe.py <url ate /mcp> <bearer token>
Faz o handshake, conta as ferramentas e o total de notebooks. Nao imprime o token.
Tambem confere que um pedido sem token e recusado.
"""
import json
import sys
import time
import urllib.error
import urllib.request


def post(url, payload, token=None, session=None):
    headers = {
        "Content-Type": "application/json",
        "Accept": "application/json, text/event-stream",
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"
    if session:
        headers["Mcp-Session-Id"] = session
    req = urllib.request.Request(url, data=json.dumps(payload).encode(), headers=headers, method="POST")
    with urllib.request.urlopen(req, timeout=120) as resp:
        body = resp.read().decode("utf-8", "replace")
        sid = resp.headers.get("Mcp-Session-Id")
    # Resposta pode vir como JSON puro ou como evento SSE ("data: {...}")
    for line in body.splitlines():
        if line.startswith("data:"):
            body = line[5:].strip()
    return (json.loads(body) if body.strip() else None), sid


def main():
    url, token = sys.argv[1], sys.argv[2]

    try:
        post(url, {"jsonrpc": "2.0", "id": 0, "method": "ping"})
        print("ALERTA: pedido sem token foi aceito")
        return 1
    except urllib.error.HTTPError as err:
        print(f"sem token: recusado (HTTP {err.code}), como esperado")

    t0 = time.time()
    init = {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
        "protocolVersion": "2025-06-18", "capabilities": {},
        "clientInfo": {"name": "remote-probe", "version": "1"}}}
    _, sid = post(url, init, token)
    print(f"handshake: {time.time() - t0:.1f} s")
    post(url, {"jsonrpc": "2.0", "method": "notifications/initialized"}, token, sid)
    tools, _ = post(url, {"jsonrpc": "2.0", "id": 2, "method": "tools/list"}, token, sid)
    print(f"ferramentas: {len(tools['result']['tools'])}")
    res, _ = post(url, {"jsonrpc": "2.0", "id": 3, "method": "tools/call",
                        "params": {"name": "notebook_list", "arguments": {"limit": 1}}}, token, sid)
    data = json.loads(res["result"]["content"][0]["text"])
    print(f"notebooks na conta: {data.get('total')}")
    print("OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
