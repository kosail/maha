namespace Maha {

/**
 * Remembers the tabs that were open during the previous run, plus which one
 * was active, so maha can restore the whole session on the next launch.
 *
 * Each entry is either a real file path or the id of the scratch file backing
 * an unsaved "New tab". Stored as a small INI file; the previous
 * single-document format and the legacy bare-path format are still understood
 * so upgrades do not lose state.
 */
public class SessionStore : GLib.Object {
    private const string GROUP = "session";
    private const string KEY_ACTIVE = "active";
    private const string KEY_COUNT = "count";
    private const string KEY_KIND = "kind";
    private const string KEY_VALUE = "value";
    private const string GROUP_LAST = "last";

    public const string KIND_FILE = "file";
    public const string KIND_SCRATCH = "scratch";

    /** One remembered tab: a file path or a scratch id. */
    public class Tab : GLib.Object {
        public string kind { get; private set; }
        public string value { get; private set; }

        public Tab (string kind, string value) {
            this.kind = kind;
            this.value = value;
        }
    }

    /** The remembered session: the tabs, in order, and the active index. */
    public class State : GLib.Object {
        public GLib.GenericArray<Tab> tabs { get; private set; default = new GLib.GenericArray<Tab> (); }
        public int active { get; set; default = 0; }
    }

    public string path { get; private set; }

    public SessionStore (string? path = null) {
        this.path = path ?? Paths.session_file ();
    }

    public State load () {
        var state = new State ();

        if (!GLib.FileUtils.test (path, GLib.FileTest.EXISTS)) {
            return state;
        }

        string contents;
        try {
            GLib.FileUtils.get_contents (path, out contents);
        } catch (GLib.Error e) {
            return state;
        }

        var keyfile = new GLib.KeyFile ();
        bool parsed = false;
        try {
            parsed = keyfile.load_from_data (contents, contents.length, GLib.KeyFileFlags.NONE);
        } catch (GLib.Error e) {
            parsed = false;
        }

        if (parsed) {
            load_list (keyfile, state);
            if (state.tabs.length > 0) {
                return state;
            }
            // Previous single-document format.
            load_single (keyfile, state);
            return state;
        }

        // Backward compatibility: a legacy session file holds a bare path.
        string trimmed = contents.strip ();
        if (trimmed != "") {
            state.tabs.add (new Tab (KIND_FILE, trimmed));
        }
        return state;
    }

    public void save (GLib.GenericArray<Tab> tabs, int active) {
        GLib.DirUtils.create_with_parents (Paths.config_dir (), 0700);

        var keyfile = new GLib.KeyFile ();
        keyfile.set_integer (GROUP, KEY_COUNT, (int) tabs.length);
        keyfile.set_integer (GROUP, KEY_ACTIVE, active < 0 ? 0 : active);
        for (uint i = 0; i < tabs.length; i++) {
            var tab = tabs.get (i);
            string group = "tab%u".printf (i);
            keyfile.set_string (group, KEY_KIND, tab.kind);
            keyfile.set_string (group, KEY_VALUE, tab.value);
        }

        size_t length;
        string data = keyfile.to_data (out length);
        if (data == null) {
            return;
        }

        try {
            // Not fsync'd: the session is a convenience, not user data, and it
            // is rewritten on every tab change.
            FileStore.save_atomic (path, data, false);
        } catch (GLib.Error e) {
            GLib.warning ("maha: could not write session \"%s\": %s", path, e.message);
        }
    }

    /** Forget the whole session (used when the last tab is closed). */
    public void clear () {
        FileStore.remove (path);
    }

    private static void load_list (GLib.KeyFile keyfile, State state) {
        if (!keyfile.has_group (GROUP)) {
            return;
        }

        int count = 0;
        try {
            count = keyfile.get_integer (GROUP, KEY_COUNT);
        } catch (GLib.Error e) {
            return;
        }

        for (int i = 0; i < count; i++) {
            string group = "tab%d".printf (i);
            if (!keyfile.has_group (group)) {
                continue;
            }
            try {
                string kind = keyfile.get_string (group, KEY_KIND);
                string value = keyfile.get_string (group, KEY_VALUE);
                if (value != "") {
                    state.tabs.add (new Tab (kind, value));
                }
            } catch (GLib.Error e) {
                // Skip a malformed entry rather than dropping the whole list.
            }
        }

        try {
            state.active = keyfile.get_integer (GROUP, KEY_ACTIVE);
        } catch (GLib.Error e) {
            state.active = 0;
        }
    }

    private static void load_single (GLib.KeyFile keyfile, State state) {
        try {
            string kind = keyfile.get_string (GROUP_LAST, KEY_KIND);
            string value = keyfile.get_string (GROUP_LAST, KEY_VALUE);
            if (value != "") {
                state.tabs.add (new Tab (kind, value));
            }
        } catch (GLib.Error e) {
            // No single-document record.
        }
    }
}

}
