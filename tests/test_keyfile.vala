using Maha.Testing;

namespace Maha {

public void register_keyfile_tests () {
    GLib.Test.add_func ("/keyfile/roundtrip", test_keyfile_roundtrip);
    GLib.Test.add_func ("/keyfile/trailing_backslash", test_keyfile_trailing_backslash);
    GLib.Test.add_func ("/keyfile/escapes", test_keyfile_escapes);
}

private void test_keyfile_roundtrip () {
    // Paths and font names are arbitrary bytes; escaping must be lossless.
    string[] samples = {
        "plain/path.txt",
        "with\\backslash",
        "with\nnewline",
        "tab\there",
        "carriage\rhere",
        "a\\nb",
        "utf8-\u00e9\u00e8",
        ""
    };

    foreach (unowned string s in samples) {
        assert (keyfile_unescape (keyfile_escape (s)) == s);
    }
}

private void test_keyfile_trailing_backslash () {
    // A value that ends in a backslash must survive the round trip (the escape
    // output ends in `\\`), and a raw lone trailing backslash is literal.
    assert (keyfile_unescape (keyfile_escape ("ends\\")) == "ends\\");
    assert (keyfile_unescape ("ends\\") == "ends\\");
}

private void test_keyfile_escapes () {
    assert (keyfile_escape ("a\nb") == "a\\nb");
    assert (keyfile_unescape ("a\\nb") == "a\nb");
    // An unknown escape is passed through as the literal character.
    assert (keyfile_unescape ("unknown\\x") == "unknownx");
}

}
