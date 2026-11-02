"""Abrupt parent death must not leave a process holding the camera device."""

import asyncio
import os
from pathlib import Path
import subprocess
import sys

import pytest


@pytest.mark.anyio
async def test_parent_death_terminates_owned_native_capture_process(tmp_path):
    ready = tmp_path / "native-pid"
    child = "import os,pathlib,sys,time;p=pathlib.Path(sys.argv[1]);t=p.with_suffix('.tmp');t.write_text(str(os.getpid()));t.replace(p);time.sleep(30)"
    parent_code = f"""
import asyncio,sys
from app.services.camera import execute
asyncio.run(execute(sys._base_executable,['-B','-c',{child!r},sys.argv[1]],timeout=30))
"""
    env = {
        k: v
        for k, v in os.environ.items()
        if not k.startswith(("BINGO_", "SUPABASE_", "AWS_", "GEMINI_"))
    }
    env["PYTHONPATH"] = os.pathsep.join(p for p in sys.path if p)
    parent = subprocess.Popen(
        [sys._base_executable, "-B", "-c", parent_code, str(ready)],
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0,
    )
    handle = None
    try:
        for _ in range(100):
            if ready.exists() or parent.poll() is not None:
                break
            await asyncio.sleep(0.1)
        assert ready.exists(), "Owned native child did not start"
        pid = int(ready.read_text())
        if os.name == "nt":
            import ctypes

            kernel = ctypes.windll.kernel32
            kernel.OpenProcess.restype = ctypes.c_void_p
            kernel.WaitForSingleObject.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
            kernel.CloseHandle.argtypes = [ctypes.c_void_p]
            kernel.TerminateProcess.argtypes = [ctypes.c_void_p, ctypes.c_uint]
            handle = kernel.OpenProcess(0x100001, False, pid)
            assert handle
        else:
            import select
            import signal

            handle = os.pidfd_open(pid)
            poll = select.poll()
            poll.register(handle, select.POLLIN)
        parent.kill()
        parent.wait(timeout=5)
        if os.name == "nt":
            assert kernel.WaitForSingleObject(handle, 2000) == 0, (
                "Capture survived service death"
            )
        else:
            assert poll.poll(2000), "Capture survived service death"
    finally:
        if parent.poll() is None:
            parent.kill()
            parent.wait(timeout=5)
        # Exact owned handle/pidfd prevents accidentally targeting a reused PID.
        if handle is not None:
            if os.name == "nt":
                if kernel.WaitForSingleObject(handle, 0) != 0:
                    kernel.TerminateProcess(handle, 1)
                    kernel.WaitForSingleObject(handle, 5000)
                kernel.CloseHandle(handle)
            else:
                if not poll.poll(0):
                    signal.pidfd_send_signal(handle, signal.SIGKILL)
                    poll.poll(5000)
                os.close(handle)
