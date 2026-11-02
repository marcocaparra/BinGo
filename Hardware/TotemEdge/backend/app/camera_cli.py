"""Operator-only camera setup and explicit real-device probe; no student UI."""

import argparse
import json
import os
from pathlib import Path
import secrets
from uuid import UUID, uuid4

import httpx2 as httpx

from app.camera_api import create_host_app, load_token
from app.services.camera import CameraError


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, required=True)
    parser.add_argument("--url", default="http://127.0.0.1:8766/camera/v1")
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("init")
    serve = commands.add_parser("serve")
    serve.add_argument("--bind", default="127.0.0.1")
    serve.add_argument("--port", type=int, default=8766)
    for name in ("devices", "selection", "status"):
        commands.add_parser(name)
    select = commands.add_parser("select")
    select.add_argument("device_id")
    probe = commands.add_parser("probe")
    probe.add_argument("--allow-real-camera", action="store_true", required=True)
    probe.add_argument("--capture-id", type=UUID, default=None)
    capture_status = commands.add_parser("capture-status")
    capture_status.add_argument("capture_id", type=UUID)
    session = commands.add_parser("capture-session")
    session.add_argument("event_id", type=UUID)
    session.add_argument("capture_id", type=UUID)
    args = parser.parse_args()
    directory = args.directory.resolve()
    token_file = directory / "camera.token"
    if args.command == "init":
        directory.mkdir(mode=0o700, parents=True, exist_ok=True)
        with token_file.open("x", encoding="ascii") as stream:
            os.chmod(token_file, 0o600)
            stream.write(secrets.token_urlsafe(48))
        print(
            "Credencial criada; conteúdo não exibido. Proteja a pasta com ACL do usuário no Windows."
        )
        return
    token = load_token(token_file)
    if args.command == "serve":
        import uvicorn

        os.environ["BINGO_CAMERA_TOKEN_FILE"] = str(token_file)
        os.environ["BINGO_CAMERA_DB"] = str(directory / "camera.sqlite3")
        uvicorn.run(
            create_host_app(),
            host=args.bind,
            port=args.port,
            workers=1,
            access_log=False,
            proxy_headers=False,
        )
        return
    # URL is operator input, but keep token away from arbitrary remote hosts.
    from urllib.parse import urlsplit

    url = urlsplit(args.url)
    if (
        url.scheme != "http"
        or url.hostname not in {"localhost", "127.0.0.1", "::1"}
        or url.username
        or url.password
        or url.query
        or url.fragment
        or url.path not in {"/camera/v1", "/local/camera"}
    ):
        raise CameraError("CAMERA_URL_CONFIGURATION")
    method, path, body = "GET", "/" + args.command, None
    if args.command == "select":
        method, path, body = "PUT", "/selection", {"device_id": args.device_id}
    elif args.command == "probe":
        method, path, body = (
            "POST",
            "/probe",
            {"capture_id": str(args.capture_id or uuid4()), "allow_real_camera": True},
        )
    elif args.command == "capture-session":
        method, path, body = (
            "POST",
            f"/sessions/{args.event_id}/capture",
            {"capture_id": str(args.capture_id)},
        )
    elif args.command == "capture-status":
        path = f"/captures/{args.capture_id}"
    with httpx.Client(trust_env=False, follow_redirects=False, timeout=20) as client:
        response = client.request(
            method,
            args.url + path,
            json=body,
            headers={"Authorization": "Bearer " + token, "X-Totem-Request": "1"},
        )
        print(json.dumps(response.json(), ensure_ascii=False, indent=2))
        if response.status_code != 200:
            raise SystemExit(1)


if __name__ == "__main__":
    try:
        main()
    except CameraError as error:
        print(error.code)
        raise SystemExit(1) from None
    except (OSError, httpx.HTTPError, ValueError):
        print("CAMERA_OPERATOR_COMMAND_FAILED")
        raise SystemExit(1) from None
