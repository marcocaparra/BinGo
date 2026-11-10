/* Native unit tests with link-time syscall fault injection. No device model,
 * fake sysfs tree, simulator or configurable production I/O root exists.
 */
#define main controller_entrypoint
#include "../bingo_controller.c"
#undef main
#include <assert.h>
#include <stdarg.h>

int __real_open(const char *, int, ...);
int __real_openat(int, const char *, int, ...);
ssize_t __real_read(int, void *, size_t);
ssize_t __real_write(int, const void *, size_t);
int __real_close(int);
int __real_clock_gettime(clockid_t, struct timespec *);
int __real_clock_nanosleep(clockid_t, int, const struct timespec *, struct timespec *);
int __real_poll(struct pollfd *, nfds_t, int);

typedef struct { int kind, side; char name[32]; } TestFD;
static TestFD handles[1024];
static int writes, fail_write, short_write, active, invalid_channel, missing_once;
static int sysfs_opens, close_failure;
static int signal_write;
static char attributes[32][32], values[32][64], chip_paths[2][128];
static int chip_count;
static char channel_names[2][64];
static int channel_count;
static char lock_paths[2][64];
static int lock_count;
static int executing, crash_write, wrong_initial, interrupt_hold, interrupt_settle, lost_peer, expired, expire_settle;
static int wrong_period, wrong_polarity, wrong_enable, clock_failure;
static int ipc_peers, pause_hold;
static int64_t test_now = 1000000000, write_times[32];

int __wrap_clock_gettime(clockid_t clock_id, struct timespec *ts)
{
    if (!executing || clock_id != CLOCK_MONOTONIC) return __real_clock_gettime(clock_id, ts);
    if (clock_failure && writes == 2) { errno = EIO; return -1; }
    ts->tv_sec = (time_t)(test_now / 1000000000);
    ts->tv_nsec = (long)(test_now % 1000000000);
    return 0;
}

int __wrap_clock_nanosleep(clockid_t clock_id, int flags, const struct timespec *ts, struct timespec *remaining)
{
    if (!executing) return __real_clock_nanosleep(clock_id, flags, ts, remaining);
    assert(clock_id == CLOCK_MONOTONIC && flags == TIMER_ABSTIME);
    if (pause_hold && writes == 2) {
        pause_hold = 0;
        struct timespec pause = {0, 750000000};
        (void)__real_clock_nanosleep(CLOCK_MONOTONIC, 0, &pause, NULL);
    }
    test_now = (int64_t)ts->tv_sec * 1000000000 + ts->tv_nsec;
    if ((interrupt_hold && writes == 2) || (interrupt_settle && writes == 4)) pwm_signal(SIGTERM);
    if (expired || (expire_settle && writes == 4)) test_now += 60000000000LL;
    return 0;
}

int __wrap_poll(struct pollfd *fds, nfds_t count, int timeout)
{
    if (!executing) return __real_poll(fds, count, timeout);
    assert(count == 2 && timeout == 0);
    if (lost_peer && writes == 2) { fds[0].revents = POLLHUP; return 1; }
    if (ipc_peers) return __real_poll(fds, count, timeout);
    return 0;
}

static int test_fd(int kind, const char *name)
{
    int fd = __real_open("/dev/null", O_RDWR);
    assert(fd >= 0 && fd < 1024);
    handles[fd].kind = kind;
    snprintf(handles[fd].name, sizeof(handles[fd].name), "%s", name);
    return fd;
}

int __wrap_open(const char *path, int flags, ...)
{
    mode_t mode = 0;
    if (flags & O_CREAT) { va_list args; va_start(args, flags); mode = (mode_t)va_arg(args, int); va_end(args); }
    if (!strncmp(path, "/sys/class/pwm/", 15)) {
        assert(chip_count < 2);
        snprintf(chip_paths[chip_count++], sizeof(chip_paths[0]), "%s", path);
        sysfs_opens++;
        int fd = test_fd(1, "chip");
        handles[fd].side = chip_count - 1;
        return fd;
    }
    if (!strncmp(path, "/run/lock/bingo-pwmchip", 23)) {
        /* Real fcntl lock on a temporary descriptor for this unit.
         * The production fixed global lock namespace is never written here.
         */
        char temporary[] = "/tmp/pwm-lock-XXXXXX";
        int fd = mkstemp(temporary);
        assert(fd >= 0 && lock_count < 2);
        snprintf(lock_paths[lock_count++], sizeof(lock_paths[0]), "%s", temporary);
        return fd;
    }
    return __real_open(path, flags, mode);
}

int __wrap_openat(int directory, const char *name, int flags, ...)
{
    if (directory >= 0 && directory < 1024 && handles[directory].kind) {
        if (handles[directory].kind == 1 && !strncmp(name, "pwm", 3)) {
            if (missing_once) { missing_once = 0; errno = ENOENT; return -1; }
            assert(channel_count < 2);
            snprintf(channel_names[channel_count++], sizeof(channel_names[0]), "%s", name);
            int fd = test_fd(2, name);
            handles[fd].side = handles[directory].side;
            return fd;
        }
        int fd = test_fd(3, name);
        handles[fd].side = handles[directory].side;
        return fd;
    }
    return __real_openat(directory, name, flags);
}

ssize_t __wrap_read(int fd, void *buffer, size_t size)
{
    if (fd >= 0 && fd < 1024 && handles[fd].kind == 3) {
        const char *value = !strcmp(handles[fd].name, "npwm") ? (invalid_channel ? "1\n" : "99\n") : (active ? "1\n" : "0\n");
        char number[64];
        if (executing && strcmp(handles[fd].name, "npwm")) {
            const char *name = handles[fd].name;
            long n = !strcmp(name, "enable") ? !wrong_enable : (!strcmp(name, "period") ? physical_pwm.config.period_ns + wrong_period :
                physical_pwm.config.hatch[handles[fd].side].closed_ns + wrong_initial);
            snprintf(number, sizeof(number), "%ld\n", n);
            value = !strcmp(name, "polarity") ? physical_pwm.config.polarity : number;
            if (!strcmp(name, "polarity") && wrong_polarity) value = "wrong-polarity";
        }
        assert(strlen(value) <= size);
        memcpy(buffer, value, strlen(value));
        return (ssize_t)strlen(value);
    }
    return __real_read(fd, buffer, size);
}

ssize_t __wrap_write(int fd, const void *buffer, size_t size)
{
    if (fd >= 0 && fd < 1024 && handles[fd].kind == 3) {
        if (executing) {
            /* Independent SQLite reader proves intent is committed and visible
             * BEFORE EVERY possible physical write, not merely in a transaction.
             */
            sqlite3 *reader = NULL;
            assert(sqlite3_open_v2(physical_pwm.config.journal, &reader, SQLITE_OPEN_READONLY, NULL) == SQLITE_OK);
            sqlite3_stmt *intent;
            assert(sqlite3_prepare_v2(reader, "SELECT count(*) FROM orders WHERE source='PHYSICAL' AND state='ACCEPTED' AND configuration=?", -1, &intent, NULL) == SQLITE_OK);
            sqlite3_bind_text(intent, 1, physical_pwm.config.snapshot, -1, SQLITE_STATIC);
            assert(sqlite3_step(intent) == SQLITE_ROW && sqlite3_column_int(intent, 0) == 1);
            sqlite3_finalize(intent); sqlite3_close(reader);
        }
        assert(writes < 32 && size < sizeof(values[0]));
        snprintf(attributes[writes], sizeof(attributes[0]), "%s", handles[fd].name);
        memcpy(values[writes], buffer, size); values[writes][size] = 0;
        write_times[writes++] = test_now;
        if (writes == crash_write) _exit(77);
        if (writes == signal_write) pwm_signal(SIGTERM);
        if (writes == fail_write) { errno = EIO; return -1; }
        if (writes == short_write) return (ssize_t)size - 1;
        return (ssize_t)size;
    }
    return __real_write(fd, buffer, size);
}

int __wrap_close(int fd)
{
    int inject = fd >= 0 && fd < 1024 && handles[fd].kind == 3 && writes && close_failure;
    if (fd >= 0 && fd < 1024) memset(&handles[fd], 0, sizeof(handles[fd]));
    int result = __real_close(fd);
    if (inject) { close_failure = 0; errno = EIO; return -1; }
    return result;
}

int main(int argc, char **argv)
{
    assert(argc == 5 || (argc == 6 && !strcmp(argv[5], "ipc")));
    PWMDriver driver; pwm_init(&driver);
    assert(pwm_load_config(&driver.config, argv[1]) == 0);
    if (!strncmp(argv[2], "execute", 7)) {
        ipc_peers = argc == 6;
        if (ipc_peers) {
            signal(SIGPIPE, SIG_IGN);
            struct sigaction stop = {.sa_handler = pwm_signal};
            sigemptyset(&stop.sa_mask);
            assert(sigaction(SIGTERM, &stop, NULL) == 0 && sigaction(SIGINT, &stop, NULL) == 0);
        }
        executing = 1;
        physical_pwm = driver;
        ipc_profile = "doorless-v1";
        if (!strcmp(argv[2], "execute-open-1")) fail_write = 1;
        if (!strcmp(argv[2], "execute-open-2")) fail_write = 2;
        if (!strcmp(argv[2], "execute-close-1")) fail_write = 3;
        if (!strcmp(argv[2], "execute-close-2")) fail_write = 4;
        if (!strcmp(argv[2], "execute-short")) short_write = 2;
        if (!strcmp(argv[2], "execute-close-error")) close_failure = 1;
        if (!strcmp(argv[2], "execute-interrupt-hold")) interrupt_hold = 1;
        if (!strcmp(argv[2], "execute-interrupt-settle")) interrupt_settle = 1;
        if (!strcmp(argv[2], "execute-lost-peer")) lost_peer = 1;
        if (!strcmp(argv[2], "execute-timeout")) expired = 1;
        if (!strcmp(argv[2], "execute-timeout-settle")) expire_settle = 1;
        if (!strcmp(argv[2], "execute-signal-pair")) signal_write = 1;
        if (!strcmp(argv[2], "execute-crash")) crash_write = 2;
        if (!strcmp(argv[2], "execute-initial")) wrong_initial = 1;
        if (!strcmp(argv[2], "execute-period")) wrong_period = 1;
        if (!strcmp(argv[2], "execute-polarity")) wrong_polarity = 1;
        if (!strcmp(argv[2], "execute-disabled")) wrong_enable = 1;
        if (!strcmp(argv[2], "execute-missing")) missing_once = 1;
        if (!strcmp(argv[2], "execute-clock")) clock_failure = 1;
        if (!strcmp(argv[2], "execute-pause")) pause_hold = 1;
        assert(ipc_start(driver.config.journal, 0) == 0);
        fprintf(stdout, "ELAPSED_NS %lld\n", (long long)(test_now - 1000000000));
        for (int i = 0; i < writes; i++)
            fprintf(stdout, "WRITE %s %s AT %lld\n", attributes[i], values[i], (long long)write_times[i]);
        for (int i = 0; i < lock_count; i++) assert(unlink(lock_paths[i]) == 0);
        return 0;
    }
    assert(driver.config.complete);
    int side = atoi(argv[3]), pose = atoi(argv[4]);
    if (!strncmp(argv[2], "plan", 4)) {
        const char *steps[7];
        int count = pwm_build_cycle(&driver.config, steps);
        if (!strcmp(argv[2], "plan-blocked")) assert(count == PWM_BLOCKED);
        else {
            assert(count == (driver.config.joint_mode ? 5 : 7));
            for (int i = 0; i < count; i++) fprintf(stdout, "%s\n", steps[i]);
        }
        assert(writes == 0 && sysfs_opens == 0);
        return 0;
    }
    if (!strcmp(argv[2], "blocked")) {
        assert(pwm_pose(&driver, side, pose) == PWM_BLOCKED);
        assert(writes == 0 && sysfs_opens == 0);
    } else {
        /* Unit-only private-state setup to cover currently unreachable low-level
         * code. No production flag/JSON/env option grants either permission.
         */
        driver.commissioned = driver.disable_is_safe = 1;
        if (!strcmp(argv[2], "active")) active = 1;
        if (!strcmp(argv[2], "range")) invalid_channel = 1;
        if (!strcmp(argv[2], "export")) missing_once = 1;
        if (!strcmp(argv[2], "short")) short_write = 4;
        if (!strcmp(argv[2], "close-error")) close_failure = 1;
        if (!strcmp(argv[2], "signal")) signal_write = 4;
        if (!strncmp(argv[2], "fail-", 5)) fail_write = atoi(argv[2] + 5);
        int result;
        if (!strncmp(argv[2], "journal-", 8)) {
            physical_pwm = driver;
            assert(sqlite3_open(":memory:", &ipc_db) == SQLITE_OK);
            ipc_sql("CREATE TABLE orders(" IPC_ORDER_COLUMNS ");" IPC_ORDER_PROTECTIONS);
            const char *id = "11111111-1111-4111-8111-111111111111";
            assert(ipc_pwm_pose(id, side, pose) == PWM_BLOCKED && writes == 0);
            sqlite3_stmt *s = ipc_prepare("INSERT INTO orders VALUES(?1,?1,'CYCLE_LOWER_HATCH','10',"
                "'ACCEPTED','PENDING','-','doorless-v1','PHYSICAL',?2)");
            ipc_bind(s, 1, id); ipc_bind(s, 2, driver.config.snapshot); ipc_done(s);
            ipc_sql("BEGIN IMMEDIATE");
            assert(ipc_pwm_pose(id, side, pose) == PWM_BLOCKED && writes == 0);
            ipc_sql("COMMIT");
            if (!strcmp(argv[2], "journal-config")) physical_pwm.config.snapshot[0] = ' ';
            result = ipc_pwm_pose(id, side, pose);
            if (!strcmp(argv[2], "journal-config")) {
                assert(result == PWM_BLOCKED && writes == 0);
                driver = physical_pwm;
                pwm_release(&driver); sqlite3_close(ipc_db);
                return 0;
            }
            s = ipc_prepare("SELECT state,result FROM orders");
            assert(sqlite3_step(s) == SQLITE_ROW);
            assert(!strcmp((const char *)sqlite3_column_text(s, 0), "FAILED"));
            assert(!strcmp((const char *)sqlite3_column_text(s, 1), "UNKNOWN"));
            sqlite3_finalize(s); sqlite3_close(ipc_db); ipc_db = NULL;
            driver = physical_pwm;
        } else result = pwm_pose(&driver, side, pose);
        if (active || invalid_channel) {
            assert(result == PWM_IO_ERROR && writes == 0);
        } else {
            assert(result == PWM_UNKNOWN && driver.indeterminate && driver.inhibited);
            int count = writes;
            assert(pwm_pose(&driver, side, pose) == PWM_BLOCKED && writes == count);
            if (!strcmp(argv[2], "stop-unverified")) {
                driver.disable_is_safe = 0;
                assert(pwm_stop(&driver) == PWM_UNKNOWN && writes == count);
            } else if (!strcmp(argv[2], "stop-two")) {
                driver.channel_fd[1 - side] = test_fd(2, "other");
                driver.touched = 3;
                fail_write = count + 1;
                assert(pwm_stop(&driver) == PWM_IO_ERROR && writes == count + 2);
                assert(!strcmp(attributes[count], "enable") && !strcmp(attributes[count + 1], "enable"));
            }
        }
    }
    for (int i = 0; i < chip_count; i++) fprintf(stdout, "CHIP %s\n", chip_paths[i]);
    for (int i = 0; i < channel_count; i++) fprintf(stdout, "CHANNEL %s\n", channel_names[i]);
    for (int i = 0; i < writes; i++) fprintf(stdout, "WRITE %s %s\n", attributes[i], values[i]);
    pwm_release(&driver);
    for (int i = 0; i < lock_count; i++) assert(unlink(lock_paths[i]) == 0);
    return 0;
}
