module vmarkdown

import strings
import term

struct PreviewFootnoteAnchor {
	line       int
	column     int
	width      int
	number     int
	occurrence int
	definition bool
}

struct PreviewFootnoteLayout {
	lines       []string
	rows        map[int][]PreviewFootnoteAnchor
	references  map[int][]PreviewFootnoteAnchor
	definitions map[int]PreviewFootnoteAnchor
}

struct PreviewFootnoteJump {
	origin        PreviewFootnoteAnchor
	cursor_offset int
	scroll        int
	window_width  int
	revealed      bool
	source_line   int
	source_column int
}

// In the private preview render, replace the brackets with single-column
// markers. They survive wrapping and table padding, and are restored before
// drawing. Rendered source text is sanitized, so it cannot create a marker.
fn (r TerminalRenderer) footnote_marker(number int, definition bool) string {
	if !r.mark_footnotes {
		return '[${number}]'
	}
	start := if definition { '\x02' } else { '\x01' }
	return '${start}${number}\x03'
}

fn render_preview_footnotes(doc Document, width int, reveal_spoilers bool) PreviewFootnoteLayout {
	renderer := new_terminal_renderer(doc, TerminalRenderOptions{
		width:           max_int(width, 20)
		reveal_spoilers: reveal_spoilers
	})
	annotated := TerminalRenderer{ ...renderer, mark_footnotes: true }.render_document(doc)
	mut lines := []string{}
	mut rows := map[int][]PreviewFootnoteAnchor{}
	mut refs := map[int][]PreviewFootnoteAnchor{}
	mut defs := map[int]PreviewFootnoteAnchor{}
	for line_index, line in wrap_preview_text(annotated, width, true) {
		if !line.contains_any('\x01\x02\x03') {
			lines << line
			continue
		}
		mut output := strings.new_builder(line.len)
		mut start := 0
		mut column := 0
		mut i := 0
		for i < line.len {
			byte := line[i]
			if byte > 3 || byte == 0 {
				i++
				continue
			}
			prefix := line[start..i]
			output.write_string(prefix)
			column += editor_display_width(term.strip_ansi(prefix))
			if byte == 3 {
				output.write_u8(`]`)
				column++
				i++
				start = i
				continue
			}
			mut end := i + 1
			for end < line.len && line[end] >= `0` && line[end] <= `9` {
				end++
			}
			output.write_u8(`[`) // A table cell may have clipped the marker.
			if end < line.len && line[end] == 3 && end > i + 1 {
				number := line[i + 1..end].int()
				anchor := PreviewFootnoteAnchor{
					line:       line_index
					column:     column
					width:      end - i + 1
					number:     number
					occurrence: refs[number].len
					definition: byte == 2
				}
				rows[line_index] << anchor
				if anchor.definition {
					defs[number] = anchor
				} else {
					refs[number] << anchor
				}
				output.write_string(line[i + 1..end])
				output.write_u8(`]`)
				column += anchor.width
				i = end + 1
			} else {
				column++
				i++
			}
			start = i
		}
		output.write_string(line[start..])
		lines << output.str()
	}
	return PreviewFootnoteLayout{ lines: lines, rows: rows, references: refs, definitions: defs }
}

fn (mut app PreviewApp) activate_footnote_at_cursor() bool {
	if app.mode != .terminal || !app.parse_options.footnotes {
		return false
	}
	visible_width := max_int(app.tui.window_width - app.line_number_gutter_width() - 1, 1)
	for anchor in app.footnote_layout.rows[app.view_cursor] {
		if app.view_cursor_x < anchor.column || app.view_cursor_x >= anchor.column + anchor.width
			|| anchor.column + anchor.width > visible_width {
			continue
		}
		if anchor.definition {
			if app.footnote_history.len > 0 && app.footnote_history.last().origin.number == anchor.number {
				return app.return_from_footnote()
			}
			return false
		}
		target := app.footnote_layout.definitions[anchor.number] or { return false }
		app.sync_source_cursor_from_view()
		app.footnote_history << PreviewFootnoteJump{
			origin:        anchor
			cursor_offset: app.view_cursor_x - anchor.column
			scroll:        app.scroll
			window_width:  app.last_width
			revealed:      app.reveal_spoilers
			source_line:   app.source_cursor_line
			source_column: app.source_cursor_x
		}
		app.current_match = -1
		app.view_cursor = target.line
		app.view_cursor_x = target.column
		app.scroll = target.line
		app.ensure_normal_cursor_visible()
		app.sync_source_cursor_from_view()
		app.search_status = 'Footnote [${anchor.number}] · Backspace to return'
		return true
	}
	return false
}

fn (mut app PreviewApp) return_from_footnote() bool {
	if app.mode != .terminal || app.footnote_history.len == 0 {
		return false
	}
	jump := app.footnote_history.pop()
	app.current_match = -1
	refs := app.footnote_layout.references[jump.origin.number]
	if jump.revealed == app.reveal_spoilers && jump.origin.occurrence < refs.len {
		origin := refs[jump.origin.occurrence]
		app.view_cursor = origin.line
		app.view_cursor_x = origin.column + jump.cursor_offset
		app.scroll = if jump.window_width == app.last_width {
			jump.scroll
		} else {
			max_int(origin.line - (jump.origin.line - jump.scroll), 0)
		}
		app.ensure_normal_cursor_visible()
		app.sync_source_cursor_from_view()
	} else {
		app.source_cursor_line = jump.source_line
		app.source_cursor_x = jump.source_column
		app.desired_cursor_row = max_int(jump.origin.line - jump.scroll, 0)
		app.reposition_from_source()
	}
	app.search_status = ''
	return true
}
