"""Stdlib-only process guard. No camera/SDK/configuration imports in the worker."""

import ctypes
import os
import signal
import subprocess
import sys
from uuid import uuid4


def windows_kernel():
    from ctypes import wintypes

    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.CreateJobObjectW.argtypes = [ctypes.c_void_p, wintypes.LPCWSTR]
    kernel.CreateJobObjectW.restype = wintypes.HANDLE
    kernel.OpenJobObjectW.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.LPCWSTR]
    kernel.OpenJobObjectW.restype = wintypes.HANDLE
    kernel.SetInformationJobObject.argtypes = [
        wintypes.HANDLE,
        ctypes.c_int,
        ctypes.c_void_p,
        wintypes.DWORD,
    ]
    kernel.AssignProcessToJobObject.argtypes = [wintypes.HANDLE, wintypes.HANDLE]
    kernel.GetCurrentProcess.restype = wintypes.HANDLE
    kernel.CloseHandle.argtypes = [wintypes.HANDLE]
    return kernel


class ProcessGuard:
    def __init__(self):
        self.handle = None
        self.name = "-"
        if os.name != "nt":
            return
        from ctypes import wintypes

        class Limits(ctypes.Structure):
            _fields_ = [
                ("process_time", ctypes.c_longlong),
                ("job_time", ctypes.c_longlong),
                ("flags", wintypes.DWORD),
                ("minimum_working_set", ctypes.c_size_t),
                ("maximum_working_set", ctypes.c_size_t),
                ("active_processes", wintypes.DWORD),
                ("affinity", ctypes.c_size_t),
                ("priority", wintypes.DWORD),
                ("scheduling", wintypes.DWORD),
            ]

        class Extended(ctypes.Structure):
            _fields_ = [
                ("basic", Limits),
                ("io", ctypes.c_ulonglong * 6),
                ("process_memory", ctypes.c_size_t),
                ("job_memory", ctypes.c_size_t),
                ("peak_process", ctypes.c_size_t),
                ("peak_job", ctypes.c_size_t),
            ]

        self.kernel = windows_kernel()
        self.name = "Local\\BinGoCamera-" + uuid4().hex
        self.handle = self.kernel.CreateJobObjectW(None, self.name)
        limits = Extended()
        limits.basic.flags = 0x2000  # JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
        if not self.handle or not self.kernel.SetInformationJobObject(
            self.handle, 9, ctypes.byref(limits), ctypes.sizeof(limits)
        ):
            self.close()
            raise OSError("Camera process guard unavailable")

    def close(self):
        if self.handle:
            self.kernel.CloseHandle(self.handle)
            self.handle = None


def run():
    parent, name, *program = sys.argv[1:]
    if os.name == "nt":
        kernel = windows_kernel()
        job = kernel.OpenJobObjectW(1, False, name)  # ASSIGN_PROCESS only
        if not job:
            raise OSError()
        try:
            if not kernel.AssignProcessToJobObject(job, kernel.GetCurrentProcess()):
                raise OSError()
        finally:
            # Only the service retains a handle: service death kills this worker
            # and all descendants. A dead owner cannot leave a device orphaned.
            kernel.CloseHandle(job)
        child = subprocess.Popen(
            program, stdin=subprocess.DEVNULL, creationflags=subprocess.CREATE_NO_WINDOW
        )
        raise SystemExit(child.wait())
    if not sys.platform.startswith("linux"):
        raise OSError()
    libc = ctypes.CDLL(None, use_errno=True)
    if libc.prctl(1, signal.SIGKILL, 0, 0, 0) != 0:  # PR_SET_PDEATHSIG
        raise OSError()
    if os.getppid() != int(parent):
        raise OSError()  # Parent died before prctl; never launch the device.
    os.execvp(program[0], program)  # Same PID and death signal, no extra daemon.


if __name__ == "__main__":
    try:
        run()
    except Exception:
        # No executable arguments, headers, image or driver error in stderr.
        raise SystemExit(2) from None
