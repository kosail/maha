namespace Maha {

/**
 * File I/O with a focus on integrity.
 *
 * `save_atomic` never writes in place: it writes a temporary file in the same
 * directory, flushes it to disk, then `rename(2)`s it over the destination.
 * A crash at any point leaves either the previous file or the new one, never a
 * half-written file.
 *
 * `read` guarantees the returned text is valid UTF-8 so it can be handed to the
 * editor: NUL bytes (a common symptom of a crash) are treated as corruption and
 * everything from the first NUL onward is dropped, while any other invalid byte
 * sequence is replaced with U+FFFD. A file repaired from NUL corruption is
 * written back best-effort without failing the read.
 */
public class FileStore : GLib.Object {

    /** Index of the first NUL byte in `data`, or -1 if there is none. */
    public static int64 find_nul (uint8[] data) {
        for (int64 i = 0; i < data.length; i++) {
            if (data[i] == 0) {
                return i;
            }
        }
        return -1;
    }

    /**
     * Read the whole file as valid UTF-8 text.
     *
     * @param recovered set to true when NUL corruption was found and repaired.
     */
    public static string read (string path, out bool recovered) throws GLib.Error {
        recovered = false;

        uint8[] data = read_bytes (path);

        int64 nul = find_nul (data);
        if (nul < 0) {
            return sanitize (bytes_to_string (data, data.length));
        }

        recovered = true;
        string cleaned = sanitize (bytes_to_string (data, nul));

        // Best effort: a read-only file must still be viewable even if the
        // repaired content cannot be written back.
        try {
            save_atomic (path, cleaned);
        } catch (GLib.Error e) {
            GLib.warning ("maha: could not rewrite recovered file \"%s\": %s", path, e.message);
        }

        GLib.warning ("maha: NUL corruption detected in \"%s\"; kept the first %s bytes and discarded the remainder.", path, nul.to_string ());
        return cleaned;
    }

    /** Read the entire file into memory using plain POSIX I/O. */
    private static uint8[] read_bytes (string path) throws GLib.Error {
        int fd = Posix.open (path, Posix.O_RDONLY | Posix.O_CLOEXEC);
        if (fd < 0) {
            throw new GLib.FileError.FAILED ("cannot open \"%s\": %s".printf (path, GLib.strerror (Posix.errno)));
        }

        Posix.Stat st;
        if (Posix.fstat (fd, out st) != 0) {
            int err = Posix.errno;
            Posix.close (fd);
            throw new GLib.FileError.FAILED ("cannot stat \"%s\": %s".printf (path, GLib.strerror (err)));
        }
        if (Posix.S_ISDIR (st.st_mode)) {
            Posix.close (fd);
            throw new GLib.FileError.FAILED ("\"%s\" is a directory".printf (path));
        }

        var buffer = new GLib.ByteArray.sized (4096);
        uint8[] chunk = new uint8[65536];
        while (true) {
            ssize_t n = Posix.read (fd, chunk, chunk.length);
            if (n < 0) {
                if (Posix.errno == Posix.EINTR) {
                    continue;
                }
                int err = Posix.errno;
                Posix.close (fd);
                throw new GLib.FileError.FAILED ("cannot read \"%s\": %s".printf (path, GLib.strerror (err)));
            }
            if (n == 0) {
                break;
            }
            buffer.append (chunk[0:(int) n]);
        }
        Posix.close (fd);
        return buffer.steal ();
    }

    /** Atomically replace `path` with `contents`. */
    public static void save_atomic (string path, string contents) throws GLib.Error {
        var dir = GLib.Path.get_dirname (path);
        if (dir == null || dir == "") {
            dir = ".";
        }

        string tmp;
        int fd = create_temp (dir, out tmp);

        try {
            write_all (fd, contents);
            if (Posix.fsync (fd) != 0) {
                throw new GLib.FileError.FAILED ("cannot flush temporary file \"%s\": %s".printf (tmp, GLib.strerror (Posix.errno)));
            }
        } catch (GLib.Error e) {
            Posix.close (fd);
            Posix.unlink (tmp);
            throw e;
        }
        Posix.close (fd);

        preserve_permissions (path, tmp);

        if (GLib.FileUtils.rename (tmp, path) != 0) {
            Posix.unlink (tmp);
            throw new GLib.FileError.FAILED ("cannot rename \"%s\" onto \"%s\": %s".printf (tmp, path, GLib.strerror (Posix.errno)));
        }

        fsync_dir (dir);
    }

    /**
     * Create a uniquely named temporary file in `dir`.
     *
     * Uses a short, bounded name (never derived from the destination's name, so
     * it cannot exceed NAME_MAX) and retries on a name collision.
     */
    private static int create_temp (string dir, out string tmp) throws GLib.Error {
        int flags = Posix.O_WRONLY | Posix.O_CREAT | Posix.O_EXCL | Posix.O_TRUNC;

        for (int attempt = 0; attempt < 16; attempt++) {
            tmp = GLib.Path.build_filename (dir, ".maha-%u-%u.tmp".printf (Posix.getpid (), GLib.Random.next_int ()));
            int fd = Posix.open (tmp, flags, (Posix.mode_t) 0644);
            if (fd >= 0) {
                return fd;
            }
            if (Posix.errno != Posix.EEXIST) {
                throw new GLib.FileError.FAILED ("cannot create temporary file in \"%s\": %s".printf (dir, GLib.strerror (Posix.errno)));
            }
        }

        throw new GLib.FileError.FAILED ("cannot create a unique temporary file in \"%s\"".printf (dir));
    }

    private static void write_all (int fd, string contents) throws GLib.Error {
        unowned uint8[] bytes = contents.data;
        uint8* ptr = (uint8*) bytes;
        size_t remaining = bytes.length;

        while (remaining > 0) {
            ssize_t written = Posix.write (fd, ptr, remaining);
            if (written < 0) {
                if (Posix.errno == Posix.EINTR) {
                    continue;
                }
                throw new GLib.FileError.FAILED ("write() failed: %s".printf (GLib.strerror (Posix.errno)));
            }
            ptr += written;
            remaining -= (size_t) written;
        }
    }

    private static void preserve_permissions (string source, string dest) {
        Posix.Stat st;
        if (Posix.stat (source, out st) == 0) {
            Posix.chmod (dest, st.st_mode & 0777);
        }
    }

    private static void fsync_dir (string dir) {
        int dfd = Posix.open (dir, Posix.O_RDONLY);
        if (dfd >= 0) {
            Posix.fsync (dfd);
            Posix.close (dfd);
        }
    }

    private static string bytes_to_string (uint8[] data, int64 len) {
        var buf = new uint8[(int) len + 1];
        if (len > 0) {
            GLib.Memory.copy (buf, data, (size_t) len);
        }
        buf[(int) len] = 0;
        return (string) buf;
    }

    private static string sanitize (string text) {
        if (text.validate ()) {
            return text;
        }
        return text.make_valid ();
    }

    /** Best-effort delete of `path`; missing files are ignored. */
    public static void remove (string path) {
        if (GLib.FileUtils.test (path, GLib.FileTest.EXISTS)) {
            GLib.FileUtils.unlink (path);
        }
    }
}

}
