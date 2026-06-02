-- BinGo V1
-- Migration: 001_initial_schema.sql

-- Extensão para geração de UUID (compatível com Postgres/Supabase)
create extension if not exists pgcrypto;

-- =========================
-- 1. SCHOOLS
-- =========================
create table schools (
    id uuid primary key default gen_random_uuid(),
    name text not null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

-- =========================
-- 2. CLASSES
-- =========================
create table classes (
    id uuid primary key default gen_random_uuid(),
    school_id uuid not null references schools(id) on delete restrict,
    segment text not null,
    grade text not null,
    name text not null,
    points_class_balance integer not null default 0 check (points_class_balance >= 0),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

-- =========================
-- 3. STUDENTS
-- =========================
create table students (
    id uuid primary key default gen_random_uuid(),
    school_id uuid not null references schools(id) on delete restrict,
    class_id uuid not null references classes(id) on delete restrict,
    name text not null,
    pin_hash text,
    is_activated boolean not null default false,
    points_student_balance integer not null default 0 check (points_student_balance >= 0),
    status text not null default 'ACTIVE' check (status in ('ACTIVE', 'INACTIVE')),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

-- =========================
-- 4. ADMINS
-- =========================
create table admins (
    id uuid primary key default gen_random_uuid(),
    school_id uuid not null references schools(id) on delete restrict,
    name text not null,
    email text not null,
    role text not null check (role in ('ADMIN', 'ADMIN_CONQUISTA')),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (email)
);

-- =========================
-- 5. MACHINES
-- =========================
create table machines (
    id uuid primary key default gen_random_uuid(),
    school_id uuid not null references schools(id) on delete restrict,
    name text not null,
    status text not null check (status in ('ONLINE', 'OFFLINE', 'MAINTENANCE', 'OUT_OF_SERVICE')),
    firmware_version text,
    last_seen timestamptz,
    bin_full boolean not null default false,
    camera_ok boolean not null default true,
    net_ok boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

-- =========================
-- 6. REWARDS
-- =========================
create table rewards (
    id uuid primary key default gen_random_uuid(),
    school_id uuid not null references schools(id) on delete restrict,
    name text not null,
    description text,
    cost_points integer not null check (cost_points > 0),
    category text,
    is_active boolean not null default true,
    stock_qty integer check (stock_qty is null or stock_qty >= 0),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

-- =========================
-- 7. DEPOSITS
-- =========================
create table deposits (
    id uuid primary key default gen_random_uuid(),
    event_id uuid not null unique,
    school_id uuid not null references schools(id) on delete restrict,
    machine_id uuid not null references machines(id) on delete restrict,
    class_id uuid not null references classes(id) on delete restrict,
    student_id uuid references students(id) on delete restrict,
    is_valid boolean not null,
    detected_type text,
    size text not null check (size in ('SMALL', 'MEDIUM', 'LARGE')),
    points_awarded_student integer not null default 0 check (points_awarded_student >= 0),
    points_awarded_class integer not null default 0 check (points_awarded_class >= 0),
    created_at timestamptz not null default now()
);

-- =========================
-- 8. REDEMPTIONS
-- =========================
create table redemptions (
    id uuid primary key default gen_random_uuid(),
    school_id uuid not null references schools(id) on delete restrict,
    student_id uuid not null references students(id) on delete restrict,
    reward_id uuid not null references rewards(id) on delete restrict,
    code text not null unique,
    status text not null check (status in ('PENDING', 'DELIVERED', 'CANCELED', 'EXPIRED')),
    request_channel text not null default 'TOTEM' check (request_channel in ('TOTEM')),
    created_at timestamptz not null default now(),
    expires_at timestamptz,
    delivered_at timestamptz,
    delivered_by_admin_id uuid references admins(id) on delete restrict
);

-- =========================
-- 9. AUDIT LOGS
-- =========================
create table audit_logs (
    id uuid primary key default gen_random_uuid(),
    school_id uuid not null references schools(id) on delete restrict,
    actor_type text not null check (actor_type in ('ADMIN', 'STUDENT', 'MACHINE', 'SYSTEM')),
    actor_id uuid,
    action text not null,
    metadata jsonb,
    created_at timestamptz not null default now()
);