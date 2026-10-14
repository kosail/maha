using Maha.Testing;

namespace Maha {

public void register_recovery_tests () {
    GLib.Test.add_func ("/recovery/trailing_nul_recovered", test_trailing_nul_recovered);
    GLib.Test.add_func ("/recovery/clean_untouched", test_clean_file_not_touched);
    GLib.Test.add_func ("/recovery/read_never_writes", test_read_never_writes);
    GLib.Test.add_func ("/recovery/nul_mid_data_is_binary", test_nul_mid_data_is_binary);
    GLib.Test.add_func ("/recovery/prefix_data_is_binary", test_prefix_data_is_binary);
    GLib.Test.add_func ("/recovery/mid_multibyte_is_binary", test_mid_multibyte_is_binary);
}

private uint8[] read_raw (string path) {
    try {
        uint8[] contents;
        GLib.FileUtils.get_data (path, out contents);
        return contents;
    } catch (GLib.Error e) {
        return new uint8[0];
    }
}

private bool bytes_equal (uint8[] a, uint8[] b) {
    if (a.length != b.length) {
        return false;
    }
    for (int i = 0; i < a.length; i++) {
        if (a[i] != b[i]) {
            return false;
        }
    }
    return true;
}

// "hello\n" followed by a zero-filled tail: a crash artifact, recovered
// non-destructively.
private void test_trailing_nul_recovered () {
    var dir = make_tmp_dir ();
    var path = GLib.Path.build_filename (dir, "corrupt.txt");

    uint8[] corrupt = { 104, 101, 108, 108, 111, 10, 0, 0, 0, 0 };
    uint8[] original = { 104, 101, 108, 108, 111, 10, 0, 0, 0, 0 };

    try {
        GLib.FileUtils.set_data (path, corrupt);

        var result = FileStore.read (path);
        assert (result.kind == FileStore.ContentKind.CORRUPT_TEXT);
        assert (result.text == "hello\n");

        // Reading must not have rewritten the file.
        assert (bytes_equal (read_raw (path), original));
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
        var result = FileStore.read (path);
        assert (result.kind == FileStore.ContentKind.TEXT);
        assert (result.text == "no corruption here");
    } catch (GLib.Error e) {
        GLib.Test.fail ();
    }
}

private void test_read_never_writes () {
    var dir = make_tmp_dir ();
    var path = GLib.Path.build_filename (dir, "binary.bin");

    // An image/executable-like blob: text prefix, then NULs and real data.
    uint8[] data = { 0x7F, 0x45, 0x4C, 0x46, 0x02, 0x01, 0x00, 0x00, 0x9A, 0x3C };

    try {
        GLib.FileUtils.set_data (path, data);
        var result = FileStore.read (path);
        assert (result.kind == FileStore.ContentKind.BINARY);

        // The original bytes must be untouched, byte for byte.
        assert (bytes_equal (read_raw (path), data));
    } catch (GLib.Error e) {
        GLib.Test.fail ();
    }
}

private void test_nul_mid_data_is_binary () {
    var dir = make_tmp_dir ();
    var path = GLib.Path.build_filename (dir, "mixed.bin");

    // "hello\0world": real data after the NUL is a binary file, not corruption.
    uint8[] data = { 104, 101, 108, 108, 111, 0, 119, 111, 114, 108, 100 };

    try {
        GLib.FileUtils.set_data (path, data);
        var result = FileStore.read (path);
        assert (result.kind == FileStore.ContentKind.BINARY);
    } catch (GLib.Error e) {
        GLib.Test.fail ();
    }
}

private void test_prefix_data_is_binary () {
    var dir = make_tmp_dir ();
    var path = GLib.Path.build_filename (dir, "prefix.bin");

    uint8[] data = { 65, 66, 67, 0, 0, 0, 68, 69, 70 };

    try {
        GLib.FileUtils.set_data (path, data);
        var result = FileStore.read (path);
        assert (result.kind == FileStore.ContentKind.BINARY);
    } catch (GLib.Error e) {
        GLib.Test.fail ();
    }
}

private void test_mid_multibyte_is_binary () {
    var dir = make_tmp_dir ();
    var path = GLib.Path.build_filename (dir, "split.bin");

    // 0xC3 starts a 2-byte sequence, but the NUL cuts it in half; data follows.
    uint8[] data = { 0xC3, 0x00, 0x41, 0x42 };

    try {
        GLib.FileUtils.set_data (path, data);
        var result = FileStore.read (path);
        assert (result.kind == FileStore.ContentKind.BINARY);
    } catch (GLib.Error e) {
        GLib.Test.fail ();
    }
}

}
