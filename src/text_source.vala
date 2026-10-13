namespace Maha {

/**
 * Supplies the text to persist for a document at save time.
 *
 * Implemented by the editor UI so the autosaver can pull the current contents
 * lazily instead of being handed a copy on every keystroke.
 */
public interface TextSource : GLib.Object {
    public abstract string get_text ();
}

}
