"""Local, root-owned evidence for attended commissioning, never pupil operation.

This verifies an administrative attestation, not the existence of a safety sensor.
The power isolator and the attending operator remain physical requirements.
"""

import hashlib
import os
import sqlite3
import stat
import sys
import time
from contextlib import closing
from pathlib import Path
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field

from app.mechanical import ControllerError

EVIDENCE = (
    "mapping_calibration",
    "direct_c_cycle",
    "python_c_cycle",
    "power_isolation",
    "obstruction_recovery",
    "power_loss_recovery",
    "guards_force_speed",
    "storage_durability",
)


class EvidenceFile(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)
    path: str
    sha256: str = Field(pattern=r"^[a-f0-9]{64}$")


class EvidenceReport(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)
    schema_version: Literal["bingo-commissioning-evidence-v1"] = Field(alias="schema")
    criterion: str
    outcome: Literal["PASSED"]
    approved_by: str = Field(min_length=3, max_length=120)
    approved_at: float
    configuration_sha256: str = Field(pattern=r"^[a-f0-9]{64}$")
    executable_sha256: str = Field(pattern=r"^[a-f0-9]{64}$")
    findings: str = Field(min_length=40, max_length=8000)


class CommissioningRecord(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)
    schema_version: Literal["bingo-attended-commissioning-v1"] = Field(alias="schema")
    authorization_id: UUID
    audience: Literal["attending-technicians-only"]
    purpose: Literal["python-c-validation", "integrated-validation"]
    operator: str = Field(min_length=3, max_length=120)
    boot_id: UUID
    issued_at: float
    issued_boottime: float
    expires_at: float
    configuration_sha256: str = Field(pattern=r"^[a-f0-9]{64}$")
    executable_sha256: str = Field(pattern=r"^[a-f0-9]{64}$")
    backend_journal: str
    controller_journal: str
    evidence: dict[str, EvidenceFile]


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def protected_file(path):
    """No writable aliases, symlinks or service-owned authority files."""
    path = Path(path)
    if not path.is_absolute():
        raise ValueError("Commissioning paths must be absolute")
    for parent in (path, *path.parents):
        st = parent.lstat()
        if stat.S_ISLNK(st.st_mode) or st.st_uid != 0 or st.st_mode & 0o6022:
            raise ValueError("Untrusted commissioning path")
    st = path.stat()
    if not stat.S_ISREG(st.st_mode) or st.st_nlink != 1:
        raise ValueError("Invalid commissioning file")
    return path


class CommissioningPolicy:
    def __init__(self, config, settings, backend_journal):
        # Fixed sibling; no browser/env enable override. Missing evidence fails closed.
        self.config = Path(config)
        self.settings = settings
        self.backend = Path(backend_journal).resolve()
        self.record_path = self.config.with_name("commissioning.json")
        self.record = None

    def check(self):
        try:
            if sys.platform != "linux" or os.geteuid() == 0:
                raise ValueError("Physical service must run unprivileged on Linux")
            for path in (self.config, self.settings.executable, self.record_path):
                protected_file(path)
            if not os.access(self.settings.executable, os.X_OK):
                raise ValueError("Controller is not executable")
            raw = self.record_path.read_bytes()
            if len(raw) > 16384:
                raise ValueError("Oversized attestation")
            record = CommissioningRecord.model_validate_json(raw)
            now = time.time()
            age = time.clock_gettime(time.CLOCK_BOOTTIME) - record.issued_boottime
            if not (
                record.issued_at <= now < record.expires_at
                and 0 < record.expires_at - record.issued_at <= 600
                and 0 <= age < record.expires_at - record.issued_at
                and UUID(Path("/proc/sys/kernel/random/boot_id").read_text().strip())
                == record.boot_id
                and digest(self.config) == record.configuration_sha256
                and digest(self.settings.executable) == record.executable_sha256
                and record.backend_journal == str(self.backend)
                and record.controller_journal == str(self.settings.journal.resolve())
                and set(record.evidence)
                == (
                    set(EVIDENCE) - {"python_c_cycle"}
                    if record.purpose == "python-c-validation"
                    else set(EVIDENCE)
                )
            ):
                raise ValueError("Commissioning mismatch/expired")
            for criterion, reference in record.evidence.items():
                report_path = protected_file(reference.path)
                if (
                    not report_path.is_absolute()
                    or report_path.stat().st_size > 16384
                    or digest(report_path) != reference.sha256
                ):
                    raise ValueError("Evidence file mismatch")
                report = EvidenceReport.model_validate_json(report_path.read_bytes())
                if (
                    report.criterion != criterion
                    or not 0 < report.approved_at <= record.issued_at
                    or report.configuration_sha256 != record.configuration_sha256
                    or report.executable_sha256 != record.executable_sha256
                ):
                    raise ValueError("Evidence does not approve this installation")
            # Prevent the known laboratory journal, including aliases.
            if "bingo-c-test" in self.settings.journal.resolve().parts:
                raise ValueError("Laboratory journal")
            for path in (self.backend, self.settings.journal):
                if not path.parent.is_dir() or not os.access(path.parent, os.W_OK):
                    raise ValueError("Journal directory unavailable")
                if path.is_symlink() or (
                    path.exists()
                    and (path.stat().st_nlink != 1 or not os.access(path, os.W_OK))
                ):
                    raise ValueError("Journal unavailable")
            if self.settings.journal.exists():
                with closing(
                    sqlite3.connect(
                        self.settings.journal.resolve().as_uri() + "?mode=ro",
                        uri=True,
                        timeout=0.1,
                    )
                ) as db:
                    if (
                        db.execute("PRAGMA application_id").fetchone()[0] != 1112098640
                        or db.execute(
                            "SELECT 1 FROM orders WHERE result='UNKNOWN' OR state='ACCEPTED' LIMIT 1"
                        ).fetchone()
                    ):
                        raise ValueError("C journal requires inspection")
            if self.backend.exists():
                with closing(
                    sqlite3.connect(
                        self.backend.as_uri() + "?mode=ro", uri=True, timeout=0.1
                    )
                ) as db:
                    if (
                        db.execute(
                            "SELECT 1 FROM mechanical_commands WHERE result='UNKNOWN' OR phase IN ('FAILED','TIMED_OUT','CANCELLED','INDETERMINATE') LIMIT 1"
                        ).fetchone()
                        or db.execute(
                            "SELECT 1 FROM cycles WHERE active_slot=1 AND state='INDETERMINATE' LIMIT 1"
                        ).fetchone()
                    ):
                        raise ValueError("Python journal requires inspection")
            # Check physical declarations, including wiring and safety references.
            if self.settings.physical.blockers():
                raise ValueError("Incomplete physical declarations")
            self.record = record
            return record
        except (OSError, ValueError, sqlite3.Error):
            raise ControllerError("PHYSICAL_SUPERVISION_PENDING") from None

    def consume(self, store, command):
        record = self.check()
        # A permit authorizes one stable command, not an unlimited start flag.
        with store.transaction() as conn:
            conn.execute("""CREATE TABLE IF NOT EXISTS mechanical_commissioning (
                authorization_id TEXT PRIMARY KEY, mechanical_command_id TEXT UNIQUE NOT NULL REFERENCES mechanical_commands(mechanical_command_id),
                attestation TEXT NOT NULL, at TEXT NOT NULL)""")
            conn.execute("""CREATE TRIGGER IF NOT EXISTS commissioning_no_update BEFORE UPDATE ON mechanical_commissioning
                BEGIN SELECT RAISE(ABORT,'Retained commissioning evidence'); END""")
            conn.execute("""CREATE TRIGGER IF NOT EXISTS commissioning_no_delete BEFORE DELETE ON mechanical_commissioning
                BEGIN SELECT RAISE(ABORT,'Retained commissioning evidence'); END""")
            previous = conn.execute(
                "SELECT mechanical_command_id FROM mechanical_commissioning WHERE authorization_id=?",
                (str(record.authorization_id),),
            ).fetchone()
            if previous and previous[0] != str(command.mechanical_command_id):
                raise ControllerError("COMMISSIONING_AUTHORIZATION_USED")
            if not previous:
                from app.storage import now

                conn.execute(
                    "INSERT INTO mechanical_commissioning VALUES(?,?,?,?)",
                    (
                        str(record.authorization_id),
                        str(command.mechanical_command_id),
                        record.model_dump_json(),
                        now(),
                    ),
                )
