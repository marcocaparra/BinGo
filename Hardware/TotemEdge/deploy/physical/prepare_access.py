"""Administrator-only access setup. No PWM write/export/enable and no motion."""

import grp
import os
import stat
from pathlib import Path


def main():
    if os.geteuid() != 0:
        raise SystemExit("Run locally as administrator with the service stopped.")
    group = grp.getgrnam("bingo").gr_gid
    # This installation is specifically the homologated chip0/channels3+4.
    # Never chmod a whole pwmchip or grant export/enable access.
    for channel in (3, 4):
        directory = Path(f"/sys/class/pwm/pwmchip0/pwm{channel}")
        if directory.is_symlink() or not directory.is_dir():
            raise SystemExit("Expected already exported PWM channel is absent.")
        fd = os.open(directory / "duty_cycle", os.O_RDONLY | os.O_NOFOLLOW)
        try:
            os.fchown(fd, 0, group)
            os.fchmod(fd, 0o660)
        finally:
            os.close(fd)
        # Stable inode in root-owned /run/lock, shared with the C driver.
        # Do not replace/unlink/truncate a lock to bypass an active process.
        lock = Path(f"/run/lock/bingo-pwmchip0-pwm{channel}.lock")
        fd = os.open(lock, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o660)
        try:
            current = os.fstat(fd)
            if not stat.S_ISREG(current.st_mode) or current.st_nlink != 1:
                raise SystemExit("Unsafe global channel lock.")
            os.fchown(fd, 0, group)
            os.fchmod(fd, 0o660)
        finally:
            os.close(fd)
    print("Prepared duty_cycle permissions and stable locks; no PWM value was written.")


if __name__ == "__main__":
    main()
