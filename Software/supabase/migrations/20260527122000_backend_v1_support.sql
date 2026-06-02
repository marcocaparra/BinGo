-- BinGo V1
-- Migration: 003_backend_v1_support.sql

alter table admins
    add column if not exists password_hash text;

alter table admins
    drop constraint if exists admins_role_check;

alter table admins
    add constraint admins_role_check check (role in ('ADMIN', 'ADMIN_CONQUISTA', 'BINGO_ADMIN'));

alter table machines
    add column if not exists api_key_hash text;

alter table rewards
    add column if not exists status text not null default 'AVAILABLE',
    add constraint rewards_status_check check (status in ('AVAILABLE', 'DISABLED', 'OUT_OF_STOCK'));

create table if not exists school_settings (
    school_id uuid primary key references schools(id) on delete restrict,
    small_item_daily_limit integer not null default 5 check (small_item_daily_limit >= 0),
    points_small_student integer not null default 10 check (points_small_student >= 0),
    points_small_class integer not null default 10 check (points_small_class >= 0),
    points_medium_student integer not null default 30 check (points_medium_student >= 0),
    points_medium_class integer not null default 30 check (points_medium_class >= 0),
    points_large_student integer not null default 50 check (points_large_student >= 0),
    points_large_class integer not null default 50 check (points_large_class >= 0),
    redemption_expiration_hours integer not null default 72 check (redemption_expiration_hours > 0),
    redemption_daily_limit integer not null default 3 check (redemption_daily_limit >= 0),
    redemption_max_pending integer not null default 3 check (redemption_max_pending >= 0),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

insert into school_settings (school_id)
select id from schools
where not exists (
    select 1 from school_settings ss where ss.school_id = schools.id
);

create index if not exists idx_deposits_student_created_at on deposits(student_id, created_at);
create index if not exists idx_redemptions_student_status on redemptions(student_id, status);
