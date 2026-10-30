"""Isolation boundaries and truthful aggregate results for validation tooling."""

import importlib.util
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch


def load(name, relative):
    spec = importlib.util.spec_from_file_location(
        name, Path(__file__).parents[1] / relative
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


validation = load("validation_profiles", "validate.py")
cleanup = load("smoke_cleanup", "validation/smoke_cleanup.py")


class ValidationTests(unittest.TestCase):
    def test_inherited_credentials_profiles_and_proxies_are_not_forwarded(self):
        source = {
            name: "sensitive-test-value"
            for name in (
                "BINGO_DEV_POLICY_FILE",
                "BINGO_DEV_MACHINE_KEY_FILE",
                "BINGO_SQLITE_PATH",
                "SUPABASE_SERVICE_ROLE_KEY",
                "AWS_PROFILE",
                "GEMINI_API_KEY",
                "https_proxy",
                "UV_ENV_FILE",
                "COMPOSE_FILE",
                "NODE_OPTIONS",
            )
        }
        source["PATH"] = "tool-path"
        env = validation.safe_environment(source)
        self.assertNotIn("sensitive-test-value", env.values())
        self.assertEqual(env["PATH"], "tool-path")
        self.assertEqual(env["UV_NO_ENV_FILE"], "1")

    def test_hosted_requires_explicit_authorization_and_never_runs_in_ci(self):
        with patch.object(validation, "build_opener") as opener:
            for authorized, env in (
                (False, {}),
                (True, {"CI": "true"}),
                (True, {"GITHUB_ACTIONS": "true"}),
            ):
                with self.subTest(env=env), self.assertRaises(ValueError):
                    validation.hosted_read_only(
                        "http://127.0.0.1:8002", authorized, env
                    )
            opener.assert_not_called()

    def test_hosted_refuses_external_urls_credentials_queries_and_paths(self):
        with patch.object(validation, "build_opener") as opener:
            for url in (
                "https://hosted.invalid",
                "http://127.0.0.1:8002/?pin=x",
                "http://user:secret@localhost",
                "http://localhost/functions/v1/register-deposit-v1",
            ):
                with self.subTest(url=url), self.assertRaises(ValueError):
                    validation.hosted_read_only(url, True, {})
            opener.assert_not_called()

    def test_failed_and_unavailable_groups_do_not_produce_success(self):
        self.assertEqual(
            validation.aggregate([{"status": "passed"}, {"status": "failed"}]), 1
        )
        self.assertEqual(validation.aggregate([{"status": "unavailable"}]), 2)
        self.assertEqual(validation.aggregate([{"status": "running"}]), 2)
        self.assertEqual(
            validation.aggregate([{"status": "passed", "tests": {"skipped": 1}}]), 2
        )
        self.assertEqual(
            validation.aggregate([{"status": "passed"}, {"status": "pending"}]), 0
        )

    def test_junit_counts_and_empty_collection(self):
        with tempfile.TemporaryDirectory() as temporary:
            report = Path(temporary) / "junit.xml"
            report.write_text(
                "<testsuites><testsuite><testcase/><testcase><failure/></testcase><testcase><skipped/></testcase></testsuite></testsuites>"
            )
            self.assertEqual(
                validation.junit_counts(report),
                {"passed": 1, "failed": 1, "skipped": 1},
            )
            report.write_text("<testsuites/>")
            with self.assertRaises(ValueError):
                validation.junit_counts(report)

    def test_cleanup_refuses_user_dev_before_running_any_command(self):
        compose, run = Mock(), Mock()
        for project in (
            "bingo-totem-edge-dev-integration",
            "bingo-simulation-test-persistent",
        ):
            with self.subTest(project=project), self.assertRaises(ValueError):
                cleanup.cleanup_projects([project], compose, run)
        compose.assert_not_called()
        run.assert_not_called()

    def test_cleanup_failure_or_leftover_volume_is_visible(self):
        compose = Mock(return_value=SimpleNamespace(returncode=0))
        run = Mock(
            side_effect=[
                SimpleNamespace(returncode=0, stdout=value)
                for value in ("", "owned-volume", "")
            ]
        )
        project = "bingo-simulation-test-0123456789ab"
        self.assertFalse(cleanup.cleanup_projects([project], compose, run)[0]["ok"])
        self.assertTrue(
            all(
                "label=com.docker.compose.project=" + project in call.args[0]
                for call in run.call_args_list
            )
        )


if __name__ == "__main__":
    unittest.main()
