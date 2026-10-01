"""Local-only browser/DB smoke. Requires Supabase reset + functions serve.

Runs the unchanged vision boundary with a controlled recognized image response;
no AWS/Gemini credential is required and no production mock mode is introduced.
"""
import functools
import importlib.util
import json
import os
import pathlib
import subprocess
import sys
import threading
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from unittest import mock

import psycopg

ROOT = pathlib.Path(__file__).resolve().parents[3]
APP = pathlib.Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('local_gateway_smoke', APP / 'vision/edge_vision_service.py')
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def main():
    sys.stdout.reconfigure(encoding='utf-8')
    config = {
        'BINGO_SUPABASE_URL': 'http://127.0.0.1:54321',
        'BINGO_MACHINE_ID': '40000000-0000-4000-8000-000000000001',
        'BINGO_MACHINE_API_KEY': 'edge-demo-key',  # Known local seed only.
        'BINGO_TOTEM_BROWSER_INTEGRATION': '1',
    }
    result = {'status': 'recognized', 'itemId': 'battery', 'candidateIds': ['battery'], 'confidence': 0.98, 'origin': 'AWS_REKOGNITION'}
    with mock.patch.dict(os.environ, config), mock.patch.object(MODULE, 'analyze_image', return_value=result):
        gateway = ThreadingHTTPServer(('127.0.0.1', 8765), MODULE.VisionHandler)
        frontend = ThreadingHTTPServer(('127.0.0.1', 8110), functools.partial(SimpleHTTPRequestHandler, directory=str(APP)))
        servers = [gateway, frontend]
        threads = [threading.Thread(target=server.serve_forever, daemon=True) for server in servers]
        for thread in threads:
            thread.start()
        try:
            run = subprocess.run(['node', '--test', str(APP / 'tests/browser.test.cjs')], cwd=ROOT, capture_output=True, text=True, encoding='utf-8', timeout=300)
            print(run.stdout)
            if run.returncode:
                print(run.stderr)
                raise RuntimeError('Browser suite failed')
            lines = [line.split('SMOKE_EVENTS=', 1)[1] for line in run.stdout.splitlines() if 'SMOKE_EVENTS=' in line]
            if not lines:
                raise RuntimeError('Real smoke did not run')
            events = json.loads(lines[-1])
            with psycopg.connect('postgresql://postgres:postgres@127.0.0.1:54322/postgres', autocommit=True) as database:
                rows = database.execute('select event_id,student_id,points_awarded_student,points_awarded_class,bonus_bincoins_awarded from deposits where event_id=any(%s::uuid[])', (events,)).fetchall()
                assert len(rows) == 2, 'Identified + class-only; replay must not duplicate'
                assert sum(row[1] is None for row in rows) == 1
                assert all(row[3] > 0 for row in rows)
                assert all(row[2] == 0 and row[4] == 0 for row in rows if row[1] is None)
                print('Local DB verified: 2 deposits, identified and class-only; exact replay did not duplicate.')
        finally:
            for server in servers:
                server.shutdown()
                server.server_close()
            for thread in threads:
                thread.join()


if __name__ == '__main__':
    main()
