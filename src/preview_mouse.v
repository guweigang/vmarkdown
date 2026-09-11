module vmarkdown

import term
import term.ui as tui

const preview_mouse_scroll_step = 3

fn (mut app PreviewApp) handle_preview_mouse_event(e &tui.Event) {
	app.editor.pending_key = ''
	if e.typ == .mouse_scroll {
		app.handle_preview_mouse_scroll(e.direction)
		return
	}
	if e.typ != .mouse_down || e.button != .left {
		return
	}
	if app.show_quit_confirm {
		app.handle_quit_confirm_click(e.x, e.y)
		return
	}
	if app.show_help {
		app.show_help = false
		return
	}
	if e.y == max_int(app.tui.window_height - 1, 1) {
		if key := preview_footer_key_at(e.x) {
			app.handle_preview_footer_click(key)
		}
		return
	}
	app.handle_preview_content_click(e.x, e.y)
}

fn (mut app PreviewApp) handle_preview_mouse_scroll(direction tui.Direction) {
	if app.show_help || app.show_quit_confirm {
		return
	}
	delta := if direction == .up { -preview_mouse_scroll_step } else { preview_mouse_scroll_step }
	if app.editing {
		app.editor.cursor_y = min_int(max_int(app.editor.cursor_y + delta, 0), max_int(app.editor.lines.len - 1, 0))
		app.editor.clamp_cursor()
		app.sync_editor_viewport()
		return
	}
	app.move_normal_cursor(delta)
}

fn (mut app PreviewApp) handle_preview_content_click(x int, y int) {
	row := y - 2
	if row < 0 || row >= app.viewport_height() {
		return
	}
	line_index := app.scroll + row
	if app.editing {
		if line_index < 0 || line_index >= app.editor.lines.len {
			return
		}
		if app.editor.mode == .command {
			app.editor.mode = .normal
			app.editor.command = ''
		}
		app.editor.cursor_y = line_index
		display_column := max_int(x - app.line_number_gutter_width(), 0)
		app.editor.cursor_x = editor_rune_index_at_display_column(app.editor.current_line(), app.edit_col_start, display_column)
		app.editor.clamp_cursor()
		app.sync_editor_viewport()
		return
	}
	if line_index < 0 || line_index >= app.lines.len {
		return
	}
	app.search_active = false
	app.current_match = -1
	app.view_cursor = line_index
	line_width := editor_display_width(term.strip_ansi(app.lines[line_index]))
	app.view_cursor_x = min_int(max_int(x - app.line_number_gutter_width(), 0), line_width)
	app.ensure_normal_cursor_visible()
	app.sync_source_cursor_from_view()
}

fn editor_rune_index_at_display_column(text string, start int, display_column int) int {
	runes := text.runes()
	safe_start := min_int(max_int(start, 0), runes.len)
	target := max_int(display_column, 0)
	mut used := 0
	for index := safe_start; index < runes.len; index++ {
		width := max_int(editor_display_width(runes[index].str()), 1)
		if target < used + width {
			return index
		}
		used += width
	}
	return runes.len
}

fn preview_footer_key_at(x int) ?string {
	column := max_int(x - 1, 0)
	plain := build_preview_footer_left_plain()
	for item in preview_mode_items() {
		marker := '[${item.key}] ${item.label}'
		start := plain.index(marker) or { continue }
		if column >= start && column < start + marker.len {
			return item.key
		}
	}
	for key, marker in {
		'i': '[i] insert'
		'?': '[?] help'
		'q': '[q] quit'
	} {
		start := plain.index(marker) or { continue }
		if column >= start && column < start + marker.len {
			return key
		}
	}
	return none
}

fn (mut app PreviewApp) handle_preview_footer_click(key string) {
	match key {
		'1' { app.activate_mouse_mode(.terminal) }
		'2' { app.activate_mouse_mode(.markdown) }
		'3' { app.activate_mouse_mode(.html) }
		'4' { app.activate_mouse_mode(.ast) }
		'i' {
			if !app.editing {
				app.start_editing()
			}
		}
		'?' {
			app.show_help = true
		}
		'q' { app.request_quit() }
		else {}
	}
}

fn (mut app PreviewApp) activate_mouse_mode(mode PreviewMode) {
	if !app.editing {
		app.set_mode(mode)
		return
	}
	if app.editor.mode == .insert {
		app.editor.end_insert_session()
	}
	app.editor.mode = .normal
	app.editor.command = ''
	app.open_editor_view(mode)
}

fn (app &PreviewApp) quit_confirm_action_at(x int, y int) ?string {
	lines := app.quit_confirm_lines()
	width := min_int(preview_help_width(lines), max_int(app.tui.window_width, 4))
	left := max_int((app.tui.window_width - width) / 2, 0)
	top := max_int((app.tui.window_height - (lines.len + 2)) / 2, 0)
	if y != top + lines.len {
		return none
	}
	column := x - left - 1
	actions := lines[lines.len - 1]
	for key, marker in {
		's':   '[s] Save and quit'
		'q':   '[q] Quit without saving'
		'esc': '[Esc] Cancel'
	} {
		start := actions.index(marker) or { continue }
		if column >= start && column < start + marker.len {
			return key
		}
	}
	return none
}

fn (mut app PreviewApp) handle_quit_confirm_click(x int, y int) {
	action := app.quit_confirm_action_at(x, y) or { return }
	match action {
		's' {
			if app.save_editor() {
				exit(0)
			}
		}
		'q' { exit(0) }
		'esc' {
			app.show_quit_confirm = false
		}
		else {}
	}
}
