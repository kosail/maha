using Maha.Testing;

namespace Maha {

public void register_config_tests () {
    GLib.Test.add_func ("/config/creates_default", test_creates_default_file);
    GLib.Test.add_func ("/config/reads_custom", test_reads_custom_values);
    GLib.Test.add_func ("/config/invalid_fallback", test_invalid_falls_back);
    GLib.Test.add_func ("/config/negative_autosave", test_negative_autosave_falls_back);
    GLib.Test.add_func ("/config/negative_font_size", test_negative_font_size_falls_back);
    GLib.Test.add_func ("/config/clamped", test_transparency_clamped);
    GLib.Test.add_func ("/config/autosave_clamped", test_autosave_clamped);
    GLib.Test.add_func ("/config/font_size_clamped", test_font_size_clamped);
    GLib.Test.add_func ("/config/line_height_default", test_line_height_default);
    GLib.Test.add_func ("/config/line_height_custom", test_line_height_custom);
    GLib.Test.add_func ("/config/line_height_invalid", test_line_height_invalid_falls_back);
    GLib.Test.add_func ("/config/line_height_normal", test_line_height_normal);
}

private void test_creates_default_file () {
    var dir = make_tmp_dir ();
    var path = GLib.Path.build_filename (dir, "config.ini");

    var config = new ConfigStore (path).load ();

    assert (config.transparency == Config.DEFAULT_TRANSPARENCY);
    assert (config.font == Config.DEFAULT_FONT);
    assert (config.font_size == Config.DEFAULT_FONT_SIZE);
    assert (config.autosave_ms == Config.DEFAULT_AUTOSAVE_MS);
    assert (config.line_height == Config.DEFAULT_LINE_HEIGHT);
    assert (GLib.FileUtils.test (path, GLib.FileTest.EXISTS));
}

private void test_reads_custom_values () {
    var dir = make_tmp_dir ();
    var path = GLib.Path.build_filename (dir, "config.ini");

    try {
        GLib.FileUtils.set_contents (path, "[appearance]\ntransparency=0.5\nfont=Fira Code\nfont_size=16\nline_height=1.4\n\n[editor]\nautosave_ms=250\n");
    } catch (GLib.Error e) {
        GLib.Test.fail ();
    }

    var config = new ConfigStore (path).load ();

    assert (config.transparency == 0.5);
    assert (config.font == "Fira Code");
    assert (config.font_size == 16);
    assert (config.autosave_ms == 250);
    assert (config.line_height == 1.4);
}

private void test_invalid_falls_back () {
    var dir = make_tmp_dir ();
    var path = GLib.Path.build_filename (dir, "config.ini");

    try {
        GLib.FileUtils.set_contents (path, "[appearance]\ntransparency=not-a-number\nfont_size=not-a-number\nline_height=not-a-number\n\n[editor]\nautosave_ms=not-a-number\n");
    } catch (GLib.Error e) {
        GLib.Test.fail ();
    }

    var config = new ConfigStore (path).load ();

    assert (config.transparency == Config.DEFAULT_TRANSPARENCY);
    assert (config.font == Config.DEFAULT_FONT);
    assert (config.font_size == Config.DEFAULT_FONT_SIZE);
    assert (config.autosave_ms == Config.DEFAULT_AUTOSAVE_MS);
    assert (config.line_height == Config.DEFAULT_LINE_HEIGHT);
}

private void test_negative_autosave_falls_back () {
    var dir = make_tmp_dir ();
    var path = GLib.Path.build_filename (dir, "config.ini");

    try {
        GLib.FileUtils.set_contents (path, "[editor]\nautosave_ms=-5\n");
    } catch (GLib.Error e) {
        GLib.Test.fail ();
    }

    var config = new ConfigStore (path).load ();

    assert (config.autosave_ms == Config.DEFAULT_AUTOSAVE_MS);
}

private void test_negative_font_size_falls_back () {
    var dir = make_tmp_dir ();
    var path = GLib.Path.build_filename (dir, "config.ini");

    try {
        GLib.FileUtils.set_contents (path, "[appearance]\nfont_size=-3\n");
    } catch (GLib.Error e) {
        GLib.Test.fail ();
    }

    var config = new ConfigStore (path).load ();

    assert (config.font_size == Config.DEFAULT_FONT_SIZE);
}

private void test_transparency_clamped () {
    var config = new Config ();

    config.transparency = 0.0;
    assert (config.effective_transparency == Config.MIN_TRANSPARENCY);

    config.transparency = 5.0;
    assert (config.effective_transparency == 1.0);

    config.transparency = 0.42;
    assert (config.effective_transparency == 0.42);
}

private void test_autosave_clamped () {
    var config = new Config ();

    config.autosave_ms = 0;
    assert (config.effective_autosave_ms == Config.MIN_AUTOSAVE_MS);

    config.autosave_ms = 2000;
    assert (config.effective_autosave_ms == 2000);
}

private void test_font_size_clamped () {
    var config = new Config ();

    config.font_size = 0;
    assert (config.effective_font_size == Config.MIN_FONT_SIZE);

    config.font_size = 18;
    assert (config.effective_font_size == 18);
}

private void test_line_height_default () {
    var dir = make_tmp_dir ();
    var path = GLib.Path.build_filename (dir, "config.ini");

    var config = new ConfigStore (path).load ();

    assert (config.line_height == Config.DEFAULT_LINE_HEIGHT);
    assert (config.effective_line_height == 0.0);
}

private void test_line_height_custom () {
    var config = new Config ();

    config.line_height = 1.4;
    assert (config.effective_line_height == 1.4);
}

private void test_line_height_invalid_falls_back () {
    var dir = make_tmp_dir ();
    var path = GLib.Path.build_filename (dir, "config.ini");

    try {
        GLib.FileUtils.set_contents (path, "[appearance]\nline_height=not-a-number\n");
    } catch (GLib.Error e) {
        GLib.Test.fail ();
    }

    var config = new ConfigStore (path).load ();

    assert (config.line_height == Config.DEFAULT_LINE_HEIGHT);
}

private void test_line_height_normal () {
    var config = new Config ();

    config.line_height = 0.0;
    assert (config.effective_line_height == 0.0);

    config.line_height = -2.0;
    assert (config.effective_line_height == 0.0);
}

}
