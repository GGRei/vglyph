#ifndef VGLYPH_PANGO_CONST_COMPAT_H
#define VGLYPH_PANGO_CONST_COMPAT_H

#include <pango/pango.h>

/* Borrowed read-only pointers for V bindings; do not free or mutate. */
static inline char* vglyph_pango_layout_get_text_borrowed(PangoLayout* layout) {
	return (char*)pango_layout_get_text(layout);
}

static inline PangoFontDescription* vglyph_pango_layout_get_font_description_borrowed(PangoLayout* layout) {
	return (PangoFontDescription*)pango_layout_get_font_description(layout);
}

static inline PangoLogAttr* vglyph_pango_layout_get_log_attrs_readonly_borrowed(PangoLayout* layout, int* n_attrs) {
	return (PangoLogAttr*)pango_layout_get_log_attrs_readonly(layout, n_attrs);
}

static inline char* vglyph_pango_font_description_get_family_borrowed(const PangoFontDescription* desc) {
	return (char*)pango_font_description_get_family(desc);
}

#endif
