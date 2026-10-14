using Maha.Testing;

namespace Maha {

public void register_reopen_tests () {
    GLib.Test.add_func ("/reopen/empty", test_reopen_empty);
    GLib.Test.add_func ("/reopen/lifo", test_reopen_lifo);
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

}
