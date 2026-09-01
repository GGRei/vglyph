#ifndef VGLYPH_WINDOWS_STATIC_LINK_TEST_H
#define VGLYPH_WINDOWS_STATIC_LINK_TEST_H

static inline int vglyph_test_glib_static_compilation(void) {
#ifdef GLIB_STATIC_COMPILATION
	return 1;
#else
	return 0;
#endif
}

static inline int vglyph_test_gobject_static_compilation(void) {
#ifdef GOBJECT_STATIC_COMPILATION
	return 1;
#else
	return 0;
#endif
}

#endif
