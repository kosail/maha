using Maha.Testing;

namespace Maha {

public void register_recovery_tests () {
    GLib.Test.add_func ("/recovery/nul_tail", test_recovers_from_nul);
    GLib.Test.add_func ("/recovery/clean_untouched", test_clean_file_not_touched);
    GLib.Test.add_func ("/recovery/prefix_only", test_recovers_prefix_only);
    GLib.Test.add_func ("/recovery/invalid_utf8_sanitized", test_invalid_utf8_sanitized);
    GLib.Test.add_func ("/recovery/mid_multibyte", test_recovery_mid_multibyte);
}

private void test_recovers_from_nul () {
    var dir = make_tmp_dir ();
    var path = GLib.Path.build_filename (dir, "corrupt.txt");

    // "hello\0world" written as raw bytes.
    uint8[] corrupt = { 104, 101, 108, 108, 111, 0, 119, 111, 114, 108, 100 };

    try {
        GLib.FileUtils.set_data (path, corrupt);

        bool recovered;
        string text = FileStore.read (path, out recovered);
        assert (recovered);
        assert (text == "hello");

        // The file must have been rewritten without the corrupt tail.
        string after;
        GLib.FileUtils.get_contents (path, out after);
        assert (after == "hello");
    } catch (GLib.Error e) {
        GLib.Test.message ("unexpected error: %s", e.message);
        GLib.Test.fail ();
    }
}

private void test_clean_file_not_touched () {
    var dir = make_tmp_dir ();
    var path = GLib.Path.build_filename (dir, "clean.txt");

    try {
        GLib.FileUtils.set_contents (path, "no corruption here");
        bool recovered;
        string text = FileStore.read (path, out recovered);
        assert (!recovered);
        assert (text == "no corruption here");
    } catch (GLib.Error e) {
        GLib.Test.fail ();
    }
}

private void test_recovers_prefix_only () {
    var dir = make_tmp_dir ();
    var path = GLib.Path.build_filename (dir, "prefix.txt");

    uint8[] corrupt = { 65, 66, 67, 0, 0, 0, 68, 69, 70 };

    try {
        GLib.FileUtils.set_data (path, corrupt);
        bool recovered;
        string text = FileStore.read (path, out recovered);
        assert (recovered);
        assert (text == "ABC");
    } catch (GLib.Error e) {
        GLib.Test.fail ();
    }
}

private void test_invalid_utf8_sanitized () {
    var dir = make_tmp_dir ();
    var path = GLib.Path.build_filename (dir, "latin1.txt");

    // "hi" + 0xFF + "!" : 0xFF is never valid UTF-8.
    uint8[] data = { 104, 105, 0xFF, 33 };

    try {
        GLib.FileUtils.set_data (path, data);
        bool recovered;
        string text = FileStore.read (path, out recovered);
        assert (!recovered);
        assert (text.validate ());
        assert (text.has_prefix ("hi"));
        assert (text.has_suffix ("!"));
    } catch (GLib.Error e) {
        GLib.Test.fail ();
    }
}

private void test_recovery_mid_multibyte () {
    var dir = make_tmp_dir ();
    var path = GLib.Path.build_filename (dir, "split.txt");

    // 0xC3 starts a 2-byte sequence, but the NUL cuts it in half.
    uint8[] data = { 0xC3, 0x00, 0x41, 0x42 };

    try {
        GLib.FileUtils.set_data (path, data);
        bool recovered;
        string text = FileStore.read (path, out recovered);
        assert (recovered);
        assert (text.validate ());

        // The recovered file on disk must also be valid UTF-8.
        string after;
        GLib.FileUtils.get_contents (path, out after);
        assert (after.validate ());
    } catch (GLib.Error e) {
        GLib.Test.fail ();
    }
}

}
