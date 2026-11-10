/* Private V1 stdio protocol. Included in bingo_controller.c to reuse static PWM
 * routines without exporting or rewriting them. No startup/replay motion.
 */
#include <ctype.h>
#include <math.h>
#include <signal.h>
#include <sqlite3.h>
#include <sys/stat.h>

#ifdef BINGO_PWM_SIMULATED
#define IPC_SOURCE "SIMULATED"
#define IPC_APPLICATION_ID 1112098627
#define IPC_APPLICATION_PRAGMA "PRAGMA application_id=1112098627;"
#define IPC_REJECTION "CONTROLLER_BUSY"
#define IPC_EXTRA_COLUMNS ""
#define IPC_EXTRA_IDENTITY ""
#define IPC_CREATE_VERSION "PRAGMA user_version=2;"
#define IPC_RESULT_CONSTRAINT \
    "CHECK((state='ACCEPTED' AND result='PENDING' AND error='-') OR " \
    "(state='COMPLETED' AND result='SUCCEEDED' AND error='-') OR " \
    "(state='REJECTED' AND result='UNAVAILABLE' AND error='CONTROLLER_BUSY') OR " \
    "(state='FAILED' AND ((result='FAILURE' AND error='OPERATION_FAILED') OR " \
    "(result='UNKNOWN' AND error='EXECUTION_ERROR'))))"
#else
/* Distinct database identity: simulated history cannot become physical evidence. */
#define IPC_SOURCE "UNAVAILABLE"
#define IPC_APPLICATION_ID 1112098640
#define IPC_APPLICATION_PRAGMA "PRAGMA application_id=1112098640;"
#define IPC_REJECTION "CONTROLLER_UNAVAILABLE"
#define IPC_EXTRA_COLUMNS "source TEXT NOT NULL,configuration TEXT NOT NULL,"
#define IPC_EXTRA_IDENTITY ",source,configuration"
#define IPC_CREATE_VERSION "PRAGMA user_version=4;"
#define IPC_RESULT_CONSTRAINT \
    "CHECK(profile='doorless-v1' AND ((source='UNAVAILABLE' AND state='REJECTED' AND result='UNAVAILABLE' " \
    "AND error IN ('CONTROLLER_UNAVAILABLE','CONTROLLER_BUSY')) OR " \
    "(source='PHYSICAL' AND ((state='ACCEPTED' AND result='PENDING' AND error='-') OR " \
    "(state='COMPLETED' AND result='SUCCEEDED' AND error='-' AND operation='CYCLE_LOWER_HATCH' " \
    "AND json_valid(configuration) AND json_extract(configuration,'$.physical.cycle.completion_policy') IS 'operational-sequence-v1') OR " \
    "(state='FAILED' AND result='UNKNOWN' AND error='EXECUTION_ERROR')))))"
#endif

static sqlite3 *ipc_db;
static const char *ipc_profile = "legacy-v1";

/* profile binds the immutable simulated sequence/calibration to each order.
 * V1 rows are retained as legacy-v1; neither migration nor GET performs PWM.
 */
#define IPC_ORDER_COLUMNS \
    "id TEXT PRIMARY KEY NOT NULL CHECK(length(id)=36)," \
    "event TEXT NOT NULL CHECK(length(event)=36)," \
    "operation TEXT NOT NULL CHECK(operation IN ('OPEN_INSERTION_DOOR','CLOSE_INSERTION_DOOR','CYCLE_LOWER_HATCH','CONFIRM_INITIAL_STATE','CONFIRM_HAND_REMOVED'))," \
    "timeout TEXT NOT NULL,state TEXT NOT NULL,result TEXT NOT NULL,error TEXT NOT NULL," \
    "profile TEXT NOT NULL CHECK(profile IN ('legacy-v1','doorless-v1'))," \
    IPC_EXTRA_COLUMNS \
    IPC_RESULT_CONSTRAINT
#define IPC_ORDER_PROTECTIONS \
    "CREATE TRIGGER order_identity BEFORE UPDATE OF id,event,operation,timeout,profile" IPC_EXTRA_IDENTITY " ON orders " \
    "BEGIN SELECT RAISE(ABORT,'Immutable order identity'); END;" \
    "CREATE TRIGGER order_retention BEFORE DELETE ON orders " \
    "BEGIN SELECT RAISE(ABORT,'Retained order identity'); END;"

static void ipc_fatal(void)
{
#ifndef BINGO_PWM_SIMULATED
    if (physical_pwm.touched) (void)pwm_stop(&physical_pwm);
    pwm_release(&physical_pwm);
#endif
    fprintf(stderr, "Controller journal/communication failure; execution blocked.\n");
    exit(2);
}

static void ipc_sql(const char *sql)
{
    if (sqlite3_exec(ipc_db, sql, NULL, NULL, NULL) != SQLITE_OK) ipc_fatal();
}

static sqlite3_stmt *ipc_prepare(const char *sql)
{
    sqlite3_stmt *statement;
    if (sqlite3_prepare_v2(ipc_db, sql, -1, &statement, NULL) != SQLITE_OK) ipc_fatal();
    return statement;
}

static void ipc_bind(sqlite3_stmt *statement, int index, const char *value)
{
    if (sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT) != SQLITE_OK)
        ipc_fatal();
}

static void ipc_done(sqlite3_stmt *statement)
{
    if (sqlite3_step(statement) != SQLITE_DONE) ipc_fatal();
    if (sqlite3_finalize(statement) != SQLITE_OK) ipc_fatal();
}

static void ipc_error(const char *code)
{
    if (fprintf(stdout, "V1 ERROR %s\n", code) < 0 || fflush(stdout)) ipc_fatal();
}

static int ipc_uuid(const char *value)
{
    if (strlen(value) != 36) return 0;
    for (int i = 0; i < 36; i++) {
        if (i == 8 || i == 13 || i == 18 || i == 23) {
            if (value[i] != '-') return 0;
        } else if (!isdigit((unsigned char)value[i]) &&
                   !(value[i] >= 'a' && value[i] <= 'f')) return 0;
    }
    return 1;
}

static int ipc_operation(const char *op)
{
    return !strcmp(op, "OPEN_INSERTION_DOOR") || !strcmp(op, "CLOSE_INSERTION_DOOR") ||
           !strcmp(op, "CYCLE_LOWER_HATCH") || !strcmp(op, "CONFIRM_INITIAL_STATE") ||
           !strcmp(op, "CONFIRM_HAND_REMOVED");
}

static int ipc_emit(const char *id)
{
#ifdef BINGO_PWM_SIMULATED
    sqlite3_stmt *s = ipc_prepare("SELECT id,event,operation,timeout,state,result,error FROM orders WHERE id=?");
#else
    sqlite3_stmt *s = ipc_prepare("SELECT id,event,operation,timeout,state,result,error,source,configuration FROM orders WHERE id=?");
#endif
    ipc_bind(s, 1, id);
    int status = sqlite3_step(s);
    if (status == SQLITE_DONE) {
        sqlite3_finalize(s);
        ipc_error("NOT_FOUND");
        return 0;
    }
    if (status != SQLITE_ROW) ipc_fatal();
    const char *source = IPC_SOURCE;
#ifndef BINGO_PWM_SIMULATED
    source = (const char *)sqlite3_column_text(s, 7);
    /* V1 GET carries no configuration field. A configured receiver must not
     * attribute an old result to a different loaded snapshot. Unconfigured
     * historical read-only inspection remains available, without dispatch.
     */
    if (physical_pwm.config.snapshot[0] &&
        strcmp(physical_pwm.config.snapshot, (const char *)sqlite3_column_text(s, 8))) {
        sqlite3_finalize(s);
        ipc_error("CONFIGURATION_CONFLICT");
        return 0;
    }
#endif
    if (fprintf(stdout, "V1 RESULT %s %s %s %s %s %s %s %s\n",
                sqlite3_column_text(s, 0), sqlite3_column_text(s, 1),
                sqlite3_column_text(s, 2), sqlite3_column_text(s, 3),
                sqlite3_column_text(s, 4), sqlite3_column_text(s, 5),
                sqlite3_column_text(s, 6), source) < 0 || fflush(stdout)) ipc_fatal();
    sqlite3_finalize(s);
    return 1;
}

static int ipc_in_sequence(const char *event, const char *op)
{
    int doorless = !strcmp(ipc_profile, "doorless-v1");
    const char *first_op = doorless ? "CONFIRM_HAND_REMOVED" : "OPEN_INSERTION_DOOR";
    if (doorless ? (!strcmp(op, "OPEN_INSERTION_DOOR") || !strcmp(op, "CLOSE_INSERTION_DOOR"))
                 : !strcmp(op, "CONFIRM_HAND_REMOVED")) return 0;
    sqlite3_stmt *s = ipc_prepare("SELECT count(*) FROM orders WHERE state IN ('ACCEPTED','FAILED','TIMED_OUT','CANCELLED')");
    if (sqlite3_step(s) != SQLITE_ROW) ipc_fatal();
    int blocked = sqlite3_column_int(s, 0);
    sqlite3_finalize(s);
    if (blocked) return 0;
    if (!strcmp(op, first_op)) {
        s = ipc_prepare("SELECT count(*) FROM orders WHERE event=? AND state='COMPLETED'");
        ipc_bind(s, 1, event);
        if (sqlite3_step(s) != SQLITE_ROW) ipc_fatal();
        int reused_event = sqlite3_column_int(s, 0);
        sqlite3_finalize(s);
        if (reused_event) return 0;
    }
    s = ipc_prepare("SELECT event,operation,profile FROM orders WHERE state='COMPLETED' ORDER BY rowid DESC LIMIT 1");
    int status = sqlite3_step(s);
    int allowed = 0;
    if (status == SQLITE_DONE) allowed = !strcmp(op, first_op);
    else if (status == SQLITE_ROW) {
        const char *previous_event = (const char *)sqlite3_column_text(s, 0);
        const char *previous_op = (const char *)sqlite3_column_text(s, 1);
        const char *previous_profile = (const char *)sqlite3_column_text(s, 2);
        if (!strcmp(op, first_op))
            allowed = strcmp(event, previous_event) && !strcmp(previous_op, "CONFIRM_INITIAL_STATE");
        else if (!strcmp(event, previous_event) && !strcmp(ipc_profile, previous_profile)) {
            allowed = (doorless && !strcmp(op, "CYCLE_LOWER_HATCH") && !strcmp(previous_op, "CONFIRM_HAND_REMOVED")) ||
                      (!strcmp(op, "CLOSE_INSERTION_DOOR") && !strcmp(previous_op, "OPEN_INSERTION_DOOR")) ||
                      (!strcmp(op, "CYCLE_LOWER_HATCH") && !strcmp(previous_op, "CLOSE_INSERTION_DOOR")) ||
                      (!strcmp(op, "CONFIRM_INITIAL_STATE") && !strcmp(previous_op, "CYCLE_LOWER_HATCH"));
        }
    } else ipc_fatal();
    sqlite3_finalize(s);
    return allowed;
}

#ifndef BINGO_PWM_SIMULATED
static int ipc_joint_execute(const char *id, double seconds)
{
    if (!ipc_db || !sqlite3_get_autocommit(ipc_db) || !ipc_uuid(id)) return PWM_BLOCKED;
    sqlite3_stmt *s = ipc_prepare("SELECT count(*) FROM orders WHERE id=? AND operation='CYCLE_LOWER_HATCH' "
        "AND profile='doorless-v1' AND source='PHYSICAL' AND state='ACCEPTED' AND configuration=?");
    ipc_bind(s, 1, id); ipc_bind(s, 2, physical_pwm.config.snapshot);
    if (sqlite3_step(s) != SQLITE_ROW) ipc_fatal();
    int allowed = sqlite3_column_int(s, 0);
    sqlite3_finalize(s);
    if (!allowed) return PWM_BLOCKED;
    int result = pwm_joint_execute(&physical_pwm, seconds);
    s = ipc_prepare("UPDATE orders SET state=?,result=?,error=? WHERE id=? AND source='PHYSICAL' AND state='ACCEPTED'");
    ipc_bind(s, 1, result ? "FAILED" : "COMPLETED");
    ipc_bind(s, 2, result ? "UNKNOWN" : "SUCCEEDED");
    ipc_bind(s, 3, result ? "EXECUTION_ERROR" : "-");
    ipc_bind(s, 4, id); ipc_done(s);
    if (sqlite3_changes(ipc_db) != 1) ipc_fatal();
    if (!result) {
        physical_pwm.touched = 0;
        pwm_release(&physical_pwm);
    }
    return result;
}
#endif

static void ipc_submit(char **parts, long delay_ms)
{
    const char *id = parts[2], *event = parts[3], *op = parts[4], *timeout = parts[5];
    char *end;
    errno = 0;
    double seconds = strtod(timeout, &end);
    if (!ipc_uuid(id) || !ipc_uuid(event) || !ipc_operation(op) ||
        errno || *end || !isfinite(seconds) || seconds <= 0 || strlen(timeout) > 32) {
        ipc_error("INVALID_COMMAND");
        return;
    }
    ipc_sql("BEGIN IMMEDIATE");
    sqlite3_stmt *s = ipc_prepare("SELECT event,operation,timeout,profile"
#ifndef BINGO_PWM_SIMULATED
        ",configuration"
#endif
        " FROM orders WHERE id=?");
    ipc_bind(s, 1, id);
    int status = sqlite3_step(s);
    if (status == SQLITE_ROW) {
        int same = !strcmp(event, (const char *)sqlite3_column_text(s, 0)) &&
                   !strcmp(op, (const char *)sqlite3_column_text(s, 1)) &&
                   !strcmp(timeout, (const char *)sqlite3_column_text(s, 2)) &&
                   !strcmp(ipc_profile, (const char *)sqlite3_column_text(s, 3));
#ifndef BINGO_PWM_SIMULATED
        same = same && !strcmp(physical_pwm.config.snapshot, (const char *)sqlite3_column_text(s, 4));
#endif
        sqlite3_finalize(s);
        ipc_sql("ROLLBACK");
        ipc_error(same ? "DUPLICATE" : "ID_CONFLICT");
        return;
    }
    if (status != SQLITE_DONE) ipc_fatal();
    sqlite3_finalize(s);
    s = ipc_prepare("SELECT count(*) FROM orders");
    if (sqlite3_step(s) != SQLITE_ROW) ipc_fatal();
    int full = sqlite3_column_int(s, 0) >= 1024;
    sqlite3_finalize(s);
    if (full) {
        ipc_sql("ROLLBACK");
        ipc_error("CAPACITY_REACHED");
        return;
    }
#ifdef BINGO_PWM_SIMULATED
    int allowed = ipc_in_sequence(event, op);
#else
    int allowed = !strcmp(op, "CYCLE_LOWER_HATCH") && seconds > 10 && seconds <= 86400 &&
        pwm_operational_configured(&physical_pwm.config);
    (void)delay_ms;
#endif
    const char *rejection = IPC_REJECTION;
#ifndef BINGO_PWM_SIMULATED
    s = ipc_prepare("SELECT count(*) FROM orders WHERE source='PHYSICAL' AND "
        "(state IN ('ACCEPTED','FAILED') OR event=?)");
    ipc_bind(s, 1, event);
    if (sqlite3_step(s) != SQLITE_ROW) ipc_fatal();
    if (sqlite3_column_int(s, 0) || pwm_stop_requested || physical_pwm.inhibited || physical_pwm.indeterminate) {
        rejection = "CONTROLLER_BUSY";
        allowed = 0;
    }
    sqlite3_finalize(s);
#endif
#ifdef BINGO_PWM_SIMULATED
    s = ipc_prepare("INSERT INTO orders(id,event,operation,timeout,state,result,error,profile) VALUES(?,?,?,?,?,?,?,?)");
#else
    s = ipc_prepare("INSERT INTO orders(id,event,operation,timeout,state,result,error,profile,source,configuration) VALUES(?,?,?,?,?,?,?,?,?,?)");
#endif
    ipc_bind(s, 1, id); ipc_bind(s, 2, event); ipc_bind(s, 3, op); ipc_bind(s, 4, timeout);
    ipc_bind(s, 5, allowed ? "ACCEPTED" : "REJECTED");
    ipc_bind(s, 6, allowed ? "PENDING" : "UNAVAILABLE");
    ipc_bind(s, 7, allowed ? "-" : rejection);
    ipc_bind(s, 8, ipc_profile);
#ifndef BINGO_PWM_SIMULATED
    ipc_bind(s, 9, allowed ? "PHYSICAL" : "UNAVAILABLE");
    ipc_bind(s, 10, physical_pwm.config.snapshot);
#endif
    ipc_done(s);
    ipc_sql("COMMIT");
    ipc_emit(id); /* durable acceptance before any possible effect */
    if (!allowed) return;

#ifdef BINGO_PWM_SIMULATED
    /* Test-only latency; no timeout, EOF or restart ever resubmits an order. */
    struct timespec pause = {delay_ms / 1000, (delay_ms % 1000) * 1000000L};
    while (nanosleep(&pause, &pause) && errno == EINTR) {}
    int failed = 0;
    if (!strcmp(op, "OPEN_INSERTION_DOOR")) failed = abrir_porta_superior();
    else if (!strcmp(op, "CLOSE_INSERTION_DOOR")) failed = fechar_porta_superior_autorizada();
    else if (!strcmp(op, "CYCLE_LOWER_HATCH"))
        failed = !strcmp(ipc_profile, "doorless-v1") ? simulated_doorless_hatch() :
                 (abrir_escotilha() || fechar_escotilha());
    /* CONFIRM_HAND_REMOVED is a logical declaration, not a sensor or PWM.
     * CONFIRM_INITIAL_STATE is only the simulated checkpoint. No homing.
     */
    s = ipc_prepare("UPDATE orders SET state=?,result=?,error=? WHERE id=? AND state='ACCEPTED'");
    ipc_bind(s, 1, failed ? "FAILED" : "COMPLETED");
    ipc_bind(s, 2, failed ? "FAILURE" : "SUCCEEDED");
    ipc_bind(s, 3, failed ? "OPERATION_FAILED" : "-");
    ipc_bind(s, 4, id);
    ipc_done(s);
#else
    (void)ipc_joint_execute(id, seconds);
#endif
}

#ifndef BINGO_PWM_SIMULATED
/* Internal building block for a future homologated cycle policy, NOT an opcode
 * or manual bypass. There is currently no production caller/commissioner.
 * The committed intent must precede any PWM; every unproven outcome is UNKNOWN.
 */
static int ipc_pwm_pose(const char *id, int side, int pose)
{
    if (!ipc_db || !sqlite3_get_autocommit(ipc_db) || !ipc_uuid(id)) return PWM_BLOCKED;
    sqlite3_stmt *s = ipc_prepare("SELECT count(*) FROM orders WHERE id=? AND operation='CYCLE_LOWER_HATCH' "
        "AND profile='doorless-v1' AND source='PHYSICAL' AND state='ACCEPTED' AND configuration=?");
    ipc_bind(s, 1, id); ipc_bind(s, 2, physical_pwm.config.snapshot);
    if (sqlite3_step(s) != SQLITE_ROW) ipc_fatal();
    int allowed = sqlite3_column_int(s, 0);
    sqlite3_finalize(s);
    if (!allowed) return PWM_BLOCKED;
    (void)pwm_pose(&physical_pwm, side, pose);
    if (physical_pwm.touched) (void)pwm_stop(&physical_pwm);
    /* Neither write success nor a wait proves hatch position. No success branch. */
    s = ipc_prepare("UPDATE orders SET state='FAILED',result='UNKNOWN',error='EXECUTION_ERROR' "
        "WHERE id=? AND source='PHYSICAL' AND state='ACCEPTED'");
    ipc_bind(s, 1, id); ipc_done(s);
    if (sqlite3_changes(ipc_db) != 1) ipc_fatal();
    return PWM_UNKNOWN;
}
#endif

static int ipc_start(const char *path, long delay_ms)
{
    umask(077);
    if (path[0] != '/') return 2;
    char lock_path[4096];
    if (snprintf(lock_path, sizeof(lock_path), "%s.lock", path) >= (int)sizeof(lock_path)) return 2;
    int lock_fd = open(lock_path, O_CREAT | O_RDWR | O_NOFOLLOW, 0600);
    struct flock lock = {.l_type = F_WRLCK, .l_whence = SEEK_SET};
    if (lock_fd < 0 || fcntl(lock_fd, F_SETLK, &lock) < 0) return 2;
    struct stat st;
    if (lstat(path, &st) == 0 && !S_ISREG(st.st_mode)) return 2;
    if (sqlite3_open_v2(path, &ipc_db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, NULL) != SQLITE_OK)
        ipc_fatal();
    /* Verify ownership before changing journal mode or migrating any schema. */
    sqlite3_stmt *identity = ipc_prepare("PRAGMA application_id");
    if (sqlite3_step(identity) != SQLITE_ROW) ipc_fatal();
    int application = sqlite3_column_int(identity, 0);
    sqlite3_finalize(identity);
    if (application != 0 && application != IPC_APPLICATION_ID) ipc_fatal();
    ipc_sql("PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL;");
    sqlite3_stmt *s = ipc_prepare("PRAGMA quick_check");
    if (sqlite3_step(s) != SQLITE_ROW || strcmp((const char *)sqlite3_column_text(s, 0), "ok")) ipc_fatal();
    sqlite3_finalize(s);
    s = ipc_prepare("PRAGMA user_version");
    if (sqlite3_step(s) != SQLITE_ROW) ipc_fatal();
    int version = sqlite3_column_int(s, 0);
    sqlite3_finalize(s);
    if (version == 0) {
        /* Refuse unrelated databases, even if they have user_version=0. */
        s = ipc_prepare("SELECT count(*) FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'");
        if (sqlite3_step(s) != SQLITE_ROW || sqlite3_column_int(s, 0)) ipc_fatal();
        sqlite3_finalize(s);
        ipc_sql("BEGIN IMMEDIATE; CREATE TABLE orders(" IPC_ORDER_COLUMNS ");"
                IPC_ORDER_PROTECTIONS
                IPC_CREATE_VERSION IPC_APPLICATION_PRAGMA "COMMIT;");
    }
#ifdef BINGO_PWM_SIMULATED
    else if (version != 1 && version != 2) ipc_fatal();
#else
    else if (version != 2 && version != 3 && version != 4) ipc_fatal();
#endif
    s = ipc_prepare("PRAGMA application_id");
    if (sqlite3_step(s) != SQLITE_ROW || sqlite3_column_int(s, 0) != IPC_APPLICATION_ID) ipc_fatal();
    sqlite3_finalize(s);
    s = ipc_prepare("SELECT count(*) FROM sqlite_master WHERE type='trigger' AND name IN ('order_identity','order_retention')");
    if (sqlite3_step(s) != SQLITE_ROW || sqlite3_column_int(s, 0) != 2) ipc_fatal();
    sqlite3_finalize(s);
    if (version == 1) {
#ifndef BINGO_PWM_SIMULATED
        ipc_fatal(); /* Only the historical simulated schema can migrate. */
#else
        /* Preserve rowids (sequence), all identities and results. A legacy
         * pending/unknown command stays unsafe; migration never authorizes replay.
         */
        ipc_sql("BEGIN IMMEDIATE; CREATE TABLE orders_upgrade(" IPC_ORDER_COLUMNS ");"
                "INSERT INTO orders_upgrade(rowid,id,event,operation,timeout,state,result,error,profile) "
                "SELECT rowid,id,event,operation,timeout,state,result,error,'legacy-v1' FROM orders;"
                "DROP TABLE orders; ALTER TABLE orders_upgrade RENAME TO orders;"
                IPC_ORDER_PROTECTIONS "PRAGMA user_version=2; COMMIT;");
#endif
    }
#ifdef BINGO_PWM_SIMULATED
    /* No automatic dispatch after crash, even if acceptance preceded all PWM. */
    ipc_sql("UPDATE orders SET state='FAILED',result='UNKNOWN',error='EXECUTION_ERROR' WHERE state='ACCEPTED'");
    if (fprintf(stdout, !strcmp(ipc_profile, "doorless-v1") ?
                "V1 READY SIMULATED DOORLESS_V1\n" : "V1 READY SIMULATED\n") < 0 || fflush(stdout)) ipc_fatal();
#else
    if (version == 2) {
        /* Preserve every old rejection and identity, including row order. */
        ipc_sql("BEGIN IMMEDIATE; CREATE TABLE orders_upgrade(" IPC_ORDER_COLUMNS ");"
                "INSERT INTO orders_upgrade(rowid,id,event,operation,timeout,state,result,error,profile,source,configuration) "
                "SELECT rowid,id,event,operation,timeout,state,result,error,profile,'UNAVAILABLE','' FROM orders;"
                "DROP TABLE orders; ALTER TABLE orders_upgrade RENAME TO orders;"
                IPC_ORDER_PROTECTIONS IPC_CREATE_VERSION "COMMIT;");
    } else if (version == 3) {
        /* Extend allowable NEW outcomes without changing old snapshots, IDs,
         * rowids or the meaning of any historical result. */
        ipc_sql("BEGIN IMMEDIATE; CREATE TABLE orders_upgrade(" IPC_ORDER_COLUMNS ");"
                "INSERT INTO orders_upgrade(rowid,id,event,operation,timeout,state,result,error,profile,source,configuration) "
                "SELECT rowid,id,event,operation,timeout,state,result,error,profile,source,configuration FROM orders;"
                "DROP TABLE orders; ALTER TABLE orders_upgrade RENAME TO orders;"
                IPC_ORDER_PROTECTIONS IPC_CREATE_VERSION "COMMIT;");
    }
    /* A crash cannot restore position or authorize redispatch, even when it
     * occurred before the first write. No PWM/homing/corrective close here.
     */
    ipc_sql("UPDATE orders SET state='FAILED',result='UNKNOWN',error='EXECUTION_ERROR' WHERE state='ACCEPTED'");
    s = ipc_prepare("SELECT count(*) FROM orders WHERE profile!='doorless-v1' OR NOT "
        "((source='UNAVAILABLE' AND state='REJECTED' AND result='UNAVAILABLE' AND error IN ('CONTROLLER_UNAVAILABLE','CONTROLLER_BUSY')) OR "
        "(source='PHYSICAL' AND state='FAILED' AND result='UNKNOWN' AND error='EXECUTION_ERROR') OR "
        "(source='PHYSICAL' AND operation='CYCLE_LOWER_HATCH' AND state='COMPLETED' AND result='SUCCEEDED' AND error='-' "
        "AND json_valid(configuration) AND json_extract(configuration,'$.physical.cycle.completion_policy') IS 'operational-sequence-v1'))");
    if (sqlite3_step(s) != SQLITE_ROW || sqlite3_column_int(s, 0)) ipc_fatal();
    sqlite3_finalize(s);
    if (fprintf(stdout, pwm_operational_configured(&physical_pwm.config) ?
                "V1 READY PHYSICAL DOORLESS_V1 OPERATIONAL_SEQUENCE_V1\n" :
                "V1 READY UNAVAILABLE DOORLESS_V1 PHYSICAL_BLOCKED\n") < 0 || fflush(stdout)) ipc_fatal();
#endif
    char line[512];
    while (
#ifndef BINGO_PWM_SIMULATED
           !pwm_stop_requested &&
#endif
           fgets(line, sizeof(line), stdin)) {
        if (!strchr(line, '\n')) {
            int ch;
            while ((ch = getchar()) != '\n' && ch != EOF) {}
            ipc_error("INVALID_FRAME");
            continue;
        }
        char *parts[8], *save = NULL;
        int count = 0;
        for (char *p = strtok_r(line, " \t\r\n", &save); p && count < 8;
             p = strtok_r(NULL, " \t\r\n", &save)) parts[count++] = p;
        if (count == 6 && !strcmp(parts[0], "V1") && !strcmp(parts[1], "SUBMIT"))
            ipc_submit(parts, delay_ms);
        else if (count == 3 && !strcmp(parts[0], "V1") && !strcmp(parts[1], "GET") && ipc_uuid(parts[2]))
            ipc_emit(parts[2]);
        else ipc_error("INVALID_FRAME");
    }
#ifdef BINGO_PWM_SIMULATED
    if (ferror(stdin)) ipc_fatal();
#else
    if (ferror(stdin) && !pwm_stop_requested) ipc_fatal();
    if (physical_pwm.touched) (void)pwm_stop(&physical_pwm);
    pwm_release(&physical_pwm);
#endif
    sqlite3_close(ipc_db);
    close(lock_fd);
    return 0;
}

int main(int argc, char **argv)
{
    signal(SIGPIPE, SIG_IGN);
#ifndef BINGO_PWM_SIMULATED
    pwm_init(&physical_pwm);
    struct sigaction stop = {.sa_handler = pwm_signal};
    sigemptyset(&stop.sa_mask);
    if (sigaction(SIGTERM, &stop, NULL) || sigaction(SIGINT, &stop, NULL)) return 2;
    if (argc == 3 && !strcmp(argv[1], "--physical-config")) {
        if (pwm_load_config(&physical_pwm.config, argv[2])) {
            fprintf(stderr, "INVALID_PWM_CONFIGURATION\n"); return 2;
        }
        pwm_config_report(&physical_pwm.config);
        return 0;
    }
#endif
    /* No journal, sysfs, startup motion or legacy demo in this read-only path. */
    if (argc == 2 && !strcmp(argv[1], "--physical-preflight"))
        return physical_preflight();
#ifdef BINGO_PWM_SIMULATED
    if (argc < 3 || argc > 9 || !(argc % 2)) return 2;
    if (strcmp(argv[1], "--ipc-simulated")) return 2;
    long delay_ms = 0;
    for (int i = 3; i < argc; i += 2) {
        if (!strcmp(argv[i], "--profile")) {
            if (strcmp(argv[i + 1], "doorless-v1") && strcmp(argv[i + 1], "legacy-v1")) return 2;
            ipc_profile = argv[i + 1];
            continue;
        }
        char *end;
        errno = 0;
        long value = strtol(argv[i + 1], &end, 10);
        if (errno || *end || value < 0 || value > 60000) return 2;
        if (!strcmp(argv[i], "--delay-ms")) delay_ms = value;
        else if (!strcmp(argv[i], "--fail-after")) simulated_fail_after = (int)value;
        else return 2;
    }
    return ipc_start(argv[2], delay_ms);
#else
    if ((argc == 5 || (argc == 7 && !strcmp(argv[5], "--config"))) && !strcmp(argv[1], "--ipc-physical") &&
        !strcmp(argv[3], "--profile") && !strcmp(argv[4], "doorless-v1")) {
        const char *config_path = argc == 7 ? argv[6] : getenv("BINGO_C_CONTROLLER_CONFIG");
        if (config_path && (pwm_load_config(&physical_pwm.config, config_path) ||
                            strcmp(physical_pwm.config.journal, argv[2]))) {
            fprintf(stderr, "INVALID_PWM_CONFIGURATION\n"); return 2;
        }
        ipc_profile = "doorless-v1";
        return ipc_start(argv[2], 0);
    }
    fprintf(stderr, "PHYSICAL blocked: PWM_MAPPING_UNVERIFIED, PULSE_CALIBRATION_UNVERIFIED, "
            "SAFETY_RECOVERY_UNVERIFIED, MOTION_CONFIRMATION_UNDEFINED, PHYSICAL_DISPATCH_DISABLED. "
            "Use --physical-preflight for read-only evidence.\n");
    return 2;
#endif
}
