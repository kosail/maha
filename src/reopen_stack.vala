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
    private const uint MAX_ENTRIES = 32;

    private GLib.Queue<string> paths = new GLib.Queue<string> ();

    public bool is_empty {
        get { return this.paths.is_empty (); }
    }

    /** Record a just-closed file path. */
    public void record (string path) {
        // Never stack the same path twice: drop an existing entry first. The
        // queue's default compare is pointer-based, so compare by value here.
        uint len = this.paths.get_length ();
        for (uint i = 0; i < len; i++) {
            if (this.paths.peek_nth (i) == path) {
                this.paths.pop_nth (i);
                break;
            }
        }
        this.paths.push_head (path);
        // Bound the history so a long session cannot grow it without limit.
        while (this.paths.get_length () > MAX_ENTRIES) {
            this.paths.pop_tail ();
        }
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
