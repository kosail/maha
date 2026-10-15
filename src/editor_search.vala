namespace Maha {

/**
 * In-document search for one editor tab: a hidden `Gtk.SearchBar` embedded at
 * the top of the tab and bound to that tab's text view.
 *
 * It searches the live buffer case-insensitively with wrap-around, selects the
 * current match (so the highlight is the theme's own selection colour - nothing
 * is hard-coded), and counts the matches to show an `i/N` counter. There is no
 * replace and no tag-based highlighting.
 *
 * Everything runs on the main loop; the only asynchrony is the search entry's
 * own debounce, which is main-loop safe. Connections use method handlers so
 * Vala emits g_signal_connect_object (weak) - no reference cycles.
 */
public class EditorSearch : GLib.Object {
    /** The search bar widget, embedded at the top of the tab. */
    public Gtk.SearchBar bar { get; private set; }

    private Gtk.TextView view;
    private Gtk.SearchEntry entry;
    private Gtk.Label counter;

    /** Upper bound on the matches counted, so a pathological query cannot stall. */
    private const uint MAX_MATCHES = 10000;
    private const Gtk.TextSearchFlags FLAGS = Gtk.TextSearchFlags.CASE_INSENSITIVE;

    private uint match_total = 0;
    private uint match_index = 0;
    private bool truncated = false;

    public EditorSearch (Gtk.TextView view) {
        this.view = view;

        this.entry = new Gtk.SearchEntry ();
        this.entry.set_placeholder_text ("Search");

        this.counter = new Gtk.Label ("");
        this.counter.add_css_class ("dim-label");

        var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
        box.append (this.entry);
        box.append (this.counter);

        this.bar = new Gtk.SearchBar ();
        this.bar.set_child (box);
        this.bar.set_show_close_button (true);
        // Binds the entry to the bar: Escape hides the bar, and while it is
        // open keystrokes are routed to the entry instead of the document.
        this.bar.connect_entry (this.entry);

        this.entry.search_changed.connect (on_search_changed);
        this.entry.next_match.connect (on_next_match);
        // Covers every way the bar can leave search mode (Escape, the close
        // button, our own close()), so focus always returns to the editor.
        this.bar.notify["search-mode-enabled"].connect (on_search_mode_changed);
        // Keep the counter honest if the document is edited while the bar is
        // open (possible by mouse, since the keyboard is captured).
        this.view.buffer.changed.connect (on_buffer_changed);
    }

    /** True while the search bar is revealed. */
    public bool active {
        get {
            return this.bar.get_search_mode ();
        }
    }

    /** Reveal the bar and focus its entry. */
    public void open () {
        this.bar.set_search_mode (true);
        this.entry.grab_focus ();
        this.entry.select_region (0, -1);
        if (this.entry.get_text () != "") {
            do_search (true);
        }
    }

    /** Hide the bar. Focus is restored by `on_search_mode_changed`. */
    public void close () {
        this.bar.set_search_mode (false);
    }

    /** Show the bar if hidden, hide it if shown. */
    public void toggle () {
        if (active) {
            close ();
        } else {
            open ();
        }
    }

    private Gtk.TextBuffer get_buffer () {
        return this.view.buffer;
    }

    private void on_search_mode_changed () {
        if (!this.bar.get_search_mode ()) {
            // Grabbing focus on a hidden tab is a harmless no-op.
            this.view.grab_focus ();
        }
    }

    private void on_search_changed () {
        if (this.entry.get_text () == "") {
            this.counter.set_text ("");
            return;
        }
        do_search (true);
    }

    private void on_next_match () {
        if (this.entry.get_text () == "") {
            return;
        }
        do_search (false);
    }

    private void on_buffer_changed () {
        if (!active) {
            return;
        }
        string query = this.entry.get_text ();
        if (query == "") {
            return;
        }
        // Only refresh the counter; never move the selection (and this cannot
        // recurse, because selecting/scrolling does not emit `changed`).
        int start = 0;
        Gtk.TextIter sel_start, sel_end;
        if (get_buffer ().get_selection_bounds (out sel_start, out sel_end)) {
            start = sel_start.get_offset ();
        }
        count_matches (query, start);
    }

    /**
     * Find a match and select it.
     *
     * `from_cursor` starts from the insertion point (used when the query
     * changes); otherwise the search continues from the end of the current
     * selection (used for Enter / next).
     */
    private void do_search (bool from_cursor) {
        Gtk.TextBuffer buffer = get_buffer ();
        string query = this.entry.get_text ();
        if (query == "") {
            return;
        }

        // Default to the insertion point; when continuing, start at the end of
        // the current selection instead.
        Gtk.TextIter start;
        buffer.get_iter_at_mark (out start, buffer.get_insert ());
        if (!from_cursor) {
            Gtk.TextIter sel_start, sel_end;
            if (buffer.get_selection_bounds (out sel_start, out sel_end)) {
                start = sel_end;
            }
        }

        Gtk.TextIter ms, me;
        if (find_from (start, query, out ms, out me)) {
            buffer.select_range (ms, me);
            this.view.scroll_to_mark (buffer.get_insert (), 0.1, false, 0.0, 0.0);
            count_matches (query, ms.get_offset ());
        } else {
            this.match_total = 0;
            this.match_index = 0;
            this.truncated = false;
            update_counter ();
        }
    }

    /** Forward search from `start`, wrapping to the top when nothing follows. */
    private bool find_from (Gtk.TextIter start, string query, out Gtk.TextIter ms, out Gtk.TextIter me) {
        Gtk.TextIter s = start;
        if (s.forward_search (query, FLAGS, out ms, out me, null)) {
            return true;
        }
        Gtk.TextIter begin;
        get_buffer ().get_start_iter (out begin);
        return begin.forward_search (query, FLAGS, out ms, out me, start);
    }

    /** Count all matches (bounded) and the 1-based index of the current one. */
    private void count_matches (string query, int current_start) {
        Gtk.TextIter iter;
        get_buffer ().get_start_iter (out iter);
        Gtk.TextIter ms = iter;
        Gtk.TextIter me = iter;
        uint n = 0;
        uint i = 0;
        while (n < MAX_MATCHES && iter.forward_search (query, FLAGS, out ms, out me, null)) {
            n++;
            if (ms.get_offset () == current_start) {
                i = n;
            }
            iter = me;
        }
        this.match_total = n;
        this.match_index = i;
        this.truncated = (n >= MAX_MATCHES);
        update_counter ();
    }

    private void update_counter () {
        if (this.entry.get_text () == "") {
            this.counter.set_text ("");
            return;
        }
        this.counter.set_text ("%u/%u%s".printf (this.match_index, this.match_total, this.truncated ? "+" : ""));
    }
}

}
