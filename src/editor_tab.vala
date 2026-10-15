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

    /**
     * Duplicate the line the cursor is on and insert the copy directly below,
     * leaving the cursor on the new line at the same column (like VS Code's
     * "duplicate line"). A whole operation, so a single undo reverts it.
     */
    public void duplicate_current_line () {
        if (document.read_only) {
            return;
        }

        Gtk.TextBuffer buffer = view.buffer;
        Gtk.TextIter cursor;
        buffer.get_iter_at_mark (out cursor, buffer.get_insert ());
        int line = cursor.get_line ();

        Gtk.TextIter line_start;
        buffer.get_iter_at_line (out line_start, line);
        int column = cursor.get_offset () - line_start.get_offset ();

        Gtk.TextIter tail;
        Gtk.TextIter insert_at;
        int copy_start;
        string text;
        if (buffer.get_iter_at_line (out tail, line + 1)) {
            // The line ends with a newline: copy it verbatim and insert at the
            // start of the following line.
            text = buffer.get_text (line_start, tail, false);
            copy_start = tail.get_offset ();
        } else {
            // The line is the last one and has no trailing newline: add one, so
            // the copy is a separate line rather than appended to the original.
            buffer.get_end_iter (out tail);
            text = "\n" + buffer.get_text (line_start, tail, false);
            copy_start = tail.get_offset () + 1;
        }
        insert_at = tail;

        buffer.begin_user_action ();
        buffer.insert (ref insert_at, text, -1);

        Gtk.TextIter place;
        buffer.get_iter_at_offset (out place, copy_start + column);
        buffer.place_cursor (place);
        buffer.end_user_action ();

        view.scroll_mark_onscreen (buffer.get_insert ());
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
