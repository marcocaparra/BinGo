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
 capture_id TEXT NOT NULL REFERENCES vision_attempts(capture_id),
 previous_attempt TEXT NOT NULL, created_at TEXT NOT NULL
)"""
