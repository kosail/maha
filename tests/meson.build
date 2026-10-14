test_sources = files(
  'test_utils.vala',
  'test_document.vala',
  'test_file_store.vala',
  'test_recovery.vala',
  'test_config.vala',
  'test_auto_saver.vala',
  'test_session.vala',
  'test_reopen.vala',
  'test_main.vala',
)

maha_tests = executable('maha-tests',
  test_sources,
  dependencies: [glib_dep, gio_dep, maha_core_dep],
  vala_args: ['--pkg=posix'],
  c_args: maha_c_args,
  install: false)

test('core', maha_tests, timeout: 60)

# Headless GUI smoke test: runs the real binary under Xvfb and exercises the
# Ctrl+S shortcut. Skipped when Xvfb/xdotool are unavailable.
run_gui_test = find_program('run-gui-test.sh')
test('gui-smoke', run_gui_test, args: [maha_exec], timeout: 90)
