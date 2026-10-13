using Maha.Testing;

namespace Maha {

public void register_document_tests () {
    GLib.Test.add_func ("/document/new_tab_name", test_new_tab_name);
    GLib.Test.add_func ("/document/scratch_path", test_scratch_path);
    GLib.Test.add_func ("/document/restore_scratch", test_restore_scratch);
    GLib.Test.add_func ("/document/promote", test_promote);
}

private void test_new_tab_name () {
    var scratch = new Document (null, "");
    assert (scratch.display_name == "New tab");
    assert (scratch.is_new);
    assert (scratch.scratch_id != null);

    var file_doc = new Document ("/tmp/example.txt", "");
    assert (file_doc.display_name == "example.txt");
    assert (!file_doc.is_new);
    assert (file_doc.scratch_id == null);

    // Two new documents must not share a scratch file.
    var other = new Document (null, "");
    assert (other.scratch_id != scratch.scratch_id);
}

private void test_scratch_path () {
    var document = new Document (null, "");
    string path = document.autosave_path;
    assert (path.has_prefix (Paths.cache_dir ()));
    assert (path.has_suffix (".tmp.txt"));

    var file_doc = new Document ("/tmp/example.txt", "");
    assert (file_doc.autosave_path == "/tmp/example.txt");
}

private void test_restore_scratch () {
    var document = Document.restore_scratch ("abc-123", "hello");
    assert (document.scratch_id == "abc-123");
    assert (document.is_new);
    assert (document.text == "hello");
    assert (document.autosave_path == Paths.scratch_file ("abc-123"));
}

private void test_promote () {
    var document = new Document (null, "hi");
    assert (document.is_new);
    document.promote ("/tmp/saved.txt");
    assert (!document.is_new);
    assert (document.scratch_id == null);
    assert (document.autosave_path == "/tmp/saved.txt");
    assert (document.display_name == "saved.txt");
}

}
