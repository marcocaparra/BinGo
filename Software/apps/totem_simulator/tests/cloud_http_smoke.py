"""Cloud-mode browser smoke on loopback with controlled upstream boundaries.

No cloud resource, external provider, Supabase write or real credential is used.
"""
import importlib.util
import os
import pathlib
import subprocess
import threading
from http.server import ThreadingHTTPServer
from unittest import mock

APP = pathlib.Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('cloud_smoke', APP / 'vision/edge_vision_service.py')
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)
CLASS_ID = '20000000-0000-4000-8000-000000000001'
STUDENT_ID = '30000000-0000-4000-8000-000000000001'
CLASS = {'id': CLASS_ID, 'name': 'Turma cloud', 'points_class_balance': 31}
STUDENT = {'id': STUDENT_ID, 'name': 'Aluno cloud', 'class_id': CLASS_ID, 'points_student_balance': 17}


def upstream(method, path, payload):
    responses = {
        '/bingo/health': {'status': 'AVAILABLE', 'can_start_deposit': True},
        '/bingo/context': {'school': {'name': 'Escola cloud'}, 'machine': {'name': 'Totem'},
                           'classes': [CLASS], 'students': [STUDENT]},
        '/bingo/rankings': {'classes': [CLASS], 'students': [STUDENT]},
        '/bingo/student-summary': {'student': STUDENT, 'summary': {}, 'last_deposits': []},
        '/bingo/student-pin': {'confirmed': True, 'student': STUDENT},
    }
    if path == '/bingo/deposits':
        return 201, {'id': 'b0000000-0000-4000-8000-000000000001', 'event_id': payload['event_id'],
                     'points_awarded_student': 0, 'points_awarded_class': 456, 'bonus_bincoins_awarded': 0}
    return 200, responses[path]


def main():
    config = {'BINGO_RUNTIME_MODE': 'cloud', 'PORT': '8080',
              'BINGO_DEMO_USERNAME': 'demo-fixture', 'BINGO_DEMO_PASSWORD': 'password-fixture'}
    vision = {'status': 'recognized', 'itemId': 'battery', 'candidateIds': ['battery'],
              'confidence': 0.98, 'origin': 'AWS_REKOGNITION'}
    with mock.patch.dict(os.environ, config), mock.patch.object(MODULE, 'forward_bingo', side_effect=upstream), \
            mock.patch.object(MODULE, 'analyze_image', return_value=vision):
        server = ThreadingHTTPServer(('127.0.0.1', 0), MODULE.VisionHandler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            env = {**os.environ, 'BINGO_CLOUD_TEST_URL': f'http://127.0.0.1:{server.server_port}'}
            result = subprocess.run(['node', '--test', str(APP / 'tests/cloud_browser.test.cjs')],
                                    env=env, timeout=120)
            return result.returncode
        finally:
            server.shutdown()
            server.server_close()
            thread.join()


if __name__ == '__main__':
    raise SystemExit(main())
