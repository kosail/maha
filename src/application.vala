namespace Maha {

/**
 * GLib entry point. Wires the application together and delegates to
 * `Application`.
 */
public class Application : Adw.Application {
    private Config config;
    private AutoSaver auto_saver;
    private SessionStore session;
    private ThemeController appearance;

    public Application () {
        Object (
            application_id: "com.korealm.maha",
            flags: GLib.ApplicationFlags.HANDLES_OPEN
        );
    }

    public override void startup () {
        base.startup ();

        // Make the embedded icons reachable as an icon theme, so the window
        // icon resolves even when running from the build directory.
        var display = Gdk.Display.get_default ();
        if (display != null) {
            Gtk.IconTheme.get_for_display (display).add_resource_path ("/com/korealm/maha/icons");
        }

        this.config = new ConfigStore ().load ();
        // One shared appearance controller for the whole application (the CSS
        // is display-wide), so the runtime font zoom affects every window.
        this.appearance = new ThemeController (this.config);
        this.auto_saver = new AutoSaver (config.effective_autosave_ms);
        this.session = new SessionStore ();

        var new_action = new GLib.SimpleAction ("new", null);
        new_action.activate.connect (on_new);
        add_action (new_action);

        var open_action = new GLib.SimpleAction ("open", null);
        open_action.activate.connect (on_open);
        add_action (open_action);

        var save_action = new GLib.SimpleAction ("save", null);
        save_action.activate.connect (on_save);
        add_action (save_action);

        var duplicate_line_action = new GLib.SimpleAction ("duplicate-line", null);
        duplicate_line_action.activate.connect (on_duplicate_line);
        add_action (duplicate_line_action);

        var find_action = new GLib.SimpleAction ("find", null);
        find_action.activate.connect (on_find);
        add_action (find_action);

        var close_tab_action = new GLib.SimpleAction ("close-tab", null);
        close_tab_action.activate.connect (on_close_tab);
        add_action (close_tab_action);

        var reopen_tab_action = new GLib.SimpleAction ("reopen-tab", null);
        reopen_tab_action.activate.connect (on_reopen_tab);
        add_action (reopen_tab_action);

        var quit_action = new GLib.SimpleAction ("quit", null);
        quit_action.activate.connect (on_quit);
        add_action (quit_action);

        var zoom_in_action = new GLib.SimpleAction ("zoom-in", null);
        zoom_in_action.activate.connect (on_zoom_in);
        add_action (zoom_in_action);

        var zoom_out_action = new GLib.SimpleAction ("zoom-out", null);
        zoom_out_action.activate.connect (on_zoom_out);
        add_action (zoom_out_action);

        var zoom_reset_action = new GLib.SimpleAction ("zoom-reset", null);
        zoom_reset_action.activate.connect (on_zoom_reset);
        add_action (zoom_reset_action);
    }

    public override void activate () {
        var window = existing_window ();
        if (window == null) {
            window = new MainWindow (this, this.config, this.auto_saver, this.session);
        }
        window.present ();
    }

    /** Open files passed on the command line or by a file manager. */
    public override void open (GLib.File[] files, string hint) {
        bool created = existing_window () == null;
        activate ();
        var window = existing_window ();
        if (window == null) {
            return;
        }
        foreach (var file in files) {
            string? path = file.get_path ();
            if (path != null) {
                window.open_path ((!) path);
            }
        }
        // Drop the empty placeholder tab that a fresh launch starts with; a
        // running instance keeps whatever tabs the user already had.
        if (created) {
            window.close_placeholder_tab ();
        }
    }

    private MainWindow? existing_window () {
        foreach (var candidate in get_windows ()) {
            var window = candidate as MainWindow;
            if (window != null) {
                return window;
            }
        }
        return null;
    }

    private void on_new () {
        var window = active_window as MainWindow;
        if (window == null) {
            activate ();
            window = active_window as MainWindow;
        }
        if (window != null) {
            window.new_tab ();
        }
    }

    private void on_open () {
        var window = this.active_window as MainWindow;
        if (window != null) {
            window.open_file_dialog ();
        }
    }

    private void on_save () {
        var window = this.active_window as MainWindow;
        if (window != null) {
            window.save_current ();
        }
    }

    private void on_close_tab () {
        var window = this.active_window as MainWindow;
        if (window != null) {
            window.close_current_tab ();
        }
    }

    private void on_duplicate_line () {
        var window = this.active_window as MainWindow;
        if (window != null) {
            window.duplicate_line ();
        }
    }

    private void on_find () {
        var window = this.active_window as MainWindow;
        if (window != null) {
            window.find ();
        }
    }

    private void on_reopen_tab () {
        var window = this.active_window as MainWindow;
        if (window != null) {
            window.reopen_last_closed_tab ();
        }
    }

    private void on_zoom_in () {
        this.appearance.zoom_in ();
    }

    private void on_zoom_out () {
        this.appearance.zoom_out ();
    }

    private void on_zoom_reset () {
        this.appearance.zoom_reset ();
    }

    private void on_quit () {
        // Close every window through the normal close path, which resolves any
        // unsaved tabs (saving, or asking the user) before the window closes.
        // The application quits when the last window is gone; a cancelled
        // prompt leaves its window open. Collect first: closing mutates the
        // window list.
        var windows = new GLib.GenericArray<MainWindow> ();
        foreach (var candidate in get_windows ()) {
            var window = candidate as MainWindow;
            if (window != null) {
                windows.add (window);
            }
        }
        if (windows.length == 0) {
            quit ();
            return;
        }
        foreach (var window in windows) {
            window.close ();
        }
    }
}

}
