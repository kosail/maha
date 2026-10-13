namespace Maha.Testing {

/** Minimal TextSource backed by a settable string, for tests. */
public class StringTextSource : GLib.Object, Maha.TextSource {
    public string text { get; set; default = ""; }

    public string get_text () {
        return text;
    }
}

public string make_tmp_dir () {
    var dir = GLib.Path.build_filename (GLib.Environment.get_tmp_dir (), "maha-test-%u".printf (GLib.Random.next_int ()));
    GLib.DirUtils.create_with_parents (dir, 0700);
    return dir;
}

public string read_file (string path) {
    try {
        string contents;
        GLib.FileUtils.get_contents (path, out contents);
        return contents;
    } catch (GLib.Error e) {
        return "";
    }
}

public void pump (uint ms) {
    var loop = new GLib.MainLoop ();
    GLib.Timeout.add (ms, () => {
        loop.quit ();
        return GLib.Source.REMOVE;
    });
    loop.run ();
}

}
