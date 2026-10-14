int main (string[] args) {
    // Isolate the XDG dirs so tests never touch the user's real config/cache.
    try {
        string cache_home = GLib.DirUtils.make_tmp ("maha-test-cache-XXXXXX");
        GLib.Environment.set_variable ("XDG_CACHE_HOME", cache_home, true);
        string config_home = GLib.DirUtils.make_tmp ("maha-test-config-XXXXXX");
        GLib.Environment.set_variable ("XDG_CONFIG_HOME", config_home, true);
    } catch (GLib.Error e) {
        // fall back to the real dirs
    }

    GLib.Test.init (ref args);

    // Only real errors are fatal; warnings (e.g. an unreadable config) are not.
    GLib.Log.set_always_fatal (GLib.LogLevelFlags.LEVEL_ERROR);

    Maha.register_document_tests ();
    Maha.register_file_store_tests ();
    Maha.register_recovery_tests ();
    Maha.register_binary_tests ();
    Maha.register_config_tests ();
    Maha.register_auto_saver_tests ();
    Maha.register_session_tests ();
    Maha.register_reopen_tests ();

    GLib.Test.run ();
    return 0;
}
