namespace Maha {

/**
 * In-memory LIFO stack of file-backed tabs closed during the current session,
 * used by "reopen closed tab" (Ctrl+Shift+T).
 *
 * Only real files are remembered: an unsaved tab is resolved by the close
 * prompt (Save/Discard/Cancel), and a discarded one is gone for good. Nothing
 * is persisted, so the history is lost when the app exits.
 */
public class ReopenStack : GLib.Object {
    private GLib.Queue<string> paths = new GLib.Queue<string> ();

    public bool is_empty {
        get { return this.paths.is_empty (); }
    }

    /** Record a just-closed file path. */
    public void record (string path) {
        this.paths.push_head (path);
    }

    /** Pop the most recently closed path, or null when the history is empty. */
    public string? pop () {
        if (this.paths.is_empty ()) {
            return null;
        }
        return this.paths.pop_head ();
    }

    ~ReopenStack () {
        while (!this.paths.is_empty ()) {
            this.paths.pop_head ();
        }
    }
}

}
