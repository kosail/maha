<p align="center">
  <img src=".github/images/banner.webp" alt="maha" width="560">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License: MIT">
  <img src="https://img.shields.io/badge/GTK-4-red.svg" alt="GTK 4">
  <img src="https://img.shields.io/badge/libadwaita-1-6c8ebf.svg" alt="libadwaita">
</p>

maha is a small text editor for the Linux desktop. It is built with GTK4 and libadwaita, so it picks up the system light/dark preference and looks like the rest of your apps. Under the hood it is deliberately boring: plain text only, no syntax highlighting, no plugins. The part that is not boring is file handling, because a notepad that loses your work is useless.

I created this project because I wanted a dead simple notepad with a modern and clean interface. I wanted transparency and blur. But nice aesthetics aside, the main reason is cos I needed an extremely fast and reliable notepad. You see, my laptop has a faulty motherboard and it randomly reboots. I often lose my work and that frustrates me.

Though the best editor I've been using that fit my needs has been VS Code, I wanted something focused. My inspiration of design was Apostrophe, the Markdown editor from the GNOME team (god I love that app!!!). 

But I have to be honest with you: I needed this app, but I don't have for it... at least for these months. Thus, I built it with heavy AI assistance, then reviewed, tested, and debugged by myself. The design decisions below (atomic writes, corruption recovery, session handling) came out from my own needs. Everything here is also modular, and on any issue it arises, fixes will be cheap and easy.


<!-- Add a screenshot at .github/images/screenshot.png and reference it here before publishing. -->

## Features

- Tabs.
- Autosave on a debounce, on by default (since I always need autosave, I set no autosave disabling mechanism).
- Atomic writes, so a crash never leaves a half-written file.
- Recovery for files with NUL corruption.
- Unsaved documents are backed by a scratch file, so a "New tab" survives a crash before you ever name it (just like VS Code does).
- Session restore: reopens the last file, or the last unsaved tab.
- Configurable window transparency, font family, and font size.
- Follows the system light/dark theme.

## Requirements

- A Vala compiler (`valac`)
- Meson and Ninja
- `glib-2.0` and `gio-2.0`
- `gtk4`
- `libadwaita-1` (>= 1.0)

For the GUI smoke test you also need `Xvfb`, `xdotool`, and `dbus-run-session`. The test skips itself if they are missing.

## Build and run

To just generate the binary:

```sh
meson setup build
meson compile -C build
./build/src/maha
```

To install it (local install):

```sh
meson setup build --prefix ~/.local
meson install -C build
```

## Keyboard shortcuts

| Action   | Shortcut      |
| -------- | ------------- |
| New tab  | `Ctrl+T`      |
| Open     | `Ctrl+O`      |
| Save     | `Ctrl+S`      |
| Quit     | `Ctrl+Q`      |

## Configuration

Settings live in `~/.config/maha/config.ini` and are not exposed in the UI because I wanted to keep it as clean as possible (personal preference). The file is created with defaults on first run. A malformed file is never overwritten, and any missing or invalid key just falls back to its default. Default config/values are:

```ini
[appearance]
transparency=0.85
font=Monospace
font_size=11
line_height=0

[editor]
autosave_ms=1500
```

`transparency` is the window background opacity, clamped to 0.05 through 1.0. `font` is a Pango family name. `font_size` is in points. `autosave_ms` is the debounce delay before a change is written, be concious with a value in here because if it is too low, you will cause unnecesary wear to your SSD.

The session file at `~/.config/maha/session` remembers the last document. Scratch files for unsaved tabs go in `~/.cache/maha/`.

## How it works

**Atomic saves.** `save_atomic` never writes over your file in place. It writes a temporary file in the same directory, flushes it with `fsync`, then renames it over the destination and flushes the directory. A crash at any point leaves either the old file or the new one, never a mix of the two. See `src/file_store.vala`.

**Recovery.** On read, a NUL byte is treated as a sign of corruption. Everything from the first NUL onward is dropped and the recoverable prefix is written back on a best-effort basis, so a read-only file can still be opened. Any other invalid byte sequence is replaced with U+FFFD before the text reaches the editor, since the editor only accepts valid UTF-8.

**Autosave.** Editing a document arms a debounce timer. When it fires, the current text is pulled from the editor and written through the same atomic path. Text is pulled lazily at save time, so typing in a large file does not copy the whole buffer on every keystroke. See `src/auto_saver.vala`.

**Scratch files and the session.** A document with no path is backed by a UUID-named scratch file in the cache directory. That way the text exists on disk before it has a name, and a crash cannot lose it. The session store remembers which document was active, whether that is a real file or a scratch id, and restores it on the next run.

## Testing

```sh
meson test -C build
```

The core suite has 35 tests covering document state, atomic I/O, corruption recovery, config parsing, autosave, and session handling. There is also a headless GUI smoke test that launches the real binary under Xvfb and sends `Ctrl+S`, which guards the GTK shortcut controller that the unit tests cannot reach.

## License

MIT. See [LICENSE](LICENSE).
