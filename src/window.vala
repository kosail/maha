namespace Maha {

// The Vala binding for libadwaita omits `adw_tab_view_close_page` because its
// name collides with the `close_page` signal. Bind it directly so the window
// can request a close (which re-enters `on_close_page`).
[CCode (cname = "adw_tab_view_close_page")]
extern void tab_view_close_page (Adw.TabView view, Adw.TabPage page);

/**
 * The single application window.
 *
 * Chrome is libadwaita: an `Adw.ToolbarView` whose top bar is an
 * `Adw.HeaderBar` hosting the "Open" button, an `Adw.TabBar` (the tabs) and a
 * "+" new-tab button. Each tab is an `Adw.TabView` page backed by an
 * `EditorTab`. Closing the last tab closes the window.
 */
public class MainWindow : Adw.ApplicationWindow {
    private Config config;
    private AutoSaver auto_saver;
    private SessionStore session;
    private Adw.TabView tab_view;
    private Adw.TabBar tab_bar;
    private Adw.HeaderBar header;
    private Gtk.Label single_title;
    private Adw.ToolbarView toolbar_view;
    private ReopenStack reopen_stack = new ReopenStack ();

    // Coalesce bursts of session-changing signals into a single write.
    private uint session_save_id = 0;
    private const uint SESSION_DEBOUNCE_MS = 500;

    // Suppress session writes while restoring the previous session and while
    // the window is being torn down (page removal fires the same signals).
    private bool restoring = false;
    private bool shutting_down = false;

    // Outcome of a save-failure recovery prompt.
    private enum RecoveryAction { SAVED, DISCARDED, CANCELLED }
    private delegate void SaveAsCallback (bool saved);
    private delegate void RecoveryCallback (RecoveryAction action);

    // State for resolving unsaved tabs before closing the window (quit or the
    // close button). Held as fields, not captured by nested callbacks, so it
    // survives the asynchronous save/recovery dialogs.
    private GLib.GenericArray<EditorTab>? resolve_tabs;
    private GLib.GenericArray<EditorTab>? resolve_discarded;
    private uint resolve_index;
    // Set while a resolved close is queued, so a further close request cannot
    // start a second resolve in the gap before the idle runs.
    private bool close_pending = false;

    // Error messages are shown one at a time; a burst of failures must not
    // stack modal dialogs on top of each other.
    private GLib.Queue<string> pending_messages = new GLib.Queue<string> ();
    private bool message_active = false;

    public MainWindow (Gtk.Application application, Config config, AutoSaver auto_saver, SessionStore session) {
        Object (application: application);
        this.config = config;
        this.auto_saver = auto_saver;
        this.session = session;

        this.add_css_class ("maha");
        this.set_default_size (920, 660);
        this.set_title ("maha");
        this.set_icon_name ("com.korealm.maha");

        this.tab_view = new Adw.TabView ();
        this.tab_view.close_page.connect (on_close_page);
        this.tab_view.page_detached.connect (on_page_detached);
        this.tab_view.notify["selected-page"].connect (() => {
            record_session ();
            update_title_widget ();
        });
        this.tab_view.notify["n-pages"].connect (update_title_widget);

        build_chrome ();
        install_shortcuts ();

        restore_session ();
        update_title_widget ();

        this.close_request.connect (() => {
            // Already confirmed and closing: let it proceed.
            if (this.shutting_down) {
                return false;
            }
            // A close is already being resolved, or a resolved close is queued
            // in the gap before its idle runs; ignore this request rather than
            // starting a second one.
            if (this.close_pending || this.resolve_tabs != null) {
                return true;
            }

            // Fast path: save every dirty tab in place, synchronously. This
            // never calls back into `close_request`, so returning false here is
            // safe (no nested close).
            var tabs = collect_dirty_tabs ();
            uint i = 0;
            while (i < tabs.length) {
                var tab = tabs.get (i);
                if (tab.save_now ()) {
                    i++;
                    continue;
                }
                // A tab could not be written: stop the close and resolve the
                // rest asynchronously (the user may Save As, discard or cancel).
                start_resolve (tabs, i);
                return true;
            }

            mark_shutting_down ();
            return false;
        });
    }

    /** Persist the session and mark the window as closing so teardown does not rewrite it. */
    public void mark_shutting_down () {
        flush_session ();
        this.shutting_down = true;
    }

    public void open_file_dialog () {
        var dialog = new Gtk.FileDialog ();
        dialog.set_title ("Open File");
        dialog.open.begin (this, null, (obj, res) => {
            try {
                var file = dialog.open.end (res);
                if (file == null) {
                    return;
                }
                string? path = file.get_path ();
                if (path == null) {
                    show_message ("Only local files can be opened.");
                    return;
                }
                open_path (path);
            } catch (GLib.Error e) {
                if (!is_dialog_cancelled (e)) {
                    show_message ("Could not open file: %s".printf (e.message));
                }
            }
        });
    }

    /** Open `path` in a tab, focusing it if already open. Returns false on failure. */
    public bool open_path (string path) {
        return open_path_page (path, true) != null;
    }

    /**
     * Open `path`, returning its page (new or already-open), or null when it
     * could not be opened. Binary files are refused (or offered read-only) when
     * `interactive` is set, and skipped silently otherwise (session restore).
     */
    private Adw.TabPage? open_path_page (string path, bool interactive = true) {
        var existing = find_tab_by_path (path);
        if (existing != null) {
            var page = this.tab_view.get_page (existing);
            this.tab_view.set_selected_page (page);
            return page;
        }

        FileStore.ReadResult result;
        try {
            // Skip building the lossy BINARY view: this path only opens text
            // (or offers read-only, which re-reads with the view).
            result = FileStore.read (path, false);
        } catch (GLib.Error e) {
            if (interactive) {
                show_message ("Could not open \"%s\": %s".printf (path, e.message));
            }
            return null;
        }

        if (result.kind == FileStore.ContentKind.BINARY) {
            if (interactive) {
                prompt_open_binary (path);
            }
            return null;
        }

        string? notice = null;
        if (result.kind == FileStore.ContentKind.CORRUPT_TEXT) {
            notice = "Corrupted data was removed; the file is unchanged until you save.";
        }

        return add_tab (new Document (path, result.text), notice);
    }

    /**
     * Tell the user a file is not text and offer to open it read-only, where it
     * can be viewed but never written back over the original.
     */
    private void prompt_open_binary (string path) {
        var dialog = new Adw.AlertDialog (
            "Not a text file",
            "\"%s\" is not plain text, so it cannot be edited. Open it read-only?".printf (GLib.Path.get_basename (path)));
        dialog.add_response ("cancel", "Cancel");
        dialog.add_response ("open", "Open Read-Only");
        dialog.set_response_appearance ("open", Adw.ResponseAppearance.SUGGESTED);
        dialog.set_default_response ("open");
        dialog.set_close_response ("cancel");

        dialog.choose.begin (this, null, (obj, res) => {
            string response = dialog.choose.end (res);
            if (response != "open") {
                return;
            }
            try {
                var result = FileStore.read (path);
                var document = new Document (path, result.text);
                document.read_only = true;
                add_tab (document, "This file is not plain text and is open read-only.");
            } catch (GLib.Error e) {
                show_message ("Could not open \"%s\": %s".printf (path, e.message));
            }
        });
    }

    /** Save the active tab: instant save, or a Save dialog for a new file. */
    public void save_current () {
        var tab = current_tab ();
        if (tab == null) {
            return;
        }
        if (tab.document.read_only) {
            show_message ("This file is open read-only.");
            return;
        }
        if (tab.document.is_new) {
            prompt_save_as (tab);
        } else if (!tab.save_now ()) {
            // The file could not be written in place (read-only, or no write
            // permission on its folder). Offer to save a copy; there is nothing
            // to discard here, since the user explicitly asked to save.
            prompt_save_recovery (tab, false, null);
        }
    }

    /** Create a new empty tab. */
    public void new_tab () {
        add_empty_tab ();
    }

    /** Duplicate the current line in the active tab (Ctrl+D). */
    public void duplicate_line () {
        var tab = current_tab ();
        if (tab != null && !tab.document.read_only) {
            tab.duplicate_current_line ();
        }
    }

    /**
     * Close the pristine, empty "New tab" placeholder, if one is present and
     * other tabs exist. Used when files are opened so a launch that passes a
     * file does not also show an empty tab.
     */
    public void close_placeholder_tab () {
        if (this.tab_view.get_n_pages () <= 1) {
            return;
        }
        int pages = this.tab_view.get_n_pages ();
        for (int i = 0; i < pages; i++) {
            var page = this.tab_view.get_nth_page (i);
            var tab = page.get_child () as EditorTab;
            if (tab != null && tab.document.is_new && !tab.has_unsaved_content ()) {
                tab_view_close_page (this.tab_view, page);
                return;
            }
        }
    }

    /**
     * Close the active tab. Closing the last remaining tab closes the window
     * (and, with it, the application), exactly like the tab's close button.
     */
    public void close_current_tab () {
        var page = this.tab_view.get_selected_page ();
        if (page != null) {
            tab_view_close_page (this.tab_view, page);
        }
    }

    /**
     * Reopen the most recently closed file. Does nothing when there is none.
     * A file that no longer exists falls back to a new empty tab.
     */
    public void reopen_last_closed_tab () {
        var path = this.reopen_stack.pop ();
        if (path == null) {
            return;
        }
        if (GLib.FileUtils.test (path, GLib.FileTest.EXISTS)) {
            open_path (path);
        } else {
            add_empty_tab ();
        }
    }

    /** Every tab with unsaved changes, in view order. */
    private GLib.GenericArray<EditorTab> collect_dirty_tabs () {
        var tabs = new GLib.GenericArray<EditorTab> ();
        int pages = this.tab_view.get_n_pages ();
        for (int i = 0; i < pages; i++) {
            var tab = this.tab_view.get_nth_page (i).get_child () as EditorTab;
            if (tab != null && tab.document.dirty) {
                tabs.add (tab);
            }
        }
        return tabs;
    }

    /**
     * Resolve the unsaved tabs starting at `index`, then close the window once
     * they are all saved or discarded. A cancelled prompt abandons the resolve
     * (the window is kept open).
     */
    private void start_resolve (GLib.GenericArray<EditorTab> tabs, uint index) {
        this.resolve_tabs = tabs;
        this.resolve_discarded = null;
        this.resolve_index = index;
        resolve_step ();
    }

    private void resolve_step () {
        var tabs = this.resolve_tabs;
        if (tabs == null) {
            return;
        }
        uint count = tabs.length;
        while (this.resolve_index < count) {
            var tab = tabs.get (this.resolve_index);
            // A new document saves to its scratch file (always writable); an
            // existing one saves in place and may fail.
            if (!tab.document.dirty || tab.save_now ()) {
                this.resolve_index++;
                continue;
            }
            prompt_save_recovery (tab, true, (action) => {
                if (action == RecoveryAction.CANCELLED) {
                    finish_resolve (false);
                } else {
                    // Remember a discarded tab; it is only actually discarded
                    // once the whole close commits, so an abort elsewhere
                    // leaves its unsaved changes intact.
                    if (action == RecoveryAction.DISCARDED) {
                        if (this.resolve_discarded == null) {
                            this.resolve_discarded = new GLib.GenericArray<EditorTab> ();
                        }
                        this.resolve_discarded.add (tab);
                    }
                    this.resolve_index++;
                    resolve_step ();
                }
            });
            return;
        }
        finish_resolve (true);
    }

    private void finish_resolve (bool proceed) {
        var discarded = this.resolve_discarded;
        this.resolve_tabs = null;
        this.resolve_discarded = null;
        this.resolve_index = 0;

        // A cancelled prompt abandons the close; nothing was mutated during the
        // resolve, so every tab keeps its unsaved changes.
        if (!proceed) {
            return;
        }

        // Apply the discards only now that the close is certain: cancel each
        // tab's pending autosave so it cannot resurrect the discarded file.
        if (discarded != null) {
            for (uint i = 0; i < discarded.length; i++) {
                discarded.get (i).discard_scratch ();
            }
        }

        // Defer the close to an idle tick. If every remaining save completed
        // without a prompt, we would otherwise call close() while still inside
        // the close-request signal emission, re-entering it. `close_pending`
        // rejects any close request that arrives before this idle runs.
        this.close_pending = true;
        GLib.Idle.add (() => {
            this.close_pending = false;
            if (!this.shutting_down) {
                mark_shutting_down ();
                this.close ();
            }
            return GLib.Source.REMOVE;
        });
    }

    public void show_message (string message) {
        this.pending_messages.push_tail (message);
        if (!this.message_active) {
            show_next_message ();
        }
    }

    private void show_next_message () {
        // Never raise a dialog once the window is tearing down.
        if (this.shutting_down || this.pending_messages.is_empty ()) {
            this.message_active = false;
            return;
        }
        this.message_active = true;
        string text = this.pending_messages.pop_head ();
        var dialog = new Adw.AlertDialog ("Heads up", text);
        dialog.add_response ("ok", "OK");
        dialog.set_default_response ("ok");
        dialog.set_close_response ("ok");
        dialog.choose.begin (this, null, (obj, res) => {
            dialog.choose.end (res);
            show_next_message ();
        });
    }

    /**
     * Save the tab to a file, reporting success through `on_finished` (when
     * provided). Used for a brand-new document, and to save a copy elsewhere
     * when an in-place save failed.
     */
    private void prompt_save_as (EditorTab tab, owned SaveAsCallback? on_finished = null) {
        var dialog = new Gtk.FileDialog ();
        dialog.set_title ("Save File");
        dialog.set_accept_label ("Save");
        dialog.set_initial_name (tab.document.is_new ? "untitled.txt" : tab.document.display_name);
        dialog.save.begin (this, null, (obj, res) => {
            bool saved = false;
            try {
                var file = dialog.save.end (res);
                if (file != null) {
                    string? path = file.get_path ();
                    if (path == null) {
                        show_message ("Only local files can be saved.");
                    } else {
                        var other = find_tab_by_path (path);
                        if (other != null && other != tab) {
                            show_message ("\"%s\" is already open in another tab.".printf (path));
                        } else if (!tab.save_as (path)) {
                            show_message ("Could not save \"%s\".".printf (path));
                        } else {
                            var page = this.tab_view.get_page (tab);
                            if (page != null) {
                                page.set_title (trim_title (tab.document.display_name));
                            }
                            update_title_widget ();
                            record_session ();
                            saved = true;
                        }
                    }
                }
            } catch (GLib.Error e) {
                if (!is_dialog_cancelled (e)) {
                    show_message ("Could not save file: %s".printf (e.message));
                }
            }

            if (on_finished != null) {
                on_finished (saved);
            }
        });
    }

    /**
     * Offer a way out when a file could not be written in place (read-only, or
     * no permission on its folder): save a copy elsewhere, discard the changes,
     * or cancel. `allow_discard` is false for an explicit Save, where there is
     * nothing to discard.
     */
    private void prompt_save_recovery (EditorTab tab, bool allow_discard, owned RecoveryCallback? on_result) {
        var dialog = new Adw.AlertDialog (
            "Couldn't save changes",
            "Couldn't save \"%s\". It may be read-only, or you may not have permission to write in its folder.".printf (tab.document.display_name));
        dialog.add_response ("cancel", "Cancel");
        if (allow_discard) {
            dialog.add_response ("discard", "Discard Changes");
        }
        dialog.add_response ("save-as", "Save As…");
        dialog.set_response_appearance ("save-as", Adw.ResponseAppearance.SUGGESTED);
        if (allow_discard) {
            dialog.set_response_appearance ("discard", Adw.ResponseAppearance.DESTRUCTIVE);
        }
        dialog.set_default_response ("save-as");
        dialog.set_close_response ("cancel");

        dialog.choose.begin (this, null, (obj, res) => {
            string response = dialog.choose.end (res);

            if (response == "save-as") {
                prompt_save_as (tab, (saved) => {
                    if (on_result != null) {
                        on_result (saved ? RecoveryAction.SAVED : RecoveryAction.CANCELLED);
                    }
                });
            } else if (response == "discard") {
                if (on_result != null) {
                    on_result (RecoveryAction.DISCARDED);
                }
            } else {
                if (on_result != null) {
                    on_result (RecoveryAction.CANCELLED);
                }
            }
        });
    }

    /**
     * Ask what to do with a new tab that has unsaved content before closing it.
     * Finishes the close asynchronously.
     */
    private void prompt_close_unsaved (EditorTab tab, Adw.TabPage page) {
        var dialog = new Adw.AlertDialog (
            "Save changes?",
            "This tab has unsaved changes. Save them before closing?");
        dialog.add_response ("cancel", "Cancel");
        dialog.add_response ("discard", "Discard");
        dialog.add_response ("save", "Save");
        dialog.set_response_appearance ("save", Adw.ResponseAppearance.SUGGESTED);
        dialog.set_response_appearance ("discard", Adw.ResponseAppearance.DESTRUCTIVE);
        dialog.set_default_response ("save");
        dialog.set_close_response ("cancel");

        dialog.choose.begin (this, null, (obj, res) => {
            string response = dialog.choose.end (res);

            if (response == "save") {
                prompt_save_as (tab, (saved) => {
                    if (saved) {
                        record_closed_tab (tab.document);
                    }
                    this.tab_view.close_page_finish (page, saved);
                });
            } else if (response == "discard") {
                tab.discard_scratch ();
                this.tab_view.close_page_finish (page, true);
            } else {
                this.tab_view.close_page_finish (page, false);
            }
        });
    }

    private void install_shortcuts () {
        var controller = new Gtk.ShortcutController ();
        controller.set_scope (Gtk.ShortcutScope.GLOBAL);
        controller.add_shortcut (make_shortcut ("<Control>t", "app.new"));
        controller.add_shortcut (make_shortcut ("<Control>n", "app.new"));
        controller.add_shortcut (make_shortcut ("<Control>o", "app.open"));
        controller.add_shortcut (make_shortcut ("<Control>s", "app.save"));
        controller.add_shortcut (make_shortcut ("<Control>w", "app.close-tab"));
        controller.add_shortcut (make_shortcut ("<Control>d", "app.duplicate-line"));
        controller.add_shortcut (make_shortcut ("<Control><Shift>t", "app.reopen-tab"));
        controller.add_shortcut (make_shortcut ("<Control>q", "app.quit"));
        // Runtime font zoom (app-wide, not persisted). Ctrl+= (no shift) and
        // Ctrl++ (shift) both zoom in, plus the keypad keys.
        controller.add_shortcut (make_shortcut ("<Control>plus", "app.zoom-in"));
        controller.add_shortcut (make_shortcut ("<Control>equal", "app.zoom-in"));
        controller.add_shortcut (make_shortcut ("<Control>KP_Add", "app.zoom-in"));
        controller.add_shortcut (make_shortcut ("<Control>minus", "app.zoom-out"));
        controller.add_shortcut (make_shortcut ("<Control>KP_Subtract", "app.zoom-out"));
        controller.add_shortcut (make_shortcut ("<Control>0", "app.zoom-reset"));

        // Bind to Gtk.Widget.add_controller, which is transfer-full (owned).
        // MainWindow also implements Gtk.ShortcutManager, whose add_controller
        // binding is *not* owned; if Vala resolves this call against that
        // overload, the freshly added controller is unreffed and freed while
        // the window still references it, segfaulting on the first shortcut.
        // Calling through a Gtk.Widget-typed reference forces the owned overload.
        Gtk.Widget widget = this;
        widget.add_controller (controller);
    }

    private static Gtk.Shortcut make_shortcut (string accelerator, string action) {
        return new Gtk.Shortcut (Gtk.ShortcutTrigger.parse_string (accelerator), new Gtk.NamedAction (action));
    }

    private void build_chrome () {
        // Tabs behave exactly like the libadwaita sample: an Adw.TabBar as the
        // header bar's title widget. `.inline` removes the tab bar's own
        // background so it shares the window transparency.
        this.tab_bar = new Adw.TabBar ();
        this.tab_bar.set_view (this.tab_view);
        this.tab_bar.add_css_class ("inline");
        // Keep the tab strip revealed even with a single tab. libadwaita's
        // default (autohide) collapses it when there is only one tab, which
        // makes the header bar shorter and shifts the content when a second
        // tab is opened.
        this.tab_bar.set_autohide (false);

        // With a single tab the header shows a plain filename label instead of
        // the tab strip; with two or more it shows the tab strip. The title
        // widget is swapped directly (Adw.HeaderBar supports this at runtime).
        this.single_title = new Gtk.Label ("");
        this.single_title.add_css_class ("maha-single-title");
        this.single_title.set_ellipsize (Pango.EllipsizeMode.NONE);

        this.header = new Adw.HeaderBar ();

        var open_content = new Adw.ButtonContent ();
        open_content.set_icon_name ("folder-open-symbolic");
        open_content.set_label ("Open");
        var open_button = new Gtk.Button ();
        open_button.set_child (open_content);
        open_button.set_tooltip_text ("Open file (Ctrl+O)");
        open_button.clicked.connect (() => open_file_dialog ());
        this.header.pack_start (open_button);

        // Plain flat "+" on the right of the header bar.
        var new_button = new Gtk.Button.from_icon_name ("tab-new-symbolic");
        new_button.set_tooltip_text ("New tab (Ctrl+T, Ctrl+N)");
        new_button.clicked.connect (() => add_empty_tab ());
        this.header.pack_end (new_button);

        this.header.set_title_widget (this.tab_bar);

        this.toolbar_view = new Adw.ToolbarView ();
        this.toolbar_view.add_top_bar (this.header);
        this.toolbar_view.set_content (this.tab_view);
        this.set_content (this.toolbar_view);
    }

    /**
     * Handle a close request for a tab. New tabs are prompted when they have
     * content and otherwise dropped; existing files are saved in place when
     * modified, falling back to a recovery prompt if the write fails. Either
     * prompt finishes the close asynchronously.
     */
    private bool on_close_page (Adw.TabPage page) {
        var tab = page.get_child () as EditorTab;
        if (tab == null) {
            this.tab_view.close_page_finish (page, true);
            return true;
        }

        if (tab.document.is_new) {
            if (tab.has_unsaved_content ()) {
                prompt_close_unsaved (tab, page);
            } else {
                tab.discard_scratch ();
                this.tab_view.close_page_finish (page, true);
            }
            return true;
        }

        if (!tab.document.dirty) {
            record_closed_tab (tab.document);
            this.tab_view.close_page_finish (page, true);
            return true;
        }

        if (tab.save_now ()) {
            record_closed_tab (tab.document);
            this.tab_view.close_page_finish (page, true);
        } else {
            prompt_save_recovery (tab, true, (action) => {
                if (action == RecoveryAction.DISCARDED) {
                    tab.discard_scratch ();
                }
                if (action != RecoveryAction.CANCELLED) {
                    record_closed_tab (tab.document);
                }
                this.tab_view.close_page_finish (page, action != RecoveryAction.CANCELLED);
            });
        }
        return true;
    }

    /** Remember a just-closed file so Ctrl+Shift+T can reopen it. */
    private void record_closed_tab (Document document) {
        if (!document.is_new && !document.read_only) {
            this.reopen_stack.record ((!) document.path);
        }
    }

    private void on_page_detached (Adw.TabPage page, int position) {
        record_session ();
        if (this.tab_view.get_n_pages () == 0) {
            this.close ();
        }
    }

    private void restore_session () {
        this.restoring = true;

        var state = this.session.load ();
        Adw.TabPage? active_page = null;

        for (uint i = 0; i < state.tabs.length; i++) {
            var entry = state.tabs.get (i);
            Adw.TabPage? page = restore_tab (entry);
            if (page != null && (int) i == state.active) {
                active_page = page;
            }
        }

        this.restoring = false;

        if (this.tab_view.get_n_pages () == 0) {
            add_empty_tab ();
        } else if (active_page != null) {
            this.tab_view.set_selected_page (active_page);
        }

        record_session ();
    }

    private Adw.TabPage? restore_tab (SessionStore.Tab entry) {
        if (entry.kind == SessionStore.KIND_FILE) {
            if (!GLib.FileUtils.test (entry.value, GLib.FileTest.EXISTS)) {
                return null;
            }
            return open_path_page (entry.value, false);
        }

        if (!Paths.is_safe_scratch_id (entry.value)) {
            return null;
        }
        string scratch = Paths.scratch_file (entry.value);
        if (!GLib.FileUtils.test (scratch, GLib.FileTest.EXISTS)) {
            return null;
        }
        try {
            var result = FileStore.read (scratch);
            if (result.kind == FileStore.ContentKind.BINARY) {
                return null;
            }
            string? notice = result.kind == FileStore.ContentKind.CORRUPT_TEXT
                ? "Corrupted data was removed; the file is unchanged until you save."
                : null;
            return add_tab (Document.restore_scratch (entry.value, result.text), notice);
        } catch (GLib.Error e) {
            GLib.warning ("maha: could not restore scratch \"%s\": %s", scratch, e.message);
            return null;
        }
    }

    private EditorTab? current_tab () {
        var page = this.tab_view.get_selected_page ();
        if (page == null) {
            return null;
        }
        return page.get_child () as EditorTab;
    }

    private EditorTab? find_tab_by_path (string path) {
        // Stat the query once, then each tab once (symlinks/hardlinks included).
        Posix.Stat target;
        bool have_target = Posix.stat (path, out target) == 0;

        int pages = this.tab_view.get_n_pages ();
        for (int i = 0; i < pages; i++) {
            var tab = this.tab_view.get_nth_page (i).get_child () as EditorTab;
            if (tab == null || tab.document.path == null) {
                continue;
            }
            string tab_path = (!) tab.document.path;
            if (tab_path == path) {
                return tab;
            }
            if (!have_target) {
                continue;
            }
            Posix.Stat st;
            if (Posix.stat (tab_path, out st) == 0 && st.st_dev == target.st_dev && st.st_ino == target.st_ino) {
                return tab;
            }
        }
        return null;
    }

    /** Schedule a session write, coalescing bursts of signals into one. */
    private void record_session () {
        if (this.restoring || this.shutting_down) {
            return;
        }
        if (this.session_save_id != 0) {
            return;
        }
        this.session_save_id = GLib.Timeout.add (SESSION_DEBOUNCE_MS, () => {
            this.session_save_id = 0;
            write_session ();
            return GLib.Source.REMOVE;
        });
    }

    /** Write the session immediately, cancelling any pending debounced write. */
    public void flush_session () {
        if (this.session_save_id != 0) {
            GLib.Source.remove (this.session_save_id);
            this.session_save_id = 0;
        }
        write_session ();
    }

    /** Persist the list of open tabs and the active index for next launch. */
    private void write_session () {
        if (this.shutting_down) {
            return;
        }

        var tabs = new GLib.GenericArray<SessionStore.Tab> ();
        var selected = this.tab_view.get_selected_page ();
        int pages = this.tab_view.get_n_pages ();
        // 0 is the fallback when the selected page is a skipped read-only tab.
        int active = 0;

        for (int i = 0; i < pages; i++) {
            var page = this.tab_view.get_nth_page (i);
            var tab = page.get_child () as EditorTab;
            if (tab == null || tab.document.read_only) {
                continue;
            }
            if (tab.document.is_new) {
                tabs.add (new SessionStore.Tab (SessionStore.KIND_SCRATCH, (!) tab.document.scratch_id));
            } else {
                tabs.add (new SessionStore.Tab (SessionStore.KIND_FILE, (!) tab.document.path));
            }
            if (page == selected) {
                active = tabs.length - 1;
            }
        }

        if (tabs.length == 0) {
            this.session.clear ();
            return;
        }
        this.session.save (tabs, active);
    }

    private void add_empty_tab () {
        add_tab (new Document (null, ""));
    }

    private Adw.TabPage add_tab (Document document, string? notice = null) {
        var tab = new EditorTab (document, this.auto_saver, notice);
        var page = this.tab_view.append (tab);
        page.set_title (trim_title (document.display_name));
        this.tab_view.set_selected_page (page);
        return page;
    }

    /**
     * Show the tab strip when there are two or more tabs, and a plain centered
     * filename (no tab chrome) when there is a single tab.
     */
    private void update_title_widget () {
        if (this.tab_view.get_n_pages () > 1) {
            this.header.set_title_widget (this.tab_bar);
            return;
        }
        var tab = current_tab ();
        this.single_title.set_text (tab != null ? trim_title (tab.document.display_name) : "");
        this.header.set_title_widget (this.single_title);
    }

    /**
     * Truncate a title to 64 characters, appending an ellipsis when it is
     * longer, so a long filename never dominates the header. The title is first
     * coerced to valid UTF-8 (filenames are arbitrary bytes on Linux) and the
     * scan is bounded by the byte length.
     */
    private static string trim_title (string title) {
        string clean = title.validate () ? title : title.make_valid ();
        const int max_chars = 64;
        if (clean.char_count () <= max_chars) {
            return clean;
        }

        long length = clean.length;
        long bytes = 0;
        int chars = 0;
        while (chars < max_chars && bytes < length) {
            uint8 b = (uint8) clean[bytes];
            long step;
            if (b < 0x80) {
                step = 1;
            } else if (b < 0xE0) {
                step = 2;
            } else if (b < 0xF0) {
                step = 3;
            } else {
                step = 4;
            }
            if (bytes + step > length) {
                break;
            }
            bytes += step;
            chars++;
        }
        return clean.substring (0, bytes) + "...";
    }

    private static bool is_dialog_cancelled (GLib.Error e) {
        return e.matches (Gtk.DialogError.quark (), Gtk.DialogError.DISMISSED)
            || e.matches (Gtk.DialogError.quark (), Gtk.DialogError.CANCELLED);
    }
}

}
