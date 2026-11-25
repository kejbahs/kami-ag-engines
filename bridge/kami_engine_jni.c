/*
 * Kami AG engine bridge. Linked INTO every engine .so (ffmpeg, ffprobe, magick, busybox).
 * The app loads the .so with System.load() in its separate ":engine" process and calls
 * com.kami.ag.engines.EngineNative.run(argv, cwd, stdoutPath, stderrPath, rcPath, env).
 * The tool's own main(argc, argv) runs in-process (Android blocks exec() of downloaded files,
 * but loading a downloaded shared library is allowed). exit() inside the tool is wrapped
 * (-Wl,--wrap=exit) so the exit code is still written to rcPath before the process ends.
 *
 * engines-6 (Kamran's phone test 2026-11-25: ffmpeg + busybox died at exit, magick did not):
 *  - exit() inside the tool no longer runs the process's atexit/static destructors (those belong to
 *    ART in the app process and crash when run from a worker thread): __wrap_exit = fflush(NULL),
 *    write rc, _exit(code).
 *  - fatal signals (SEGV, ABRT, BUS, ILL, FPE, SYS — SIGSYS = a syscall Android's app seccomp forbids)
 *    are caught: «SIG <n> <name> [syscall <nr>]» goes to crash.txt next to rc.txt, rc = 128+n, _exit.
 *    The app then shows the REAL reason instead of a bare «کرش».
 */
#include <jni.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <signal.h>

extern int main(int argc, char **argv);
extern void __real_exit(int code);

static char g_rc_path[1024];
static int g_crash_fd = -1;

static void write_rc(int code) {
    if (!g_rc_path[0]) return;
    int fd = open(g_rc_path, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (fd >= 0) { char b[32]; int n = snprintf(b, sizeof b, "%d\n", code); if (write(fd, b, n) < 0) {} close(fd); }
}

void __wrap_exit(int code) {
    fflush(NULL);
    write_rc(code);
    _exit(code);
}

/* async-signal-safe tiny formatter */
static int put_num(char *b, long v) { char t[24]; int n = 0, k = 0; if (v < 0) { b[k++] = '-'; v = -v; } do { t[n++] = (char) ('0' + v % 10); v /= 10; } while (v && n < 22); while (n) b[k++] = t[--n]; return k; }

static void on_fatal(int sig, siginfo_t *info, void *uc) {
    (void) uc;
    char b[128]; int k = 0;
    const char *nm = sig == SIGSEGV ? "SEGV" : sig == SIGABRT ? "ABRT" : sig == SIGBUS ? "BUS" : sig == SIGILL ? "ILL" : sig == SIGFPE ? "FPE" :
#ifdef SIGSYS
        sig == SIGSYS ? "SYS" :
#endif
        "?";
    memcpy(b + k, "SIG ", 4); k += 4; k += put_num(b + k, sig); b[k++] = ' ';
    while (*nm && k < 100) b[k++] = *nm++;
#if defined(SIGSYS) && defined(si_syscall)
    if (sig == SIGSYS && info) { memcpy(b + k, " syscall ", 9); k += 9; k += put_num(b + k, info->si_syscall); }
#else
    (void) info;
#endif
    b[k++] = '\n';
    if (g_crash_fd >= 0) { if (write(g_crash_fd, b, (size_t) k) < 0) {} }
    if (write(2, b, (size_t) k) < 0) {}
    write_rc(128 + sig);
    _exit(128 + sig);
}

static void install_fatal_handlers(void) {
    /* crash.txt sits next to rc.txt (job folder) and is opened BEFORE the tool runs. */
    char p[1100]; strncpy(p, g_rc_path, sizeof p - 16); p[sizeof p - 16] = 0;
    char *sl = strrchr(p, '/'); if (sl) strcpy(sl + 1, "crash.txt"); else strcpy(p, "crash.txt");
    g_crash_fd = open(p, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0600);
    struct sigaction sa; memset(&sa, 0, sizeof sa);
    sa.sa_sigaction = on_fatal; sa.sa_flags = SA_SIGINFO | SA_ONSTACK;
    sigemptyset(&sa.sa_mask);
    int sigs[] = { SIGSEGV, SIGABRT, SIGBUS, SIGILL, SIGFPE,
#ifdef SIGSYS
        SIGSYS,
#endif
    };
    for (size_t i = 0; i < sizeof sigs / sizeof sigs[0]; i++) sigaction(sigs[i], &sa, NULL);
}

/* Plain C entry for the CI smoke test (no JVM). */
__attribute__((visibility("default"))) int kami_engine_main(int argc, char **argv) { return main(argc, argv); }

JNIEXPORT jint JNICALL Java_com_kami_ag_engines_EngineNative_run(JNIEnv *env, jclass cls,
        jobjectArray jargs, jstring jcwd, jstring jout, jstring jerr, jstring jrc, jobjectArray jenv) {
    (void) cls;
    const char *rc = (*env)->GetStringUTFChars(env, jrc, NULL);
    strncpy(g_rc_path, rc, sizeof g_rc_path - 1);
    (*env)->ReleaseStringUTFChars(env, jrc, rc);
    install_fatal_handlers();
    { /* own signal stack for this thread so even a stack overflow is reported */
        stack_t ss; ss.ss_sp = malloc(256 * 1024); ss.ss_size = 256 * 1024; ss.ss_flags = 0;
        if (ss.ss_sp) sigaltstack(&ss, NULL);
    }

    jsize ne = jenv ? (*env)->GetArrayLength(env, jenv) : 0;
    for (jsize i = 0; i < ne; i++) {
        jstring s = (jstring) (*env)->GetObjectArrayElement(env, jenv, i);
        const char *kv = (*env)->GetStringUTFChars(env, s, NULL);
        const char *eq = strchr(kv, '=');
        if (eq) { char k[256]; size_t kl = (size_t) (eq - kv); if (kl < sizeof k) { memcpy(k, kv, kl); k[kl] = 0; setenv(k, eq + 1, 1); } }
        (*env)->ReleaseStringUTFChars(env, s, kv);
    }

    const char *cwd = (*env)->GetStringUTFChars(env, jcwd, NULL);
    if (chdir(cwd) != 0) { /* keep going; the tool reports missing files itself */ }
    (*env)->ReleaseStringUTFChars(env, jcwd, cwd);

    const char *op = (*env)->GetStringUTFChars(env, jout, NULL);
    const char *ep = (*env)->GetStringUTFChars(env, jerr, NULL);
    int fo = open(op, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    int fe = open(ep, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    int fi = open("/dev/null", O_RDONLY);
    (*env)->ReleaseStringUTFChars(env, jout, op);
    (*env)->ReleaseStringUTFChars(env, jerr, ep);
    fflush(stdout); fflush(stderr);
    if (fo >= 0) dup2(fo, 1);
    if (fe >= 0) dup2(fe, 2);
    if (fi >= 0) dup2(fi, 0);
    setvbuf(stdout, NULL, _IOLBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);

    jsize n = (*env)->GetArrayLength(env, jargs);
    char **argv = (char **) calloc((size_t) n + 1, sizeof(char *));
    for (jsize i = 0; i < n; i++) {
        jstring s = (jstring) (*env)->GetObjectArrayElement(env, jargs, i);
        const char *a = (*env)->GetStringUTFChars(env, s, NULL);
        argv[i] = strdup(a);
        (*env)->ReleaseStringUTFChars(env, s, a);
    }
    argv[n] = NULL;
    int code = main((int) n, argv);
    fflush(NULL);
    write_rc(code);
    return code;
}
