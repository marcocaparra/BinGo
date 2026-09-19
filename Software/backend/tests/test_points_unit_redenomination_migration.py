import os
import uuid
from decimal import Decimal
from pathlib import Path

import psycopg
import pytest
from psycopg.conninfo import conninfo_to_dict, make_conninfo


MIGRATION_TEST_DATABASE_URL = os.getenv("BINGO_MIGRATION_TEST_DATABASE_URL")
REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
DATABASE_MIGRATIONS = REPOSITORY_ROOT / "database" / "migrations"
DATABASE_MIGRATION = DATABASE_MIGRATIONS / "011_points_unit_redenomination.sql"
SUPABASE_MIGRATION = (
    REPOSITORY_ROOT
    / "supabase"
    / "migrations"
    / "20260913120000_points_unit_redenomination.sql"
)


def test_database_and_supabase_migrations_have_the_same_executable_body():
    database_sql = DATABASE_MIGRATION.read_text(encoding="utf-8")
    supabase_sql = SUPABASE_MIGRATION.read_text(encoding="utf-8")

    assert database_sql[database_sql.index("begin;") :] == supabase_sql[
        supabase_sql.index("begin;") :
    ]


@pytest.mark.skipif(
    not MIGRATION_TEST_DATABASE_URL,
    reason=(
        "Defina BINGO_MIGRATION_TEST_DATABASE_URL para executar a migration "
        "em bancos PostgreSQL temporarios."
    ),
)
def test_points_unit_redenomination_converts_and_audits_existing_data():
    with temporary_database() as database_url:
        with psycopg.connect(database_url, autocommit=True) as connection:
            prepare_schema_before_redenomination(connection)
            fixture = seed_conversion_fixture(connection)
            execute_sql_file(connection, DATABASE_MIGRATION)

            with connection.cursor() as cursor:
                cursor.execute(
                    """
                    select deposit_bincoins_base, deposit_class_xp_base,
                           class_weekly_xp_goal, created_at, updated_at
                    from public.school_settings
                    where school_id = %s
                    """,
                    (fixture["school_id"],),
                )
                assert cursor.fetchone() == (
                    1000,
                    2000,
                    15000,
                    fixture["settings_created_at"],
                    fixture["settings_updated_at"],
                )

                cursor.execute(
                    """
                    select id, points_student_balance, created_at, updated_at
                    from public.students where id = %s
                    """,
                    (fixture["student_id"],),
                )
                assert cursor.fetchone() == (
                    fixture["student_id"],
                    1200,
                    fixture["student_created_at"],
                    fixture["student_updated_at"],
                )

                cursor.execute(
                    """
                    select id, points_class_balance, created_at, updated_at
                    from public.classes where id = %s
                    """,
                    (fixture["class_id"],),
                )
                assert cursor.fetchone() == (
                    fixture["class_id"],
                    700,
                    fixture["class_created_at"],
                    fixture["class_updated_at"],
                )

                cursor.execute(
                    """
                    select id, points_awarded_student, points_awarded_class,
                           bonus_rate_applied, bonus_bincoins_awarded, created_at
                    from public.deposits where id = %s
                    """,
                    (fixture["deposit_id"],),
                )
                assert cursor.fetchone() == (
                    fixture["deposit_id"],
                    1500,
                    2000,
                    fixture["bonus_rate_applied"],
                    500,
                    fixture["deposit_created_at"],
                )

                cursor.execute(
                    "select bonus_rate from public.waste_categories where id = %s",
                    (fixture["category_id"],),
                )
                assert cursor.fetchone()[0] == Decimal("0.5000")

                cursor.execute(
                    """
                    select id, cost_points, stock_qty, created_at, updated_at
                    from public.rewards where id = %s
                    """,
                    (fixture["reward_id"],),
                )
                assert cursor.fetchone() == (
                    fixture["reward_id"],
                    3000,
                    9,
                    fixture["reward_created_at"],
                    fixture["reward_updated_at"],
                )

                cursor.execute(
                    """
                    select id, school_id, student_id, reward_id, code, status,
                           request_channel, created_at, expires_at, delivered_at,
                           delivered_by_admin_id
                    from public.redemptions where id = %s
                    """,
                    (fixture["redemption_id"],),
                )
                assert cursor.fetchone() == fixture["redemption_snapshot"]

                cursor.execute(
                    "select metadata from public.audit_logs where id = %s",
                    (fixture["historical_audit_id"],),
                )
                assert cursor.fetchone()[0] == fixture["historical_metadata"]

                cursor.execute(
                    """
                    select count(*)::integer,
                           min(actor_type),
                           bool_and(actor_id is null),
                           min((metadata ->> 'factor')::integer),
                           min(metadata ->> 'migration_id'),
                           min(metadata ->> 'database_migration'),
                           min(metadata ->> 'supabase_migration'),
                           min(metadata ->> 'historical_audit_logs_metadata')
                    from public.audit_logs
                    where school_id = %s
                      and action = 'POINTS_UNIT_REDENOMINATED_V1'
                    """,
                    (fixture["school_id"],),
                )
                assert cursor.fetchone() == (
                    1,
                    "SYSTEM",
                    True,
                    100,
                    "POINTS_UNIT_REDENOMINATION_V1",
                    "011_points_unit_redenomination.sql",
                    "20260913120000_points_unit_redenomination.sql",
                    "PRESERVED_IN_PREVIOUS_UNIT",
                )

                cursor.execute(
                    """
                    select count(*)::integer,
                           count(distinct school_id)::integer,
                           bool_and(events_per_school = 1)
                    from (
                        select school_id, count(*)::integer as events_per_school
                        from public.audit_logs
                        where action = 'POINTS_UNIT_REDENOMINATED_V1'
                        group by school_id
                    ) as redenomination_events
                    """
                )
                assert cursor.fetchone() == (2, 2, True)

                assert_table_counts(cursor, fixture["counts_before"], audit_delta=2)
                assert_final_defaults(cursor)

                cursor.execute(
                    "insert into public.schools (id, name) values (%s, 'Defaults novos')",
                    (uuid.uuid4(),),
                )
                default_school_id = cursor.execute(
                    "select id from public.schools where name = 'Defaults novos'"
                ).fetchone()[0]
                cursor.execute(
                    "insert into public.school_settings (school_id) values (%s) returning deposit_bincoins_base, deposit_class_xp_base, class_weekly_xp_goal",
                    (default_school_id,),
                )
                assert cursor.fetchone() == (800, 1900, 10000)

            with pytest.raises(psycopg.Error) as repeated:
                execute_sql_file(connection, DATABASE_MIGRATION)
            assert repeated.value.sqlstate == "P0001"
            assert "unidade nova ja esta configurada" in str(repeated.value)
            connection.rollback()

            with connection.cursor() as cursor:
                cursor.execute(
                    "select points_student_balance from public.students where id = %s",
                    (fixture["student_id"],),
                )
                assert cursor.fetchone()[0] == 1200
                cursor.execute(
                    "select count(*) from public.audit_logs where action = 'POINTS_UNIT_REDENOMINATED_V1'"
                )
                assert cursor.fetchone()[0] == 2


@pytest.mark.skipif(
    not MIGRATION_TEST_DATABASE_URL,
    reason=(
        "Defina BINGO_MIGRATION_TEST_DATABASE_URL para executar os guards "
        "estruturais em bancos PostgreSQL temporarios."
    ),
)
@pytest.mark.parametrize(
    ("default_mutation", "expected_message"),
    [
        (
            "alter table public.school_settings alter column deposit_class_xp_base set default 1900",
            "defaults em estado inesperado",
        ),
        (
            "alter table public.school_settings alter column deposit_bincoins_base set default 9",
            "defaults em estado inesperado",
        ),
        (
            "alter table public.school_settings alter column deposit_bincoins_base set default null",
            "defaults estruturais de pontuacao ausentes",
        ),
        (
            "alter table public.school_settings alter column deposit_bincoins_base drop default",
            "defaults estruturais de pontuacao ausentes",
        ),
        (
            """
            create function public.points_default_evaluation_failure()
            returns integer
            language plpgsql
            as $$
            begin
                raise exception 'default nao pode ser avaliado';
            end;
            $$;
            alter table public.school_settings
                alter column deposit_bincoins_base
                set default public.points_default_evaluation_failure()
            """,
            "defaults estruturais de pontuacao inesperados",
        ),
    ],
    ids=(
        "mixed-defaults",
        "unexpected-numeric-default",
        "null-default",
        "missing-default",
        "default-evaluation-failure",
    ),
)
def test_points_unit_redenomination_rejects_unexpected_structural_defaults(
    default_mutation,
    expected_message,
):
    with temporary_database() as database_url:
        with psycopg.connect(database_url, autocommit=True) as connection:
            prepare_schema_before_redenomination(connection)
            fixture = seed_conversion_fixture(connection)
            connection.execute(default_mutation)
            before = economic_values_snapshot(connection, fixture)

            with pytest.raises(psycopg.Error) as rejected:
                execute_sql_file(connection, DATABASE_MIGRATION)
            assert rejected.value.sqlstate == "P0001"
            assert expected_message in str(rejected.value)
            connection.rollback()

            assert economic_values_snapshot(connection, fixture) == before
            with connection.cursor() as cursor:
                cursor.execute(
                    "select count(*) from public.audit_logs where action = 'POINTS_UNIT_REDENOMINATED_V1'"
                )
                assert cursor.fetchone()[0] == 0


@pytest.mark.skipif(
    not MIGRATION_TEST_DATABASE_URL,
    reason=(
        "Defina BINGO_MIGRATION_TEST_DATABASE_URL para executar a prova "
        "transacional de overflow."
    ),
)
def test_points_unit_redenomination_overflow_aborts_without_partial_state():
    with temporary_database() as database_url:
        with psycopg.connect(database_url, autocommit=True) as connection:
            prepare_schema_before_redenomination(connection)
            school_id, class_id, student_id = seed_overflow_fixture(connection)

            with pytest.raises(psycopg.Error) as overflow:
                execute_sql_file(connection, DATABASE_MIGRATION)
            assert overflow.value.sqlstate == "22003"
            assert "students.points_student_balance" in str(overflow.value)
            connection.rollback()

            with connection.cursor() as cursor:
                cursor.execute(
                    "select deposit_bincoins_base, deposit_class_xp_base, class_weekly_xp_goal from public.school_settings where school_id = %s",
                    (school_id,),
                )
                assert cursor.fetchone() == (8, 19, 100)
                cursor.execute(
                    "select points_class_balance from public.classes where id = %s",
                    (class_id,),
                )
                assert cursor.fetchone()[0] == 7
                cursor.execute(
                    "select points_student_balance from public.students where id = %s",
                    (student_id,),
                )
                assert cursor.fetchone()[0] == 21_474_837
                cursor.execute(
                    "select count(*) from public.audit_logs where action = 'POINTS_UNIT_REDENOMINATED_V1'"
                )
                assert cursor.fetchone()[0] == 0
                assert_old_defaults(cursor)


class temporary_database:
    def __init__(self):
        self.database_name = f"bingo_points_migration_test_{uuid.uuid4().hex}"
        self.admin_parameters = conninfo_to_dict(MIGRATION_TEST_DATABASE_URL)
        self.admin_url = make_conninfo(**self.admin_parameters)
        self.test_url = make_conninfo(
            **{**self.admin_parameters, "dbname": self.database_name}
        )

    def __enter__(self):
        with psycopg.connect(self.admin_url, autocommit=True) as connection:
            connection.execute(
                f'create database "{self.database_name}" template template0 encoding \'UTF8\''
            )
        return self.test_url

    def __exit__(self, exc_type, exc_value, traceback):
        with psycopg.connect(self.admin_url, autocommit=True) as connection:
            connection.execute(
                """
                select pg_terminate_backend(pid)
                from pg_stat_activity
                where datname = %s and pid <> pg_backend_pid()
                """,
                (self.database_name,),
            )
            connection.execute(f'drop database if exists "{self.database_name}"')


def prepare_schema_before_redenomination(connection):
    connection.execute("create schema if not exists auth")
    connection.execute(
        """
        create function auth.uid()
        returns uuid
        language sql
        stable
        as $$ select null::uuid $$
        """
    )
    for migration in sorted(DATABASE_MIGRATIONS.glob("[0-9][0-9][0-9]_*.sql")):
        if migration.name >= DATABASE_MIGRATION.name:
            break
        execute_sql_file(connection, migration)


def execute_sql_file(connection, path):
    connection.execute(path.read_text(encoding="utf-8"))


def seed_conversion_fixture(connection):
    identifiers = {
        "school_id": uuid.uuid4(),
        "second_school_id": uuid.uuid4(),
        "class_id": uuid.uuid4(),
        "student_id": uuid.uuid4(),
        "machine_id": uuid.uuid4(),
        "deposit_id": uuid.uuid4(),
        "reward_id": uuid.uuid4(),
        "redemption_id": uuid.uuid4(),
        "historical_audit_id": uuid.uuid4(),
    }
    historical_metadata = {
        "event_id": str(uuid.uuid4()),
        "points_awarded_student": 15,
        "points_awarded_class": 20,
        "bonus_bincoins_awarded": 5,
    }

    with connection.transaction():
        with connection.cursor() as cursor:
            cursor.execute(
                "insert into public.schools (id, name) values (%s, 'Escola migration')",
                (identifiers["school_id"],),
            )
            cursor.execute(
                "insert into public.schools (id, name) values (%s, 'Escola migration 2')",
                (identifiers["second_school_id"],),
            )
            cursor.execute(
                """
                insert into public.school_settings (
                    school_id, deposit_bincoins_base, deposit_class_xp_base,
                    class_weekly_xp_goal
                ) values (%s, 10, 20, 150)
                """,
                (identifiers["school_id"],),
            )
            cursor.execute(
                "insert into public.school_settings (school_id) values (%s)",
                (identifiers["second_school_id"],),
            )
            cursor.execute(
                """
                insert into public.classes (
                    id, school_id, segment, grade, name, points_class_balance
                ) values (%s, %s, 'TEST', '1', 'Turma migration', 7)
                """,
                (identifiers["class_id"], identifiers["school_id"]),
            )
            cursor.execute(
                """
                insert into public.students (
                    id, school_id, class_id, name, points_student_balance, status
                ) values (%s, %s, %s, 'Aluno migration', 12, 'ACTIVE')
                """,
                (
                    identifiers["student_id"],
                    identifiers["school_id"],
                    identifiers["class_id"],
                ),
            )
            cursor.execute(
                """
                insert into public.machines (id, school_id, name, status)
                values (%s, %s, 'Totem migration', 'ONLINE')
                """,
                (identifiers["machine_id"], identifiers["school_id"]),
            )
            category_id = cursor.execute(
                "select id from public.waste_categories where code = 'MOBILE_DEVICE'"
            ).fetchone()[0]
            cursor.execute(
                "update public.waste_categories set bonus_rate = 0.5000 where id = %s",
                (category_id,),
            )
            cursor.execute(
                """
                insert into public.deposits (
                    id, event_id, school_id, machine_id, class_id, student_id,
                    is_valid, detected_type, points_awarded_student,
                    points_awarded_class, created_at, waste_category_id,
                    category_source, bonus_rate_applied,
                    bonus_bincoins_awarded
                ) values (
                    %s, %s, %s, %s, %s, %s, true, 'mobile', 15, 20,
                    '2026-09-01T12:34:56Z', %s, 'AI_CONFIRMED', 0.5000, 5
                )
                """,
                (
                    identifiers["deposit_id"],
                    historical_metadata["event_id"],
                    identifiers["school_id"],
                    identifiers["machine_id"],
                    identifiers["class_id"],
                    identifiers["student_id"],
                    category_id,
                ),
            )
            cursor.execute(
                """
                insert into public.rewards (
                    id, school_id, name, cost_points, is_active, status, stock_qty
                ) values (%s, %s, 'Reward migration', 30, true, 'AVAILABLE', 9)
                """,
                (identifiers["reward_id"], identifiers["school_id"]),
            )
            cursor.execute(
                """
                insert into public.redemptions (
                    id, school_id, student_id, reward_id, code, status,
                    request_channel, created_at, expires_at
                ) values (
                    %s, %s, %s, %s, 'MIGRTEST', 'PENDING', 'TOTEM',
                    '2026-09-02T10:00:00Z', '2026-09-03T10:00:00Z'
                )
                """,
                (
                    identifiers["redemption_id"],
                    identifiers["school_id"],
                    identifiers["student_id"],
                    identifiers["reward_id"],
                ),
            )
            cursor.execute(
                """
                insert into public.audit_logs (
                    id, school_id, actor_type, actor_id, action, metadata,
                    created_at
                ) values (
                    %s, %s, 'MACHINE', %s, 'DEPOSIT_REGISTERED', %s::jsonb,
                    '2026-09-01T12:34:57Z'
                )
                """,
                (
                    identifiers["historical_audit_id"],
                    identifiers["school_id"],
                    identifiers["machine_id"],
                    psycopg.types.json.Jsonb(historical_metadata),
                ),
            )

            identifiers.update(read_fixture_snapshots(cursor, identifiers))
            identifiers["category_id"] = category_id
            identifiers["historical_metadata"] = historical_metadata
            identifiers["counts_before"] = table_counts(cursor)
    return identifiers


def seed_overflow_fixture(connection):
    school_id = uuid.uuid4()
    class_id = uuid.uuid4()
    student_id = uuid.uuid4()
    with connection.transaction():
        connection.execute(
            "insert into public.schools (id, name) values (%s, 'Escola overflow')",
            (school_id,),
        )
        connection.execute(
            "insert into public.school_settings (school_id) values (%s)",
            (school_id,),
        )
        connection.execute(
            """
            insert into public.classes (
                id, school_id, segment, grade, name, points_class_balance
            ) values (%s, %s, 'TEST', '1', 'Turma overflow', 7)
            """,
            (class_id, school_id),
        )
        connection.execute(
            """
            insert into public.students (
                id, school_id, class_id, name, points_student_balance, status
            ) values (%s, %s, %s, 'Aluno overflow', 21474837, 'ACTIVE')
            """,
            (student_id, school_id, class_id),
        )
    return school_id, class_id, student_id


def read_fixture_snapshots(cursor, identifiers):
    cursor.execute(
        "select created_at, updated_at from public.school_settings where school_id = %s",
        (identifiers["school_id"],),
    )
    settings_created_at, settings_updated_at = cursor.fetchone()
    cursor.execute(
        "select created_at, updated_at from public.students where id = %s",
        (identifiers["student_id"],),
    )
    student_created_at, student_updated_at = cursor.fetchone()
    cursor.execute(
        "select created_at, updated_at from public.classes where id = %s",
        (identifiers["class_id"],),
    )
    class_created_at, class_updated_at = cursor.fetchone()
    cursor.execute(
        "select created_at from public.deposits where id = %s",
        (identifiers["deposit_id"],),
    )
    deposit_created_at = cursor.fetchone()[0]
    cursor.execute(
        "select created_at, updated_at from public.rewards where id = %s",
        (identifiers["reward_id"],),
    )
    reward_created_at, reward_updated_at = cursor.fetchone()
    cursor.execute(
        """
        select id, school_id, student_id, reward_id, code, status,
               request_channel, created_at, expires_at, delivered_at,
               delivered_by_admin_id
        from public.redemptions where id = %s
        """,
        (identifiers["redemption_id"],),
    )
    return {
        "settings_created_at": settings_created_at,
        "settings_updated_at": settings_updated_at,
        "student_created_at": student_created_at,
        "student_updated_at": student_updated_at,
        "class_created_at": class_created_at,
        "class_updated_at": class_updated_at,
        "deposit_created_at": deposit_created_at,
        "reward_created_at": reward_created_at,
        "reward_updated_at": reward_updated_at,
        "redemption_snapshot": cursor.fetchone(),
        "bonus_rate_applied": Decimal("0.5000"),
    }


def economic_values_snapshot(connection, identifiers):
    with connection.cursor() as cursor:
        cursor.execute(
            """
            select
                (select deposit_bincoins_base from public.school_settings where school_id = %s),
                (select deposit_class_xp_base from public.school_settings where school_id = %s),
                (select class_weekly_xp_goal from public.school_settings where school_id = %s),
                (select points_student_balance from public.students where id = %s),
                (select points_class_balance from public.classes where id = %s),
                (select points_awarded_student from public.deposits where id = %s),
                (select points_awarded_class from public.deposits where id = %s),
                (select bonus_bincoins_awarded from public.deposits where id = %s),
                (select cost_points from public.rewards where id = %s)
            """,
            (
                identifiers["school_id"],
                identifiers["school_id"],
                identifiers["school_id"],
                identifiers["student_id"],
                identifiers["class_id"],
                identifiers["deposit_id"],
                identifiers["deposit_id"],
                identifiers["deposit_id"],
                identifiers["reward_id"],
            ),
        )
        return cursor.fetchone()


def table_counts(cursor):
    return {
        table: cursor.execute(f"select count(*) from public.{table}").fetchone()[0]
        for table in (
            "school_settings",
            "students",
            "classes",
            "deposits",
            "rewards",
            "redemptions",
            "audit_logs",
        )
    }


def assert_table_counts(cursor, before, audit_delta):
    after = table_counts(cursor)
    assert after == {**before, "audit_logs": before["audit_logs"] + audit_delta}


def assert_final_defaults(cursor):
    cursor.execute(
        """
        select
            pg_get_expr(bincoins.adbin, bincoins.adrelid),
            pg_get_expr(class_xp.adbin, class_xp.adrelid),
            pg_get_expr(weekly_goal.adbin, weekly_goal.adrelid)
        from pg_attrdef as bincoins
        join pg_attribute as bincoins_attribute
          on bincoins_attribute.attrelid = bincoins.adrelid
         and bincoins_attribute.attnum = bincoins.adnum
        join pg_attrdef as class_xp on class_xp.adrelid = bincoins.adrelid
        join pg_attribute as class_xp_attribute
          on class_xp_attribute.attrelid = class_xp.adrelid
         and class_xp_attribute.attnum = class_xp.adnum
        join pg_attrdef as weekly_goal on weekly_goal.adrelid = bincoins.adrelid
        join pg_attribute as weekly_goal_attribute
          on weekly_goal_attribute.attrelid = weekly_goal.adrelid
         and weekly_goal_attribute.attnum = weekly_goal.adnum
        where bincoins.adrelid = 'public.school_settings'::regclass
          and bincoins_attribute.attname = 'deposit_bincoins_base'
          and class_xp_attribute.attname = 'deposit_class_xp_base'
          and weekly_goal_attribute.attname = 'class_weekly_xp_goal'
        """
    )
    defaults = cursor.fetchone()
    assert tuple(int(value.split("::")[0]) for value in defaults) == (
        800,
        1900,
        10000,
    )


def assert_old_defaults(cursor):
    cursor.execute(
        """
        select column_name, column_default
        from information_schema.columns
        where table_schema = 'public'
          and table_name = 'school_settings'
          and column_name in (
              'deposit_bincoins_base',
              'deposit_class_xp_base',
              'class_weekly_xp_goal'
          )
        """
    )
    defaults = {name: value for name, value in cursor.fetchall()}
    assert int(defaults["deposit_bincoins_base"].split("::")[0]) == 8
    assert int(defaults["deposit_class_xp_base"].split("::")[0]) == 19
    assert int(defaults["class_weekly_xp_goal"].split("::")[0]) == 100
