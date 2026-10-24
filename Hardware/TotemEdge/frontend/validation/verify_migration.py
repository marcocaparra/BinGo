"""Verifica assets e preservação do protótipo após integração da entrada local."""

from functools import partial
from hashlib import sha256
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import re
import subprocess
from threading import Thread
from urllib.parse import quote
from urllib.request import urlopen


FRONTEND = Path(__file__).resolve().parents[1]
REPO = FRONTEND.parents[2]
SOURCE = REPO / "Software/apps/totem_ui"
REPLACEMENTS = {
    "../../mobile/bingo_app/assets/fonts/Sora[wght].ttf": "./assets/fonts/Sora[wght].ttf",
    "../../mobile/bingo_app/assets/fonts/Inter[opsz,wght].ttf": "./assets/fonts/Inter[opsz,wght].ttf",
    "../../mobile/bingo_app/assets/images/Praça Central - Limpa.png": "./assets/backgrounds/Praça Central - Limpa.png",
}
EXTRA_ASSETS = {
    "fonts/Sora[wght].ttf": "fonts/Sora[wght].ttf",
    "fonts/Inter[opsz,wght].ttf": "fonts/Inter[opsz,wght].ttf",
    "backgrounds/Praça Central - Limpa.png": "images/Praça Central - Limpa.png",
}


class QuietHandler(SimpleHTTPRequestHandler):
    def log_message(self, *_args):
        pass


def main():
    original = sorted(
        p for p in SOURCE.rglob("*") if p.is_file() and p.name != ".gitignore"
    )
    identical = 0
    inventory = []
    for source in original:
        relative = source.relative_to(SOURCE)
        dest = FRONTEND / relative
        expected = source.read_bytes()
        if relative.as_posix() in {"index.html", "styles.css"}:
            for before, after in REPLACEMENTS.items():
                expected = expected.replace(before.encode(), after.encode())
        elif relative.as_posix() != "script.js":
            identical += 1
        name = relative.as_posix()
        if name == "script.js":
            marker = 'kiosk.addEventListener("click", handleKioskClick);'
            assert source.read_text(encoding="utf-8").split(marker)[0] == dest.read_text(encoding="utf-8").split('if (new URLSearchParams(window.location.search).get("runtime")')[0]
        elif name == "index.html":
            assert '<script src="./local_api.js"></script>' in dest.read_text(encoding="utf-8")
            assert '<script src="./operational.js"></script>' in dest.read_text(encoding="utf-8")
        elif name == "styles.css":
            actual = dest.read_text(encoding="utf-8")
            original_css = expected.decode("utf-8").replace("\r\n", "\n")
            assert original_css in actual, "Estilos originais alterados além de caminhos/banner"
        else:
            assert dest.read_bytes() == expected, f"Divergência: {relative}"
        inventory.append(dest)
    inventory.extend(FRONTEND / name for name in ("local_api.js", "operational.js"))
    for target, origin in EXTRA_ASSETS.items():
        dest = FRONTEND / "assets" / target
        source = REPO / "Software/mobile/bingo_app/assets" / origin
        assert dest.read_bytes() == source.read_bytes(), f"Asset diferente: {target}"
        inventory.append(dest)

    references = []
    for name in ("index.html", "styles.css", "script.js"):
        code = (FRONTEND / name).read_text(encoding="utf-8")
        assert "../../mobile/" not in code, name
        found = re.findall(r'(?:src|href)=["\']([^"\']+)', code)
        found += re.findall(r'url\(["\']?([^"\')]+)', code)
        found += re.findall(r'["\'](\./assets/[^"\']+)["\']', code)
        for ref in found:
            if "${" in ref or ref.startswith("(["):
                continue  # Template dinâmico ou regex do preloader, não URL literal.
            path = ref.split("?", 1)[0]
            assert path.startswith("./"), f"Referência não local: {ref}"
            resolved = (FRONTEND / path).resolve()
            assert resolved.is_relative_to(FRONTEND) and resolved.is_file(), ref
            references.append(path)

    subprocess.run(["node", "--check", str(FRONTEND / "script.js")], check=True)
    for name in ("local_api.js", "operational.js"):
        subprocess.run(["node", "--check", str(FRONTEND / name)], check=True)
    handler = partial(QuietHandler, directory=str(FRONTEND))
    server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
    thread = Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        base = f"http://127.0.0.1:{server.server_port}/"
        for path in inventory:
            relative = path.relative_to(FRONTEND).as_posix()
            with urlopen(base + quote(relative), timeout=5) as response:
                assert response.status == 200, relative
                assert response.read() == path.read_bytes(), relative
    finally:
        server.shutdown()
        server.server_close()
        thread.join()

    output = FRONTEND / ".validation"
    output.mkdir(exist_ok=True)
    manifest = [
        {"path": p.relative_to(FRONTEND).as_posix(), "bytes": p.stat().st_size,
         "sha256": sha256(p.read_bytes()).hexdigest()}
        for p in sorted(inventory)
    ]
    report = {
        "original_files": len(original), "byte_identical": identical,
        "entry_and_mode_adjusted_files": 3, "additional_assets": len(EXTRA_ASSETS),
        "local_reference_occurrences": len(references), "http_files_ok": len(inventory),
        "javascript_syntax": "passed", "inventory": manifest,
    }
    (output / "integrity.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps({k: v for k, v in report.items() if k != "inventory"}))


if __name__ == "__main__":
    main()
