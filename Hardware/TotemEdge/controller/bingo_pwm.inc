/* Two lower hatches only. No Linux indices, periods or pulses are defaults.
 * dafc9ab supplies the sysfs write sequence, NOT this assembly's calibration.
 * No production caller grants a commissioning permit in this version.
 */
#ifndef BINGO_PWM_SIMULATED
#include <ctype.h>
#include <limits.h>
#include <math.h>
#include <signal.h>
#include <sqlite3.h>
#include <sys/stat.h>

typedef struct {
    long chip, channel, closed_ns, open_ns;
    long closed_degrees, open_degrees;
    char intended_signal[3]; /* Metadata ONLY; never used to derive a channel. */
    char pin[128], pad[128];
} HatchPWM;

typedef struct {
    HatchPWM hatch[2]; /* RIGHT, LEFT: mechanical sides, not PWM label indices. */
    long period_ns;
    char polarity[16], journal[4096];
    char references[4][512];
    char snapshot[16385];
    int complete;
    int open_first, close_first;
    char cycle_references[2][512];
} PWMConfig;

typedef struct {
    PWMConfig config;
    int chip_fd[2], channel_fd[2], lock_fd[2];
    unsigned touched;
    int commissioned, disable_is_safe, inhibited, indeterminate;
} PWMDriver;

enum { PWM_RIGHT, PWM_LEFT };
enum { PWM_CLOSED, PWM_OPEN };
enum { PWM_BLOCKED = -1, PWM_IO_ERROR = -2, PWM_UNKNOWN = -3 };
static PWMDriver physical_pwm;
static volatile sig_atomic_t pwm_stop_requested;

static void pwm_init(PWMDriver *driver)
{
    memset(driver, 0, sizeof(*driver));
    driver->config.period_ns = -1;
    driver->config.open_first = driver->config.close_first = -1;
    for (int i = 0; i < 2; i++) {
        driver->config.hatch[i].chip = driver->config.hatch[i].channel = -1;
        driver->config.hatch[i].closed_ns = driver->config.hatch[i].open_ns = -1;
        driver->config.hatch[i].closed_degrees = driver->config.hatch[i].open_degrees = -1;
        driver->chip_fd[i] = driver->channel_fd[i] = driver->lock_fd[i] = -1;
    }
}

/* SQLite JSON functions reuse the existing dependency. Missing JSON support
 * fails closed; no shell, Python helper or second configuration parser runs.
 */
static sqlite3_stmt *pwm_json(sqlite3 *db, const char *json, const char *path)
{
    sqlite3_stmt *s = NULL;
    if (sqlite3_prepare_v2(db, "SELECT json_type(?1,?2),json_extract(?1,?2)", -1, &s, NULL) != SQLITE_OK)
        return NULL;
    sqlite3_bind_text(s, 1, json, -1, SQLITE_STATIC);
    sqlite3_bind_text(s, 2, path, -1, SQLITE_TRANSIENT);
    if (sqlite3_step(s) != SQLITE_ROW) { sqlite3_finalize(s); return NULL; }
    return s;
}

static int pwm_number(sqlite3 *db, const char *json, const char *path, long *out)
{
    sqlite3_stmt *s = pwm_json(db, json, path);
    if (!s) return -1;
    const char *type = (const char *)sqlite3_column_text(s, 0);
    int result = 1;
    if (type && strcmp(type, "null")) {
        sqlite3_int64 value = sqlite3_column_int64(s, 1);
        result = strcmp(type, "integer") || sqlite3_column_type(s, 1) != SQLITE_INTEGER ||
                 value < 0 || value > LONG_MAX ? -1 : 0;
        if (!result) *out = (long)value;
    }
    sqlite3_finalize(s);
    return result;
}

static int pwm_string(sqlite3 *db, const char *json, const char *path, char *out, size_t size)
{
    sqlite3_stmt *s = pwm_json(db, json, path);
    if (!s) return -1;
    const char *type = (const char *)sqlite3_column_text(s, 0);
    int result = 1;
    if (type && strcmp(type, "null")) {
        const char *value = (const char *)sqlite3_column_text(s, 1);
        int bytes = sqlite3_column_bytes(s, 1), nonspace = 0;
        result = -1;
        if (!strcmp(type, "text") && value && bytes > 0 && (size_t)bytes < size &&
            strlen(value) == (size_t)bytes) {
            result = 0;
            for (int i = 0; i < bytes; i++) {
                if ((unsigned char)value[i] < 32) result = -1;
                if (value[i] != ' ') nonspace = 1;
            }
            if (!nonspace) result = -1;
            if (!result) memcpy(out, value, (size_t)bytes + 1);
        }
    }
    sqlite3_finalize(s);
    return result;
}

static int pwm_keys_valid(sqlite3 *db, const char *json)
{
    static const char *keys[] = {
        "$", "$.schema", "$.executable", "$.journal", "$.profile", "$.io_timeout_seconds",
        "$.physical", "$.physical.right", "$.physical.left", "$.physical.period_ns", "$.physical.polarity",
        "$.physical.mapping_reference", "$.physical.calibration_reference", "$.physical.completion_reference",
        "$.physical.safety_recovery_reference",
        "$.physical.cycle", "$.physical.cycle.open_order", "$.physical.cycle.close_order",
        "$.physical.cycle.drop_reference", "$.physical.cycle.homologation_reference",
        "$.physical.right.intended_signal", "$.physical.right.closed_degrees", "$.physical.right.open_degrees",
        "$.physical.left.intended_signal", "$.physical.left.closed_degrees", "$.physical.left.open_degrees",
        "$.physical.right.connector_pin", "$.physical.right.soc_pad", "$.physical.right.pwm_chip",
        "$.physical.right.pwm_channel", "$.physical.right.closed_pulse_ns", "$.physical.right.open_pulse_ns",
        "$.physical.left.connector_pin", "$.physical.left.soc_pad", "$.physical.left.pwm_chip",
        "$.physical.left.pwm_channel", "$.physical.left.closed_pulse_ns", "$.physical.left.open_pulse_ns"
    };
    sqlite3_stmt *s = NULL;
    if (sqlite3_prepare_v2(db, "SELECT path,key,type FROM json_tree(?1)", -1, &s, NULL) != SQLITE_OK) return 0;
    sqlite3_bind_text(s, 1, json, -1, SQLITE_STATIC);
    int status, valid = 1;
    while ((status = sqlite3_step(s)) == SQLITE_ROW) {
        const char *parent = (const char *)sqlite3_column_text(s, 0);
        const char *member = (const char *)sqlite3_column_text(s, 1);
        const char *type = (const char *)sqlite3_column_text(s, 2);
        char key[160];
        if (member) {
            for (const char *p = member; *p; p++)
                if (!isalnum((unsigned char)*p) && *p != '_') valid = 0;
            if (snprintf(key, sizeof(key), "%s.%s", parent, member) >= (int)sizeof(key)) valid = 0;
        } else snprintf(key, sizeof(key), "$");
        int found = 0;
        for (size_t i = 0; i < sizeof(keys) / sizeof(keys[0]); i++) if (!strcmp(key, keys[i])) found = 1;
        int object = !strcmp(key, "$") || !strcmp(key, "$.physical") ||
                     !strcmp(key, "$.physical.right") || !strcmp(key, "$.physical.left") || !strcmp(key, "$.physical.cycle");
        if (!found || (object ? strcmp(type, "object") : !strcmp(type, "object")) || !strcmp(type, "array")) valid = 0;
    }
    sqlite3_finalize(s);
    if (status != SQLITE_DONE || !valid) return 0;
    if (sqlite3_prepare_v2(db, "SELECT count(*) FROM (SELECT parent,key FROM json_tree(?1) GROUP BY parent,key HAVING count(*)>1)", -1, &s, NULL) != SQLITE_OK) return 0;
    sqlite3_bind_text(s, 1, json, -1, SQLITE_STATIC);
    valid = sqlite3_step(s) == SQLITE_ROW && sqlite3_column_int(s, 0) == 0;
    sqlite3_finalize(s);
    return valid;
}

static int pwm_load_config(PWMConfig *config, const char *path)
{
    /* Load once. The exact bytes become part of immutable C order identity. */
    if (!path || path[0] != '/') return -1;
    int fd = open(path, O_RDONLY | O_NONBLOCK);
    struct stat st;
    if (fd < 0) return -1;
    if (fstat(fd, &st) || !S_ISREG(st.st_mode)) { close(fd); return -1; }
    size_t used = 0;
    ssize_t n;
    while (used < sizeof(config->snapshot) &&
           (n = read(fd, config->snapshot + used, sizeof(config->snapshot) - used)) > 0) used += (size_t)n;
    int closed = close(fd);
    if (used == sizeof(config->snapshot) || !used || n < 0 || closed || memchr(config->snapshot, 0, used)) return -1;
    config->snapshot[used] = 0;
    /* Some SQLite JSON versions truncate decoded strings at U+0000. Reject
     * that escape before extraction, while respecting escaped backslashes.
     */
    for (size_t i = 0; i + 1 < used; i++) {
        if (config->snapshot[i] == '\\') {
            if (i + 5 < used && !memcmp(config->snapshot + i + 1, "u0000", 5)) return -1;
            i++;
        }
    }
    sqlite3 *db = NULL;
    if (sqlite3_open(":memory:", &db) != SQLITE_OK) { sqlite3_close(db); return -1; }
    int bad = !pwm_keys_valid(db, config->snapshot), missing = 0;
    char schema[64] = "", profile[32] = "", executable[4096] = "";
    bad |= pwm_string(db, config->snapshot, "$.schema", schema, sizeof(schema)) != 0 || strcmp(schema, "bingo-c-controller-v1");
    bad |= pwm_string(db, config->snapshot, "$.profile", profile, sizeof(profile)) != 0 || strcmp(profile, "doorless-v1");
    bad |= pwm_string(db, config->snapshot, "$.executable", executable, sizeof(executable)) != 0 || executable[0] != '/';
    bad |= pwm_string(db, config->snapshot, "$.journal", config->journal, sizeof(config->journal)) != 0 || config->journal[0] != '/';
    sqlite3_stmt *timeout = pwm_json(db, config->snapshot, "$.io_timeout_seconds");
    if (!timeout) bad = 1;
    else {
        const char *type = (const char *)sqlite3_column_text(timeout, 0);
        double value = sqlite3_column_double(timeout, 1);
        if (type && (strcmp(type, "integer") && strcmp(type, "real"))) bad = 1;
        if (type && (!isfinite(value) || value <= 0 || value > 60)) bad = 1;
        sqlite3_finalize(timeout);
    }
    int rc = pwm_number(db, config->snapshot, "$.physical.period_ns", &config->period_ns);
    bad |= rc < 0 || config->period_ns == 0; missing |= rc > 0;
    rc = pwm_string(db, config->snapshot, "$.physical.polarity", config->polarity, sizeof(config->polarity));
    bad |= rc < 0 || (!rc && strcmp(config->polarity, "normal") && strcmp(config->polarity, "inversed")); missing |= rc > 0;
    const char *references[] = {"mapping_reference", "calibration_reference", "completion_reference", "safety_recovery_reference"};
    for (int i = 0; i < 4; i++) {
        char key[96]; snprintf(key, sizeof(key), "$.physical.%s", references[i]);
        rc = pwm_string(db, config->snapshot, key, config->references[i], sizeof(config->references[i]));
        bad |= rc < 0; missing |= rc > 0;
    }
    for (int side = 0; side < 2; side++) {
        HatchPWM *h = &config->hatch[side];
        const char *fields[] = {"pwm_chip", "pwm_channel", "closed_pulse_ns", "open_pulse_ns"};
        long *values[] = {&h->chip, &h->channel, &h->closed_ns, &h->open_ns};
        for (int i = 0; i < 4; i++) {
            char key[96]; snprintf(key, sizeof(key), "$.physical.%s.%s", side ? "left" : "right", fields[i]);
            rc = pwm_number(db, config->snapshot, key, values[i]);
            bad |= rc < 0 || (i >= 2 && *values[i] == 0) || (i < 2 && *values[i] > INT_MAX);
            missing |= rc > 0;
            if (i >= 2 && config->period_ns > 0 && *values[i] >= config->period_ns) bad = 1;
        }
        char key[96]; snprintf(key, sizeof(key), "$.physical.%s.connector_pin", side ? "left" : "right");
        rc = pwm_string(db, config->snapshot, key, h->pin, sizeof(h->pin)); bad |= rc < 0; missing |= rc > 0;
        snprintf(key, sizeof(key), "$.physical.%s.soc_pad", side ? "left" : "right");
        rc = pwm_string(db, config->snapshot, key, h->pad, sizeof(h->pad)); bad |= rc < 0; missing |= rc > 0;
        snprintf(key, sizeof(key), "$.physical.%s.intended_signal", side ? "left" : "right");
        rc = pwm_string(db, config->snapshot, key, h->intended_signal, sizeof(h->intended_signal));
        bad |= rc < 0 || (!rc && strcmp(h->intended_signal, "RX") && strcmp(h->intended_signal, "TX"));
        snprintf(key, sizeof(key), "$.physical.%s.closed_degrees", side ? "left" : "right");
        rc = pwm_number(db, config->snapshot, key, &h->closed_degrees); bad |= rc < 0 || h->closed_degrees > 180;
        snprintf(key, sizeof(key), "$.physical.%s.open_degrees", side ? "left" : "right");
        rc = pwm_number(db, config->snapshot, key, &h->open_degrees); bad |= rc < 0 || h->open_degrees > 180;
    }
    const char *orders[] = {"open_order", "close_order"};
    int *first[] = {&config->open_first, &config->close_first};
    const char *cycle_refs[] = {"drop_reference", "homologation_reference"};
    for (int i = 0; i < 2; i++) {
        char key[96], order[32] = "";
        snprintf(key, sizeof(key), "$.physical.cycle.%s", orders[i]);
        rc = pwm_string(db, config->snapshot, key, order, sizeof(order));
        bad |= rc < 0;
        if (!rc) {
            if (!strcmp(order, "left_then_right")) *first[i] = PWM_LEFT;
            else if (!strcmp(order, "right_then_left")) *first[i] = PWM_RIGHT;
            else bad = 1;
        }
        snprintf(key, sizeof(key), "$.physical.cycle.%s", cycle_refs[i]);
        rc = pwm_string(db, config->snapshot, key, config->cycle_references[i], sizeof(config->cycle_references[i]));
        bad |= rc < 0;
    }
    if (config->hatch[0].chip >= 0 && config->hatch[0].channel >= 0 &&
        config->hatch[0].chip == config->hatch[1].chip && config->hatch[0].channel == config->hatch[1].channel) bad = 1;
    sqlite3_close(db);
    config->complete = !bad && !missing;
    return bad ? -1 : 0;
}

/* A plan, not evidence and not a simulator. No step advances on elapsed time.
 * Actual dispatch stays blocked until a homologated evidence/cycle provider
 * can correlate each step with the committed V1 intent/configuration.
 */
static int pwm_build_cycle(const PWMConfig *config, const char *steps[7])
{
    if (config->open_first < 0 || config->close_first < 0 ||
        !config->cycle_references[0][0] || !config->cycle_references[1][0]) return PWM_BLOCKED;
    steps[0] = config->open_first == PWM_LEFT ? "OPEN_LEFT" : "OPEN_RIGHT";
    steps[1] = config->open_first == PWM_LEFT ? "OPEN_RIGHT" : "OPEN_LEFT";
    steps[2] = "AWAIT_OPEN_EVIDENCE";
    steps[3] = "AWAIT_DROP_EVIDENCE";
    steps[4] = config->close_first == PWM_LEFT ? "CLOSE_LEFT" : "CLOSE_RIGHT";
    steps[5] = config->close_first == PWM_LEFT ? "CLOSE_RIGHT" : "CLOSE_LEFT";
    steps[6] = "AWAIT_INITIAL_EVIDENCE";
    return 7;
}

static void pwm_json_number(long value)
{
    if (value < 0) fputs("null", stdout); else fprintf(stdout, "%ld", value);
}

static void pwm_config_report(const PWMConfig *config)
{
    fprintf(stdout, "{\"protocol\":\"bingo-pwm-config-v1\",\"configuration\":\"%s\","
        "\"execution_ready\":false,\"completion_provider\":false,\"stop_policy\":false,\"mapping\":{",
        config->complete ? "DECLARED" : "INCOMPLETE");
    for (int side = 0; side < 2; side++) {
        const HatchPWM *h = &config->hatch[side];
        fprintf(stdout, "%s\"%s\":{\"pwm_chip\":", side ? "," : "", side ? "left" : "right");
        pwm_json_number(h->chip); fputs(",\"pwm_channel\":", stdout); pwm_json_number(h->channel);
        fputs(",\"closed_pulse_ns\":", stdout); pwm_json_number(h->closed_ns);
        fputs(",\"open_pulse_ns\":", stdout); pwm_json_number(h->open_ns);
        fputs(",\"closed_degrees\":", stdout); pwm_json_number(h->closed_degrees);
        fputs(",\"open_degrees\":", stdout); pwm_json_number(h->open_degrees);
        fputs(",\"intended_signal\":", stdout);
        if (h->intended_signal[0]) fprintf(stdout, "\"%s\"", h->intended_signal); else fputs("null", stdout);
        fputs("}", stdout);
    }
    fputs("},\"period_ns\":", stdout); pwm_json_number(config->period_ns);
    fputs(",\"polarity\":", stdout);
    if (config->polarity[0]) fprintf(stdout, "\"%s\"", config->polarity); else fputs("null", stdout);
    fputs(",\"cycle_plan\":[", stdout);
    const char *steps[7];
    if (pwm_build_cycle(config, steps) == 7)
        for (int i = 0; i < 7; i++) fprintf(stdout, "%s\"%s\"", i ? "," : "", steps[i]);
    fputs("]}\n", stdout);
}

static int pwm_write_at(int directory, const char *name, const char *text)
{
    int fd = openat(directory, name, O_WRONLY | O_NOFOLLOW);
    if (fd < 0) return -1;
    size_t size = strlen(text);
    ssize_t n = write(fd, text, size); /* Never retry an uncertain/partial write. */
    int result = n == (ssize_t)size ? 0 : -1;
    if (close(fd)) result = -1;
    return result;
}

static int pwm_write_number(int directory, const char *name, long value)
{
    char text[32]; snprintf(text, sizeof(text), "%ld", value);
    return pwm_write_at(directory, name, text);
}

static int pwm_read_number(int directory, const char *name, long *value)
{
    char text[64];
    int fd = openat(directory, name, O_RDONLY | O_NOFOLLOW);
    if (fd < 0) return -1;
    ssize_t n = read(fd, text, sizeof(text) - 1);
    int closed = close(fd);
    if (n <= 0 || n >= (ssize_t)sizeof(text) - 1 || closed) return -1;
    text[n] = 0;
    char *end; errno = 0; long parsed = strtol(text, &end, 10);
    if (errno || end == text || (*end && strcmp(end, "\n"))) return -1;
    *value = parsed;
    return 0;
}

static int pwm_lock_channels(PWMDriver *driver)
{
    /* Acquire in a stable order, across journals and even when sides swap. */
    int first = driver->config.hatch[0].chip < driver->config.hatch[1].chip ||
        (driver->config.hatch[0].chip == driver->config.hatch[1].chip &&
         driver->config.hatch[0].channel < driver->config.hatch[1].channel) ? 0 : 1;
    for (int index = 0; index < 2; index++) {
        int side = index ? 1 - first : first;
        HatchPWM *h = &driver->config.hatch[side];
        char path[160]; snprintf(path, sizeof(path), "/run/lock/bingo-pwmchip%ld-pwm%ld.lock", h->chip, h->channel);
        int fd = open(path, O_CREAT | O_RDWR | O_NOFOLLOW, 0600);
        struct stat st;
        struct flock lock = {.l_type = F_WRLCK, .l_whence = SEEK_SET};
        if (fd < 0) return -1;
        if (fstat(fd, &st) || !S_ISREG(st.st_mode) || st.st_nlink != 1 || fcntl(fd, F_SETLK, &lock)) { close(fd); return -1; }
        driver->lock_fd[side] = fd;
    }
    return 0;
}

static int pwm_open_channel(PWMDriver *driver, int side)
{
    HatchPWM *h = &driver->config.hatch[side];
    char path[160], name[64];
    snprintf(path, sizeof(path), "/sys/class/pwm/pwmchip%ld", h->chip);
    /* pwmchip is a kernel-provided symlink; channel/files may not redirect. */
    int chip = open(path, O_RDONLY | O_DIRECTORY);
    if (chip < 0) return -1;
    driver->chip_fd[side] = chip;
    long npwm;
    if (pwm_read_number(chip, "npwm", &npwm) || h->channel >= npwm) return -1;
    snprintf(name, sizeof(name), "pwm%ld", h->channel);
    int channel = openat(chip, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW);
    if (channel < 0) {
        if (errno != ENOENT || pwm_stop_requested || pwm_write_number(chip, "export", h->channel)) return -1;
        for (int attempt = 0; attempt < 40 && channel < 0 && !pwm_stop_requested; attempt++) {
            struct timespec pause = {0, 50000000L};
            if (nanosleep(&pause, NULL)) return -1;
            channel = openat(chip, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW);
            if (channel < 0 && errno != ENOENT) return -1;
        }
    }
    if (channel < 0) return -1;
    driver->channel_fd[side] = channel;
    long enabled;
    /* Refuse takeover of a running output; never silently remove its torque. */
    return pwm_read_number(channel, "enable", &enabled) || enabled != 0 ? -1 : 0;
}

static int pwm_stop(PWMDriver *driver)
{
    driver->inhibited = 1;
    if (!driver->touched) return PWM_BLOCKED;
    driver->indeterminate = 1;
    /* disable=0 is NOT mechanically safe unless that policy was homologated. */
    if (!driver->disable_is_safe) return PWM_UNKNOWN;
    int failed = 0;
    for (int side = 0; side < 2; side++) {
        if ((driver->touched & (1u << side)) && driver->channel_fd[side] >= 0)
            if (pwm_write_number(driver->channel_fd[side], "enable", 0)) failed = 1;
    }
    return failed ? PWM_IO_ERROR : PWM_UNKNOWN; /* No position confirmation. */
}

static int pwm_pose(PWMDriver *driver, int side, int pose)
{
    if (side < 0 || side > 1 || (pose != PWM_OPEN && pose != PWM_CLOSED) ||
        !driver->config.complete || !driver->commissioned || !driver->disable_is_safe ||
        driver->inhibited || driver->indeterminate || pwm_stop_requested) return PWM_BLOCKED;
    /* This entry requires a durable ACCEPTED intent and physical commissioning.
     * Neither production IPC nor JSON currently grants that permit.
     */
    if (pwm_lock_channels(driver) || pwm_open_channel(driver, side)) {
        driver->inhibited = 1;
        return PWM_IO_ERROR;
    }
    driver->touched |= 1u << side; /* Latch uncertainty BEFORE any output write. */
    int channel = driver->channel_fd[side];
    HatchPWM *h = &driver->config.hatch[side];
    if (pwm_stop_requested || pwm_write_number(channel, "duty_cycle", 0) || pwm_stop_requested ||
        pwm_write_number(channel, "period", driver->config.period_ns) || pwm_stop_requested ||
        pwm_write_at(channel, "polarity", driver->config.polarity) || pwm_stop_requested ||
        pwm_write_number(channel, "duty_cycle", pose == PWM_OPEN ? h->open_ns : h->closed_ns) || pwm_stop_requested ||
        pwm_write_number(channel, "enable", 1) || pwm_stop_requested) {
        driver->indeterminate = 1;
        (void)pwm_stop(driver);
        return PWM_UNKNOWN;
    }
    /* Even a complete write sequence is not evidence of motion. No sleep or
     * elapsed-time branch can promote this result to success.
     */
    driver->indeterminate = driver->inhibited = 1;
    return PWM_UNKNOWN;
}

static void pwm_release(PWMDriver *driver)
{
    /* Releasing descriptors does not disable PWM or prove a safe position. */
    for (int side = 0; side < 2; side++) {
        if (driver->channel_fd[side] >= 0) close(driver->channel_fd[side]);
        if (driver->chip_fd[side] >= 0) close(driver->chip_fd[side]);
        if (driver->lock_fd[side] >= 0) close(driver->lock_fd[side]);
        driver->channel_fd[side] = driver->chip_fd[side] = driver->lock_fd[side] = -1;
    }
}

static void pwm_signal(int signal_number)
{
    (void)signal_number;
    pwm_stop_requested = 1; /* Signal handler performs no SQLite/sysfs I/O. */
}
#endif
