/*
 * engines-6 smoke: calls the REAL JNI entry Java_com_kami_ag_engines_EngineNative_run exactly the way the
 * app does (from a worker thread with a 64 MB stack, stdout/stderr redirected to files, rc file), using a
 * minimal fake JNIEnv. Then prints RC (from rc.txt), CRASH (crash.txt) and the captured stdout, so CI can
 * check exit code AND output content — not just "a file exists".
 *   jni_harness <lib.so> <jobdir> <argv0> [args…]
 */
#include <jni.h>
#include <dlfcn.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/wait.h>

#ifdef __ANDROID__
#define JNI_IFC struct JNINativeInterface
#else
#define JNI_IFC struct JNINativeInterface_ /* desktop JDK jni.h (local test) */
#endif

typedef struct { int n; const char **v; } FakeArr;

static const char *JNICALL f_GetStringUTFChars(JNIEnv *e, jstring s, jboolean *c) { (void) e; if (c) *c = 0; return (const char *) s; }
static void JNICALL f_ReleaseStringUTFChars(JNIEnv *e, jstring s, const char *u) { (void) e; (void) s; (void) u; }
static jsize JNICALL f_GetArrayLength(JNIEnv *e, jarray a) { (void) e; return ((FakeArr *) a)->n; }
static jobject JNICALL f_GetObjectArrayElement(JNIEnv *e, jobjectArray a, jsize i) { (void) e; return (jobject) ((FakeArr *) a)->v[i]; }

typedef jint (*RunFn)(JNIEnv *, jclass, jobjectArray, jstring, jstring, jstring, jstring, jobjectArray);
static RunFn run_fn; static JNIEnv *g_env; static FakeArr g_args, g_envs;
static char p_out[1024], p_err[1024], p_rc[1024], cwd[1024];
static int result;

static void *worker(void *x) {
    (void) x;
    result = run_fn(g_env, NULL, (jobjectArray) &g_args, (jstring) cwd, (jstring) p_out, (jstring) p_err, (jstring) p_rc, (jobjectArray) &g_envs);
    return NULL;
}

static void cat(const char *tag, const char *p, size_t max) {
    FILE *f = fopen(p, "rb"); if (!f) { printf("%s <none>\n", tag); return; }
    char *b = malloc(max + 1); size_t n = fread(b, 1, max, f); b[n] = 0; fclose(f);
    printf("%s %s%s", tag, b, (n && b[n - 1] == '\n') ? "" : "\n"); free(b);
}

int main(int argc, char **argv) {
    if (argc < 4) { fprintf(stderr, "usage: jni_harness lib.so jobdir argv0 [args]\n"); return 2; }
    void *h = dlopen(argv[1], RTLD_NOW);
    if (!h) { printf("HARNESS dlopen failed: %s\n", dlerror()); return 3; }
    run_fn = (RunFn) dlsym(h, "Java_com_kami_ag_engines_EngineNative_run");
    if (!run_fn) { printf("HARNESS no JNI entry\n"); return 4; }
    JNI_IFC *fn = calloc(1, sizeof *fn);
    fn->GetStringUTFChars = f_GetStringUTFChars; fn->ReleaseStringUTFChars = f_ReleaseStringUTFChars;
    fn->GetArrayLength = f_GetArrayLength; fn->GetObjectArrayElement = f_GetObjectArrayElement;
    const JNI_IFC *ifc = fn; g_env = (JNIEnv *) &ifc;
    snprintf(cwd, sizeof cwd, "%s", argv[2]);
    snprintf(p_out, sizeof p_out, "%s/out.txt", argv[2]); snprintf(p_err, sizeof p_err, "%s/err.txt", argv[2]);
    snprintf(p_rc, sizeof p_rc, "%s/rc.txt", argv[2]);
    char p_crash[1100]; snprintf(p_crash, sizeof p_crash, "%s/crash.txt", argv[2]);
    unlink(p_out); unlink(p_err); unlink(p_rc); unlink(p_crash);
    g_args.n = argc - 3; g_args.v = (const char **) (argv + 3);
    static const char *envs[] = { "KAMI_SMOKE=1" }; g_envs.n = 1; g_envs.v = envs;
    /* The tool may call exit() (→ _exit in the bridge) and end THIS process: run it in a child so the
       harness survives and can report, exactly like the app's separate :engine process. */
    fflush(stdout);
    pid_t pid = fork();
    if (pid == 0) {
        pthread_attr_t at; pthread_attr_init(&at); pthread_attr_setstacksize(&at, 64u << 20);
        pthread_t t; pthread_create(&t, &at, worker, NULL); pthread_join(t, NULL);
        _exit(0);
    }
    int st = 0; waitpid(pid, &st, 0);
    if (WIFSIGNALED(st)) printf("HARNESS child killed by signal %d\n", WTERMSIG(st));
    cat("RC", p_rc, 64); cat("CRASH", p_crash, 256);
    cat("STDOUT", p_out, 4000); cat("STDERR", p_err, 1500);
    return 0;
}
