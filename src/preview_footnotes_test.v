module vmarkdown

import term
import term.ui as tui

fn test_preview_footnote_anchors_match_rendered_references_in_headings_and_tables() {
	markdown := '# Heading[^n]\n\nLiteral [1]. 中文正文[^n].\n\n| Cell | Other |\n| --- | --- |\n| Table[^n] | [1] |\n\n[^n]: Definition.\n'
	options := ParseOptions{ footnotes: true }
	doc := parse_with_options(markdown, options) or { panic(err) }
	marked := render_preview_footnotes(doc, 40, false)
	regular := preview_lines_with_options(markdown, .terminal, 40, options) or { panic(err) }
	assert marked.lines == regular
	refs := marked.references[1]
	assert refs.len == 3
	assert marked.definitions[1].definition
	for ref in refs {
		plain := term.strip_ansi(marked.lines[ref.line])
		start := editor_rune_index_at_display_column(plain, 0, ref.column)
		assert plain.runes()[start..start + ref.width].string() == '[1]'
	}
	body := term.strip_ansi(marked.lines[refs[1].line])
	assert refs[1].column == editor_display_width(body.all_before_last('[1]'))
}

fn test_preview_mouse_and_enter_follow_a_repeated_footnote_and_restore_exact_origin() {
	markdown := 'First[^n]. Again[^n].\n\n${'More text.\n\n'.repeat(10)}[^n]: Definition.\n'
	options := ParseOptions{ footnotes: true }
	mut app := PreviewApp{
		markdown:      markdown
		doc:           parse_with_options(markdown, options) or { panic(err) }
		parse_options: options
		tui:           &tui.Context{ window_width: 60, window_height: 9 }
	}
	app.ensure_lines()
	from := app.footnote_layout.references[1][1]
	definition := app.footnote_layout.definitions[1]
	app.handle_preview_content_click(app.line_number_gutter_width() + from.column + 1, from.line + 2)
	assert app.view_cursor == definition.line
	assert app.view_cursor_x == definition.column
	assert app.footnote_history.len == 1
	assert app.footnote_history[0].origin.occurrence == 1
	preview_event(&tui.Event{ typ: .key_down, code: .enter, modifiers: .shift }, &app)
	assert app.view_cursor == from.line
	assert app.view_cursor_x == from.column + 1
	assert app.scroll == 0
	preview_event(&tui.Event{ typ: .key_down, code: .enter }, &app)
	assert app.view_cursor == definition.line
	preview_event(&tui.Event{ typ: .key_down, code: .backspace }, &app)
	assert app.view_cursor == from.line
	assert app.view_cursor_x == from.column + 1
	assert app.footnote_history.len == 0
}

fn test_preview_footnote_return_tracks_reference_after_wrapping_changes() {
	markdown := 'Literal [1]. First[^n]. ${'word '.repeat(14)}Again[^n].\n\n[^n]: Definition.\n'
	options := ParseOptions{ footnotes: true }
	mut app := PreviewApp{
		markdown:      markdown
		doc:           parse_with_options(markdown, options) or { panic(err) }
		parse_options: options
		tui:           &tui.Context{ window_width: 100, window_height: 10 }
	}
	app.ensure_lines()
	literal_column := term.strip_ansi(app.lines[0]).index('[1]') or { panic('missing literal [1]') }
	app.view_cursor_x = literal_column
	assert !app.activate_footnote_at_cursor()
	from := app.footnote_layout.references[1][1]
	app.view_cursor = from.line
	app.view_cursor_x = from.column
	assert app.activate_footnote_at_cursor()
	app.tui.window_width = 40
	app.ensure_lines()
	wrapped := app.footnote_layout.references[1][1]
	assert wrapped.line > from.line
	assert app.return_from_footnote()
	assert app.view_cursor == wrapped.line
	assert app.view_cursor_x == wrapped.column
}

fn test_nested_footnote_jumps_return_one_reference_at_a_time() {
	markdown := 'Start[^a] and later[^b].\n\n[^a]: See also[^b].\n[^b]: Destination.\n'
	options := ParseOptions{ footnotes: true }
	mut app := PreviewApp{
		markdown:      markdown
		doc:           parse_with_options(markdown, options) or { panic(err) }
		parse_options: options
		tui:           &tui.Context{ window_width: 70, window_height: 9 }
	}
	app.ensure_lines()
	first := app.footnote_layout.references[1][0]
	app.view_cursor = first.line
	app.view_cursor_x = first.column
	assert app.activate_footnote_at_cursor()
	nested := app.footnote_layout.references[2][1]
	assert nested.line == app.view_cursor
	app.view_cursor_x = nested.column
	assert app.activate_footnote_at_cursor()
	assert app.footnote_history.len == 2
	assert app.return_from_footnote()
	assert app.view_cursor == nested.line
	assert app.view_cursor_x == nested.column
	assert app.return_from_footnote()
	assert app.view_cursor == first.line
	assert app.view_cursor_x == first.column
}

fn test_preview_word_motion_uses_visible_footnote_and_bracket_columns() {
	markdown := '读[^shared] [] next\n\n[^shared]: Definition.\n'
	options := ParseOptions{ footnotes: true }
	mut app := PreviewApp{
		markdown:      markdown
		doc:           parse_with_options(markdown, options) or { panic(err) }
		parse_options: options
		tui:           &tui.Context{ window_width: 60, window_height: 12 }
	}
	app.ensure_lines()
	for column in [2, 3, 4, 6, 9] {
		preview_event(&tui.Event{ typ: .key_down, code: .w }, &app)
		assert app.view_cursor == 0
		assert app.view_cursor_x == column
	}
	for column in [6, 4, 3, 2] {
		preview_event(&tui.Event{ typ: .key_down, code: .b }, &app)
		assert app.view_cursor_x == column
	}
	preview_event(&tui.Event{ typ: .key_down, code: .enter }, &app)
	assert app.view_cursor == app.footnote_layout.definitions[1].line
}
