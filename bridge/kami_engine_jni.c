/*
 * Kami AG engine bridge. Linked INTO every engine .so (ffmpeg, ffprobe, magick, busybox).
 * The app loads the .so with System.load() in its separate ":engine" process and calls
 * com.kami.ag.engines.EngineNative.run(argv, cwd, stdoutPath, stderrPath, rcPath, env).
 * The tool's own main(argc, argv) runs in-process (Android blocks exec() of downloaded files,
 * but loading a downloaded shared library is allowed). exit() inside the tool is wrapped
 * (-Wl,--wrap=exit) so the exit code is still written to rcPath before the process ends.
 */
#include <jni.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>

extern int main(int argc, char **argv);
extern void __real_exit(int code);

static char g_rc_path[1024];

static void write_rc(int code) {
    if (!g_rc_path[0]) return;
    int fd = open(g_rc_path, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (fd >= 0) { char b[32]; int n = snprintf(b, sizeof b, "%d\n", code); if (write(fd, b, n) < 0) {} close(fd); }
}

void __wrap_exit(int code) {
    fflush(stdout); fflush(stderr);
    write_rc(code);
    __real_exit(code);
}

/* Plain C entry for the CI smoke test (no JVM). */
__attribute__((visibility("default"))) int kami_engine_main(int argc, char **argv) { return main(argc, argv); }

JNIEXPORT jint JNICALL Java_com_kami_ag_engines_EngineNative_run(JNIEnv *env, jclass cls,
        jobjectArray jargs, jstring jcwd, jstring jout, jstring jerr, jstring jrc, jobjectArray jenv) {
    (void) cls;
    const char *rc = (*env)->GetStringUTFChars(env, jrc, NULL);
    strncpy(g_rc_path, rc, sizeof g_rc_path - 1);
    (*env)->ReleaseStringUTFChars(env, jrc, rc);

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
    fflush(stdout); fflush(stderr);
    write_rc(code);
    return code;
}
