#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <stdint.h>
#include <stdarg.h>
#include <sys/types.h>
#include <sys/sysctl.h>
#include <sys/user.h>

extern int sceUserServiceInitialize(const void *);
extern int sceUserServiceGetForegroundUser(int *);
extern int sceLncUtilInitialize(void);
extern int sceLncUtilLaunchApp(const char *title_id, char *argv, const void *param);
extern int sceSystemServiceLaunchApp(const char *title_id, const char **argv, const void *opts);

static FILE *g;
static void L(const char *fmt, ...) { va_list ap; va_start(ap, fmt); if (!g) g = fopen("/data/padbridge.log", "a"); if (g) { vfprintf(g, fmt, ap); fputc('\n', g); fflush(g); } va_end(ap); }

static pid_t eboot_pid(void) {
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PROC, 0 };
    size_t len = 0;
    if (sysctl(mib, 4, NULL, &len, NULL, 0) != 0 || !len) return -1;
    len += 4096;
    uint8_t *buf = malloc(len);
    if (!buf) return -1;
    pid_t found = -1;
    if (sysctl(mib, 4, buf, &len, NULL, 0) == 0) {
        for (uint8_t *p = buf; p < buf + len; ) {
            struct kinfo_proc *ki = (struct kinfo_proc *)p;
            if (ki->ki_structsize <= 0) break;
            if (!strcmp(ki->ki_comm, "eboot.bin")) { found = ki->ki_pid; break; }
            p += ki->ki_structsize;
        }
    }
    free(buf);
    return found;
}

static int wait_eboot(int seconds) {
    for (int i = 0; i < seconds * 10; i++) {
        pid_t p = eboot_pid();
        if (p > 0) return (int)p;
        usleep(100000);
    }
    return 0;
}

int main(void) {
    L("=== launch_app pid=%d ===", (int)getpid());
    if (eboot_pid() > 0) { L("already running pid=%d", (int)eboot_pid()); return 0; }
    sceUserServiceInitialize(NULL);
    int user = 0;
    sceUserServiceGetForegroundUser(&user);
    sceLncUtilInitialize();
    L("fg user=0x%08x", (unsigned)user);

    char param[1024];
    memset(param, 0, sizeof(param));
    *(uint32_t *)(param + 0x00) = sizeof(param);
    *(int32_t  *)(param + 0x04) = user;
    int rc = sceLncUtilLaunchApp("PPSA99700", NULL, param);
    L("LNC launch(param) -> 0x%08x", (unsigned)rc);
    int pid = wait_eboot(8);
    L("after param wait pid=%d", pid);
    if (!pid) {
        rc = sceLncUtilLaunchApp("PPSA99700", NULL, NULL);
        L("LNC launch(null) -> 0x%08x", (unsigned)rc);
        pid = wait_eboot(6);
        L("after null wait pid=%d", pid);
    }
    if (!pid) {
        rc = sceSystemServiceLaunchApp("PPSA99700", NULL, NULL);
        L("SYS launch -> 0x%08x", (unsigned)rc);
        pid = wait_eboot(6);
        L("after sys wait pid=%d", pid);
    }
    L("=== done pid=%d ===", pid);
    return 0;
}
