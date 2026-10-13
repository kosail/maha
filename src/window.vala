namespace Maha {

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
    private ThemeController theme;
    private Adw.TabView tab_view;
    private Adw.TabBar tab_bar;
    private Adw.ToolbarView toolbar_view;

    public MainWindow (Gtk.Application application, Config config, AutoSaver auto_saver, SessionStore session) {
        Object (application: application);
        this.config = config;
        this.auto_saver = auto_saver;
        this.session = session;

        this.add_css_class ("maha");
        this.set_default_size (920, 660);
        this.set_title ("maha");

        this.tab_view = new Adw.TabView ();
        this.tab_view.close_page.connect (on_close_page);
        this.tab_view.page_detached.connect (on_page_detached);
        this.tab_view.notify["selected-page"].connect (() => record_current_document ());

        build_chrome ();
        install_shortcuts ();

        this.theme = new ThemeController (config);

        restore_session ();
        record_current_document ();

        this.close_request.connect (() => {
            if (flush_all ()) {
                return false;
            }
            show_message ("Could not save all tabs; the window was kept open to avoid data loss.");
            return true;
        });
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
        var existing = find_tab_by_path (path);
        if (existing != null) {
            this.tab_view.set_selected_page (this.tab_view.get_page (existing));
            return true;
        }

        Document document;
        bool recovered = false;
        try {
            string text = FileStore.read (path, out recovered);
            document = new Document (path, text);
        } catch (GLib.Error e) {
            show_message ("Could not open \"%s\": %s".printf (path, e.message));
            return false;
        }

        add_tab (document);
        record_current_document ();

        if (recovered) {
            show_message ("\"%s\" contained corrupt data; the recoverable part was restored and saved.".printf (path));
        }
        return true;
    }

    /** Save the active tab: instant save, or a Save dialog for a new file. */
    public void save_current () {
        var tab = current_tab ();
        if (tab == null) {
            return;
        }
        if (tab.document.is_new) {
            prompt_save_as (tab);
        } else {
            tab.save_now ();
        }
    }

    /** Create a new empty tab. */
    public void new_tab () {
        add_empty_tab ();
    }

    /** Save every tab immediately. Returns false if any save failed. */
    public bool flush_all () {
        bool all_saved = true;
        int pages = this.tab_view.get_n_pages ();
        for (int i = 0; i < pages; i++) {
            var tab = this.tab_view.get_nth_page (i).get_child () as EditorTab;
            if (tab != null && !tab.save_now ()) {
                all_saved = false;
            }
        }
        return all_saved;
    }

    public void show_message (string message) {
        GLib.warning ("maha: %s", message);
        var dialog = new Gtk.AlertDialog ("%s", message);
        dialog.set_modal (true);
        dialog.show (this);
    }

    private void prompt_save_as (EditorTab tab) {
        var dialog = new Gtk.FileDialog ();
        dialog.set_title ("Save File");
        dialog.set_accept_label ("Save");
        dialog.set_initial_name ("untitled.txt");
        dialog.save.begin (this, null, (obj, res) => {
            try {
                var file = dialog.save.end (res);
                if (file == null) {
                    return;
                }
                string? path = file.get_path ();
                if (path == null) {
                    show_message ("Only local files can be saved.");
                    return;
                }
                var other = find_tab_by_path (path);
                if (other != null && other != tab) {
                    show_message ("\"%s\" is already open in another tab.".printf (path));
                    return;
                }
                if (!tab.save_as (path)) {
                    show_message ("Could not save \"%s\".".printf (path));
                    return;
                }
                var page = this.tab_view.get_page (tab);
                if (page != null) {
                    page.set_title (tab.document.display_name);
                }
                record_current_document ();
            } catch (GLib.Error e) {
                if (!is_dialog_cancelled (e)) {
                    show_message ("Could not save file: %s".printf (e.message));
                }
            }
        });
    }

    private void install_shortcuts () {
        var controller = new Gtk.ShortcutController ();
        controller.set_scope (Gtk.ShortcutScope.GLOBAL);
        controller.add_shortcut (make_shortcut ("<Control>t", "app.new"));
        controller.add_shortcut (make_shortcut ("<Control>o", "app.open"));
        controller.add_shortcut (make_shortcut ("<Control>s", "app.save"));
        controller.add_shortcut (make_shortcut ("<Control>q", "app.quit"));

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

        var header = new Adw.HeaderBar ();

        var open_content = new Adw.ButtonContent ();
        open_content.set_icon_name ("folder-open-symbolic");
        open_content.set_label ("Open");
        var open_button = new Gtk.Button ();
        open_button.set_child (open_content);
        open_button.set_tooltip_text ("Open file (Ctrl+O)");
        open_button.clicked.connect (() => open_file_dialog ());
        header.pack_start (open_button);

        // Plain flat "+" on the right of the header bar.
        var new_button = new Gtk.Button.from_icon_name ("tab-new-symbolic");
        new_button.set_tooltip_text ("New tab (Ctrl+T)");
        new_button.clicked.connect (() => add_empty_tab ());
        header.pack_end (new_button);

        header.set_title_widget (this.tab_bar);

        this.toolbar_view = new Adw.ToolbarView ();
        this.toolbar_view.add_top_bar (header);
        this.toolbar_view.set_content (this.tab_view);
        this.set_content (this.toolbar_view);
    }

    /** Confirm closing a tab; abort if its contents cannot be saved. */
    private bool on_close_page (Adw.TabPage page) {
        var tab = page.get_child () as EditorTab;
        bool ok = (tab == null) || tab.save_now ();
        this.tab_view.close_page_finish (page, ok);
        return true;
    }

    private void on_page_detached (Adw.TabPage page, int position) {
        if (this.tab_view.get_n_pages () == 0) {
            this.close ();
        }
    }

    private void restore_session () {
        // Prefer restoring an unsaved "New tab" from its scratch file.
        string? scratch_id = this.session.load_last_scratch ();
        if (scratch_id != null) {
            string scratch_path = Paths.scratch_file (scratch_id);
            if (GLib.FileUtils.test (scratch_path, GLib.FileTest.EXISTS)) {
                try {
                    bool scratch_recovered;
                    string text = FileStore.read (scratch_path, out scratch_recovered);
                    add_tab (Document.restore_scratch (scratch_id, text));
                    return;
                } catch (GLib.Error e) {
                    GLib.warning ("maha: could not restore scratch \"%s\": %s", scratch_path, e.message);
                }
            }
        }

        var last = this.session.load_last_file ();
        if (last != null && GLib.FileUtils.test (last, GLib.FileTest.EXISTS) && open_path (last)) {
            return;
        }
        add_empty_tab ();
    }

    private EditorTab? current_tab () {
        var page = this.tab_view.get_selected_page ();
        if (page == null) {
            return null;
        }
        return page.get_child () as EditorTab;
    }

    private EditorTab? find_tab_by_path (string path) {
        int pages = this.tab_view.get_n_pages ();
        for (int i = 0; i < pages; i++) {
            var tab = this.tab_view.get_nth_page (i).get_child () as EditorTab;
            if (tab != null && tab.document.path == path) {
                return tab;
            }
        }
        return null;
    }

    private void record_current_document () {
        record_tab (current_tab ());
    }

    private void record_tab (EditorTab? tab) {
        if (tab == null) {
            this.session.clear ();
            return;
        }
        if (tab.document.is_new) {
            this.session.save_last_scratch ((!) tab.document.scratch_id);
        } else {
            this.session.save_last_file (tab.document.path);
        }
    }

    private void add_empty_tab () {
        add_tab (new Document (null, ""));
    }

    private void add_tab (Document document) {
        var tab = new EditorTab (document, this.auto_saver);
        var page = this.tab_view.append (tab);
        page.set_title (document.display_name);
        this.tab_view.set_selected_page (page);
    }

    private static bool is_dialog_cancelled (GLib.Error e) {
        return e.matches (Gtk.DialogError.quark (), Gtk.DialogError.DISMISSED)
            || e.matches (Gtk.DialogError.quark (), Gtk.DialogError.CANCELLED);
    }
}

}
