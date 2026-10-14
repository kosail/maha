namespace Maha {

/**
 * Pure in-memory representation of a document.
 *
 * Holds no GTK objects and performs no I/O: it only tracks the file path, the
 * text contents and whether the contents differ from what is on disk.
 *
 * A document without a path is "new": it is backed by a scratch file in the
 * cache directory so its text survives a crash even before it is saved.
 */
public class Document : GLib.Object {
    public string? path { get; set; default = null; }
    public string text { get; set; default = ""; }
    public bool dirty { get; set; default = false; }

    /** Identifier of the backing scratch file, for a path-less document. */
    public string? scratch_id { get; private set; default = null; }

    public Document (string? path = null, string text = "") {
        this.path = path;
        this.text = text;
        if (path == null || path == "") {
            this.scratch_id = GLib.Uuid.string_random ();
        }
    }

    private Document.with_scratch (string id, string text) {
        this.path = null;
        this.text = text;
        this.scratch_id = id;
    }

    /** Rebuild a path-less document backed by an existing scratch file. */
    public static Document restore_scratch (string id, string text) {
        return new Document.with_scratch (id, text);
    }

    public string display_name {
        owned get {
            if (path == null || path == "") {
                return "New tab";
            }
            return GLib.Path.get_basename (path);
        }
    }

    /** Where the autosaver persists this document: its file or its scratch. */
    public string autosave_path {
        owned get {
            if (path != null && path != "") {
                return path;
            }
            return Paths.scratch_file ((!) scratch_id);
        }
    }

    /** True while this document has never been stored to a real file. */
    public bool is_new {
        get {
            return path == null || path == "";
        }
    }

    /** Promote a scratch document to a real file path. */
    public void promote (string new_path) {
        if (new_path == "") {
            return;
        }
        this.path = new_path;
        this.scratch_id = null;
    }
}

}
