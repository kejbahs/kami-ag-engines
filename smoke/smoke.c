/* CI smoke test: dlopen an engine .so and run its main with the given args (arm64 Android executable). */
#include <dlfcn.h>
#include <stdio.h>
int main(int argc, char **argv) {
    if (argc < 3) { fprintf(stderr, "usage: smoke lib.so argv0 [args]\n"); return 2; }
    void *h = dlopen(argv[1], RTLD_NOW);
    if (!h) { fprintf(stderr, "dlopen failed: %s\n", dlerror()); return 3; }
    int (*m)(int, char **) = (int (*)(int, char **)) dlsym(h, "kami_engine_main");
    if (!m) { fprintf(stderr, "no kami_engine_main\n"); return 4; }
    if (!dlsym(h, "Java_com_kami_ag_engines_EngineNative_run")) { fprintf(stderr, "no JNI entry\n"); return 5; }
    return m(argc - 2, argv + 2);
}
