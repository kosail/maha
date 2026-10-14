maha_resources = gnome.compile_resources('maha-resources',
  'maha.gresource.xml',
  c_name: 'maha_resources',
  source_dir: meson.current_source_dir())

# favicon.png is the source master the icons/ sizes were generated from; it is
# intentionally neither installed nor compiled into the gresource.

# hicolor icon theme layout (<size>/apps/...) for the installed app icon.
# strip_directory drops the leading "icons/" so the size dirs land directly
# under hicolor/.
install_subdir('icons',
  install_dir: get_option('datadir') / 'icons' / 'hicolor',
  strip_directory: true)

install_data('com.korealm.maha.desktop',
  install_dir: get_option('datadir') / 'applications')
