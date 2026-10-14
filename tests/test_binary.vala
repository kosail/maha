using Maha.Testing;

namespace Maha {

public void register_binary_tests () {
    GLib.Test.add_func ("/binary/empty_is_text", test_empty_is_text);
    GLib.Test.add_func ("/binary/plain_utf8_is_text", test_plain_utf8_is_text);
    GLib.Test.add_func ("/binary/multibyte_utf8_is_text", test_multibyte_utf8_is_text);
    GLib.Test.add_func ("/binary/latin1_is_binary", test_latin1_is_binary);
    GLib.Test.add_func ("/binary/control_heavy_is_binary", test_control_heavy_is_binary);
    GLib.Test.add_func ("/binary/png_is_binary", test_png_is_binary);
    GLib.Test.add_func ("/binary/pdf_is_binary", test_pdf_is_binary);
    GLib.Test.add_func ("/binary/utf16_is_binary", test_utf16_is_binary);
    GLib.Test.add_func ("/binary/view_text_is_valid", test_view_text_is_valid);
}

private void test_empty_is_text () {
    assert (FileStore.classify (new uint8[0]) == FileStore.ContentKind.TEXT);
}

private void test_plain_utf8_is_text () {
    uint8[] data = { 104, 101, 108, 108, 111, 10, 119, 111, 114, 108, 100 };
    assert (FileStore.classify (data) == FileStore.ContentKind.TEXT);
}

private void test_multibyte_utf8_is_text () {
    // "café\n" in UTF-8.
    uint8[] data = { 99, 97, 102, 0xC3, 0xA9, 10 };
    assert (FileStore.classify (data) == FileStore.ContentKind.TEXT);
}

private void test_latin1_is_binary () {
    // "caf" + 0xE9 (é in ISO-8859-1): never valid UTF-8, so not text.
    uint8[] data = { 99, 97, 102, 0xE9 };
    assert (FileStore.classify (data) == FileStore.ContentKind.BINARY);
}

private void test_control_heavy_is_binary () {
    uint8[] data = { 1, 2, 3, 4, 5, 6, 7, 8, 11, 12, 14, 15 };
    assert (FileStore.classify (data) == FileStore.ContentKind.BINARY);
}

private void test_png_is_binary () {
    // PNG signature + IHDR start: high byte and NULs.
    uint8[] data = { 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D };
    assert (FileStore.classify (data) == FileStore.ContentKind.BINARY);
}

private void test_pdf_is_binary () {
    // "%PDF-1.7\n" then a binary stream header with a NUL.
    uint8[] data = { 0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x37, 10, 0x00, 0x01, 0x02, 0xFF };
    assert (FileStore.classify (data) == FileStore.ContentKind.BINARY);
}

private void test_utf16_is_binary () {
    // UTF-16LE BOM + "hi": NUL bytes with real data after them.
    uint8[] data = { 0xFF, 0xFE, 0x68, 0x00, 0x69, 0x00 };
    assert (FileStore.classify (data) == FileStore.ContentKind.BINARY);
}

private void test_view_text_is_valid () {
    var dir = make_tmp_dir ();
    var path = GLib.Path.build_filename (dir, "blob.bin");

    uint8[] data = { 0x00, 0xFF, 0x41, 0x00, 0xE9 };

    try {
        GLib.FileUtils.set_data (path, data);
        var result = FileStore.read (path);
        assert (result.kind == FileStore.ContentKind.BINARY);
        // The read-only view must be valid UTF-8 and free of NUL.
        assert (result.text.validate ());
        bool has_nul = false;
        for (int i = 0; i < result.text.length; i++) {
            if (result.text[i] == 0) {
                has_nul = true;
            }
        }
        assert (!has_nul);
    } catch (GLib.Error e) {
        GLib.Test.fail ();
    }
}

}
