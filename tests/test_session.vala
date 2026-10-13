using Maha.Testing;

namespace Maha {

public void register_session_tests () {
    GLib.Test.add_func ("/session/roundtrip", test_session_roundtrip);
    GLib.Test.add_func ("/session/scratch_roundtrip", test_scratch_roundtrip);
    GLib.Test.add_func ("/session/legacy_raw_path", test_legacy_raw_path);
    GLib.Test.add_func ("/session/missing", test_missing_file);
}

private void test_session_roundtrip () {
    var dir = make_tmp_dir ();
    var path = GLib.Path.build_filename (dir, "session");

    var store = new SessionStore (path);

    assert (store.load_last_file () == null);

    store.save_last_file ("/tmp/some/file.txt");
    assert (store.load_last_file () == "/tmp/some/file.txt");
    assert (store.load_last_scratch () == null);
}

private void test_scratch_roundtrip () {
    var dir = make_tmp_dir ();
    var path = GLib.Path.build_filename (dir, "session");

    var store = new SessionStore (path);

    store.save_last_scratch ("uuid-1234");
    assert (store.load_last_scratch () == "uuid-1234");
    assert (store.load_last_file () == null);

    // Saving a real file supersedes the scratch reference.
    store.save_last_file ("/tmp/real.txt");
    assert (store.load_last_file () == "/tmp/real.txt");
    assert (store.load_last_scratch () == null);

    store.clear ();
    assert (store.load_last_file () == null);
    assert (store.load_last_scratch () == null);
}

private void test_legacy_raw_path () {
    var dir = make_tmp_dir ();
    var path = GLib.Path.build_filename (dir, "session");

    try {
        GLib.FileUtils.set_contents (path, "/tmp/legacy.txt\n");
    } catch (GLib.Error e) {
        GLib.Test.fail ();
    }

    var store = new SessionStore (path);
    assert (store.load_last_file () == "/tmp/legacy.txt");
    assert (store.load_last_scratch () == null);
}

private void test_missing_file () {
    var dir = make_tmp_dir ();
    var path = GLib.Path.build_filename (dir, "does-not-exist");

    assert (new SessionStore (path).load_last_file () == null);
}

}
