module vglyph

#include "@VMODROOT/windows_static_link_test.h"

fn C.vglyph_test_glib_static_compilation() int
fn C.vglyph_test_gobject_static_compilation() int

fn test_windows_static_consumer_macros_follow_pkgconfig_mode() {
	$if windows {
		$if $d('v:static_pkgconfig', false) {
			assert C.vglyph_test_glib_static_compilation() == 1
			assert C.vglyph_test_gobject_static_compilation() == 1
		} $else {
			assert C.vglyph_test_glib_static_compilation() == 0
			assert C.vglyph_test_gobject_static_compilation() == 0
		}
	} $else {
		assert C.vglyph_test_glib_static_compilation() == 0
		assert C.vglyph_test_gobject_static_compilation() == 0
	}
}
