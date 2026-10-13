namespace Maha {

/**
 * GLib entry point. Wires the application together and delegates to
 * `Application`.
 */
public class Application : Adw.Application {
    private Config config;
    private AutoSaver auto_saver;
    private SessionStore session;

    public Application () {
        Object (
            application_id: "io.github.maha",
            flags: GLib.ApplicationFlags.DEFAULT_FLAGS
        );
    }

    public override void startup () {
        base.startup ();

        this.config = new ConfigStore ().load ();
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

        var quit_action = new GLib.SimpleAction ("quit", null);
        quit_action.activate.connect (on_quit);
        add_action (quit_action);
    }

    public override void activate () {
        var window = existing_window ();
        if (window == null) {
            window = new MainWindow (this, this.config, this.auto_saver, this.session);
        }
        window.present ();
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

    private bool flush_all_windows () {
        bool all_saved = true;
        foreach (var candidate in get_windows ()) {
            var window = candidate as MainWindow;
            if (window != null && !window.flush_all ()) {
                all_saved = false;
            }
        }
        return all_saved;
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

    private void on_quit () {
        if (flush_all_windows ()) {
            quit ();
            return;
        }

        var window = existing_window ();
        if (window != null) {
            window.show_message ("Could not save all files; quit was cancelled to avoid data loss.");
        }
    }
}

}
