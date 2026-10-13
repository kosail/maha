namespace Maha {

/**
 * One editor tab: a plain text view bound to a `Document`, plus its own tab
 * label.
 *
 * Keystrokes mark the document dirty and arm the debounced `AutoSaver`, which
 * pulls the live text from this tab only when it actually saves (to the real
 * file, or to the scratch store for a new document). No syntax highlighting,
 * tags or markup are used.
 */
public class EditorTab : Gtk.Box, TextSource {
    public Document document { get; private set; }
    public Gtk.TextView view { get; private set; }

    private AutoSaver auto_saver;
    private bool loading = false;

    public EditorTab (Document document, AutoSaver auto_saver) {
        Object (orientation: Gtk.Orientation.VERTICAL);
        this.document = document;
        this.auto_saver = auto_saver;

        this.view = new Gtk.TextView ();
        this.view.set_wrap_mode (Gtk.WrapMode.WORD_CHAR);
        this.view.set_left_margin (8);
        this.view.set_right_margin (8);
        this.view.set_top_margin (8);
        this.view.set_bottom_margin (8);
        this.view.add_css_class ("maha-editor");

        this.loading = true;
        this.view.buffer.text = document.text;
        this.view.buffer.set_modified (false);
        this.loading = false;

        this.view.buffer.changed.connect (on_changed);

        var scroller = new Gtk.ScrolledWindow ();
        scroller.set_hexpand (true);
        scroller.set_vexpand (true);
        scroller.set_child (this.view);
        this.append (scroller);
    }

    /** The live text of this tab, pulled lazily by the autosaver. */
    public string get_text () {
        return view.buffer.text;
    }

    /** Persist the current contents (to the file, or the scratch store). */
    public bool save_now () {
        if (!auto_saver.flush (document)) {
            return false;
        }
        view.buffer.set_modified (false);
        return true;
    }

    /**
     * Store the contents to a real file (Save / Save As) and promote the
     * document out of scratch mode. Returns false on failure.
     */
    public bool save_as (string path) {
        string text = view.buffer.text;
        string? scratch = document.is_new ? document.autosave_path : null;

        try {
            FileStore.save_atomic (path, text);
        } catch (GLib.Error e) {
            GLib.warning ("maha: could not save \"%s\": %s", path, e.message);
            return false;
        }

        auto_saver.cancel (document);
        document.text = text;
        document.dirty = false;
        document.promote (path);
        view.buffer.set_modified (false);

        if (scratch != null && scratch != path) {
            FileStore.remove (scratch);
        }

        return true;
    }

    private void on_changed () {
        if (loading) {
            return;
        }
        document.dirty = true;
        auto_saver.schedule (document, this);
    }
}

}
