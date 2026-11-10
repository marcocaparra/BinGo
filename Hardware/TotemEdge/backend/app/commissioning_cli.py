"""Issue one attended permit from existing approved reports; never move hardware."""

import argparse
import json
import os
import tempfile
import time
from pathlib import Path
from uuid import uuid4

from app.services.commissioning import (
    EVIDENCE,
    CommissioningRecord,
    EvidenceReport,
    digest,
    protected_file,
)
from app.services.controller_config import CControllerSettings


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--backend-journal", type=Path, required=True)
    parser.add_argument("--reports", type=Path, required=True)
    parser.add_argument("--operator", required=True)
    parser.add_argument(
        "--purpose",
        choices=("python-c-validation", "integrated-validation"),
        required=True,
    )
    args = parser.parse_args()
    if os.name != "posix" or os.geteuid() != 0:
        parser.error(
            "Only the local administrator may issue attended commissioning evidence."
        )
    settings = CControllerSettings.from_file(
        protected_file(args.config), backend_journal=args.backend_journal
    )
    protected_file(settings.executable)
    if settings.physical.blockers() or not settings.physical.c_executor_configured():
        parser.error("Physical declarations and operational sequence are incomplete.")
    config_hash, binary_hash = digest(args.config), digest(settings.executable)
    evidence = {}
    now = time.time()
    required = set(EVIDENCE) - (
        {"python_c_cycle"} if args.purpose == "python-c-validation" else set()
    )
    for criterion in sorted(required):
        path = protected_file(args.reports / (criterion + ".json"))
        if path.stat().st_size > 16384:
            parser.error("Evidence file is too large.")
        report = EvidenceReport.model_validate_json(path.read_bytes())
        if (
            report.criterion != criterion
            or not 0 < report.approved_at <= now
            or report.configuration_sha256 != config_hash
            or report.executable_sha256 != binary_hash
        ):
            parser.error("Evidence does not approve this installation.")
        evidence[criterion] = {"path": str(path), "sha256": digest(path)}
    record = CommissioningRecord.model_validate_json(
        json.dumps(
            {
                "schema": "bingo-attended-commissioning-v1",
                "authorization_id": str(uuid4()),
                "audience": "attending-technicians-only",
                "purpose": args.purpose,
                "operator": args.operator,
                "boot_id": Path("/proc/sys/kernel/random/boot_id").read_text().strip(),
                "issued_at": now,
                "issued_boottime": time.clock_gettime(time.CLOCK_BOOTTIME),
                "expires_at": now + 600,
                "configuration_sha256": config_hash,
                "executable_sha256": binary_hash,
                "backend_journal": str(args.backend_journal.resolve()),
                "controller_journal": str(settings.journal.resolve()),
                "evidence": evidence,
            }
        )
    )
    target = args.config.with_name("commissioning.json")
    # Atomic replacement, sync data and directory; do not edit a consumed record.
    with tempfile.NamedTemporaryFile(
        dir=target.parent, prefix=".commissioning-", delete=False
    ) as stream:
        temporary = Path(stream.name)
        try:
            stream.write(record.model_dump_json(by_alias=True).encode())
            stream.flush()
            os.fchmod(stream.fileno(), 0o444)
            os.fsync(stream.fileno())
            os.replace(temporary, target)
            directory = os.open(target.parent, os.O_RDONLY | os.O_DIRECTORY)
            try:
                os.fsync(directory)
            finally:
                os.close(directory)
        finally:
            temporary.unlink(missing_ok=True)
    print(
        json.dumps(
            {
                "authorization_id": str(record.authorization_id),
                "expires_at": record.expires_at,
                "audience": record.audience,
                "movement_sent": False,
            }
        )
    )


if __name__ == "__main__":
    main()
