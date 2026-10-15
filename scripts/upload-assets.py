"""Carrega a arte de assets/ui para o Roblox e devolve os ids.

    python -I scripts/upload-assets.py            # carrega o que falta
    python -I scripts/upload-assets.py --dry-run  # só mostra o que ia fazer

Usa a Open Cloud (`apis.roblox.com/assets/v1`), que faz o mesmo que o
Gerenciador de Ativos do Studio sem um único clique.

A chave vive em `.secrets/roblox.txt`, que o git ignora:

    linha 1: a chave de API
    linha 2: o teu userId (ou `group:<groupId>` se o jogo for de um grupo)

**É retomável.** Os ids já obtidos ficam em `assets/ui/asset-ids.json` e os
ficheiros que lá estão não voltam a subir — se a ligação cair a meio, correr
outra vez continua de onde ficou em vez de duplicar as imagens.

Só biblioteca padrão: nada para instalar.
"""
import json
import mimetypes
import os
import sys
import time
import urllib.error
import urllib.request
import uuid

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART = os.path.join(ROOT, "assets", "ui")
OUT = os.path.join(ART, "asset-ids.json")
SECRET = os.path.join(ROOT, ".secrets", "roblox.txt")

API = "https://apis.roblox.com/assets/v1"
POLL_TRIES = 40
POLL_WAIT = 3.0


def read_secret() -> tuple[str, dict]:
    if not os.path.exists(SECRET):
        raise SystemExit(
            f"falta {os.path.relpath(SECRET, ROOT)}\n"
            "  linha 1: a chave de API\n"
            "  linha 2: o teu userId, ou group:<groupId>"
        )
    lines = [ln.strip() for ln in open(SECRET, encoding="utf-8") if ln.strip()]
    if len(lines) < 2:
        raise SystemExit("o ficheiro da chave precisa de duas linhas: chave e userId")
    key, owner = lines[0], lines[1]
    if owner.startswith("group:"):
        creator = {"groupId": owner[6:]}
    else:
        creator = {"userId": owner}
    return key, creator


def post(url: str, key: str, fields: list[tuple[str, str, bytes, str | None]]) -> dict:
    """POST multipart/form-data. Cada campo é (nome, tipo, corpo, ficheiro?)."""
    boundary = "----coinkings" + uuid.uuid4().hex
    body = bytearray()
    for name, content_type, payload, filename in fields:
        body += f"--{boundary}\r\n".encode()
        disposition = f'form-data; name="{name}"'
        if filename:
            disposition += f'; filename="{filename}"'
        body += f"Content-Disposition: {disposition}\r\n".encode()
        body += f"Content-Type: {content_type}\r\n\r\n".encode()
        body += payload
        body += b"\r\n"
    body += f"--{boundary}--\r\n".encode()

    req = urllib.request.Request(url, data=bytes(body), method="POST")
    req.add_header("x-api-key", key)
    req.add_header("Content-Type", f"multipart/form-data; boundary={boundary}")
    with urllib.request.urlopen(req, timeout=120) as resp:
        return json.load(resp)


def get(url: str, key: str) -> dict:
    req = urllib.request.Request(url)
    req.add_header("x-api-key", key)
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.load(resp)


def explain(error: urllib.error.HTTPError) -> str:
    detail = error.read().decode("utf-8", "replace")[:400]
    if error.code == 401:
        return "chave recusada (401) — confirma a chave e se já não expirou"
    if error.code == 403:
        return ("sem permissão (403) — a chave precisa de Assets com leitura e "
                f"escrita, e o dono tem de ser quem está na linha 2.\n    {detail}")
    if error.code == 429:
        return "demasiados pedidos (429)"
    return f"HTTP {error.code}: {detail}"


def upload(path: str, name: str, key: str, creator: dict) -> str:
    request = {
        "assetType": "Decal",
        "displayName": f"CoinKings {name}",
        "description": "Arte da interface do Coin Kings.",
        "creationContext": {"creator": creator},
    }
    mime = mimetypes.guess_type(path)[0] or "image/png"
    operation = post(f"{API}/assets", key, [
        ("request", "application/json", json.dumps(request).encode(), None),
        ("fileContent", mime, open(path, "rb").read(), os.path.basename(path)),
    ])

    op = operation.get("path") or f"operations/{operation.get('operationId', '')}"
    for _ in range(POLL_TRIES):
        if operation.get("done"):
            asset = operation.get("response") or {}
            asset_id = asset.get("assetId")
            if asset_id:
                return str(asset_id)
            raise RuntimeError(f"operação terminou sem id: {operation}")
        time.sleep(POLL_WAIT)
        operation = get(f"{API}/{op}", key)
    raise RuntimeError("a operação não terminou a tempo (a moderação pode estar lenta)")


def main(argv: list[str]) -> int:
    dry = "--dry-run" in argv
    key, creator = ("", {}) if dry else read_secret()

    done: dict[str, str] = {}
    if os.path.exists(OUT):
        done = json.load(open(OUT, encoding="utf-8"))

    todo: list[tuple[str, str]] = []
    for folder, _, files in os.walk(ART):
        for f in sorted(files):
            if not f.lower().endswith(".png"):
                continue
            rel = os.path.relpath(os.path.join(folder, f), ART).replace("\\", "/")
            if rel not in done:
                todo.append((rel, os.path.join(folder, f)))

    print(f"{len(done)} já carregadas, {len(todo)} por carregar")
    if dry:
        for rel, _ in todo:
            print("  " + rel)
        return 0

    for index, (rel, path) in enumerate(todo, 1):
        name = os.path.splitext(os.path.basename(rel))[0]
        try:
            done[rel] = upload(path, name, key, creator)
            print(f"  [{index}/{len(todo)}] {rel} -> {done[rel]}")
        except urllib.error.HTTPError as error:
            print(f"  [{index}/{len(todo)}] {rel}: {explain(error)}")
            break
        except Exception as error:  # noqa: BLE001 - queremos guardar o que já foi
            print(f"  [{index}/{len(todo)}] {rel}: {error}")
            break
        finally:
            # grava a cada passo: uma falha a meio nunca perde o que ja subiu
            json.dump(done, open(OUT, "w", encoding="utf-8"), indent=2, sort_keys=True)

    print(f"\n{len(done)} ids em {os.path.relpath(OUT, ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
