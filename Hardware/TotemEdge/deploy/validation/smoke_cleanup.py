"""Remove and verify only resources labeled with this smoke's exact UUID project."""

import re


def cleanup_projects(projects, compose, run):
    if not all(
        re.fullmatch(
            r"bingo-(?:simulation|dev-integration)-test-[0-9a-f]{12}(?:-http|-failure|-timeout)?",
            project,
        )
        for project in projects
    ):
        raise ValueError("Refusing cleanup outside smoke projects")
    results = []
    for project in reversed(projects):
        result = {"project": project, "ok": False}
        try:
            stopped = compose(
                "down", "--volumes", "--remove-orphans", name=project, check=False
            )
            result["down_returncode"] = stopped.returncode
            remaining = []
            for resource, options in (
                ("container", ["ls", "-aq"]),
                ("volume", ["ls", "-q"]),
                ("network", ["ls", "-q"]),
            ):
                probe = run(
                    [
                        "docker",
                        resource,
                        *options,
                        "--filter",
                        f"label=com.docker.compose.project={project}",
                    ],
                    check=False,
                )
                remaining.append(probe.returncode != 0 or bool(probe.stdout.strip()))
            result["ok"] = stopped.returncode == 0 and not any(remaining)
        except Exception:
            result["error"] = (
                "Cleanup could not be verified; inspect this exact UUID project"
            )
        results.append(result)
    return results
