module vglyph

$if windows {
	// Static Windows consumers must disable the GLib/GObject DLL import annotations.
	#flag -DGLIB_STATIC_COMPILATION
	#flag -DGOBJECT_STATIC_COMPILATION
	#linker c++
	#flag -liconv
}
