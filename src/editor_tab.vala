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

    public EditorTab (Document document, AutoSaver auto_saver, string? notice = null) {
        Object (orientation: Gtk.Orientation.VERTICAL);
        this.document = document;
        this.auto_saver = auto_saver;

        this.view = new Gtk.TextView ();
        this.view.set_wrap_mode (Gtk.WrapMode.WORD_CHAR);
        this.view.set_left_margin (12);
        this.view.set_right_margin (12);
        this.view.set_top_margin (12);
        this.view.set_bottom_margin (12);
        this.view.add_css_class ("maha-editor");

        if (document.read_only) {
            this.view.set_editable (false);
            this.view.set_cursor_visible (false);
        }

        this.loading = true;
        this.view.buffer.text = document.text;
        this.view.buffer.set_modified (false);
        this.loading = false;

        this.view.buffer.changed.connect (on_changed);

        // Keep GTK's "modified since last save" flag and the document's dirty
        // flag in lockstep. Whenever the document is persisted (manually or by
        // the autosaver), clear the buffer's modified state, so that undoing
        // back to the saved text reports the document as clean.
        this.document.notify["dirty"].connect (() => {
            if (!this.document.dirty) {
                this.view.buffer.set_modified (false);
            }
        });

        if (notice != null) {
            var banner = new Adw.Banner ((!) notice);
            banner.set_revealed (true);
            banner.set_button_label ("Dismiss");
            banner.button_clicked.connect (() => banner.set_revealed (false));
            this.append (banner);
        }

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

    /** True when this is a path-less document with content never saved to a file. */
    public bool has_unsaved_content () {
        return document.is_new && view.buffer.get_char_count () > 0;
    }

    /** Delete this document's scratch file, if it has one. */
    public void discard_scratch () {
        // Cancel the pending autosave first: otherwise the debounce timer would
        // fire after the file is gone and recreate the scratch file.
        auto_saver.cancel (document);
        document.dirty = false;
        if (document.is_new && document.scratch_id != null) {
            FileStore.remove (Paths.scratch_file ((!) document.scratch_id));
        }
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
        if (document.read_only) {
            return false;
        }

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
        if (loading || document.read_only) {
            return;
        }
        // Mirror GTK's own modified state (it resets to false when the buffer
        // returns to the last saved text); do not force dirty on every change,
        // or an undo back to the original would still count as unsaved.
        document.dirty = view.buffer.get_modified ();
        if (document.dirty) {
            auto_saver.schedule (document, this);
        } else {
            auto_saver.cancel (document);
        }
    }
}

}
