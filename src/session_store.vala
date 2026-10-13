namespace Maha {

/**
 * Remembers the document that was active during the previous run so maha can
 * restore it: either a real file or an unsaved "New tab" backed by a scratch
 * file in the cache directory.
 *
 * Stored as a small INI file; a legacy plain-path session file is still
 * understood so upgrades do not lose the last opened file.
 */
public class SessionStore : GLib.Object {
    private const string GROUP = "last";
    private const string KEY_KIND = "kind";
    private const string KEY_VALUE = "value";
    private const string KIND_FILE = "file";
    private const string KIND_SCRATCH = "scratch";

    public string path { get; private set; }

    public SessionStore (string? path = null) {
        this.path = path ?? Paths.session_file ();
    }

    /** The last opened real file, or null. */
    public string? load_last_file () {
        string? kind;
        string? value;
        load (out kind, out value);
        return kind == KIND_FILE ? value : null;
    }

    /** The scratch id of the last unsaved "New tab", or null. */
    public string? load_last_scratch () {
        string? kind;
        string? value;
        load (out kind, out value);
        return kind == KIND_SCRATCH ? value : null;
    }

    public void save_last_file (string? file) {
        if (file == null || file == "") {
            return;
        }
        save (KIND_FILE, file);
    }

    public void save_last_scratch (string id) {
        if (id == "") {
            return;
        }
        save (KIND_SCRATCH, id);
    }

    /** Forget the last document (used when the last tab is closed). */
    public void clear () {
        FileStore.remove (path);
    }

    private void load (out string? kind, out string? value) {
        kind = null;
        value = null;

        if (!GLib.FileUtils.test (path, GLib.FileTest.EXISTS)) {
            return;
        }

        string contents;
        try {
            GLib.FileUtils.get_contents (path, out contents);
        } catch (GLib.Error e) {
            return;
        }

        bool parsed = false;
        var keyfile = new GLib.KeyFile ();
        try {
            parsed = keyfile.load_from_data (contents, contents.length, GLib.KeyFileFlags.NONE);
        } catch (GLib.Error e) {
            parsed = false;
        }

        if (parsed) {
            try {
                string k = keyfile.get_string (GROUP, KEY_KIND);
                string v = keyfile.get_string (GROUP, KEY_VALUE);
                if (v != "") {
                    kind = k;
                    value = v;
                }
            } catch (GLib.Error e) {
                // treat as empty
            }
            return;
        }

        // Backward compatibility: a legacy session file holds a bare path.
        string trimmed = contents.strip ();
        if (trimmed != "") {
            kind = KIND_FILE;
            value = trimmed;
        }
    }

    private void save (string kind, string value) {
        GLib.DirUtils.create_with_parents (Paths.config_dir (), 0700);

        var keyfile = new GLib.KeyFile ();
        keyfile.set_string (GROUP, KEY_KIND, kind);
        keyfile.set_string (GROUP, KEY_VALUE, value);

        size_t length;
        string data = keyfile.to_data (out length);
        if (data == null) {
            return;
        }

        try {
            FileStore.save_atomic (path, data);
        } catch (GLib.Error e) {
            GLib.warning ("maha: could not write session \"%s\": %s", path, e.message);
        }
    }
}

}
