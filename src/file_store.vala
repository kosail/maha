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

    /**
     * Atomically replace `path` with `contents`.
     *
     * @param sync flush to stable storage. Callers that store non-critical,
     *   frequently-written state (config, session) pass false to avoid an
     *   fsync on every update.
     */
    public static void save_atomic (string path, string contents, bool sync = true) throws GLib.Error {
        // Follow symlinks so saving through one updates its target instead of
        // replacing the link with a regular file.
        string target = resolve_target (path);

        var dir = GLib.Path.get_dirname (target);
        if (dir == null || dir == "") {
            dir = ".";
        }

        // A new temp file starts private (0600) so an existing private file's
        // contents are never briefly world-readable; the destination's mode is
        // restored below. A brand-new file is created as 0666 (umask applies).
        Posix.Stat st;
        bool exists = Posix.stat (target, out st) == 0;
        Posix.mode_t create_mode = exists ? (Posix.mode_t) 0600 : (Posix.mode_t) 0666;

        string tmp;
        int fd = create_temp (dir, create_mode, out tmp);

        try {
            write_all (fd, contents);
            if (sync && Posix.fsync (fd) != 0) {
                throw new GLib.FileError.FAILED ("cannot flush temporary file \"%s\": %s".printf (tmp, GLib.strerror (Posix.errno)));
            }
        } catch (GLib.Error e) {
            Posix.close (fd);
            Posix.unlink (tmp);
            throw e;
        }
        Posix.close (fd);

        if (exists) {
            Posix.chmod (tmp, st.st_mode & 0777);
        }

        if (GLib.FileUtils.rename (tmp, target) != 0) {
            Posix.unlink (tmp);
            throw new GLib.FileError.FAILED ("cannot rename \"%s\" onto \"%s\": %s".printf (tmp, target, GLib.strerror (Posix.errno)));
        }

        if (sync) {
            fsync_dir (dir);
        }
    }

    /**
     * Resolve `path` to the file it ultimately points at when it already
     * exists (so a symlink is preserved). Falls back to `path` for new files
     * or when resolution fails.
     */
    private static string resolve_target (string path) {
        if (!GLib.FileUtils.test (path, GLib.FileTest.EXISTS) &&
            !GLib.FileUtils.test (path, GLib.FileTest.IS_SYMLINK)) {
            return path;
        }
        string? real = Posix.realpath (path, null);
        if (real != null && real != "") {
            return real;
        }
        return path;
    }

    /**
     * Create a uniquely named temporary file in `dir`.
     *
     * Uses a short, bounded name (never derived from the destination's name, so
     * it cannot exceed NAME_MAX) and retries on a name collision.
     */
    private static int create_temp (string dir, Posix.mode_t mode, out string tmp) throws GLib.Error {
        int flags = Posix.O_WRONLY | Posix.O_CREAT | Posix.O_EXCL | Posix.O_TRUNC;

        for (int attempt = 0; attempt < 16; attempt++) {
            tmp = GLib.Path.build_filename (dir, ".maha-%u-%u.tmp".printf (Posix.getpid (), GLib.Random.next_int ()));
            int fd = Posix.open (tmp, flags, mode);
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
