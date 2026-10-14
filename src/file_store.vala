namespace Maha {

// Bound directly so classification can validate a byte buffer in place,
// without copying it into a string first.
[CCode (cname = "g_utf8_validate", cheader_filename = "glib.h")]
extern static bool utf8_validate (void* str, ssize_t max_len, void* end);

/**
 * File I/O with a focus on integrity.
 *
 * `save_atomic` never writes in place: it writes a temporary file in the same
 * directory, flushes it to disk, then `rename(2)`s it over the destination.
 * A crash at any point leaves either the previous file or the new one, never a
 * half-written file.
 *
 * `read` is strictly read-only: it never modifies the file it reads. It
 * classifies the bytes so the caller can refuse (or open read-only) anything
 * that is not text, instead of mangling a binary file. A text file whose tail
 * was zero-filled by a crash is reported as `CORRUPT_TEXT` and its recoverable
 * prefix is returned, but the original file is left untouched until the user
 * saves.
 */
public class FileStore : GLib.Object {

    /** How the bytes of a file should be treated. */
    public enum ContentKind {
        /** Valid UTF-8 with no suspicious bytes. */
        TEXT,
        /** Looks like text whose tail was zero-filled by a crash. */
        CORRUPT_TEXT,
        /** Not text (contains binary data). */
        BINARY
    }

    /** Result of reading a file: its classification and (best-effort) text. */
    public class ReadResult : GLib.Object {
        public ContentKind kind { get; private set; }
        public string text { get; private set; }

        public ReadResult (ContentKind kind, string text) {
            this.kind = kind;
            this.text = text;
        }
    }

    /** Fraction of non-text control bytes above which data is treated as binary. */
    private const double CONTROL_RATIO_LIMIT = 0.10;

    /** Largest file maha will load into memory. */
    private const int64 MAX_READ_BYTES = 64 * 1024 * 1024;

    /** Index of the first NUL byte in `data`, or -1 if there is none. */
    private static int64 find_nul (uint8[] data) {
        for (int64 i = 0; i < data.length; i++) {
            if (data[i] == 0) {
                return i;
            }
        }
        return -1;
    }

    /**
     * Read a file and classify it, without ever writing to it.
     *
     * For `TEXT` and `CORRUPT_TEXT` the returned text is valid UTF-8 (for the
     * latter, only the recoverable prefix before the corruption). For `BINARY`
     * the text is a lossy, read-only view (invalid bytes become U+FFFD), unless
     * `binary_view` is false, in which case no view is built (callers that only
     * care about the classification avoid the extra allocation).
     */
    public static ReadResult read (string path, bool binary_view = true) throws GLib.Error {
        uint8[] data = read_bytes (path);
        ContentKind kind = classify (data);

        switch (kind) {
            case ContentKind.TEXT:
                return new ReadResult (kind, bytes_to_string (data, data.length));
            case ContentKind.CORRUPT_TEXT:
                int64 nul = find_nul (data);
                return new ReadResult (kind, sanitize (bytes_to_string (data, nul)));
            default:
                return new ReadResult (ContentKind.BINARY, binary_view ? to_view_text (data, data.length) : "");
        }
    }

    /**
     * Classify raw file bytes.
     *
     * A NUL byte alone does not make a file binary: a crash can zero-fill the
     * tail of a real text file. So a NUL is only treated as crash corruption
     * (`CORRUPT_TEXT`) when the bytes before it look like text *and* every byte
     * from the first NUL to the end is NUL. Anything else - data after the NUL,
     * invalid UTF-8, or a high ratio of control bytes - is `BINARY`.
     */
    public static ContentKind classify (uint8[] data) {
        if (data.length == 0) {
            return ContentKind.TEXT;
        }

        int64 nul = find_nul (data);
        if (nul < 0) {
            return is_text_like (data, data.length) ? ContentKind.TEXT : ContentKind.BINARY;
        }

        // A NUL at the very start, or a non-text prefix, is not recoverable text.
        if (nul == 0 || !is_text_like (data, nul)) {
            return ContentKind.BINARY;
        }

        // Only a zero-filled tail counts as corruption; real data after the NUL
        // means this is a binary file (an image, a PDF, an executable, ...).
        for (int64 i = nul; i < data.length; i++) {
            if (data[i] != 0) {
                return ContentKind.BINARY;
            }
        }

        return ContentKind.CORRUPT_TEXT;
    }

    /** True when `data[0..len)` is valid UTF-8 with few control bytes. */
    private static bool is_text_like (uint8[] data, int64 len) {
        if (len == 0) {
            return true;
        }

        if (!utf8_validate ((void*) data, (ssize_t) len, null)) {
            return false;
        }

        int64 control = 0;
        for (int64 i = 0; i < len; i++) {
            uint8 b = data[i];
            bool allowed = b == 0x09 || b == 0x0A || b == 0x0D;
            if ((b < 0x20 && !allowed) || b == 0x7F) {
                control++;
            }
        }
        return ((double) control / (double) len) <= CONTROL_RATIO_LIMIT;
    }

    /**
     * Build a valid-UTF-8, NUL-free view of arbitrary bytes for read-only
     * display. NUL and invalid sequences become U+FFFD.
     */
    private static string to_view_text (uint8[] data, int64 len) {
        var sb = new StringBuilder.sized ((int) len);
        for (int64 i = 0; i < len; i++) {
            if (data[i] == 0) {
                sb.append ("\uFFFD");
            } else {
                sb.append_c ((char) data[i]);
            }
        }
        string s = sb.str;
        return s.validate () ? s : s.make_valid ();
    }

    /** Read the entire file into memory using plain POSIX I/O. */
    private static uint8[] read_bytes (string path) throws GLib.Error {
        // O_NONBLOCK so opening a FIFO can never block; regular files ignore it.
        int fd = Posix.open (path, Posix.O_RDONLY | Posix.O_CLOEXEC | Posix.O_NONBLOCK);
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
        // Only regular files: a FIFO, socket or device can hang or never end.
        if (!Posix.S_ISREG (st.st_mode)) {
            Posix.close (fd);
            throw new GLib.FileError.FAILED ("\"%s\" is not a regular file".printf (path));
        }
        if ((int64) st.st_size > MAX_READ_BYTES) {
            Posix.close (fd);
            throw new GLib.FileError.FAILED ("\"%s\" is too large to open".printf (path));
        }

        // Grow the buffer ourselves: appending chunk slices to a ByteArray
        // would copy every chunk twice.
        size_t capacity = 65536;
        long size = (long) st.st_size;
        if (size > 0) {
            capacity = (size_t) size;
        }
        if (capacity > (size_t) MAX_READ_BYTES) {
            capacity = (size_t) MAX_READ_BYTES;
        }
        uint8[] data = new uint8[capacity];
        size_t used = 0;
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
            // A file that lies about its size (or grew) still cannot exceed the cap.
            if (used + (size_t) n > (size_t) MAX_READ_BYTES) {
                Posix.close (fd);
                throw new GLib.FileError.FAILED ("\"%s\" is too large to open".printf (path));
            }
            if (used + (size_t) n > data.length) {
                size_t newcap = data.length == 0 ? 65536 : data.length;
                while (newcap < used + (size_t) n) {
                    newcap *= 2;
                }
                uint8[] bigger = new uint8[newcap];
                GLib.Memory.copy (bigger, data, used);
                data = bigger;
            }
            GLib.Memory.copy (((uint8*) data) + used, chunk, (size_t) n);
            used += (size_t) n;
        }
        Posix.close (fd);

        if (used == data.length) {
            return data;
        }
        uint8[] exact = new uint8[used];
        if (used > 0) {
            GLib.Memory.copy (exact, data, used);
        }
        return exact;
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
            Posix.chmod (tmp, st.st_mode & 07777);
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
        string current = path;
        // Follow symlink chains (bounded, to survive a loop).
        for (int i = 0; i < 40; i++) {
            if (!GLib.FileUtils.test (current, GLib.FileTest.IS_SYMLINK)) {
                return current;
            }
            string link;
            try {
                link = GLib.FileUtils.read_link (current);
            } catch (GLib.Error e) {
                return current;
            }
            if (link == "") {
                return current;
            }
            if (!GLib.Path.is_absolute (link)) {
                link = GLib.Path.build_filename (GLib.Path.get_dirname (current), link);
            }
            current = link;
        }
        return current;
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
            tmp = GLib.Path.build_filename (dir, ".maha-%u-%u.tmp".printf ((uint) Posix.getpid (), (uint) GLib.Random.next_int ()));
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
        int dfd = Posix.open (dir, Posix.O_RDONLY | Posix.O_CLOEXEC);
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
