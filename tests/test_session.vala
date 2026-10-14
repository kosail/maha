using Maha.Testing;

namespace Maha {

public void register_session_tests () {
    GLib.Test.add_func ("/session/roundtrip", test_session_roundtrip);
    GLib.Test.add_func ("/session/scratch_roundtrip", test_scratch_roundtrip);
    GLib.Test.add_func ("/session/empty_list", test_empty_list);
    GLib.Test.add_func ("/session/legacy_single", test_legacy_single);
    GLib.Test.add_func ("/session/legacy_raw_path", test_legacy_raw_path);
    GLib.Test.add_func ("/session/missing", test_missing_file);
    GLib.Test.add_func ("/session/value_with_newline", test_value_with_newline);
    GLib.Test.add_func ("/session/nested_parent_created", test_session_nested_parent_created);
}

private void test_session_roundtrip () {
    var dir = make_tmp_dir ();
    var path = GLib.Path.build_filename (dir, "session");

    var store = new SessionStore (path);
    assert (store.load ().tabs.length == 0);

    var tabs = new GLib.GenericArray<SessionStore.Tab> ();
    tabs.add (new SessionStore.Tab (SessionStore.KIND_FILE, "/tmp/some/file.txt"));
    tabs.add (new SessionStore.Tab (SessionStore.KIND_FILE, "/tmp/other.txt"));
    store.save (tabs, 1);

    var state = store.load ();
    assert (state.tabs.length == 2);
    assert (state.tabs.get (0).kind == SessionStore.KIND_FILE);
    assert (state.tabs.get (0).value == "/tmp/some/file.txt");
    assert (state.tabs.get (1).value == "/tmp/other.txt");
    assert (state.active == 1);
}

private void test_scratch_roundtrip () {
    var dir = make_tmp_dir ();
    var path = GLib.Path.build_filename (dir, "session");

    var store = new SessionStore (path);

    var tabs = new GLib.GenericArray<SessionStore.Tab> ();
    tabs.add (new SessionStore.Tab (SessionStore.KIND_SCRATCH, "uuid-1234"));
    tabs.add (new SessionStore.Tab (SessionStore.KIND_FILE, "/tmp/real.txt"));
    store.save (tabs, 0);

    var state = store.load ();
    assert (state.tabs.length == 2);
    assert (state.tabs.get (0).kind == SessionStore.KIND_SCRATCH);
    assert (state.tabs.get (0).value == "uuid-1234");
    assert (state.tabs.get (1).kind == SessionStore.KIND_FILE);
    assert (state.active == 0);

    store.clear ();
    assert (store.load ().tabs.length == 0);
}

private void test_empty_list () {
    var dir = make_tmp_dir ();
    var path = GLib.Path.build_filename (dir, "session");

    var store = new SessionStore (path);
    store.save (new GLib.GenericArray<SessionStore.Tab> (), 0);

    // An empty (but valid) session must not be mistaken for a bare path.
    assert (store.load ().tabs.length == 0);
}

private void test_legacy_single () {
    var dir = make_tmp_dir ();
    var path = GLib.Path.build_filename (dir, "session");

    try {
        GLib.FileUtils.set_contents (path, "[last]\nkind=file\nvalue=/tmp/old.txt\n");
    } catch (GLib.Error e) {
        GLib.Test.fail ();
    }

    var state = new SessionStore (path).load ();
    assert (state.tabs.length == 1);
    assert (state.tabs.get (0).kind == SessionStore.KIND_FILE);
    assert (state.tabs.get (0).value == "/tmp/old.txt");
}

private void test_legacy_raw_path () {
    var dir = make_tmp_dir ();
    var path = GLib.Path.build_filename (dir, "session");

    try {
        GLib.FileUtils.set_contents (path, "/tmp/legacy.txt\n");
    } catch (GLib.Error e) {
        GLib.Test.fail ();
    }

    var state = new SessionStore (path).load ();
    assert (state.tabs.length == 1);
    assert (state.tabs.get (0).kind == SessionStore.KIND_FILE);
    assert (state.tabs.get (0).value == "/tmp/legacy.txt");
}

private void test_missing_file () {
    var dir = make_tmp_dir ();
    var path = GLib.Path.build_filename (dir, "does-not-exist");

    assert (new SessionStore (path).load ().tabs.length == 0);
}

// A path containing a newline must round-trip (not corrupt the file).
private void test_value_with_newline () {
    var dir = make_tmp_dir ();
    var path = GLib.Path.build_filename (dir, "session");

    var store = new SessionStore (path);
    var tabs = new GLib.GenericArray<SessionStore.Tab> ();
    tabs.add (new SessionStore.Tab (SessionStore.KIND_FILE, "/tmp/weird\nname.txt"));
    store.save (tabs, 0);

    var state = store.load ();
    assert (state.tabs.length == 1);
    assert (state.tabs.get (0).value == "/tmp/weird\nname.txt");
}

// The store must create its own parent directory, not the global config dir.
private void test_session_nested_parent_created () {
    var dir = make_tmp_dir ();
    var path = GLib.Path.build_filename (dir, "sub", "deeper", "session");

    var store = new SessionStore (path);
    var tabs = new GLib.GenericArray<SessionStore.Tab> ();
    tabs.add (new SessionStore.Tab (SessionStore.KIND_FILE, "/tmp/x.txt"));
    store.save (tabs, 0);

    assert (GLib.FileUtils.test (path, GLib.FileTest.EXISTS));
}

}
