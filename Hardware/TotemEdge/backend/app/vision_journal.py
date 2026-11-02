"""Local audit extension; no photographs, credentials or economic category."""

SCHEMA = """CREATE TABLE IF NOT EXISTS vision_attempts (
    capture_id TEXT PRIMARY KEY,
    event_id TEXT NOT NULL UNIQUE REFERENCES cycles(event_id),
    close_command_id TEXT NOT NULL REFERENCES mechanical_commands(mechanical_command_id),
    phase TEXT NOT NULL CHECK(phase IN ('CAPTURING','CLASSIFYING','COMPLETED','FAILED')),
    observation TEXT, decision TEXT, provenance TEXT,
    error_code TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL
)"""

RETRY_SCHEMA = """CREATE TABLE IF NOT EXISTS vision_analysis_retries (
 analysis_id TEXT PRIMARY KEY, event_id TEXT NOT NULL REFERENCES cycles(event_id),
 capture_id TEXT NOT NULL,
 previous_attempt TEXT NOT NULL, created_at TEXT NOT NULL,
 FOREIGN KEY(capture_id,event_id) REFERENCES vision_capture_ids(capture_id,event_id)
)"""


def prepare_capture_history(conn):
    """Historical identities must not reference the mutable current projection."""
    conn.execute(
        "CREATE TABLE IF NOT EXISTS vision_capture_ids (capture_id TEXT PRIMARY KEY, event_id TEXT NOT NULL REFERENCES cycles(event_id), UNIQUE(capture_id,event_id))"
    )
    conn.execute(
        "INSERT OR IGNORE INTO vision_capture_ids SELECT capture_id,event_id FROM vision_attempts"
    )
    conn.execute(
        "INSERT OR IGNORE INTO vision_capture_ids SELECT capture_id,event_id FROM vision_analysis_retries"
    )
    conn.execute(
        "INSERT OR IGNORE INTO vision_capture_ids SELECT capture_id,event_id FROM vision_recaptures"
    )
    conn.execute(
        "INSERT OR IGNORE INTO vision_capture_ids SELECT previous_capture_id,event_id FROM vision_recaptures"
    )
    if any(
        row[2] == "vision_attempts"
        for row in conn.execute("PRAGMA foreign_key_list(vision_analysis_retries)")
    ):
        conn.execute(
            "ALTER TABLE vision_analysis_retries RENAME TO vision_analysis_retries_legacy"
        )
        conn.execute(RETRY_SCHEMA)
        conn.execute(
            "INSERT INTO vision_analysis_retries SELECT * FROM vision_analysis_retries_legacy"
        )
        conn.execute("DROP TABLE vision_analysis_retries_legacy")
    conn.execute(
        "CREATE TRIGGER IF NOT EXISTS vision_capture_identity_insert AFTER INSERT ON vision_attempts BEGIN INSERT OR IGNORE INTO vision_capture_ids VALUES(NEW.capture_id,NEW.event_id); END"
    )
    conn.execute(
        "CREATE TRIGGER IF NOT EXISTS vision_capture_identity_update BEFORE UPDATE OF capture_id ON vision_attempts BEGIN INSERT OR IGNORE INTO vision_capture_ids VALUES(NEW.capture_id,NEW.event_id); END"
    )
    conn.execute(
        "CREATE TRIGGER IF NOT EXISTS vision_capture_ids_no_update BEFORE UPDATE ON vision_capture_ids BEGIN SELECT RAISE(ABORT,'Immutable capture identity'); END"
    )
    conn.execute(
        "CREATE TRIGGER IF NOT EXISTS vision_capture_ids_no_delete BEFORE DELETE ON vision_capture_ids BEGIN SELECT RAISE(ABORT,'Immutable capture identity'); END"
    )


RECAPTURE_SCHEMA = """CREATE TABLE IF NOT EXISTS vision_recaptures (
 recapture_id TEXT PRIMARY KEY, event_id TEXT NOT NULL REFERENCES cycles(event_id),
 previous_capture_id TEXT NOT NULL, capture_id TEXT NOT NULL UNIQUE,
 previous_attempt TEXT NOT NULL, result_attempt TEXT, created_at TEXT NOT NULL
)"""
