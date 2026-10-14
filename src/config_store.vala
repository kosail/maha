namespace Maha {

/**
 * Loads and creates `~/.config/maha/config.ini`.
 *
 * The file is created with defaults when it does not exist. A malformed file
 * is never overwritten; each missing/invalid key simply falls back to its
 * default value.
 */
public class ConfigStore : GLib.Object {
    public const string GROUP = "appearance";
    public const string KEY_TRANSPARENCY = "transparency";
    public const string KEY_FONT = "font";
    public const string KEY_FONT_SIZE = "font_size";
    public const string KEY_LINE_HEIGHT = "line_height";

    public const string GROUP_EDITOR = "editor";
    public const string KEY_AUTOSAVE_MS = "autosave_ms";

    public string path { get; private set; }

    public ConfigStore (string? path = null) {
        this.path = path ?? default_path ();
    }

    public static string default_path () {
        return Paths.config_file ();
    }

    public Config load () {
        var config = new Config ();

        if (!GLib.FileUtils.test (path, GLib.FileTest.EXISTS)) {
            save (config);
            return config;
        }

        var keyfile = new GLib.KeyFile ();
        try {
            keyfile.load_from_file (path, GLib.KeyFileFlags.NONE);
        } catch (GLib.Error e) {
            GLib.warning ("maha: could not parse \"%s\": %s", path, e.message);
            return config;
        }

        config.transparency = read_double (keyfile, GROUP, KEY_TRANSPARENCY, Config.DEFAULT_TRANSPARENCY);
        config.font = read_string (keyfile, GROUP, KEY_FONT, Config.DEFAULT_FONT);

        int font_size = read_int (keyfile, GROUP, KEY_FONT_SIZE, Config.DEFAULT_FONT_SIZE);
        config.font_size = font_size > 0 ? font_size : Config.DEFAULT_FONT_SIZE;

        config.line_height = read_double (keyfile, GROUP, KEY_LINE_HEIGHT, Config.DEFAULT_LINE_HEIGHT);

        int autosave_ms = read_int (keyfile, GROUP_EDITOR, KEY_AUTOSAVE_MS, (int) Config.DEFAULT_AUTOSAVE_MS);
        config.autosave_ms = autosave_ms > 0 ? (uint) autosave_ms : Config.DEFAULT_AUTOSAVE_MS;
        return config;
    }

    public void save (Config config) {
        string dir = GLib.Path.get_dirname (path);
        if (dir != null && dir != "") {
            GLib.DirUtils.create_with_parents (dir, 0700);
        }

        // Written by hand rather than via GLib.KeyFile so doubles are rendered
        // readably (e.g. `0.85`, not `0.84999999999999998`). KeyFile still
        // parses the result on load.
        var data = new StringBuilder ();
        data.append ("[appearance]\n");
        data.append ("transparency=").append (format_double (config.transparency)).append_c ('\n');
        data.append ("font=").append (keyfile_escape (config.font)).append_c ('\n');
        data.append ("font_size=").append (config.font_size.to_string ()).append_c ('\n');
        data.append ("line_height=").append (format_double (config.line_height)).append_c ('\n');
        data.append ("\n[editor]\n");
        data.append ("autosave_ms=").append (config.autosave_ms.to_string ()).append_c ('\n');

        try {
            // Not fsync'd: preferences are not user data and are rewritten on
            // every launch.
            FileStore.save_atomic (path, data.str, false);
        } catch (GLib.Error e) {
            GLib.warning ("maha: could not write \"%s\": %s", path, e.message);
        }
    }

    private static string format_double (double value) {
        return "%g".printf (value);
    }

    private static double read_double (GLib.KeyFile keyfile, string group, string key, double fallback) {
        try {
            return keyfile.get_double (group, key);
        } catch (GLib.Error e) {
            return fallback;
        }
    }

    private static string read_string (GLib.KeyFile keyfile, string group, string key, string fallback) {
        try {
            return keyfile.get_string (group, key);
        } catch (GLib.Error e) {
            return fallback;
        }
    }

    private static int read_int (GLib.KeyFile keyfile, string group, string key, int fallback) {
        try {
            return keyfile.get_integer (group, key);
        } catch (GLib.Error e) {
            return fallback;
        }
    }
}

}
