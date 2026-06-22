module accessibility

// Stub implementation for platforms without native accessibility
// (Windows, FreeBSD, etc.). Selected by new_accessibility_backend()
// when no platform backend matches.
struct StubAccessibilityBackend {}

fn (mut b StubAccessibilityBackend) update_tree(_nodes map[int]AccessibilityNode, _root_id int) {
	// Do nothing on unsupported platforms.
}

fn (mut b StubAccessibilityBackend) set_focus(_node_id int) {
	// Do nothing
}

fn (mut b StubAccessibilityBackend) post_notification(_node_id int,
	_notification AccessibilityNotification) {
	// Do nothing
}

fn (mut b StubAccessibilityBackend) update_text_field(_node_id int, _value string,
	_selected_range Range, _cursor_line int) {
	// Do nothing
}

fn (mut b StubAccessibilityBackend) flush() {
	// Do nothing
}
