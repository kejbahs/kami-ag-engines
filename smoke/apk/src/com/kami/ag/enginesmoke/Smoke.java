package com.kami.ag.enginesmoke;

import android.app.Activity;
import android.os.Bundle;
import com.kami.ag.engines.EngineNative;
import java.io.File;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.List;

/** files/job/args.txt: line 1 = lib file name in files/, then one argv item per line. */
public class Smoke extends Activity {
    @Override protected void onCreate(Bundle b) {
        super.onCreate(b);
        final File files = getFilesDir();
        final File job = new File(files, "job");
        new Thread(null, new Runnable() { public void run() {
            File rc = new File(job, "rc.txt");
            try {
                write(new File(job, "pid"), String.valueOf(android.os.Process.myPid()));
                List<String> lines = Files.readAllLines(new File(job, "args.txt").toPath(), StandardCharsets.UTF_8);
                System.load(new File(files, lines.get(0).trim()).getPath());
                String[] argv = lines.subList(1, lines.size()).toArray(new String[0]);
                String[] env = { "HOME=" + job.getPath(), "TMPDIR=" + getCacheDir().getPath(),
                    "MAGICK_CONFIGURE_PATH=" + new File(files, "config").getPath(), "MAGICK_TEMPORARY_PATH=" + getCacheDir().getPath() };
                int code = EngineNative.run(argv, job.getPath(), new File(job, "out.txt").getPath(), new File(job, "err.txt").getPath(), rc.getPath(), env);
                if (!rc.exists()) write(rc, code + "\n");
            } catch (Throwable t) {
                write(new File(job, "fail.txt"), t.getClass().getSimpleName() + ": " + t.getMessage());
                if (!rc.exists()) write(rc, "-1\n");
            }
            android.os.Process.killProcess(android.os.Process.myPid());
        } }, "engine", 64L << 20).start();
    }

    private static void write(File f, String s) {
        try (FileOutputStream o = new FileOutputStream(f)) { o.write(s.getBytes(StandardCharsets.UTF_8)); } catch (Exception ignored) { }
    }
}
