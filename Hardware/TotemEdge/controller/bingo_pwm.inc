/* Two lower hatches only. No Linux indices, periods or pulses are defaults.
 * dafc9ab supplies the sysfs write sequence, NOT this assembly's calibration.
 * Operational completion is versioned separately from position evidence.
 */
#ifndef BINGO_PWM_SIMULATED
#include <ctype.h>
#include <limits.h>
#include <math.h>
#include <signal.h>
#include <sqlite3.h>
#include <sys/stat.h>
#include <stdint.h>
#include <poll.h>

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
    int joint_mode;
    long hold_open_ms;
    char hold_start[40], hold_clock[16];
    int operational_completion;
    long close_settle_ms;
    char initial_condition[40];
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
    driver->config.hold_open_ms = -1;
    driver->config.close_settle_ms = -1;
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
        "$.physical.cycle.mode", "$.physical.cycle.hold_open_ms",
        "$.physical.cycle.hold_start", "$.physical.cycle.hold_clock",
        "$.physical.cycle.completion_policy", "$.physical.cycle.close_settle_ms",
        "$.physical.cycle.initial_condition",
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
    char mode[32] = "";
    rc = pwm_string(db, config->snapshot, "$.physical.cycle.mode", mode, sizeof(mode));
    bad |= rc < 0;
    if (!rc) {
        if (!strcmp(mode, "joint-v1")) config->joint_mode = 1;
        else bad = 1;
    }
    rc = pwm_number(db, config->snapshot, "$.physical.cycle.hold_open_ms", &config->hold_open_ms);
    bad |= rc < 0;
    rc = pwm_string(db, config->snapshot, "$.physical.cycle.hold_start", config->hold_start, sizeof(config->hold_start));
    bad |= rc < 0;
    rc = pwm_string(db, config->snapshot, "$.physical.cycle.hold_clock", config->hold_clock, sizeof(config->hold_clock));
    bad |= rc < 0;
    if (config->joint_mode) {
        /* joint-v1 fixes timing semantics; references do not grant permission. */
        bad |= config->hold_open_ms != 5000 ||
               strcmp(config->hold_start, "after_both_open_commands") ||
               strcmp(config->hold_clock, "monotonic") ||
               config->open_first >= 0 || config->close_first >= 0;
    } else {
        /* No implicit promotion of an old sequential/empty config into joint. */
        bad |= config->hold_open_ms >= 0 || config->hold_start[0] || config->hold_clock[0];
    }
    char completion[48] = "";
    rc = pwm_string(db, config->snapshot, "$.physical.cycle.completion_policy", completion, sizeof(completion));
    bad |= rc < 0;
    if (!rc) {
        if (!strcmp(completion, "operational-sequence-v1")) config->operational_completion = 1;
        else bad = 1;
    }
    rc = pwm_number(db, config->snapshot, "$.physical.cycle.close_settle_ms", &config->close_settle_ms);
    bad |= rc < 0;
    rc = pwm_string(db, config->snapshot, "$.physical.cycle.initial_condition", config->initial_condition, sizeof(config->initial_condition));
    bad |= rc < 0;
    if (config->operational_completion) {
        bad |= !config->joint_mode || config->close_settle_ms != 5000 ||
               strcmp(config->initial_condition, "closed_pwm_readback");
    } else bad |= config->close_settle_ms >= 0 || config->initial_condition[0];
    if (config->hatch[0].chip >= 0 && config->hatch[0].channel >= 0 &&
        config->hatch[0].chip == config->hatch[1].chip && config->hatch[0].channel == config->hatch[1].channel) bad = 1;
    sqlite3_close(db);
    config->complete = !bad && !missing;
    return bad ? -1 : 0;
}

static int pwm_operational_configured(const PWMConfig *config)
{
    if (!config->joint_mode || !config->operational_completion || config->close_settle_ms != 5000 ||
        strcmp(config->initial_condition, "closed_pwm_readback") || config->hold_open_ms != 5000 ||
        strcmp(config->hold_start, "after_both_open_commands") || strcmp(config->hold_clock, "monotonic") ||
        config->period_ns <= 0 || !config->polarity[0] ||
        !config->references[0][0] || !config->references[1][0] || !config->references[2][0] ||
        !config->cycle_references[1][0]) return 0;
    for (int side = 0; side < 2; side++) {
        const HatchPWM *h = &config->hatch[side];
        if (h->chip < 0 || h->channel < 0 || h->closed_ns <= 0 || h->open_ns <= 0 ||
            h->closed_ns >= config->period_ns || h->open_ns >= config->period_ns) return 0;
    }
    return config->hatch[0].chip != config->hatch[1].chip || config->hatch[0].channel != config->hatch[1].channel;
}

/* A pure plan, not evidence. HOLD_OPEN delays the close stage
 * for joint-v1's 5000 monotonic ms after BOTH open-command writes succeed.
 * It never proves an open/closed pose or drop. No planning function waits/acts.
 * The optional operational completion policy preserves the original plan when
 * absent; only its explicitly versioned extension can dispatch via durable IPC.
 */
static int pwm_build_cycle(const PWMConfig *config, const char *steps[7])
{
    if (config->joint_mode) {
        if (config->hold_open_ms != 5000 ||
            strcmp(config->hold_start, "after_both_open_commands") ||
            strcmp(config->hold_clock, "monotonic") ||
            config->open_first >= 0 || config->close_first >= 0) return PWM_BLOCKED;
        steps[0] = config->operational_completion ? "REQUIRE_CLOSED_PWM" : "REQUIRE_INITIAL_CLOSED";
        steps[1] = "OPEN_BOTH";
        steps[2] = "HOLD_OPEN";
        steps[3] = "CLOSE_BOTH";
        steps[4] = config->operational_completion ? "SETTLE_CLOSED" : "AWAIT_INITIAL_EVIDENCE";
        return 5;
    }
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
    int count = pwm_build_cycle(config, steps);
    for (int i = 0; i < count; i++) fprintf(stdout, "%s\"%s\"", i ? "," : "", steps[i]);
    fputs("]", stdout);
    if (config->joint_mode) {
        fprintf(stdout, ",\"cycle_policy\":{\"mode\":\"joint-v1\",\"hold_open_ms\":%ld,"
            "\"hold_start\":\"%s\",\"hold_clock\":\"%s\"",
            config->hold_open_ms, config->hold_start, config->hold_clock);
        if (config->operational_completion)
            fprintf(stdout, ",\"completion_policy\":\"operational-sequence-v1\",\"close_settle_ms\":%ld,"
                "\"initial_condition\":\"closed_pwm_readback\"", config->close_settle_ms);
        fputs("}", stdout);
    }
    fprintf(stdout, ",\"c_executor_configured\":%s", pwm_operational_configured(config) ? "true" : "false");
    fputs("}\n", stdout);
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

static int pwm_channel_files(PWMDriver *driver, int side, int export_missing)
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
        if (!export_missing || errno != ENOENT || pwm_stop_requested || pwm_write_number(chip, "export", h->channel)) return -1;
        for (int attempt = 0; attempt < 40 && channel < 0 && !pwm_stop_requested; attempt++) {
            struct timespec pause = {0, 50000000L};
            if (nanosleep(&pause, NULL)) return -1;
            channel = openat(chip, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW);
            if (channel < 0 && errno != ENOENT) return -1;
        }
    }
    if (channel < 0) return -1;
    driver->channel_fd[side] = channel;
    return 0;
}

static int pwm_open_channel(PWMDriver *driver, int side)
{
    if (pwm_channel_files(driver, side, 1)) return -1;
    long enabled;
    /* Refuse takeover of a running output; never silently remove its torque. */
    return pwm_read_number(driver->channel_fd[side], "enable", &enabled) || enabled != 0 ? -1 : 0;
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

static int pwm_now(int64_t *now)
{
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) || ts.tv_sec < 0 ||
        ts.tv_nsec < 0 || ts.tv_nsec >= 1000000000 ||
        ts.tv_sec > (INT64_MAX - ts.tv_nsec) / 1000000000LL) return -1;
    *now = (int64_t)ts.tv_sec * 1000000000LL + ts.tv_nsec;
    return 0;
}

static int pwm_cycle_guard(int64_t deadline)
{
    int64_t now;
    struct pollfd peers[2] = {{STDIN_FILENO, 0, 0}, {STDOUT_FILENO, 0, 0}};
    if (pwm_stop_requested || pwm_now(&now) || now >= deadline ||
        poll(peers, 2, 0) < 0) return -1;
    for (int i = 0; i < 2; i++)
        if (peers[i].revents & (POLLHUP | POLLERR | POLLNVAL)) return -1;
    return 0;
}

static int pwm_cycle_wait(long milliseconds, int64_t deadline)
{
    int64_t now;
    if (pwm_now(&now)) return -1;
    if (now > INT64_MAX - (int64_t)milliseconds * 1000000) return -1;
    int64_t target = now + (int64_t)milliseconds * 1000000;
    while (1) {
        if (pwm_cycle_guard(deadline) || pwm_now(&now)) return -1;
        if (now >= target) return 0;
        /* Short absolute sleeps keep interruption/peer-loss detection bounded.
         * Neither this clock nor sysfs readback measures a mechanical pose.
         */
        int64_t wake = now + 20000000;
        if (wake > target) wake = target;
        struct timespec ts = {(time_t)(wake / 1000000000), (long)(wake % 1000000000)};
        if (clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, &ts, NULL)) return -1;
    }
}

static int pwm_closed_command(PWMDriver *driver, int side)
{
    if (pwm_channel_files(driver, side, 0)) return -1;
    int channel = driver->channel_fd[side];
    long enabled, period, duty;
    char polarity[16];
    int fd = openat(channel, "polarity", O_RDONLY | O_NOFOLLOW);
    if (fd < 0) return -1;
    ssize_t n = read(fd, polarity, sizeof(polarity) - 1);
    int failed = close(fd);
    if (n <= 0 || n >= (ssize_t)sizeof(polarity) - 1 || failed) return -1;
    polarity[n] = 0;
    if (polarity[n - 1] == '\n') polarity[n - 1] = 0;
    return strcmp(polarity, driver->config.polarity) ||
        pwm_read_number(channel, "enable", &enabled) || enabled != 1 ||
        pwm_read_number(channel, "period", &period) || period != driver->config.period_ns ||
        pwm_read_number(channel, "duty_cycle", &duty) || duty != driver->config.hatch[side].closed_ns ? -1 : 0;
}

static int pwm_joint_write(PWMDriver *driver, int pose, int64_t deadline)
{
    /* One stage: back-to-back sysfs writes, no per-motor waits/primitives.
     * sysfs does not promise electrically simultaneous edges.
     */
    for (int side = 0; side < 2; side++) {
        if (pwm_cycle_guard(deadline)) return -1;
        driver->touched |= 1u << side; /* BEFORE the potentially partial write. */
        const HatchPWM *h = &driver->config.hatch[side];
        if (pwm_write_number(driver->channel_fd[side], "duty_cycle",
                             pose == PWM_OPEN ? h->open_ns : h->closed_ns)) return -1;
    }
    return pwm_cycle_guard(deadline);
}

/* Caller must verify a committed, immutable PHYSICAL ACCEPTED intent first.
 * Success means only operational-sequence-v1 completed without detected fault.
 */
static int pwm_joint_execute(PWMDriver *driver, double seconds)
{
    int64_t now, deadline;
    const char *steps[7];
    if (!pwm_operational_configured(&driver->config) || driver->inhibited ||
        driver->indeterminate || !isfinite(seconds) || seconds <= 10 || seconds > 86400 ||
        pwm_build_cycle(&driver->config, steps) != 5 || pwm_now(&now)) goto unknown;
    int64_t budget = (int64_t)(seconds * 1000000000.0);
    if (now > INT64_MAX - budget) goto unknown;
    deadline = now + budget;
    for (int stage = 0; stage < 5; stage++) {
        if (pwm_cycle_guard(deadline)) goto unknown;
        if (!strcmp(steps[stage], "REQUIRE_CLOSED_PWM")) {
            if (pwm_lock_channels(driver)) goto unknown;
            for (int side = 0; side < 2; side++)
                if (pwm_cycle_guard(deadline) || pwm_closed_command(driver, side)) goto unknown;
        } else if (!strcmp(steps[stage], "OPEN_BOTH")) {
            if (pwm_joint_write(driver, PWM_OPEN, deadline)) goto unknown;
        } else if (!strcmp(steps[stage], "HOLD_OPEN")) {
            if (pwm_cycle_wait(driver->config.hold_open_ms, deadline)) goto unknown;
        } else if (!strcmp(steps[stage], "CLOSE_BOTH")) {
            if (pwm_joint_write(driver, PWM_CLOSED, deadline)) goto unknown;
        } else if (!strcmp(steps[stage], "SETTLE_CLOSED")) {
            if (pwm_cycle_wait(driver->config.close_settle_ms, deadline)) goto unknown;
        } else goto unknown;
    }
    if (pwm_cycle_guard(deadline)) goto unknown;
    /* Retain both global locks through the durable final journal update. */
    return 0;
unknown:
    /* No recovery close or automatic torque removal has been homologated.
     * Inhibit writes; retain the last PWM commands and durable uncertainty.
     */
    driver->inhibited = driver->indeterminate = 1;
    if (driver->touched) (void)pwm_stop(driver);
    /* Retain acquired locks while this failed receiver remains alive. */
    return PWM_UNKNOWN;
}

static void pwm_signal(int signal_number)
{
    (void)signal_number;
    pwm_stop_requested = 1; /* Signal handler performs no SQLite/sysfs I/O. */
}
#endif
