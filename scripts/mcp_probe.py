"""Testa o servidor MCP do NotebookLM pelo protocolo, como o Claude o inicia.

Uso: python mcp_probe.py <comando do servidor> [argumentos...]
Mostra o tempo do handshake, o numero de ferramentas e o total de notebooks.
Nao imprime cookies, tokens nem dados da conta.
"""
import json
import subprocess
import sys
import threading
import time


def main() -> int:
    if len(sys.argv) < 2:
        print("uso: python mcp_probe.py <comando do servidor> [args...]")
        return 2

    proc = subprocess.Popen(
        sys.argv[1:],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )

    def send(obj):
        proc.stdin.write((json.dumps(obj) + "\n").encode("utf-8"))
        proc.stdin.flush()

    def recv(timeout=150):
        out = []
        th = threading.Thread(target=lambda: out.append(proc.stdout.readline()), daemon=True)
        th.start()
        th.join(timeout)
        return json.loads(out[0]) if out and out[0] else None

    try:
        t0 = time.time()
        send({
            "jsonrpc": "2.0", "id": 1, "method": "initialize",
            "params": {
                "protocolVersion": "2025-06-18",
                "capabilities": {},
                "clientInfo": {"name": "mcp-probe", "version": "1"},
            },
        })
        if not recv():
            print("FALHOU: o servidor nao respondeu ao handshake")
            return 1
        print(f"handshake: {time.time() - t0:.1f} s")

        send({"jsonrpc": "2.0", "method": "notifications/initialized"})
        send({"jsonrpc": "2.0", "id": 2, "method": "tools/list"})
        tools = recv()["result"]["tools"]
        print(f"ferramentas: {len(tools)}")

        send({"jsonrpc": "2.0", "id": 3, "method": "tools/call",
              "params": {"name": "notebook_list", "arguments": {"limit": 1}}})
        reply = recv()
        result = reply.get("result", {}) if reply else {}
        if result.get("isError") or not result.get("content"):
            print("FALHOU: notebook_list devolveu erro (confira o login)")
            return 1
        data = json.loads(result["content"][0]["text"])
        print(f"notebooks na conta: {data.get('total')}")
        print("OK")
        return 0
    finally:
        proc.kill()


if __name__ == "__main__":
    sys.exit(main())
