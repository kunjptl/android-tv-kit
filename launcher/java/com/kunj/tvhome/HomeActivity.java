package com.kunj.tvhome;

import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Color;
import android.graphics.drawable.Drawable;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.util.DisplayMetrics;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.View;
import android.view.ViewGroup;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextClock;
import android.widget.TextView;
import android.widget.Toast;

import java.io.InputStream;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Minimal TV home: rotating wallpaper, clock, one row of favourite apps.
 * No libraries. Wallpapers are bundled under assets/wallpapers.
 */
public class HomeActivity extends Activity {

    private static final long ROTATE_MS = 5L * 60L * 1000L;
    private static final int TILE_DP = 120;
    private static final int MATCH = ViewGroup.LayoutParams.MATCH_PARENT;
    private static final int WRAP = ViewGroup.LayoutParams.WRAP_CONTENT;

    private final Handler handler = new Handler(Looper.getMainLooper());
    private final ExecutorService exec = Executors.newSingleThreadExecutor();

    private ImageView wallBack;
    private ImageView wallFront;
    private LinearLayout dock;
    private TextView focusLabel;

    private final List<String> walls = new ArrayList<String>();
    private int wallIndex = -1;
    private boolean wallShown = false;
    private boolean loading = false;
    private boolean started = false;

    private final Runnable rotate = new Runnable() {
        @Override
        public void run() {
            nextWall();
            handler.postDelayed(this, ROTATE_MS);
        }
    };

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);

        FrameLayout root = new FrameLayout(this);
        root.setBackgroundColor(0xFF0B1210);
        root.setClipChildren(false);

        wallBack = newWall();
        wallFront = newWall();
        root.addView(wallBack);
        root.addView(wallFront);

        View topScrim = new View(this);
        topScrim.setBackground(new GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM,
                new int[] { 0x88000000, 0x00000000 }));
        root.addView(topScrim, new FrameLayout.LayoutParams(MATCH, dp(200), Gravity.TOP));

        View bottomScrim = new View(this);
        bottomScrim.setBackground(new GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM,
                new int[] { 0x00000000, 0xCC000000 }));
        root.addView(bottomScrim, new FrameLayout.LayoutParams(MATCH, dp(400), Gravity.BOTTOM));

        TextClock clock = new TextClock(this);
        clock.setFormat12Hour("h:mm a");
        clock.setFormat24Hour("HH:mm");
        clock.setTextColor(Color.WHITE);
        clock.setTextSize(TypedValue.COMPLEX_UNIT_SP, 30);
        clock.setShadowLayer(8f, 0f, 2f, 0xAA000000);
        FrameLayout.LayoutParams clockLp = new FrameLayout.LayoutParams(WRAP, WRAP, Gravity.TOP | Gravity.END);
        clockLp.setMargins(0, dp(40), dp(56), 0);
        root.addView(clock, clockLp);

        focusLabel = new TextView(this);
        focusLabel.setTextColor(Color.WHITE);
        focusLabel.setTextSize(TypedValue.COMPLEX_UNIT_SP, 24);
        focusLabel.setShadowLayer(8f, 0f, 2f, 0xAA000000);
        focusLabel.setGravity(Gravity.CENTER_HORIZONTAL);
        FrameLayout.LayoutParams labelLp = new FrameLayout.LayoutParams(MATCH, WRAP, Gravity.BOTTOM);
        labelLp.bottomMargin = dp(236);
        root.addView(focusLabel, labelLp);

        dock = new LinearLayout(this);
        dock.setOrientation(LinearLayout.HORIZONTAL);
        dock.setGravity(Gravity.CENTER);
        dock.setClipChildren(false);
        dock.setClipToPadding(false);
        int pad = dp(14);
        dock.setPadding(pad, pad, pad, pad);
        GradientDrawable pill = new GradientDrawable();
        pill.setColor(0x44000000);
        pill.setCornerRadius(dp(40));
        dock.setBackground(pill);
        FrameLayout.LayoutParams dockLp = new FrameLayout.LayoutParams(WRAP, WRAP,
                Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL);
        dockLp.bottomMargin = dp(56);
        root.addView(dock, dockLp);

        setContentView(root);

        try {
            String[] names = getAssets().list("wallpapers");
            if (names != null) {
                for (String n : names) {
                    String l = n.toLowerCase();
                    if (l.endsWith(".jpg") || l.endsWith(".jpeg") || l.endsWith(".png") || l.endsWith(".webp")) {
                        walls.add(n);
                    }
                }
            }
        } catch (Exception ignored) {
            // No wallpapers bundled. The gradient below is used.
        }
        Collections.shuffle(walls);

        if (walls.isEmpty()) {
            GradientDrawable g = new GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM,
                    new int[] { 0xFF1B4332, 0xFF081C15 });
            wallBack.setImageDrawable(g);
        }
    }

    @Override
    protected void onResume() {
        super.onResume();
        buildDock();
        focusFirst();
        handler.removeCallbacks(rotate);
        if (!started) {
            started = true;
            nextWall();
        }
        handler.postDelayed(rotate, ROTATE_MS);
    }

    @Override
    protected void onPause() {
        super.onPause();
        handler.removeCallbacks(rotate);
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        exec.shutdownNow();
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        focusFirst();
    }

    @Override
    public boolean onKeyDown(int keyCode, KeyEvent event) {
        if (keyCode == KeyEvent.KEYCODE_MENU) {
            startActivity(new Intent(this, AppsActivity.class));
            return true;
        }
        return super.onKeyDown(keyCode, event);
    }

    @Override
    public void onBackPressed() {
        // Home screen stays put.
    }

    // ---- dock ----

    private void buildDock() {
        dock.removeAllViews();
        PackageManager pm = getPackageManager();

        for (final String pkg : Prefs.favorites(this)) {
            final Intent li = Prefs.launchIntent(this, pkg);
            if (li == null) continue;
            ResolveInfo ri = pm.resolveActivity(li, 0);
            if (ri == null) continue;
            final String label = String.valueOf(ri.loadLabel(pm));
            Drawable icon = ri.loadIcon(pm);

            View t = tile(icon, label);
            t.setOnClickListener(new View.OnClickListener() {
                @Override
                public void onClick(View v) {
                    launch(li);
                }
            });
            t.setOnLongClickListener(new View.OnLongClickListener() {
                @Override
                public boolean onLongClick(View v) {
                    Prefs.toggle(HomeActivity.this, pkg);
                    Toast.makeText(HomeActivity.this, "Removed " + label + " from the dock",
                            Toast.LENGTH_SHORT).show();
                    buildDock();
                    focusFirst();
                    return true;
                }
            });
            dock.addView(t);
        }

        View apps = tile(getDrawable(R.drawable.ic_apps), "All apps");
        apps.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                startActivity(new Intent(HomeActivity.this, AppsActivity.class));
            }
        });
        dock.addView(apps);

        View settings = tile(getDrawable(R.drawable.ic_settings), "Settings");
        settings.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                launch(new Intent(Settings.ACTION_SETTINGS));
            }
        });
        dock.addView(settings);
    }

    private void focusFirst() {
        if (dock.getChildCount() > 0) dock.getChildAt(0).requestFocus();
    }

    private View tile(Drawable icon, final String label) {
        FrameLayout f = new FrameLayout(this);
        int size = dp(TILE_DP);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(size, size);
        lp.setMargins(dp(10), dp(10), dp(10), dp(10));
        f.setLayoutParams(lp);

        final GradientDrawable bg = new GradientDrawable();
        bg.setCornerRadius(dp(26));
        bg.setColor(0x33FFFFFF);
        f.setBackground(bg);
        f.setFocusable(true);
        f.setClickable(true);

        ImageView iv = new ImageView(this);
        iv.setImageDrawable(icon);
        iv.setScaleType(ImageView.ScaleType.FIT_CENTER);
        int p = dp(16);
        iv.setPadding(p, p, p, p);
        f.addView(iv, new FrameLayout.LayoutParams(MATCH, MATCH));

        f.setOnFocusChangeListener(new View.OnFocusChangeListener() {
            @Override
            public void onFocusChange(View v, boolean has) {
                float s = has ? 1.18f : 1f;
                v.animate().scaleX(s).scaleY(s).setDuration(120).start();
                bg.setColor(has ? 0x88FFFFFF : 0x33FFFFFF);
                if (has) focusLabel.setText(label);
            }
        });
        return f;
    }

    private void launch(Intent i) {
        try {
            startActivity(i);
        } catch (Exception e) {
            Toast.makeText(this, "Cannot open that app", Toast.LENGTH_SHORT).show();
        }
    }

    // ---- wallpaper ----

    private ImageView newWall() {
        ImageView v = new ImageView(this);
        v.setScaleType(ImageView.ScaleType.CENTER_CROP);
        v.setLayoutParams(new FrameLayout.LayoutParams(MATCH, MATCH));
        return v;
    }

    private void nextWall() {
        if (walls.isEmpty() || loading) return;
        loading = true;
        wallIndex = (wallIndex + 1) % walls.size();
        final String name = walls.get(wallIndex);
        exec.execute(new Runnable() {
            @Override
            public void run() {
                final Bitmap bm = decode(name);
                runOnUiThread(new Runnable() {
                    @Override
                    public void run() {
                        loading = false;
                        if (bm != null && !isFinishing()) show(bm);
                    }
                });
            }
        });
    }

    private void show(final Bitmap bm) {
        if (!wallShown) {
            wallShown = true;
            wallBack.setImageBitmap(bm);
            wallFront.setImageBitmap(bm);
            return;
        }
        wallBack.setImageBitmap(bm);
        wallFront.animate().alpha(0f).setDuration(1200).withEndAction(new Runnable() {
            @Override
            public void run() {
                wallFront.setImageBitmap(bm);
                wallFront.setAlpha(1f);
            }
        }).start();
    }

    private Bitmap decode(String name) {
        try {
            DisplayMetrics dm = getResources().getDisplayMetrics();
            int w = dm.widthPixels;
            int h = dm.heightPixels;

            BitmapFactory.Options o = new BitmapFactory.Options();
            o.inJustDecodeBounds = true;
            InputStream in = getAssets().open("wallpapers/" + name);
            BitmapFactory.decodeStream(in, null, o);
            in.close();

            int sample = 1;
            while (o.outWidth / (sample * 2) >= w && o.outHeight / (sample * 2) >= h) sample *= 2;

            BitmapFactory.Options d = new BitmapFactory.Options();
            d.inSampleSize = sample;
            d.inPreferredConfig = Bitmap.Config.RGB_565;
            in = getAssets().open("wallpapers/" + name);
            Bitmap bm = BitmapFactory.decodeStream(in, null, d);
            in.close();
            return bm;
        } catch (Exception e) {
            return null;
        }
    }

    private int dp(int v) {
        return (int) (v * getResources().getDisplayMetrics().density + 0.5f);
    }
}
