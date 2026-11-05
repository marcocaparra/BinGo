/* Private V1 stdio protocol. Included in bingo_controller.c to reuse static PWM
 * routines without exporting or rewriting them. Only the simulated build runs.
 */
#include <ctype.h>
#include <math.h>
#include <signal.h>
#include <sqlite3.h>
#include <sys/stat.h>

#ifdef BINGO_PWM_SIMULATED
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
    "CHECK((state='ACCEPTED' AND result='PENDING' AND error='-') OR " \
    "(state='COMPLETED' AND result='SUCCEEDED' AND error='-') OR " \
    "(state='REJECTED' AND result='UNAVAILABLE' AND error='CONTROLLER_BUSY') OR " \
    "(state='FAILED' AND ((result='FAILURE' AND error='OPERATION_FAILED') OR " \
    "(result='UNKNOWN' AND error='EXECUTION_ERROR'))))"
#define IPC_ORDER_PROTECTIONS \
    "CREATE TRIGGER order_identity BEFORE UPDATE OF id,event,operation,timeout,profile ON orders " \
    "BEGIN SELECT RAISE(ABORT,'Immutable order identity'); END;" \
    "CREATE TRIGGER order_retention BEFORE DELETE ON orders " \
    "BEGIN SELECT RAISE(ABORT,'Retained order identity'); END;"

static void ipc_fatal(void)
{
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
    sqlite3_stmt *s = ipc_prepare("SELECT id,event,operation,timeout,state,result,error FROM orders WHERE id=?");
    ipc_bind(s, 1, id);
    int status = sqlite3_step(s);
    if (status == SQLITE_DONE) {
        sqlite3_finalize(s);
        ipc_error("NOT_FOUND");
        return 0;
    }
    if (status != SQLITE_ROW) ipc_fatal();
    if (fprintf(stdout, "V1 RESULT %s %s %s %s %s %s %s SIMULATED\n",
                sqlite3_column_text(s, 0), sqlite3_column_text(s, 1),
                sqlite3_column_text(s, 2), sqlite3_column_text(s, 3),
                sqlite3_column_text(s, 4), sqlite3_column_text(s, 5),
                sqlite3_column_text(s, 6)) < 0 || fflush(stdout)) ipc_fatal();
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
    sqlite3_stmt *s = ipc_prepare("SELECT event,operation,timeout,profile FROM orders WHERE id=?");
    ipc_bind(s, 1, id);
    int status = sqlite3_step(s);
    if (status == SQLITE_ROW) {
        int same = !strcmp(event, (const char *)sqlite3_column_text(s, 0)) &&
                   !strcmp(op, (const char *)sqlite3_column_text(s, 1)) &&
                   !strcmp(timeout, (const char *)sqlite3_column_text(s, 2)) &&
                   !strcmp(ipc_profile, (const char *)sqlite3_column_text(s, 3));
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
    int allowed = ipc_in_sequence(event, op);
    s = ipc_prepare("INSERT INTO orders(id,event,operation,timeout,state,result,error,profile) VALUES(?,?,?,?,?,?,?,?)");
    ipc_bind(s, 1, id); ipc_bind(s, 2, event); ipc_bind(s, 3, op); ipc_bind(s, 4, timeout);
    ipc_bind(s, 5, allowed ? "ACCEPTED" : "REJECTED");
    ipc_bind(s, 6, allowed ? "PENDING" : "UNAVAILABLE");
    ipc_bind(s, 7, allowed ? "-" : "CONTROLLER_BUSY");
    ipc_bind(s, 8, ipc_profile);
    ipc_done(s);
    ipc_sql("COMMIT");
    ipc_emit(id); /* durable acceptance before any possible effect */
    if (!allowed) return;

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
}

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
                "PRAGMA user_version=2; PRAGMA application_id=1112098627; COMMIT;");
    } else if (version != 1 && version != 2) ipc_fatal();
    s = ipc_prepare("PRAGMA application_id");
    if (sqlite3_step(s) != SQLITE_ROW || sqlite3_column_int(s, 0) != 1112098627) ipc_fatal();
    sqlite3_finalize(s);
    s = ipc_prepare("SELECT count(*) FROM sqlite_master WHERE type='trigger' AND name IN ('order_identity','order_retention')");
    if (sqlite3_step(s) != SQLITE_ROW || sqlite3_column_int(s, 0) != 2) ipc_fatal();
    sqlite3_finalize(s);
    if (version == 1) {
        /* Preserve rowids (sequence), all identities and results. A legacy
         * pending/unknown command stays unsafe; migration never authorizes replay.
         */
        ipc_sql("BEGIN IMMEDIATE; CREATE TABLE orders_upgrade(" IPC_ORDER_COLUMNS ");"
                "INSERT INTO orders_upgrade(rowid,id,event,operation,timeout,state,result,error,profile) "
                "SELECT rowid,id,event,operation,timeout,state,result,error,'legacy-v1' FROM orders;"
                "DROP TABLE orders; ALTER TABLE orders_upgrade RENAME TO orders;"
                IPC_ORDER_PROTECTIONS "PRAGMA user_version=2; COMMIT;");
    }
    /* No automatic dispatch after crash, even if acceptance preceded all PWM. */
    ipc_sql("UPDATE orders SET state='FAILED',result='UNKNOWN',error='EXECUTION_ERROR' WHERE state='ACCEPTED'");
    if (fprintf(stdout, !strcmp(ipc_profile, "doorless-v1") ?
                "V1 READY SIMULATED DOORLESS_V1\n" : "V1 READY SIMULATED\n") < 0 || fflush(stdout)) ipc_fatal();
    char line[512];
    while (fgets(line, sizeof(line), stdin)) {
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
    if (ferror(stdin)) ipc_fatal();
    sqlite3_close(ipc_db);
    close(lock_fd);
    return 0;
}
#endif

int main(int argc, char **argv)
{
    signal(SIGPIPE, SIG_IGN);
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
    (void)argc; (void)argv;
    fprintf(stderr, "PHYSICAL blocked: evidence, calibration and safety approval pending.\n");
    return 2;
#endif
}
