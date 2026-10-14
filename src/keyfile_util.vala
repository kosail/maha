namespace Maha {

/**
 * Helpers for storing arbitrary values (file paths, font names) in a
 * `GLib.KeyFile` without depending on the key file's own escaping rules.
 *
 * `save` writes values through `keyfile_escape`; `load` reads them back with
 * `keyfile_unescape`. A path containing a newline or backslash therefore
 * round-trips instead of corrupting the file.
 */
public string keyfile_escape (string value) {
    var sb = new StringBuilder ();
    foreach (uint8 b in value.data) {
        switch (b) {
        case '\\': sb.append ("\\\\"); break;
        case '\n': sb.append ("\\n"); break;
        case '\r': sb.append ("\\r"); break;
        case '\t': sb.append ("\\t"); break;
        default: sb.append_c ((char) b); break;
        }
    }
    return sb.str;
}

public string keyfile_unescape (string value) {
    var sb = new StringBuilder.sized (value.length);
    for (int i = 0; i < value.length; i++) {
        char c = value[i];
        if (c != '\\') {
            sb.append_c (c);
            continue;
        }
        if (i + 1 >= value.length) {
            // A lone trailing backslash is literal, not an escape introducer.
            sb.append_c ('\\');
            break;
        }
        i++;
        switch (value[i]) {
        case 'n': sb.append_c ('\n'); break;
        case 'r': sb.append_c ('\r'); break;
        case 't': sb.append_c ('\t'); break;
        case '\\': sb.append_c ('\\'); break;
        default: sb.append_c (value[i]); break;
        }
    }
    return sb.str;
}

}
