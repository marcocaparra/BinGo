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

typedef struct { int kind; char name[32]; } TestFD;
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
        return test_fd(1, "chip");
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
            return test_fd(2, name);
        }
        return test_fd(3, name);
    }
    return __real_openat(directory, name, flags);
}

ssize_t __wrap_read(int fd, void *buffer, size_t size)
{
    if (fd >= 0 && fd < 1024 && handles[fd].kind == 3) {
        const char *value = !strcmp(handles[fd].name, "npwm") ? (invalid_channel ? "1\n" : "99\n") : (active ? "1\n" : "0\n");
        assert(strlen(value) <= size);
        memcpy(buffer, value, strlen(value));
        return (ssize_t)strlen(value);
    }
    return __real_read(fd, buffer, size);
}

ssize_t __wrap_write(int fd, const void *buffer, size_t size)
{
    if (fd >= 0 && fd < 1024 && handles[fd].kind == 3) {
        assert(writes < 32 && size < sizeof(values[0]));
        snprintf(attributes[writes], sizeof(attributes[0]), "%s", handles[fd].name);
        memcpy(values[writes], buffer, size); values[writes][size] = 0;
        writes++;
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
    assert(argc == 5);
    PWMDriver driver; pwm_init(&driver);
    assert(pwm_load_config(&driver.config, argv[1]) == 0 && driver.config.complete);
    int side = atoi(argv[3]), pose = atoi(argv[4]);
    if (!strncmp(argv[2], "plan", 4)) {
        const char *steps[7];
        int count = pwm_build_cycle(&driver.config, steps);
        if (!strcmp(argv[2], "plan-blocked")) assert(count == PWM_BLOCKED);
        else {
            assert(count == 7);
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
