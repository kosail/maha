using Maha.Testing;

namespace Maha {

public void register_file_store_tests () {
    GLib.Test.add_func ("/file_store/roundtrip", test_file_store_roundtrip);
    GLib.Test.add_func ("/file_store/no_temp_left_behind", test_no_temp_left_behind);
    GLib.Test.add_func ("/file_store/permissions_preserved", test_permissions_preserved);
    GLib.Test.add_func ("/file_store/private_mode_preserved", test_private_mode_preserved);
    GLib.Test.add_func ("/file_store/symlink_preserved", test_symlink_preserved);
    GLib.Test.add_func ("/file_store/large_content", test_large_content);
    GLib.Test.add_func ("/file_store/long_filename", test_long_filename);
    GLib.Test.add_func ("/file_store/dangling_symlink_creates_target", test_dangling_symlink);
    GLib.Test.add_func ("/file_store/fifo_refused", test_fifo_refused);
    GLib.Test.add_func ("/file_store/too_large_refused", test_too_large_refused);
}

private void test_file_store_roundtrip () {
    var dir = make_tmp_dir ();
    var path = GLib.Path.build_filename (dir, "note.txt");

    try {
        FileStore.save_atomic (path, "hello world");
        var result = FileStore.read (path);
        assert (result.kind == FileStore.ContentKind.TEXT);
        assert (result.text == "hello world");
    } catch (GLib.Error e) {
        GLib.Test.message ("unexpected error: %s", e.message);
        GLib.Test.fail ();
    }
}

private void test_no_temp_left_behind () {
    var dir = make_tmp_dir ();
    var path = GLib.Path.build_filename (dir, "note.txt");

    try {
        FileStore.save_atomic (path, "a");
        FileStore.save_atomic (path, "bb");
        FileStore.save_atomic (path, "ccc");
    } catch (GLib.Error e) {
        GLib.Test.fail ();
    }

    try {
        var directory = GLib.Dir.open (dir, 0);
        int count = 0;
        while (directory.read_name () != null) {
            count++;
        }
        assert (count == 1);
    } catch (GLib.Error e) {
        GLib.Test.fail ();
    }
}

private void test_permissions_preserved () {
    var dir = make_tmp_dir ();
    var path = GLib.Path.build_filename (dir, "note.txt");

    try {
        GLib.FileUtils.set_contents (path, "x");
        Posix.chmod (path, (Posix.mode_t) 0640);
        FileStore.save_atomic (path, "y");
    } catch (GLib.Error e) {
        GLib.Test.fail ();
    }

    Posix.Stat st;
    assert (Posix.stat (path, out st) == 0);
    assert ((st.st_mode & 0777) == 0640);
}

private void test_private_mode_preserved () {
    var dir = make_tmp_dir ();
    var path = GLib.Path.build_filename (dir, "secret.txt");

    try {
        GLib.FileUtils.set_contents (path, "x");
        Posix.chmod (path, (Posix.mode_t) 0600);
        FileStore.save_atomic (path, "y");
    } catch (GLib.Error e) {
        GLib.Test.fail ();
    }

    Posix.Stat st;
    assert (Posix.stat (path, out st) == 0);
    assert ((st.st_mode & 0777) == 0600);
}

private void test_symlink_preserved () {
    var dir = make_tmp_dir ();
    var target = GLib.Path.build_filename (dir, "target.txt");
    var link = GLib.Path.build_filename (dir, "link.txt");

    try {
        GLib.FileUtils.set_contents (target, "old");
    } catch (GLib.Error e) {
        GLib.Test.fail ();
    }

    if (GLib.FileUtils.symlink (target, link) != 0) {
        GLib.Test.message ("symlinks unsupported here; skipping");
        return;
    }

    try {
        FileStore.save_atomic (link, "new");
    } catch (GLib.Error e) {
        GLib.Test.fail ();
    }

    // The link must survive and the target must hold the new content.
    assert (GLib.FileUtils.test (link, GLib.FileTest.IS_SYMLINK));
    assert (read_file (target) == "new");
}

private void test_large_content () {
    var dir = make_tmp_dir ();
    var path = GLib.Path.build_filename (dir, "big.txt");

    var builder = new StringBuilder ();
    for (int i = 0; i < 200000; i++) {
        builder.append ("line %d\n".printf (i));
    }
    string content = builder.str;

    try {
        FileStore.save_atomic (path, content);
        var result = FileStore.read (path);
        assert (result.kind == FileStore.ContentKind.TEXT);
        assert (result.text == content);
    } catch (GLib.Error e) {
        GLib.Test.fail ();
    }
}

private void test_long_filename () {
    var dir = make_tmp_dir ();

    // ~230-char basename: a temp name derived from it would exceed NAME_MAX.
    var name = new StringBuilder ();
    for (int i = 0; i < 230; i++) {
        name.append_c ('a');
    }
    name.append (".txt");
    var path = GLib.Path.build_filename (dir, name.str);

    try {
        FileStore.save_atomic (path, "long");
        var result = FileStore.read (path);
        assert (result.text == "long");
    } catch (GLib.Error e) {
        GLib.Test.message ("unexpected error: %s", e.message);
        GLib.Test.fail ();
    }
}

// Saving through a symlink whose target does not exist yet must create the
// target and keep the link (rather than replacing the link with a file).
private void test_dangling_symlink () {
    var dir = make_tmp_dir ();
    var target = GLib.Path.build_filename (dir, "target.txt");
    var link = GLib.Path.build_filename (dir, "link.txt");

    if (GLib.FileUtils.symlink (target, link) != 0) {
        GLib.Test.message ("symlinks unsupported here; skipping");
        return;
    }

    assert (!GLib.FileUtils.test (target, GLib.FileTest.EXISTS));

    try {
        FileStore.save_atomic (link, "data");
    } catch (GLib.Error e) {
        GLib.Test.fail ();
    }

    assert (GLib.FileUtils.test (link, GLib.FileTest.IS_SYMLINK));
    assert (read_file (target) == "data");
}

// A FIFO must be refused, and opening it must not block.
private void test_fifo_refused () {
    var dir = make_tmp_dir ();
    var path = GLib.Path.build_filename (dir, "pipe");

    if (Posix.mkfifo (path, (Posix.mode_t) 0600) != 0) {
        GLib.Test.message ("mkfifo unsupported here; skipping");
        return;
    }

    bool threw = false;
    try {
        FileStore.read (path);
    } catch (GLib.Error e) {
        threw = true;
    }
    assert (threw);
}

// A file larger than the in-memory cap must be refused.
private void test_too_large_refused () {
    var dir = make_tmp_dir ();
    var path = GLib.Path.build_filename (dir, "big.bin");

    int fd = Posix.open (path, Posix.O_WRONLY | Posix.O_CREAT | Posix.O_TRUNC, (Posix.mode_t) 0600);
    if (fd < 0) {
        GLib.Test.fail ();
        return;
    }
    if (Posix.ftruncate (fd, (Posix.off_t) (64L * 1024 * 1024 + 1)) != 0) {
        Posix.close (fd);
        GLib.Test.message ("ftruncate failed; skipping");
        return;
    }
    Posix.close (fd);

    bool threw = false;
    try {
        FileStore.read (path);
    } catch (GLib.Error e) {
        threw = true;
    }
    assert (threw);
}

}
