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
        // Never let a scratch id escape the cache directory: keep only
        // characters that are safe in a filename (real ids are UUIDs).
        var sb = new StringBuilder ();
        foreach (unowned uint8 b in id.data) {
            if ((b >= 'a' && b <= 'z') || (b >= 'A' && b <= 'Z') ||
                (b >= '0' && b <= '9') || b == '-' || b == '_') {
                sb.append_c ((char) b);
            }
        }
        string safe = sb.str;
        if (safe == "") {
            safe = "scratch";
        }
        return GLib.Path.build_filename (cache_dir (), "%s.tmp.txt".printf (safe));
    }

    /** True when `id` is a well-formed scratch identifier (no path parts). */
    public static bool is_safe_scratch_id (string id) {
        if (id == "" || id == "." || id == "..") {
            return false;
        }
        foreach (unowned uint8 b in id.data) {
            if (!((b >= 'a' && b <= 'z') || (b >= 'A' && b <= 'Z') ||
                  (b >= '0' && b <= '9') || b == '-' || b == '_')) {
                return false;
            }
        }
        return true;
    }
}

}
