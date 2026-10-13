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

    public const string GROUP_EDITOR = "editor";
    public const string KEY_AUTOSAVE_MS = "autosave_ms";

    public string path { get; private set; }

    public ConfigStore (string? path = null) {
        this.path = path ?? default_path ();
    }

    public static string config_dir () {
        return Paths.config_dir ();
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

        int autosave_ms = read_int (keyfile, GROUP_EDITOR, KEY_AUTOSAVE_MS, (int) Config.DEFAULT_AUTOSAVE_MS);
        config.autosave_ms = autosave_ms > 0 ? (uint) autosave_ms : Config.DEFAULT_AUTOSAVE_MS;
        return config;
    }

    public void save (Config config) {
        GLib.DirUtils.create_with_parents (config_dir (), 0700);

        var keyfile = new GLib.KeyFile ();
        keyfile.set_double (GROUP, KEY_TRANSPARENCY, config.transparency);
        keyfile.set_string (GROUP, KEY_FONT, config.font);
        keyfile.set_integer (GROUP, KEY_FONT_SIZE, config.font_size);
        keyfile.set_integer (GROUP_EDITOR, KEY_AUTOSAVE_MS, (int) config.autosave_ms);

        size_t length;
        string data = keyfile.to_data (out length);
        if (data == null) {
            return;
        }

        try {
            FileStore.save_atomic (path, data);
        } catch (GLib.Error e) {
            GLib.warning ("maha: could not write \"%s\": %s", path, e.message);
        }
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
