module vglyph

import gg

// Regression coverage for the typed TextStyle.rise baseline-shift primitive.

const rise_test_font = 'Roboto Flex 24'
const rise_test_font_path = '${@DIR}/assets/RobotoFlex.ttf'
const rise_selection_tolerance = f32(0.75)

fn new_rise_test_context() !&Context {
	mut ctx := new_context(1.0)!
	ctx.add_font_file(rise_test_font_path) or {
		ctx.free()
		return error('failed to load rise test font ${rise_test_font_path}: ${err}')
	}
	return ctx
}

fn f64_abs(v f64) f64 {
	return if v < 0 { -v } else { v }
}

fn item_for_index(layout Layout, index int) ?Item {
	for item in layout.items {
		if index >= item.start_index && index < item.start_index + item.length {
			return item
		}
	}
	return none
}

fn char_rect_for_index(layout Layout, index int) ?CharRect {
	for rect in layout.char_rects {
		if rect.index == index {
			return rect
		}
	}
	return none
}

fn line_for_index(layout Layout, index int) ?Line {
	for line in layout.lines {
		if index >= line.start_index && index < line.start_index + line.length {
			return line
		}
	}
	return none
}

fn assert_rect_contains_rect(outer gg.Rect, inner gg.Rect, label string) {
	assert outer.x <= inner.x + rise_selection_tolerance, '${label} left edge should contain rect'
	assert outer.x + outer.width + rise_selection_tolerance >= inner.x + inner.width, '${label} right edge should contain rect'
	assert outer.y <= inner.y + rise_selection_tolerance, '${label} top edge should contain rect'
	assert outer.y + outer.height + rise_selection_tolerance >= inner.y + inner.height, '${label} bottom edge should contain rect'
}

fn assert_hit_test_center(layout Layout, rect gg.Rect, index int, label string) {
	center_x := rect.x + rect.width / 2
	center_y := rect.y + rect.height / 2
	assert layout.hit_test(center_x, center_y) == index, '${label} hit-test center should resolve to byte index'
}

fn assert_selection_contains_rect(selection gg.Rect, rect gg.Rect, label string) {
	assert selection.x <= rect.x + rise_selection_tolerance, '${label} selection left should cover char rect'
	assert selection.x + selection.width + rise_selection_tolerance >= rect.x + rect.width, '${label} selection right should cover char rect'
	assert selection.y <= rect.y + rise_selection_tolerance, '${label} selection top should cover char rect'
	assert selection.y + selection.height + rise_selection_tolerance >= rect.y + rect.height, '${label} selection bottom should cover char rect'
}

fn test_plain_text_rise_moves_base_style_run() {
	mut ctx := new_rise_test_context()!
	defer { ctx.free() }

	base := ctx.layout_text('A', TextConfig{
		style: TextStyle{
			font_name: rise_test_font
		}
	})!
	raised := ctx.layout_text('A', TextConfig{
		style: TextStyle{
			font_name: rise_test_font
			rise:      8
		}
	})!
	lowered := ctx.layout_text('A', TextConfig{
		style: TextStyle{
			font_name: rise_test_font
			rise:      -6
		}
	})!

	assert base.items.len > 0
	assert raised.items.len > 0
	assert lowered.items.len > 0

	assert raised.items[0].y < base.items[0].y, 'base TextConfig.style positive rise should move the run baseline up'
	assert lowered.items[0].y > base.items[0].y, 'base TextConfig.style negative rise should move the run baseline down'

	base_rect := char_rect_for_index(base, 0) or {
		assert false, 'base char rect missing'
		return
	}
	raised_rect := char_rect_for_index(raised, 0) or {
		assert false, 'raised char rect missing'
		return
	}
	lowered_rect := char_rect_for_index(lowered, 0) or {
		assert false, 'lowered char rect missing'
		return
	}
	assert raised_rect.rect.y < base_rect.rect.y, 'base TextConfig.style positive rise should move hit geometry up'
	assert lowered_rect.rect.y > base_rect.rect.y, 'base TextConfig.style negative rise should move hit geometry down'
	raised_item_delta := base.items[0].y - raised.items[0].y
	lowered_item_delta := lowered.items[0].y - base.items[0].y
	raised_rect_delta := f64(base_rect.rect.y - raised_rect.rect.y)
	lowered_rect_delta := f64(lowered_rect.rect.y - base_rect.rect.y)
	assert raised_item_delta > 6.0, 'positive rise should move item baseline by roughly one rise'
	assert raised_item_delta < 10.0, 'positive rise should not be applied twice to item baseline'
	assert lowered_item_delta > 4.0, 'negative rise should move item baseline by roughly one rise'
	assert lowered_item_delta < 8.0, 'negative rise should not be applied twice to item baseline'
	assert raised_rect_delta > 6.0, 'positive rise should move hit geometry by roughly one rise'
	assert raised_rect_delta < 10.0, 'positive rise should not be applied twice to hit geometry'
	assert lowered_rect_delta > 4.0, 'negative rise should move hit geometry by roughly one rise'
	assert lowered_rect_delta < 8.0, 'negative rise should not be applied twice to hit geometry'
	assert f64_abs(raised_item_delta - raised_rect_delta) <= 1.0, 'item and hit geometry rise should stay coherent'
	assert f64_abs(lowered_item_delta - lowered_rect_delta) <= 1.0, 'lowered item and hit geometry rise should stay coherent'

	raised_cursor := raised.get_cursor_pos(0) or {
		assert false, 'raised cursor geometry missing'
		return
	}
	assert raised_cursor.y == raised_rect.rect.y
	assert raised_cursor.height == raised_rect.rect.height

	lowered_cursor := lowered.get_cursor_pos(0) or {
		assert false, 'lowered cursor geometry missing'
		return
	}
	assert lowered_cursor.y == lowered_rect.rect.y
	assert lowered_cursor.height == lowered_rect.rect.height

	raised_selection := raised.get_selection_rects(0, 1)
	assert raised_selection.len > 0, 'raised selection geometry missing'
	assert_selection_contains_rect(raised_selection[0], raised_rect.rect, 'raised base-style')

	lowered_selection := lowered.get_selection_rects(0, 1)
	assert lowered_selection.len > 0, 'lowered selection geometry missing'
	assert_selection_contains_rect(lowered_selection[0], lowered_rect.rect, 'lowered base-style')

	assert_hit_test_center(base, base_rect.rect, 0, 'base-style plain')
	assert_hit_test_center(raised, raised_rect.rect, 0, 'base-style raised')
	assert_hit_test_center(lowered, lowered_rect.rect, 0, 'base-style lowered')
}

fn test_rich_text_rise_moves_run_geometry() {
	mut ctx := new_rise_test_context()!
	defer { ctx.free() }

	plain := ctx.layout_text('ABC', TextConfig{
		style: TextStyle{
			font_name: rise_test_font
		}
	})!

	rt := RichText{
		runs: [
			StyleRun{
				text: 'A'
			},
			StyleRun{
				text:  'B'
				style: TextStyle{
					rise: 8
				}
			},
			StyleRun{
				text:  'C'
				style: TextStyle{
					rise: -6
				}
			},
		]
	}

	layout := ctx.layout_rich_text(rt, TextConfig{
		style: TextStyle{
			font_name: rise_test_font
		}
	})!

	base_item := item_for_index(layout, 0) or {
		assert false, 'base run item missing'
		return
	}
	raised_item := item_for_index(layout, 1) or {
		assert false, 'raised run item missing'
		return
	}
	lowered_item := item_for_index(layout, 2) or {
		assert false, 'lowered run item missing'
		return
	}

	assert raised_item.y < base_item.y, 'positive rise should move the run baseline up'
	assert lowered_item.y > base_item.y, 'negative rise should move the run baseline down'

	plain_base_item := item_for_index(plain, 0) or {
		assert false, 'plain base run item missing'
		return
	}
	assert f64_abs(base_item.y - plain_base_item.y) <= 1.0, 'unraised run in a mixed-rise line should stay on the plain baseline'

	base_rect := char_rect_for_index(layout, 0) or {
		assert false, 'base char rect missing'
		return
	}
	raised_rect := char_rect_for_index(layout, 1) or {
		assert false, 'raised char rect missing'
		return
	}
	lowered_rect := char_rect_for_index(layout, 2) or {
		assert false, 'lowered char rect missing'
		return
	}

	assert raised_rect.rect.y < base_rect.rect.y, 'positive rise should move hit geometry up'
	assert lowered_rect.rect.y > base_rect.rect.y, 'negative rise should move hit geometry down'
	assert_hit_test_center(layout, base_rect.rect, 0, 'mixed-rise base')
	assert_hit_test_center(layout, raised_rect.rect, 1, 'mixed-rise raised')
	assert_hit_test_center(layout, lowered_rect.rect, 2, 'mixed-rise lowered')

	plain_base_rect := char_rect_for_index(plain, 0) or {
		assert false, 'plain base char rect missing'
		return
	}
	assert f64_abs(f64(base_rect.rect.y - plain_base_rect.rect.y)) <= 1.0, 'unraised run hit geometry should stay on the plain baseline'

	line := line_for_index(layout, 0) or {
		assert false, 'mixed-rise line geometry missing'
		return
	}
	assert_rect_contains_rect(line.rect, base_rect.rect, 'mixed-rise line/base')
	assert_rect_contains_rect(line.rect, raised_rect.rect, 'mixed-rise line/raised')
	assert_rect_contains_rect(line.rect, lowered_rect.rect, 'mixed-rise line/lowered')

	raised_cursor := layout.get_cursor_pos(1) or {
		assert false, 'raised cursor geometry missing'
		return
	}
	assert raised_cursor.y == raised_rect.rect.y
	assert raised_cursor.height == raised_rect.rect.height

	raised_selection := layout.get_selection_rects(1, 2)
	assert raised_selection.len > 0, 'raised selection geometry missing'
	assert_selection_contains_rect(raised_selection[0], raised_rect.rect, 'raised')

	cross_run_selection := layout.get_selection_rects(0, 3)
	assert cross_run_selection.len > 0, 'cross-run selection geometry missing'
	assert_selection_contains_rect(cross_run_selection[0], base_rect.rect, 'cross-run base')
	assert_selection_contains_rect(cross_run_selection[0], raised_rect.rect, 'cross-run raised')
	assert_selection_contains_rect(cross_run_selection[0], lowered_rect.rect, 'cross-run lowered')

	end_cursor := layout.get_cursor_pos(3) or {
		assert false, 'mixed-rise end cursor geometry missing'
		return
	}
	assert end_cursor.y == line.rect.y
	assert end_cursor.height == line.rect.height
}

fn test_multiline_rise_stays_on_own_line_geometry() {
	mut ctx := new_rise_test_context()!
	defer { ctx.free() }

	text := 'AB\nCD'
	plain := ctx.layout_text(text, TextConfig{
		style: TextStyle{
			font_name: rise_test_font
		}
	})!
	layout := ctx.layout_rich_text(RichText{
		runs: [
			StyleRun{
				text: 'A'
			},
			StyleRun{
				text:  'B'
				style: TextStyle{
					rise: 8
				}
			},
			StyleRun{
				text: '\nCD'
			},
		]
	}, TextConfig{
		style: TextStyle{
			font_name: rise_test_font
		}
	})!

	assert layout.lines.len == 2, 'explicit newline should produce two lines'

	first_line := line_for_index(layout, 0) or {
		assert false, 'first line geometry missing'
		return
	}
	second_line := line_for_index(layout, 3) or {
		assert false, 'second line geometry missing'
		return
	}
	assert second_line.rect.y > first_line.rect.y, 'second line should stay below the raised first line'

	first_base_rect := char_rect_for_index(layout, 0) or {
		assert false, 'first line base char rect missing'
		return
	}
	first_raised_rect := char_rect_for_index(layout, 1) or {
		assert false, 'first line raised char rect missing'
		return
	}
	second_c_rect := char_rect_for_index(layout, 3) or {
		assert false, 'second line C char rect missing'
		return
	}
	second_d_rect := char_rect_for_index(layout, 4) or {
		assert false, 'second line D char rect missing'
		return
	}
	assert first_raised_rect.rect.y < first_base_rect.rect.y, 'rise should move only the first line run up'
	assert_rect_contains_rect(first_line.rect, first_base_rect.rect, 'first line/base')
	assert_rect_contains_rect(first_line.rect, first_raised_rect.rect, 'first line/raised')
	assert_rect_contains_rect(second_line.rect, second_c_rect.rect, 'second line/C')
	assert_rect_contains_rect(second_line.rect, second_d_rect.rect, 'second line/D')
	assert_hit_test_center(layout, first_base_rect.rect, 0, 'multiline base')
	assert_hit_test_center(layout, first_raised_rect.rect, 1, 'multiline raised')
	assert_hit_test_center(layout, second_c_rect.rect, 3, 'multiline second C')
	assert_hit_test_center(layout, second_d_rect.rect, 4, 'multiline second D')

	plain_second_line := line_for_index(plain, 3) or {
		assert false, 'plain second line geometry missing'
		return
	}
	plain_second_c_rect := char_rect_for_index(plain, 3) or {
		assert false, 'plain second line C char rect missing'
		return
	}
	second_line_offset := f64(second_c_rect.rect.y - second_line.rect.y)
	plain_second_line_offset := f64(plain_second_c_rect.rect.y - plain_second_line.rect.y)
	assert f64_abs(second_line_offset - plain_second_line_offset) <= 1.0, 'rise from first line should not change second-line internal geometry'

	first_selection := layout.get_selection_rects(0, 2)
	assert first_selection.len == 1, 'first-line selection should stay on one line'
	assert_selection_contains_rect(first_selection[0], first_base_rect.rect,
		'first-line selection/base')
	assert_selection_contains_rect(first_selection[0], first_raised_rect.rect,
		'first-line selection/raised')

	second_selection := layout.get_selection_rects(3, 5)
	assert second_selection.len == 1, 'second-line selection should stay on one line'
	assert_selection_contains_rect(second_selection[0], second_c_rect.rect,
		'second-line selection/C')
	assert_selection_contains_rect(second_selection[0], second_d_rect.rect,
		'second-line selection/D')

	cross_line_selection := layout.get_selection_rects(0, 5)
	assert cross_line_selection.len == 2, 'cross-line selection should produce one rect per line'
	assert_selection_contains_rect(cross_line_selection[0], first_base_rect.rect,
		'cross-line first/base')
	assert_selection_contains_rect(cross_line_selection[0], first_raised_rect.rect,
		'cross-line first/raised')
	assert_selection_contains_rect(cross_line_selection[1], second_c_rect.rect,
		'cross-line second/C')
	assert_selection_contains_rect(cross_line_selection[1], second_d_rect.rect,
		'cross-line second/D')

	end_cursor := layout.get_cursor_pos(text.len) or {
		assert false, 'multiline end cursor geometry missing'
		return
	}
	assert end_cursor.y == second_line.rect.y
	assert end_cursor.height == second_line.rect.height
}

fn test_rich_text_rise_adds_to_base_style_rise() {
	mut ctx := new_rise_test_context()!
	defer { ctx.free() }

	layout := ctx.layout_rich_text(RichText{
		runs: [
			StyleRun{
				text: 'A'
			},
			StyleRun{
				text:  'A'
				style: TextStyle{
					rise: 7
				}
			},
		]
	}, TextConfig{
		style: TextStyle{
			font_name: rise_test_font
			rise:      5
		}
	})!

	base_item := item_for_index(layout, 0) or {
		assert false, 'base run item missing'
		return
	}
	raised_item := item_for_index(layout, 1) or {
		assert false, 'raised run item missing'
		return
	}

	delta := base_item.y - raised_item.y
	assert delta > 4.5, 'run rise should add to base rise instead of replacing it'
	assert delta < 9.5, 'run rise delta should remain bounded near the per-run rise'

	base_rect := char_rect_for_index(layout, 0) or {
		assert false, 'base char rect missing'
		return
	}
	raised_rect := char_rect_for_index(layout, 1) or {
		assert false, 'raised char rect missing'
		return
	}
	rect_delta := base_rect.rect.y - raised_rect.rect.y
	assert rect_delta > 4.5, 'cumulative run rise should move hit geometry up'
	assert rect_delta < 9.5, 'cumulative run rise hit geometry should remain bounded near the per-run rise'

	raised_cursor := layout.get_cursor_pos(1) or {
		assert false, 'raised cursor geometry missing'
		return
	}
	assert raised_cursor.y == raised_rect.rect.y
	assert raised_cursor.height == raised_rect.rect.height

	raised_selection := layout.get_selection_rects(1, 2)
	assert raised_selection.len > 0, 'raised cumulative selection geometry missing'
	assert_selection_contains_rect(raised_selection[0], raised_rect.rect, 'raised cumulative')
}

fn test_rich_text_run_rise_can_cancel_base_style_rise() {
	mut ctx := new_rise_test_context()!
	defer { ctx.free() }

	layout := ctx.layout_rich_text(RichText{
		runs: [
			StyleRun{
				text: 'A'
			},
			StyleRun{
				text:  'A'
				style: TextStyle{
					rise: -5
				}
			},
		]
	}, TextConfig{
		style: TextStyle{
			font_name: rise_test_font
			rise:      5
		}
	})!

	base_item := item_for_index(layout, 0) or {
		assert false, 'base run item missing'
		return
	}
	cancelled_item := item_for_index(layout, 1) or {
		assert false, 'cancelled run item missing'
		return
	}

	delta := cancelled_item.y - base_item.y
	assert delta > 3.5, 'run rise should be able to cancel base rise'
	assert delta < 6.5, 'cancelled rise delta should stay near the base rise'

	base_rect := char_rect_for_index(layout, 0) or {
		assert false, 'base char rect missing'
		return
	}
	cancelled_rect := char_rect_for_index(layout, 1) or {
		assert false, 'cancelled char rect missing'
		return
	}
	rect_delta := cancelled_rect.rect.y - base_rect.rect.y
	assert rect_delta > 3.5, 'cancelled run rise should lower hit geometry relative to base rise'
	assert rect_delta < 6.5, 'cancelled run hit geometry delta should stay near the base rise'

	cancelled_cursor := layout.get_cursor_pos(1) or {
		assert false, 'cancelled cursor geometry missing'
		return
	}
	assert cancelled_cursor.y == cancelled_rect.rect.y
	assert cancelled_cursor.height == cancelled_rect.rect.height

	cancelled_selection := layout.get_selection_rects(1, 2)
	assert cancelled_selection.len > 0, 'cancelled selection geometry missing'
	assert_selection_contains_rect(cancelled_selection[0], cancelled_rect.rect, 'cancelled')
}

fn test_markup_rise_adds_to_base_style_rise() {
	mut ctx := new_rise_test_context()!
	defer { ctx.free() }

	plain := ctx.layout_text('AB', TextConfig{
		style: TextStyle{
			font_name: rise_test_font
		}
	})!
	layout := ctx.layout_text('A<span rise="7168">B</span>', TextConfig{
		style:      TextStyle{
			font_name: rise_test_font
			rise:      5
		}
		use_markup: true
	})!

	plain_a_rect := char_rect_for_index(plain, 0) or {
		assert false, 'plain A char rect missing'
		return
	}
	plain_b_rect := char_rect_for_index(plain, 1) or {
		assert false, 'plain B char rect missing'
		return
	}
	markup_a_rect := char_rect_for_index(layout, 0) or {
		assert false, 'markup A char rect missing'
		return
	}
	markup_b_rect := char_rect_for_index(layout, 1) or {
		assert false, 'markup B char rect missing'
		return
	}

	base_delta := f64(plain_a_rect.rect.y - markup_a_rect.rect.y)
	span_delta := f64(plain_b_rect.rect.y - markup_b_rect.rect.y)
	run_delta := f64(markup_a_rect.rect.y - markup_b_rect.rect.y)
	assert base_delta > 3.5, 'base TextConfig.style rise should apply in markup layout'
	assert base_delta < 6.5, 'base markup rise delta should stay near the base rise'
	assert span_delta > 10.0, 'markup span rise should add to the base rise'
	assert span_delta < 14.0, 'markup span rise should not replace or double the base rise'
	assert run_delta > 5.5, 'markup span should remain raised relative to the base run'
	assert run_delta < 8.5, 'markup span relative rise should stay near the span rise'

	markup_b_cursor := layout.get_cursor_pos(1) or {
		assert false, 'markup B cursor geometry missing'
		return
	}
	assert markup_b_cursor.y == markup_b_rect.rect.y
	assert markup_b_cursor.height == markup_b_rect.rect.height

	markup_b_selection := layout.get_selection_rects(1, 2)
	assert markup_b_selection.len > 0, 'markup B selection geometry missing'
	assert_selection_contains_rect(markup_b_selection[0], markup_b_rect.rect, 'markup B')
}

fn test_markup_rise_recomposition_preserves_attrs_and_spacing() {
	mut ctx := new_rise_test_context()!
	defer { ctx.free() }

	markup := 'A<span foreground="#112233" background="#445566" underline="single" rise="2048">B</span>'
	unspaced := ctx.layout_text(markup, TextConfig{
		style:      TextStyle{
			font_name: rise_test_font
			rise:      5
		}
		use_markup: true
	})!
	spaced := ctx.layout_text(markup, TextConfig{
		style:      TextStyle{
			font_name:      rise_test_font
			letter_spacing: 10
			rise:           5
		}
		use_markup: true
	})!

	spaced_b := item_for_index(spaced, 1) or {
		assert false, 'styled markup B item missing'
		return
	}
	assert spaced_b.color.r == 17
	assert spaced_b.color.g == 34
	assert spaced_b.color.b == 51
	assert spaced_b.color.a == 255
	assert spaced_b.has_bg_color
	assert spaced_b.bg_color.r == 68
	assert spaced_b.bg_color.g == 85
	assert spaced_b.bg_color.b == 102
	assert spaced_b.bg_color.a == 255
	assert spaced_b.has_underline

	unspaced_a := item_for_index(unspaced, 0) or {
		assert false, 'unspaced markup A item missing'
		return
	}
	unspaced_b := item_for_index(unspaced, 1) or {
		assert false, 'unspaced markup B item missing'
		return
	}
	spaced_a := item_for_index(spaced, 0) or {
		assert false, 'spaced markup A item missing'
		return
	}
	unspaced_gap := unspaced_b.x - unspaced_a.x
	spaced_gap := spaced_b.x - spaced_a.x
	assert spaced_gap > unspaced_gap + 1.0, 'base letter spacing should survive markup rise attr recomposition'
}

fn test_markup_layout_rejects_embedded_nul_before_rise_composition() {
	mut ctx := new_rise_test_context()!
	defer { ctx.free() }

	nul_markup := [u8(`A`), 0, u8(`B`)].bytestr()
	ctx.layout_text(nul_markup, TextConfig{
		style:      TextStyle{
			font_name: rise_test_font
			rise:      5
		}
		use_markup: true
	}) or {
		assert err.msg().contains('NUL byte')
		return
	}
	assert false, 'markup text with embedded NUL should be rejected before Pango length lookup'
}

fn test_utf8_rise_hit_test_uses_byte_indices() {
	mut ctx := new_rise_test_context()!
	defer { ctx.free() }

	layout := ctx.layout_rich_text(RichText{
		runs: [
			StyleRun{
				text: 'A'
			},
			StyleRun{
				text:  'é'
				style: TextStyle{
					rise: 8
				}
			},
			StyleRun{
				text: 'B'
			},
		]
	}, TextConfig{
		style: TextStyle{
			font_name: rise_test_font
		}
	})!

	base_rect := char_rect_for_index(layout, 0) or {
		assert false, 'UTF-8 base char rect missing'
		return
	}
	raised_rect := char_rect_for_index(layout, 1) or {
		assert false, 'UTF-8 raised char rect missing'
		return
	}
	trailing_rect := char_rect_for_index(layout, 3) or {
		assert false, 'UTF-8 trailing char rect missing'
		return
	}
	assert_hit_test_center(layout, base_rect.rect, 0, 'UTF-8 base')
	assert_hit_test_center(layout, raised_rect.rect, 1, 'UTF-8 raised')
	assert_hit_test_center(layout, trailing_rect.rect, 3, 'UTF-8 trailing')

	line := line_for_index(layout, 1) or {
		assert false, 'UTF-8 mixed-rise line missing'
		return
	}
	assert_rect_contains_rect(line.rect, base_rect.rect, 'UTF-8 line/base')
	assert_rect_contains_rect(line.rect, raised_rect.rect, 'UTF-8 line/raised')
	assert_rect_contains_rect(line.rect, trailing_rect.rect, 'UTF-8 line/trailing')

	end_cursor := layout.get_cursor_pos(4) or {
		assert false, 'UTF-8 end cursor geometry missing'
		return
	}
	assert end_cursor.y == line.rect.y
	assert end_cursor.height == line.rect.height

	selection := layout.get_selection_rects(0, 4)
	assert selection.len > 0, 'UTF-8 cross-run selection geometry missing'
	assert_selection_contains_rect(selection[0], base_rect.rect, 'UTF-8 selection/base')
	assert_selection_contains_rect(selection[0], raised_rect.rect, 'UTF-8 selection/raised')
	assert_selection_contains_rect(selection[0], trailing_rect.rect, 'UTF-8 selection/trailing')
}

fn test_vertical_rise_moves_visual_y_without_column_x_shift() {
	mut ctx := new_rise_test_context()!
	defer { ctx.free() }

	base := ctx.layout_text('A', TextConfig{
		style:       TextStyle{
			font_name: rise_test_font
		}
		orientation: .vertical
	})!
	raised := ctx.layout_text('A', TextConfig{
		style:       TextStyle{
			font_name: rise_test_font
			rise:      8
		}
		orientation: .vertical
	})!

	assert base.items.len > 0
	assert raised.items.len > 0
	assert f64_abs(raised.items[0].x - base.items[0].x) <= 0.5, 'vertical rise must not shift the column X position'
	vertical_delta := base.items[0].y - raised.items[0].y
	assert vertical_delta > 6.0, 'vertical positive rise should move the visual run up on Y'
	assert vertical_delta < 10.0, 'vertical positive rise should not be applied twice on Y'
}
