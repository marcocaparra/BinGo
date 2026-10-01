import base64
import importlib.util
import json
import os
import pathlib
import threading
import unittest
from http.server import ThreadingHTTPServer
from urllib.error import HTTPError
from urllib.request import Request, urlopen
from unittest import mock

SPEC = importlib.util.spec_from_file_location(
    'cloud_gateway', pathlib.Path(__file__).parents[1] / 'edge_vision_service.py')
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)
CONFIG = {'BINGO_RUNTIME_MODE': 'cloud', 'PORT': '8080',
          'BINGO_DEMO_USERNAME': 'demo-fixture', 'BINGO_DEMO_PASSWORD': 'password-fixture'}
AUTH = 'Basic ' + base64.b64encode(b'demo-fixture:password-fixture').decode()


class RuntimeTests(unittest.TestCase):
    def test_local_default_and_non_loopback_bind_rejected(self):
        with mock.patch.dict(os.environ, {}, clear=True):
            self.assertEqual(MODULE.listen_address(), ('127.0.0.1', 8765))
        with mock.patch.dict(os.environ, {'BINGO_VISION_HOST': '0.0.0.0'}, clear=True):
            with self.assertRaises(ValueError):
                MODULE.listen_address()

    def test_cloud_requires_port_and_credentials(self):
        with mock.patch.dict(os.environ, CONFIG, clear=True):
            self.assertEqual(MODULE.listen_address(), ('0.0.0.0', 8080))
        for missing in ['PORT', 'BINGO_DEMO_USERNAME', 'BINGO_DEMO_PASSWORD']:
            with mock.patch.dict(os.environ, {k: v for k, v in CONFIG.items() if k != missing}, clear=True):
                with self.assertRaises((ValueError, KeyError)):
                    MODULE.listen_address()
        for value in ['0', '65536', 'invalid']:
            with mock.patch.dict(os.environ, {**CONFIG, 'PORT': value}, clear=True):
                with self.assertRaises(ValueError):
                    MODULE.listen_address()
        with mock.patch.dict(os.environ, {'BINGO_RUNTIME_MODE': 'typo'}, clear=True):
            with self.assertRaises(ValueError):
                MODULE.listen_address()


class CloudHttpTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = ThreadingHTTPServer(('127.0.0.1', 0), MODULE.VisionHandler)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.base = f'http://127.0.0.1:{cls.server.server_port}'

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join()

    def setUp(self):
        self.environment = mock.patch.dict(os.environ, CONFIG, clear=True)
        self.environment.start()
        self.addCleanup(self.environment.stop)

    def call(self, path, auth=AUTH, origin=None, data=None, headers=None):
        request_headers = dict(headers or {})
        if auth is not None:
            request_headers['Authorization'] = auth
        if origin:
            request_headers['Origin'] = origin
        try:
            return urlopen(Request(self.base + path, data=data, headers=request_headers), timeout=3)
        except HTTPError as error:
            return error

    def test_missing_and_invalid_basic_auth_rejected_on_frontend_and_apis(self):
        with mock.patch.object(MODULE, 'forward_bingo') as upstream, mock.patch.object(MODULE, 'analyze_primary_with_fallback') as vision:
            for path, data in [('/', None), ('/runtime.js', None), ('/bingo/context', None), ('/vision/analyze', b'image')]:
                for auth in [None, 'Bearer invalid', 'Basic !!!', 'Basic ' + base64.b64encode(b'wrong:wrong').decode(),
                             'Basic ' + base64.b64encode(b'demo-fixture:wrong').decode()]:
                    with self.call(path, auth=auth, data=data) as response:
                        self.assertEqual(response.status, 401)
                        self.assertIn('Basic', response.headers['WWW-Authenticate'])
            upstream.assert_not_called()
            vision.assert_not_called()

    def test_cloud_without_credentials_fails_closed_but_healthz_is_minimal(self):
        os.environ.pop('BINGO_DEMO_PASSWORD')
        with self.call('/') as response:
            self.assertEqual(response.status, 503)
        with self.call('/healthz', auth=None) as response:
            self.assertEqual(response.status, 200)
            self.assertEqual(json.load(response), {'status': 'ok'})

    def test_basic_auth_same_origin_tls_proxy_and_no_cors(self):
        for origin, headers in [(self.base, {}), ('https://demo.example', {'Host': 'demo.example', 'X-Forwarded-Proto': 'https'})]:
            with mock.patch.object(MODULE, 'forward_bingo', return_value=(200, {'school': {'name': 'Fixture'}})) as upstream:
                with self.call('/bingo/context', origin=origin, headers=headers) as response:
                    self.assertEqual(response.status, 200)
                    self.assertIsNone(response.headers.get('Access-Control-Allow-Origin'))
                upstream.assert_called_once_with('GET', '/bingo/context', None)
        with self.call('/bingo/context', origin='https://evil.example') as response:
            self.assertEqual(response.status, 403)
        with self.call('/bingo/context', headers={'Sec-Fetch-Site': 'cross-site'}) as response:
            self.assertEqual(response.status, 403)

    def test_static_allowlist_mime_and_runtime_contains_no_secrets(self):
        for path, mime in [('/', 'text/html'), ('/style.css?v=1', 'text/css'), ('/app.js', 'text/javascript'),
                           ('/vision/vision_provider.js', 'text/javascript'), ('/backend_client.js', 'text/javascript')]:
            with self.call(path) as response:
                self.assertEqual(response.status, 200)
                self.assertTrue(response.headers['Content-Type'].startswith(mime))
        with self.call('/runtime.js') as response:
            body = response.read().decode()
            self.assertIn('BinGoRuntimeMode = "cloud"', body)
            self.assertNotIn('password-fixture', body)
            self.assertNotIn('demo-fixture', body)
        with self.call('/sample_library.js') as response:
            self.assertEqual(response.read(), b'window.BinGoSamples = Object.freeze([]);\n')

    def test_private_files_samples_and_traversal_never_served(self):
        for path in ['/.env', '/.env.cloud', '/README.md', '/tests/browser.test.cjs', '/vision/edge.env.example',
                     '/vision/edge_vision_service.py', '/assets/samples/battery.png', '/Dockerfile', '/arbitrary',
                     '/../index.html', '/%2e%2e/index.html', '/%252e%252e/index.html', '/vision/../index.html',
                     '/%2findex.html', '/vision%5c..%5cindex.html']:
            with self.subTest(path=path), self.call(path) as response:
                self.assertEqual(response.status, 404)

    def test_vision_upload_preserves_cascade_and_logs_omit_credentials(self):
        result = {'status': 'recognized', 'itemId': 'battery', 'origin': 'AWS_REKOGNITION'}
        with mock.patch.object(MODULE, 'analyze_primary_with_fallback', return_value=result) as vision, mock.patch('builtins.print') as logs:
            with self.call('/vision/analyze', origin=self.base, data=b'image', headers={'Content-Type': 'image/png'}) as response:
                self.assertEqual(json.load(response), result)
            vision.assert_called_once_with(b'image', 'image/png')
            text = str(logs.call_args_list)
            self.assertNotIn('password-fixture', text)
            self.assertNotIn('demo-fixture', text)


if __name__ == '__main__':
    unittest.main()
