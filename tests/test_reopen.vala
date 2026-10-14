namespace Maha {

public void register_reopen_tests () {
    GLib.Test.add_func ("/reopen/empty", test_reopen_empty);
    GLib.Test.add_func ("/reopen/lifo", test_reopen_lifo);
    GLib.Test.add_func ("/reopen/dedupe", test_reopen_dedupe);
    GLib.Test.add_func ("/reopen/capped", test_reopen_capped);
}

private void test_reopen_empty () {
    var stack = new ReopenStack ();
    assert (stack.is_empty);
    assert (stack.pop () == null);
}

private void test_reopen_lifo () {
    var stack = new ReopenStack ();
    stack.record ("/tmp/a.txt");
    stack.record ("/tmp/b.txt");

    assert (!stack.is_empty);

    var first = stack.pop ();
    assert (first == "/tmp/b.txt");

    var second = stack.pop ();
    assert (second == "/tmp/a.txt");

    assert (stack.pop () == null);
    assert (stack.is_empty);
}

// Re-closing the same file must not stack it twice.
private void test_reopen_dedupe () {
    var stack = new ReopenStack ();
    stack.record ("/tmp/a.txt");
    stack.record ("/tmp/b.txt");
    stack.record ("/tmp/a.txt");

    assert (stack.pop () == "/tmp/a.txt");
    assert (stack.pop () == "/tmp/b.txt");
    assert (stack.pop () == null);
}

// The history is bounded; only the newest entries survive.
private void test_reopen_capped () {
    var stack = new ReopenStack ();
    for (int i = 0; i < 40; i++) {
        stack.record ("/tmp/file-%d.txt".printf (i));
    }

    int count = 0;
    string? last = null;
    while (true) {
        var p = stack.pop ();
        if (p == null) {
            break;
        }
        count++;
        last = p;
    }
    assert (count == 32);
    assert (last == "/tmp/file-8.txt");
}

}
