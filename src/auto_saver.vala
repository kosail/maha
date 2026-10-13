namespace Maha {

/**
 * Debounced persistence for documents.
 *
 * Whenever a document changes, `schedule()` (re)arms a timer. When the timer
 * fires the current text is pulled from the registered `TextSource` and written
 * atomically through `FileStore`. A `flush()` (Ctrl+S or shutdown) writes
 * immediately and cancels the timer.
 *
 * Text is pulled lazily at save time, so editing a large document does not copy
 * the whole buffer on every keystroke. No GTK dependency: only a running GLib
 * main loop is required.
 */
public class AutoSaver : GLib.Object {
    public uint debounce_ms { get; set; default = 1500; }

    private class Entry : GLib.Object {
        public uint source_id;
        public TextSource source;
    }

    private GLib.HashTable<Document, Entry> entries;

    public AutoSaver (uint debounce_ms = 1500) {
        this.debounce_ms = debounce_ms;
        this.entries = new GLib.HashTable<Document, Entry> (GLib.direct_hash, GLib.direct_equal);
    }

    /** Arm (or re-arm) the debounce timer for `document`. */
    public void schedule (Document document, TextSource source) {
        cancel (document);

        var entry = new Entry ();
        entry.source = source;
        entry.source_id = GLib.Timeout.add (debounce_ms, () => {
            entries.remove (document);
            save (document, source);
            return GLib.Source.REMOVE;
        });
        entries.insert (document, entry);
    }

    /** Cancel any pending save for `document`. */
    public void cancel (Document document) {
        Entry? entry = entries.lookup (document);
        if (entry != null) {
            GLib.Source.remove (entry.source_id);
            entries.remove (document);
        }
    }

    /**
     * Write `document` immediately.
     *
     * @return true when the document was saved or had nothing to save.
     */
    public bool flush (Document document) {
        Entry? entry = entries.lookup (document);
        if (entry != null) {
            return save (document, entry.source);
        }
        return save (document, null);
    }

    private bool save (Document document, TextSource? source) {
        cancel (document);

        if (!document.dirty) {
            return true;
        }

        if (source != null) {
            document.text = source.get_text ();
        }

        // New documents are backed by a scratch file; make sure its directory
        // exists before the atomic write.
        if (document.is_new && GLib.DirUtils.create_with_parents (Paths.cache_dir (), 0700) != 0) {
            GLib.warning ("maha: could not create cache dir \"%s\"", Paths.cache_dir ());
            return false;
        }

        string path = document.autosave_path;
        try {
            FileStore.save_atomic (path, document.text);
            document.dirty = false;
            return true;
        } catch (GLib.Error e) {
            GLib.warning ("maha: failed to autosave \"%s\": %s", path, e.message);
            return false;
        }
    }
}

}
