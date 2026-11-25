/*
 * Kami AG «حذف پس‌زمینه» engine — fully on the phone, open source, no Play services.
 *   bgremove <in.jpg|png|bmp> <out.png> [--mask mask.png] [--bg RRGGBB] [--threads N]
 * Model: U-2-Netp (u2netp.onnx, Apache-2.0, 320x320). Runtime: ONNX Runtime (MIT) loaded with dlopen()
 * from the SAME folder as this library (libonnxruntime.so ships in the same pack), model from
 * <pack>/config/u2netp.onnx (or $KAMI_BG_MODEL). Image I/O: stb_image / stb_image_write (public domain).
 * Prints one line «BGREMOVE OK <w>x<h> fg=<percent>%» on success.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include "onnxruntime_c_api.h"
#define STB_IMAGE_IMPLEMENTATION
#define STBI_NO_HDR
#define STBI_NO_LINEAR
#include "stb_image.h"
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"

#define S 320

static const OrtApi *ort;

static int fail(const char *what, const char *detail) {
    fprintf(stderr, "bgremove: %s%s%s\n", what, detail ? ": " : "", detail ? detail : "");
    return 1;
}

static int check(OrtStatus *st, const char *what) {
    if (!st) return 0;
    fprintf(stderr, "bgremove: %s: %s\n", what, ort->GetErrorMessage(st));
    ort->ReleaseStatus(st);
    return 1;
}

static void self_dir(char *out, size_t n) {
    Dl_info info;
    out[0] = 0;
    if (dladdr((void *) &self_dir, &info) && info.dli_fname) {
        strncpy(out, info.dli_fname, n - 1); out[n - 1] = 0;
        char *s = strrchr(out, '/'); if (s) *s = 0; else strcpy(out, ".");
    } else strcpy(out, ".");
}

/* bilinear sample of a single-channel float map */
static float sample(const float *m, int w, int h, float x, float y) {
    if (x < 0) x = 0; if (y < 0) y = 0;
    if (x > w - 1) x = (float) (w - 1); if (y > h - 1) y = (float) (h - 1);
    int x0 = (int) x, y0 = (int) y, x1 = x0 + 1 < w ? x0 + 1 : x0, y1 = y0 + 1 < h ? y0 + 1 : y0;
    float fx = x - x0, fy = y - y0;
    float a = m[y0 * w + x0] * (1 - fx) + m[y0 * w + x1] * fx;
    float b = m[y1 * w + x0] * (1 - fx) + m[y1 * w + x1] * fx;
    return a * (1 - fy) + b * fy;
}

static int hexrgb(const char *s, unsigned char rgb[3]) {
    if (*s == '#') s++;
    if (strlen(s) != 6) return 0;
    for (int i = 0; i < 3; i++) { unsigned v; if (sscanf(s + 2 * i, "%2x", &v) != 1) return 0; rgb[i] = (unsigned char) v; }
    return 1;
}

int main(int argc, char **argv) {
    const char *in = NULL, *out = NULL, *maskp = NULL; unsigned char bg[3]; int useBg = 0, threads = 2;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--mask") && i + 1 < argc) maskp = argv[++i];
        else if (!strcmp(argv[i], "--bg") && i + 1 < argc) { if (!hexrgb(argv[++i], bg)) return fail("bad --bg colour", argv[i]); useBg = 1; }
        else if (!strcmp(argv[i], "--threads") && i + 1 < argc) threads = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--version")) { printf("bgremove 1.0 (U-2-Netp + ONNX Runtime)\n"); return 0; }
        else if (!in) in = argv[i]; else if (!out) out = argv[i];
        else return fail("too many arguments", argv[i]);
    }
    if (!in || !out) { fprintf(stderr, "usage: bgremove in.jpg out.png [--mask m.png] [--bg ffffff]\n"); return 2; }

    char dir[PATH_MAX], lib[PATH_MAX], model[PATH_MAX];
    self_dir(dir, sizeof dir);
    snprintf(lib, sizeof lib, "%s/libonnxruntime.so", dir);
    const char *envm = getenv("KAMI_BG_MODEL");
    if (envm && *envm) snprintf(model, sizeof model, "%s", envm); else snprintf(model, sizeof model, "%s/config/u2netp.onnx", dir);

    int w, hgt, ch;
    fprintf(stderr, "stage: read input\n");
    unsigned char *img = stbi_load(in, &w, &hgt, &ch, 3);
    if (!img) return fail("cannot read input image", stbi_failure_reason());
    if (w < 2 || hgt < 2) return fail("image too small", NULL);

    fprintf(stderr, "stage: load ONNX Runtime %s\n", lib);
    void *h = dlopen(lib, RTLD_NOW | RTLD_LOCAL);
    if (!h) { const char *alt = getenv("KAMI_ORT_LIB"); if (alt) h = dlopen(alt, RTLD_NOW | RTLD_LOCAL); }
    if (!h) return fail("ONNX Runtime not loaded", dlerror());
    const OrtApiBase *(*getBase)(void) = (const OrtApiBase *(*)(void)) dlsym(h, "OrtGetApiBase");
    if (!getBase) return fail("OrtGetApiBase missing", NULL);
    ort = getBase()->GetApi(ORT_API_VERSION);
    if (!ort) return fail("ONNX Runtime API version not supported", getBase()->GetVersionString());

    fprintf(stderr, "stage: ONNX Runtime API ok\n");

    /* 320x320 bilinear resize + ImageNet normalisation (as rembg does for u2netp) */
    static float input[3 * S * S];
    const float mean[3] = {0.485f, 0.456f, 0.406f}, stdv[3] = {0.229f, 0.224f, 0.225f};
    for (int y = 0; y < S; y++) for (int x = 0; x < S; x++) {
        float sx = (x + 0.5f) * w / S - 0.5f, sy = (y + 0.5f) * hgt / S - 0.5f;
        if (sx < 0) sx = 0; if (sy < 0) sy = 0;
        int x0 = (int) sx, y0 = (int) sy, x1 = x0 + 1 < w ? x0 + 1 : x0, y1 = y0 + 1 < hgt ? y0 + 1 : y0;
        float fx = sx - x0, fy = sy - y0;
        for (int c = 0; c < 3; c++) {
            float a = img[(y0 * w + x0) * 3 + c] * (1 - fx) + img[(y0 * w + x1) * 3 + c] * fx;
            float b = img[(y1 * w + x0) * 3 + c] * (1 - fx) + img[(y1 * w + x1) * 3 + c] * fx;
            input[c * S * S + y * S + x] = ((a * (1 - fy) + b * fy) / 255.0f - mean[c]) / stdv[c];
        }
    }

    OrtEnv *env; OrtSessionOptions *so; OrtSession *sess; OrtMemoryInfo *mi; OrtValue *tin = NULL, *tout = NULL;
    fprintf(stderr, "stage: CreateEnv\n");
    if (check(ort->CreateEnv(ORT_LOGGING_LEVEL_ERROR, "bgremove", &env), "CreateEnv")) return 1;
    if (check(ort->CreateSessionOptions(&so), "SessionOptions")) return 1;
    ort->SetIntraOpNumThreads(so, threads > 0 ? threads : 2);
    ort->SetSessionGraphOptimizationLevel(so, ORT_ENABLE_ALL);
    FILE *mf = fopen(model, "rb");
    if (!mf) return fail("model file missing", model);
    fclose(mf);
    if (check(ort->CreateSession(env, model, so, &sess), "load model")) return 1;
    OrtAllocator *al; ort->GetAllocatorWithDefaultOptions(&al);
    char *inName, *outName;
    if (check(ort->SessionGetInputName(sess, 0, al, &inName), "input name")) return 1;
    if (check(ort->SessionGetOutputName(sess, 0, al, &outName), "output name")) return 1;
    if (check(ort->CreateCpuMemoryInfo(OrtArenaAllocator, OrtMemTypeDefault, &mi), "MemoryInfo")) return 1;
    int64_t shape[4] = {1, 3, S, S};
    if (check(ort->CreateTensorWithDataAsOrtValue(mi, input, sizeof input, shape, 4, ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, &tin), "input tensor")) return 1;
    const char *ins[1] = {inName}, *outs[1] = {outName};
    if (check(ort->Run(sess, NULL, ins, (const OrtValue *const *) &tin, 1, outs, 1, &tout), "run model")) return 1;
    float *pred; if (check(ort->GetTensorMutableData(tout, (void **) &pred), "output data")) return 1;

    /* min-max normalise the 320x320 mask, upscale to the photo, write RGBA (or flattened on --bg) */
    float mn = pred[0], mx = pred[0];
    for (int i = 1; i < S * S; i++) { if (pred[i] < mn) mn = pred[i]; if (pred[i] > mx) mx = pred[i]; }
    float rng = mx - mn > 1e-6f ? mx - mn : 1.0f;
    static float mask[S * S];
    for (int i = 0; i < S * S; i++) mask[i] = (pred[i] - mn) / rng;
    int oc = useBg ? 3 : 4;
    unsigned char *o = malloc((size_t) w * hgt * oc), *mk = maskp ? malloc((size_t) w * hgt) : NULL;
    if (!o || (maskp && !mk)) return fail("out of memory", NULL);
    long fg = 0;
    for (int y = 0; y < hgt; y++) for (int x = 0; x < w; x++) {
        float a = sample(mask, S, S, (x + 0.5f) * S / w - 0.5f, (y + 0.5f) * S / hgt - 0.5f);
        if (a < 0) a = 0; if (a > 1) a = 1;
        unsigned char A = (unsigned char) lrintf(a * 255.0f);
        if (A >= 128) fg++;
        const unsigned char *p = img + ((size_t) y * w + x) * 3;
        unsigned char *q = o + ((size_t) y * w + x) * oc;
        if (useBg) for (int c = 0; c < 3; c++) q[c] = (unsigned char) lrintf(p[c] * a + bg[c] * (1 - a));
        else { q[0] = p[0]; q[1] = p[1]; q[2] = p[2]; q[3] = A; }
        if (mk) mk[(size_t) y * w + x] = A;
    }
    const char *ext = strrchr(out, '.');
    int ok = (ext && (!strcasecmp(ext, ".jpg") || !strcasecmp(ext, ".jpeg")))
        ? (useBg ? stbi_write_jpg(out, w, hgt, 3, o, 92) : (fprintf(stderr, "bgremove: JPEG has no transparency — use .png or --bg\n"), 0))
        : stbi_write_png(out, w, hgt, oc, o, w * oc);
    if (!ok) return fail("cannot write output", out);
    if (mk && !stbi_write_png(maskp, w, hgt, 1, mk, w)) return fail("cannot write mask", maskp);
    printf("BGREMOVE OK %dx%d fg=%ld%%\n", w, hgt, fg * 100 / ((long) w * hgt));
    fflush(stdout);
    ort->ReleaseValue(tout); ort->ReleaseValue(tin); ort->ReleaseMemoryInfo(mi);
    ort->ReleaseSession(sess); ort->ReleaseSessionOptions(so); ort->ReleaseEnv(env);
    stbi_image_free(img); free(o); free(mk);
    return 0;
}
