namespace Maha {

/**
 * User-tunable settings, loaded from `~/.config/maha/config.ini`.
 *
 * Not exposed through the UI by design.
 */
public class Config : GLib.Object {
    public const string DEFAULT_FONT = "Monospace";
    public const int DEFAULT_FONT_SIZE = 11;
    public const int MIN_FONT_SIZE = 1;
    public const double DEFAULT_TRANSPARENCY = 0.85;
    public const double MIN_TRANSPARENCY = 0.05;
    public const double DEFAULT_LINE_HEIGHT = 0.0;
    public const uint DEFAULT_AUTOSAVE_MS = 1500;
    public const uint MIN_AUTOSAVE_MS = 10;

    /** Window background opacity, 0.0 (see-through) to 1.0 (opaque). */
    public double transparency { get; set; default = DEFAULT_TRANSPARENCY; }

    /** Font family name, e.g. "Monospace" or "Cascadia Code". */
    public string font { get; set; default = DEFAULT_FONT; }

    /** Editor font size in points. */
    public int font_size { get; set; default = DEFAULT_FONT_SIZE; }

    /**
     * Editor line height, as a multiple of the font size (e.g. 1.4). A value
     * of 0 (or less) keeps the font's natural line spacing.
     */
    public double line_height { get; set; default = DEFAULT_LINE_HEIGHT; }

    /** Debounce time before autosaving, in milliseconds. */
    public uint autosave_ms { get; set; default = DEFAULT_AUTOSAVE_MS; }

    /** `transparency` clamped to the supported range. */
    public double effective_transparency {
        get {
            if (transparency < MIN_TRANSPARENCY) {
                return MIN_TRANSPARENCY;
            }
            if (transparency > 1.0) {
                return 1.0;
            }
            return transparency;
        }
    }

    /** `font_size` clamped to the supported range. */
    public int effective_font_size {
        get {
            if (font_size < MIN_FONT_SIZE) {
                return MIN_FONT_SIZE;
            }
            return font_size;
        }
    }

    /** `autosave_ms` clamped to the supported range. */
    public uint effective_autosave_ms {
        get {
            if (autosave_ms < MIN_AUTOSAVE_MS) {
                return MIN_AUTOSAVE_MS;
            }
            return autosave_ms;
        }
    }

    /**
     * `line_height` for CSS: 0 means "use the font's natural spacing", any
     * positive value is used as a multiple of the font size.
     */
    public double effective_line_height {
        get {
            if (line_height <= 0.0) {
                return 0.0;
            }
            return line_height;
        }
    }
}

}
