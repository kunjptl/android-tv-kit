package com.kunj.tvhome;

import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.graphics.Color;
import android.graphics.drawable.Drawable;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.text.TextUtils;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.AdapterView;
import android.widget.BaseAdapter;
import android.widget.GridView;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;

import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** Full app list. Hold OK on an app to add it to or remove it from the dock. */
public class AppsActivity extends Activity {

    private static final int MATCH = ViewGroup.LayoutParams.MATCH_PARENT;
    private static final int WRAP = ViewGroup.LayoutParams.WRAP_CONTENT;

    private static class Item {
        String pkg;
        String label;
        Drawable icon;
    }

    private final List<Item> items = new ArrayList<Item>();
    private final ExecutorService exec = Executors.newSingleThreadExecutor();
    private List<String> favs = new ArrayList<String>();
    private GridView grid;
    private TextView status;

    private final BaseAdapter adapter = new BaseAdapter() {
        @Override
        public int getCount() {
            return items.size();
        }

        @Override
        public Object getItem(int i) {
            return items.get(i);
        }

        @Override
        public long getItemId(int i) {
            return i;
        }

        @Override
        public View getView(int pos, View cv, ViewGroup parent) {
            LinearLayout row;
            if (cv == null) {
                row = new LinearLayout(AppsActivity.this);
                row.setOrientation(LinearLayout.VERTICAL);
                row.setGravity(Gravity.CENTER_HORIZONTAL);
                row.setPadding(dp(8), dp(10), dp(8), dp(10));

                ImageView iv = new ImageView(AppsActivity.this);
                iv.setId(1);
                iv.setScaleType(ImageView.ScaleType.FIT_CENTER);
                row.addView(iv, new LinearLayout.LayoutParams(dp(88), dp(88)));

                TextView tv = new TextView(AppsActivity.this);
                tv.setId(2);
                tv.setSingleLine(true);
                tv.setEllipsize(TextUtils.TruncateAt.END);
                tv.setGravity(Gravity.CENTER_HORIZONTAL);
                tv.setTextColor(Color.WHITE);
                tv.setTextSize(TypedValue.COMPLEX_UNIT_SP, 16);
                row.addView(tv, new LinearLayout.LayoutParams(MATCH, WRAP));
            } else {
                row = (LinearLayout) cv;
            }
            ImageView iconView = (ImageView) row.findViewById(1);
            TextView labelView = (TextView) row.findViewById(2);
            Item it = items.get(pos);
            iconView.setImageDrawable(it.icon);
            labelView.setText((favs.contains(it.pkg) ? "★ " : "") + it.label);
            return row;
        }
    };

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);

        LinearLayout col = new LinearLayout(this);
        col.setOrientation(LinearLayout.VERTICAL);
        col.setBackgroundColor(0xF2101418);
        col.setPadding(dp(56), dp(40), dp(56), dp(24));

        TextView title = new TextView(this);
        title.setText("All apps");
        title.setTextColor(Color.WHITE);
        title.setTextSize(TypedValue.COMPLEX_UNIT_SP, 30);
        col.addView(title, new LinearLayout.LayoutParams(WRAP, WRAP));

        TextView hint = new TextView(this);
        hint.setText("Hold OK on an app to add it to the dock or remove it. A star marks dock apps.");
        hint.setTextColor(0xAAFFFFFF);
        hint.setTextSize(TypedValue.COMPLEX_UNIT_SP, 16);
        LinearLayout.LayoutParams hintLp = new LinearLayout.LayoutParams(WRAP, WRAP);
        hintLp.bottomMargin = dp(16);
        col.addView(hint, hintLp);

        status = new TextView(this);
        status.setText("Loading apps...");
        status.setTextColor(Color.WHITE);
        status.setTextSize(TypedValue.COMPLEX_UNIT_SP, 20);
        col.addView(status, new LinearLayout.LayoutParams(WRAP, WRAP));

        grid = new GridView(this);
        grid.setNumColumns(6);
        grid.setStretchMode(GridView.STRETCH_COLUMN_WIDTH);
        grid.setVerticalSpacing(dp(12));
        grid.setHorizontalSpacing(dp(12));
        GradientDrawable sel = new GradientDrawable();
        sel.setCornerRadius(dp(18));
        sel.setColor(0x55FFFFFF);
        grid.setSelector(sel);
        grid.setAdapter(adapter);
        col.addView(grid, new LinearLayout.LayoutParams(MATCH, 0, 1f));

        grid.setOnItemClickListener(new AdapterView.OnItemClickListener() {
            @Override
            public void onItemClick(AdapterView<?> parent, View v, int pos, long id) {
                Intent i = Prefs.launchIntent(AppsActivity.this, items.get(pos).pkg);
                if (i != null) {
                    try {
                        startActivity(i);
                    } catch (Exception e) {
                        Toast.makeText(AppsActivity.this, "Cannot open that app", Toast.LENGTH_SHORT).show();
                    }
                }
            }
        });

        grid.setOnItemLongClickListener(new AdapterView.OnItemLongClickListener() {
            @Override
            public boolean onItemLongClick(AdapterView<?> parent, View v, int pos, long id) {
                Item it = items.get(pos);
                boolean added = Prefs.toggle(AppsActivity.this, it.pkg);
                favs = Prefs.favorites(AppsActivity.this);
                adapter.notifyDataSetChanged();
                Toast.makeText(AppsActivity.this,
                        (added ? "Added " : "Removed ") + it.label + (added ? " to the dock" : " from the dock"),
                        Toast.LENGTH_SHORT).show();
                return true;
            }
        });

        setContentView(col);
        load();
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        exec.shutdownNow();
    }

    private void load() {
        exec.execute(new Runnable() {
            @Override
            public void run() {
                PackageManager pm = getPackageManager();
                List<Item> found = new ArrayList<Item>();
                Set<String> seen = new HashSet<String>();
                String[] cats = { Intent.CATEGORY_LEANBACK_LAUNCHER, Intent.CATEGORY_LAUNCHER };
                for (String cat : cats) {
                    Intent q = new Intent(Intent.ACTION_MAIN);
                    q.addCategory(cat);
                    for (ResolveInfo ri : pm.queryIntentActivities(q, 0)) {
                        String pkg = ri.activityInfo.packageName;
                        if (pkg.equals(getPackageName()) || !seen.add(pkg)) continue;
                        Item it = new Item();
                        it.pkg = pkg;
                        it.label = String.valueOf(ri.loadLabel(pm));
                        it.icon = ri.loadIcon(pm);
                        found.add(it);
                    }
                }
                Collections.sort(found, new Comparator<Item>() {
                    @Override
                    public int compare(Item a, Item b) {
                        return a.label.compareToIgnoreCase(b.label);
                    }
                });
                final List<Item> result = found;
                runOnUiThread(new Runnable() {
                    @Override
                    public void run() {
                        items.clear();
                        items.addAll(result);
                        favs = Prefs.favorites(AppsActivity.this);
                        status.setVisibility(View.GONE);
                        adapter.notifyDataSetChanged();
                        grid.requestFocus();
                    }
                });
            }
        });
    }

    private int dp(int v) {
        return (int) (v * getResources().getDisplayMetrics().density + 0.5f);
    }
}
