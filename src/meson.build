maha_core_sources = files(
  'paths.vala',
  'text_source.vala',
  'document.vala',
  'file_store.vala',
  'auto_saver.vala',
  'config.vala',
  'config_store.vala',
  'session_store.vala',
  'reopen_stack.vala',
  'keyfile_util.vala',
)

maha_ui_sources = files(
  'theme_controller.vala',
  'editor_search.vala',
  'editor_tab.vala',
  'window.vala',
  'application.vala',
  'main.vala',
)

# Non-GTK core (model, I/O, config, scheduling). Shared by the app and tests.
maha_core = static_library('maha-core',
  maha_core_sources,
  dependencies: [glib_dep, gobject_dep],
  vala_args: ['--pkg=posix'],
  c_args: maha_c_args,
  vala_header: 'maha-core.h',
  vala_vapi: 'maha-core.vapi',
  install: false)

maha_core_dep = declare_dependency(
  link_with: maha_core,
  include_directories: include_directories('.'))

maha_exec = executable('maha',
  maha_ui_sources,
  maha_resources,
  dependencies: [glib_dep, gio_dep, gtk_dep, adw_dep, maha_core_dep],
  vala_args: ['--pkg=posix'],
  c_args: maha_c_args,
  install: true)
