namespace Maha {

// Bound directly to avoid the deprecated `Gtk.StyleContext` type reference.
[CCode (cname = "gtk_style_context_add_provider_for_display")]
extern void add_provider_for_display (Gdk.Display display, Gtk.StyleProvider provider, uint priority);

/**
 * Applies the appearance settings from `Config` through CSS.
 *
 * The app uses libadwaita's native look and follows the system light/dark
 * preference. This class only layers one thing on top: background transparency.
 * The window (and, by extension, the header bar, the tab strip and the editor
 * body) is painted with `alpha(@theme_bg_color, transparency)`, so every surface
 * shares the same transparency. Only text stays fully opaque.
 *
 * The provider is registered against the display and every rule is scoped to
 * `window.maha`, so a single instance governs the whole application: it is
 * created once by `Application` (not per window), and the runtime font zoom it
 * exposes affects every open window at once.
 */
public class ThemeController : GLib.Object {
    private Config config;
    private Gtk.CssProvider provider;
    // Font size lives in its own provider so a zoom only reparses one rule.
    private Gtk.CssProvider font_provider;
    private int font_size;

    public ThemeController (Config config) {
        this.config = config;
        this.provider = new Gtk.CssProvider ();
        this.font_provider = new Gtk.CssProvider ();
        this.font_size = config.effective_font_size;

        var display = Gdk.Display.get_default ();
        if (display != null) {
            // USER priority so nothing (theme/user stylesheet) outranks the
            // transparency; every rule is scoped to `window.maha`.
            add_provider_for_display (display, provider, Gtk.STYLE_PROVIDER_PRIORITY_USER);
            add_provider_for_display (display, font_provider, Gtk.STYLE_PROVIDER_PRIORITY_USER);
        }

        apply ();
        load_font ();
    }

    /** Increase the editor font size by one point, clamped (app-wide). */
    public void zoom_in () {
        apply_font (Config.zoom_step (font_size, +1));
    }

    /** Decrease the editor font size by one point, clamped (app-wide). */
    public void zoom_out () {
        apply_font (Config.zoom_step (font_size, -1));
    }

    /** Restore the configured font size (app-wide). Never persisted. */
    public void zoom_reset () {
        apply_font (config.effective_font_size);
    }

    private void apply_font (int pt) {
        if (pt == font_size) {
            return;
        }
        font_size = pt;
        load_font ();
    }

    private void load_font () {
        font_provider.load_from_string (build_font_css (font_size));
    }

    private void apply () {
        provider.load_from_string (build_css (config));
    }

    private static string build_css (Config config) {
        var css = new StringBuilder ();

        double opacity = config.effective_transparency;

        // The window background carries the single transparency value.
        css.append (("window.maha {"
            + " background-color: alpha(@theme_bg_color, %.4f);"
            + " background-image: none; }\n").printf (opacity));

        // Every surface inside the window is transparent, so the whole window
        // (header, tabs, editor) shows the window's background at the same
        // transparency. No colors are overridden, so text stays theme-styled.
        css.append ("window.maha headerbar {"
            + " background: none; background-color: transparent;"
            + " background-image: none; border: none; box-shadow: none; }\n");
        css.append ("window.maha tabbar, window.maha tabbar .box {"
            + " background: none; background-color: transparent;"
            + " background-image: none; box-shadow: none; }\n");
        // With a single tab the header shows a plain filename label instead of
        // the tab strip; dim it so the user's focus stays on the text content.
        css.append ("window.maha .maha-single-title { opacity: 0.7; }\n");
        css.append ("window.maha toolbarview, window.maha tabview,"
            + " window.maha scrolledwindow {"
            + " background-color: transparent; background-image: none; }\n");
        // GtkTextView's node (.view), its text child, and (GTK >= 4.24) the
        // opaque border subnodes.
        css.append ("window.maha textview.view, window.maha textview.view text,"
            + " window.maha textview.view > border {"
            + " background-color: transparent; background-image: none; }\n");
        // Scroll shadows only appear while scrolling, but keep them see-through.
        css.append ("window.maha scrolledwindow > overshoot,"
            + " window.maha scrolledwindow > junction { background: none; }\n");

        // Editor font (user configurable).
        var description = Pango.FontDescription.from_string (config.font);
        string? family = description.get_family ();
        if (family == null || family == "") {
            family = config.font;
        }
        if (family != "") {
            css.append ("textview.maha-editor { font-family: \"%s\"; }\n".printf (escape (family)));
        }

        // Line height (user configurable); a multiple of the font size. When
        // unset (0) the font's natural line spacing is kept.
        double line_height = config.effective_line_height;
        if (line_height > 0.0) {
            css.append ("textview.maha-editor { line-height: %.4f; }\n".printf (line_height));
        }

        return css.str;
    }

    // The editor font size, in its own provider so a runtime zoom reparses
    // only this rule. See the constructor.
    private static string build_font_css (int pt) {
        return "textview.maha-editor { font-size: %dpt; }\n".printf (pt);
    }

    private static string escape (string value) {
        var sb = new StringBuilder ();
        foreach (uint8 b in value.data) {
            if (b < 0x20 || b == 0x7f) {
                continue;
            }
            if (b == '\\' || b == '"') {
                sb.append_c ('\\');
            }
            sb.append_c ((char) b);
        }
        return sb.str;
    }
}

}
