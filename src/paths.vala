namespace Maha {

/**
 * Application directories, kept in one place so config, session and scratch
 * files all agree on the layout.
 */
public class Paths : GLib.Object {
    public const string APP_DIR = "maha";

    public static string config_dir () {
        return GLib.Path.build_filename (GLib.Environment.get_user_config_dir (), APP_DIR);
    }

    public static string cache_dir () {
        return GLib.Path.build_filename (GLib.Environment.get_user_cache_dir (), APP_DIR);
    }

    public static string config_file () {
        return GLib.Path.build_filename (config_dir (), "config.ini");
    }

    public static string session_file () {
        return GLib.Path.build_filename (config_dir (), "session");
    }

    /** Crash-safe backing store for an unsaved document. */
    public static string scratch_file (string id) {
        return GLib.Path.build_filename (cache_dir (), "%s.tmp.txt".printf (id));
    }
}

}
