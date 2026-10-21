package com.kunj.tvhome;

import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;

import java.io.BufferedReader;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

/** Dock favourites. Stored as a comma separated package list. */
final class Prefs {
    private static final String FILE = "home";
    private static final String KEY = "favs";

    /** Used only when favorites.txt is empty and nothing was saved yet. */
    private static final String[] DEFAULTS = {
        "com.netflix.ninja",
        "com.google.android.youtube.tv",
        "com.amazon.amazonvideo.livingroom",
        "com.disney.disneyplus",
        "com.hulu.livingroomplus",
        "com.plexapp.android",
        "org.xbmc.kodi",
        "com.spotify.tv.android"
    };

    private Prefs() {}

    static Intent launchIntent(Context c, String pkg) {
        PackageManager pm = c.getPackageManager();
        Intent i = pm.getLeanbackLaunchIntentForPackage(pkg);
        if (i == null) i = pm.getLaunchIntentForPackage(pkg);
        return i;
    }

    static boolean launchable(Context c, String pkg) {
        return launchIntent(c, pkg) != null;
    }

    static List<String> favorites(Context c) {
        SharedPreferences sp = c.getSharedPreferences(FILE, Context.MODE_PRIVATE);
        String raw = sp.getString(KEY, null);
        if (raw == null) {
            raw = readAsset(c);
            if (raw == null || raw.trim().length() == 0) {
                raw = join(Arrays.asList(DEFAULTS));
            }
        }
        List<String> out = new ArrayList<String>();
        for (String p : raw.split(",")) {
            p = p.trim();
            if (p.length() > 0 && !out.contains(p) && launchable(c, p)) out.add(p);
        }
        return out;
    }

    static void save(Context c, List<String> list) {
        c.getSharedPreferences(FILE, Context.MODE_PRIVATE)
            .edit().putString(KEY, join(list)).apply();
    }

    static boolean toggle(Context c, String pkg) {
        List<String> list = favorites(c);
        boolean added;
        if (list.contains(pkg)) {
            list.remove(pkg);
            added = false;
        } else {
            list.add(pkg);
            added = true;
        }
        save(c, list);
        return added;
    }

    private static String join(List<String> list) {
        StringBuilder sb = new StringBuilder();
        for (String s : list) {
            if (sb.length() > 0) sb.append(',');
            sb.append(s);
        }
        return sb.toString();
    }

    private static String readAsset(Context c) {
        try {
            InputStream in = c.getAssets().open("favorites.txt");
            BufferedReader r = new BufferedReader(new InputStreamReader(in, "UTF-8"));
            StringBuilder sb = new StringBuilder();
            String line;
            while ((line = r.readLine()) != null) {
                line = line.trim();
                if (line.length() == 0 || line.startsWith("#")) continue;
                if (sb.length() > 0) sb.append(',');
                sb.append(line);
            }
            r.close();
            return sb.toString();
        } catch (Exception e) {
            return null;
        }
    }
}
