CREATE TABLE projects (
    id UUID PRIMARY KEY,
    name VARCHAR(120) NOT NULL UNIQUE,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE images (
    id UUID PRIMARY KEY,
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    original_filename VARCHAR(255) NOT NULL,
    stored_filename VARCHAR(255) NOT NULL,
    storage_path TEXT NOT NULL,
    content_type VARCHAR(120),
    size_bytes BIGINT NOT NULL,
    checksum_sha256 VARCHAR(64) NOT NULL,
    width INTEGER,
    height INTEGER,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE provider_runs (
    id UUID PRIMARY KEY,
    image_id UUID NOT NULL REFERENCES images(id) ON DELETE CASCADE,
    provider VARCHAR(80) NOT NULL,
    status VARCHAR(40) NOT NULL,
    response_time_ms INTEGER,
    raw_response JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE provider_labels (
    id UUID PRIMARY KEY,
    provider_run_id UUID NOT NULL REFERENCES provider_runs(id) ON DELETE CASCADE,
    label_name VARCHAR(180) NOT NULL,
    confidence NUMERIC(7, 3) NOT NULL
);

CREATE TABLE human_evaluations (
    id UUID PRIMARY KEY,
    provider_run_id UUID NOT NULL UNIQUE REFERENCES provider_runs(id) ON DELETE CASCADE,
    correct_class VARCHAR(80) NOT NULL,
    evaluation_result VARCHAR(40) NOT NULL,
    is_target_object BOOLEAN NOT NULL,
    human_note TEXT,
    evaluated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_projects_created_at ON projects(created_at DESC);
CREATE INDEX idx_images_project_id ON images(project_id);
CREATE INDEX idx_images_created_at ON images(created_at DESC);
CREATE INDEX idx_provider_runs_image_id ON provider_runs(image_id);
CREATE INDEX idx_provider_runs_provider ON provider_runs(provider);
CREATE INDEX idx_human_evaluations_result ON human_evaluations(evaluation_result);
