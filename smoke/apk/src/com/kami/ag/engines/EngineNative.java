package com.kami.ag.engines;

/** Same JNI signature as Kami AG (app/src/main/java/com/kami/ag/engines/EngineStore.kt). */
public final class EngineNative {
    public static native int run(String[] argv, String cwd, String out, String err, String rc, String[] env);
}
