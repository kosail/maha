using Maha.Testing;

namespace Maha {

public void register_auto_saver_tests () {
    GLib.Test.add_func ("/auto_saver/debounced", test_debounced_save);
    GLib.Test.add_func ("/auto_saver/coalesces", test_debounce_coalesces);
    GLib.Test.add_func ("/auto_saver/flush_immediate", test_flush_immediate);
    GLib.Test.add_func ("/auto_saver/source_consulted", test_source_consulted_at_save);
    GLib.Test.add_func ("/auto_saver/scratch_persisted", test_scratch_persisted);
    GLib.Test.add_func ("/auto_saver/cancel_prevents_write", test_cancel_prevents_write);
    GLib.Test.add_func ("/auto_saver/cancel_prevents_scratch", test_cancel_prevents_scratch);
}

private void test_debounced_save () {
    var dir = make_tmp_dir ();
    var path = GLib.Path.build_filename (dir, "auto.txt");

    var document = new Document (path, "first");
    var source = new StringTextSource ();
    source.text = "second";
    document.dirty = true;

    var saver = new AutoSaver (50);
    saver.schedule (document, source);

    // Not written yet (debounce still pending).
    assert (read_file (path) == "");

    pump (200);

    assert (read_file (path) == "second");
    assert (!document.dirty);
}

private void test_debounce_coalesces () {
    var dir = make_tmp_dir ();
    var path = GLib.Path.build_filename (dir, "coalesce.txt");

    var document = new Document (path, "");
    var source = new StringTextSource ();
    document.dirty = true;

    var saver = new AutoSaver (80);

    source.text = "one";
    saver.schedule (document, source);

    pump (30);
    source.text = "one two";
    saver.schedule (document, source);

    pump (30);
    source.text = "one two three";
    saver.schedule (document, source);

    pump (200);

    assert (read_file (path) == "one two three");
}

private void test_flush_immediate () {
    var dir = make_tmp_dir ();
    var path = GLib.Path.build_filename (dir, "flush.txt");

    var document = new Document (path, "");
    var source = new StringTextSource ();
    source.text = "now";
    document.dirty = true;

    var saver = new AutoSaver (5000);
    saver.schedule (document, source);

    assert (saver.flush (document));

    assert (read_file (path) == "now");
    assert (!document.dirty);
}

private void test_source_consulted_at_save () {
    var dir = make_tmp_dir ();
    var path = GLib.Path.build_filename (dir, "lazy.txt");

    var document = new Document (path, "");
    var source = new StringTextSource ();

    // The text on the document is stale; the source carries the live value.
    document.text = "stale";
    document.dirty = true;
    source.text = "source value";

    var saver = new AutoSaver (5000);
    saver.schedule (document, source);

    assert (saver.flush (document));
    assert (read_file (path) == "source value");
    assert (document.text == "source value");
}

private void test_scratch_persisted () {
    var document = new Document (null, "");
    var source = new StringTextSource ();
    source.text = "unsaved text";
    document.dirty = true;

    var saver = new AutoSaver (50);
    saver.schedule (document, source);

    string scratch = document.autosave_path;
    assert (scratch.has_prefix (Paths.cache_dir ()));
    assert (scratch.has_suffix (".tmp.txt"));

    pump (200);

    // A brand new tab must be persisted to its scratch file.
    assert (read_file (scratch) == "unsaved text");
    assert (!document.dirty);

    FileStore.remove (scratch);
}

// A cancelled autosave (as happens when a new tab is discarded) must not write.
private void test_cancel_prevents_write () {
    var dir = make_tmp_dir ();
    var path = GLib.Path.build_filename (dir, "cancel.txt");

    var document = new Document (path, "");
    var source = new StringTextSource ();
    source.text = "must not be written";
    document.dirty = true;

    var saver = new AutoSaver (50);
    saver.schedule (document, source);
    saver.cancel (document);

    pump (200);

    assert (!GLib.FileUtils.test (path, GLib.FileTest.EXISTS));
}

// The discarded-tab case: cancelling must not recreate the scratch file.
private void test_cancel_prevents_scratch () {
    var document = new Document (null, "");
    var source = new StringTextSource ();
    source.text = "gone";
    document.dirty = true;

    var saver = new AutoSaver (50);
    saver.schedule (document, source);
    string scratch = document.autosave_path;
    saver.cancel (document);
    document.dirty = false;

    pump (200);

    assert (!GLib.FileUtils.test (scratch, GLib.FileTest.EXISTS));
}

}
