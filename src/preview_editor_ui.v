module vmarkdown

import os
import term
import term.ui as tui
import encoding.utf8.east_asian

// Interactive preview editor input, persistence, and cursor rendering.

fn (mut app PreviewApp) start_editing() {
	app.sync_source_cursor_from_view()
	app.preview_scroll_before_edit = app.scroll
	app.editing = true
	app.mode = .markdown
	app.editor.mode = .insert
	app.editor.begin_insert_session()
	app.editor.cursor_y = min_int(app.source_cursor_line, max_int(app.editor.lines.len - 1, 0))
	app.editor.cursor_x = min_int(app.source_cursor_x, app.editor.current_line().runes().len)
	app.editor.clamp_cursor()
	app.editor.status = ''
	app.current_match = -1
	app.search_query = ''
	app.search_status = ''
	app.last_width = 0
}

fn (mut app PreviewApp) handle_editor_input(e &tui.Event) {
	match app.editor.mode {
		.insert { app.handle_editor_insert_input(e) }
		.command { app.handle_editor_command_input(e) }
		.normal { app.handle_editor_normal_input(e) }
	}
	if app.editing {
		app.editor.clamp_cursor()
		app.sync_editor_viewport()
	}
}

fn (mut app PreviewApp) handle_editor_insert_input(e &tui.Event) {
	if e.modifiers.has(.ctrl) && e.code == .s {
		app.save_editor()
		return
	}
	match e.code {
		.escape {
			app.editor.end_insert_session()
			app.editor.pending_key = ''
			app.editor.mode = .normal
		}
		.enter {
			app.editor.insert_text('\n')
		}
		.backspace {
			app.editor.backspace()
		}
		.delete {
			app.editor.delete_forward()
		}
		.left {
			app.editor.move_left()
		}
		.right {
			app.editor.move_right()
		}
		.up {
			app.editor.move_up()
		}
		.down {
			app.editor.move_down()
		}
		.home {
			app.editor.cursor_x = 0
		}
		.end {
			app.editor.cursor_x = app.editor.current_line().runes().len
		}
		else {
			if !e.modifiers.has(.ctrl) && !e.modifiers.has(.alt) && e.utf8.len > 0
				&& e.utf8 != '\x00' {
				app.editor.insert_text(e.utf8)
			}
		}
	}
}

fn (mut app PreviewApp) handle_editor_normal_input(e &tui.Event) {
	if app.editor.pending_key.len > 0 {
		continues_delete := app.editor.pending_key == 'd' && e.code == .d
		continues_goto := app.editor.pending_key == 'g' && e.code == .g && !e.modifiers.has(.shift)
		continues_pending := !e.modifiers.has(.ctrl) && (continues_delete || continues_goto)
		if !continues_pending {
			app.editor.pending_key = ''
		}
	}
	if e.modifiers.has(.ctrl) {
		match e.code {
			.r {
				app.editor.redo()
			}
			.s {
				app.save_editor()
			}
			.d {
				app.editor.cursor_y = min_int(app.editor.cursor_y + app.half_page_step(), app.editor.lines.len - 1)
			}
			.u {
				app.editor.cursor_y = max_int(app.editor.cursor_y - app.half_page_step(), 0)
			}
			else {}
		}
		return
	}
	match e.code {
		.q {
			app.request_quit()
		}
		._1 {
			app.open_editor_view(.terminal)
		}
		._2 {
			app.open_editor_view(.markdown)
		}
		._3 {
			app.open_editor_view(.html)
		}
		._4 {
			app.open_editor_view(.ast)
		}
		.escape {
			app.editor.pending_key = ''
		}
		.h, .left {
			app.editor.move_left()
		}
		.j, .down {
			app.editor.move_down()
		}
		.k, .up {
			app.editor.move_up()
		}
		.l, .right {
			app.editor.move_right()
		}
		.w {
			app.editor.move_word_forward()
		}
		.b {
			app.editor.move_word_backward()
		}
		._0, .home {
			app.editor.cursor_x = 0
		}
		.dollar, .end {
			app.editor.cursor_x = app.editor.current_line().runes().len
		}
		.i {
			app.editor.begin_insert_session()
			app.editor.mode = .insert
		}
		.a {
			app.editor.move_right()
			app.editor.begin_insert_session()
			app.editor.mode = .insert
		}
		.o {
			app.editor.begin_insert_session()
			if e.modifiers.has(.shift) {
				app.editor.open_line_above()
			} else {
				app.editor.open_line_below()
			}
		}
		.x, .delete {
			app.editor.delete_forward()
		}
		.u {
			app.editor.undo()
		}
		.colon {
			app.editor.mode = .command
			app.editor.command = ''
			app.editor.status = ''
		}
		.g {
			if e.modifiers.has(.shift) {
				app.editor.cursor_y = app.editor.lines.len - 1
			} else if app.editor.pending_key == 'g' {
				app.editor.cursor_y = 0
				app.editor.pending_key = ''
			} else {
				app.editor.pending_key = 'g'
			}
		}
		.d {
			if app.editor.pending_key == 'd' {
				app.editor.delete_line()
				app.editor.pending_key = ''
			} else {
				app.editor.pending_key = 'd'
			}
		}
		else {
			app.editor.pending_key = ''
		}
	}
}

fn (mut app PreviewApp) handle_editor_command_input(e &tui.Event) {
	match e.code {
		.escape {
			app.editor.mode = .normal
			app.editor.command = ''
		}
		.enter {
			command := app.editor.command.trim_space()
			app.editor.mode = .normal
			app.editor.command = ''
			app.execute_editor_command(command)
		}
		.backspace {
			if app.editor.command.runes().len == 0 {
				app.editor.mode = .normal
			} else {
				runes := app.editor.command.runes()
				app.editor.command = runes[..runes.len - 1].string()
			}
		}
		else {
			if !e.modifiers.has(.ctrl) && !e.modifiers.has(.alt) && e.utf8.len > 0
				&& e.utf8 != '\x00' {
				app.editor.command += e.utf8
			}
		}
	}
}

fn (mut app PreviewApp) execute_editor_command(command string) {
	match command {
		'w' {
			app.save_editor()
		}
		'w!' {
			app.save_editor_force()
		}
		'q' {
			if app.editor.dirty {
				app.editor.status = 'E37: no write since last change (use :q!)'
			} else {
				exit(0)
			}
		}
		'q!' {
			exit(0)
		}
		'wq', 'x' {
			if app.save_editor() {
				exit(0)
			}
		}
		'wq!' {
			if app.save_editor_force() {
				exit(0)
			}
		}
		'preview', 'p' {
			app.show_editor_preview()
		}
		else {
			app.editor.status = 'not an editor command: ${command}'
		}
	}
}

fn (mut app PreviewApp) show_editor_preview() {
	app.open_editor_view(.terminal)
	app.scroll = app.preview_scroll_before_edit
}

fn (mut app PreviewApp) open_editor_view(mode PreviewMode) {
	text := app.editor.text()
	doc := parse(text) or {
		app.editor.status = 'preview parse failed: ${err}'
		return
	}
	app.markdown = text
	app.doc = doc
	app.source_cursor_line = app.editor.cursor_y
	app.source_cursor_x = app.editor.cursor_x
	app.desired_cursor_row = max_int(app.editor.cursor_y - app.scroll, 0)
	app.pending_source_reposition = true
	app.editing = false
	app.mode = mode
	app.last_width = 0
}

fn (mut app PreviewApp) refresh_normal_view() {
	text := app.editor.text()
	doc := parse(text) or {
		app.search_status = 'preview parse failed: ${err}'
		return
	}
	app.markdown = text
	app.doc = doc
	app.source_cursor_line = app.editor.cursor_y
	app.source_cursor_x = app.editor.cursor_x
	app.desired_cursor_row = max_int(app.current_line_index() - app.scroll, 0)
	app.pending_source_reposition = true
	app.last_width = 0
}

fn (mut app PreviewApp) save_editor() bool {
	return app.save_editor_with_force(false)
}

fn (mut app PreviewApp) save_editor_force() bool {
	return app.save_editor_with_force(true)
}

fn (mut app PreviewApp) save_editor_with_force(force bool) bool {
	if app.source_path.len == 0 {
		app.editor.status = 'no file name'
		return false
	}
	if !force
		&& source_file_changed_on_disk(app.source_path, app.editor.saved_text, app.source_raw, app.source_loaded) {
		app.editor.status = 'file changed on disk; use :w! to overwrite'
		return false
	}
	text := app.editor.text()
	encoded := encode_markdown_text(text, app.source_encoding, app.source_bom) or {
		app.editor.status = 'write failed: ${err}'
		return false
	}
	atomic_write_markdown_file_bytes(app.source_path, encoded) or {
		app.editor.status = 'write failed: ${err}'
		return false
	}
	app.source_raw = encoded.clone()
	app.source_loaded = true
	app.markdown = text
	app.doc = parse(text) or {
		app.editor.status = 'written; preview parse failed: ${err}'
		app.editor.mark_saved()
		app.last_width = 0
		return true
	}
	app.editor.mark_saved()
	app.last_width = 0
	return true
}

fn source_file_changed_on_disk(path string, expected string, expected_raw []u8, loaded bool) bool {
	if path.len == 0 || !os.exists(path) {
		return true
	}
	if loaded {
		current := os.read_bytes(path) or { return true }
		return current != expected_raw
	}
	current := os.read_file(path) or { return true }
	return current != expected
}

fn atomic_write_preview_file(path string, text string) ! {
	atomic_write_markdown_file_bytes(path, text.bytes())!
}

fn (mut app PreviewApp) sync_editor_viewport() {
	if app.editor.cursor_y < app.scroll {
		app.scroll = app.editor.cursor_y
	}
	if app.editor.cursor_y >= app.scroll + app.viewport_height() {
		app.scroll = app.editor.cursor_y - app.viewport_height() + 1
	}
	app.scroll = min_int(max_int(app.scroll, 0), max_int(app.editor.lines.len - app.viewport_height(), 0))
	content_width := max_int(app.tui.window_width - app.line_number_gutter_width() - 2, 1)
	if app.editor.cursor_x < app.edit_col_start {
		app.edit_col_start = app.editor.cursor_x
	}
	line := app.editor.current_line().runes()
	for app.edit_col_start < app.editor.cursor_x
		&& editor_display_width(line[app.edit_col_start..app.editor.cursor_x].string()) >= content_width {
		app.edit_col_start++
	}
}

fn (mut app PreviewApp) draw_editor_content() {
	app.sync_editor_viewport()
	height := app.viewport_height()
	gutter_width := app.line_number_gutter_width()
	content_width := max_int(app.tui.window_width - gutter_width - 1, 1)
	for i in 0 .. height {
		line_index := app.scroll + i
		if line_index >= app.editor.lines.len {
			break
		}
		line_no := format_preview_line_number(line_index + 1, gutter_width, line_index == app.editor.cursor_y)
		runes := app.editor.lines[line_index].runes()
		start := min_int(app.edit_col_start, runes.len)
		visible := fit_editor_display(runes[start..].string().replace('\t', '    '), content_width)
		app.tui.draw_text(0, i + 2, line_no)
		app.tui.draw_text(gutter_width, i + 2, visible)
	}
}

fn (mut app PreviewApp) position_editor_cursor() {
	if app.show_help || app.show_quit_confirm {
		app.tui.hide_cursor()
		return
	}
	app.tui.show_cursor()
	if !app.editing {
		line_index := app.current_line_index()
		line_width := if line_index >= 0 && line_index < app.lines.len {
			editor_display_width(term.strip_ansi(app.lines[line_index]))
		} else {
			0
		}
		x := app.line_number_gutter_width() + min_int(app.view_cursor_x, line_width)
		y := app.current_line_index() - app.scroll + 2
		app.tui.set_cursor_position(x, max_int(y, 1))
		return
	}
	if app.editor.mode == .command {
		x := editor_display_width(':' + app.editor.command) + 1
		app.tui.set_cursor_position(x, max_int(app.tui.window_height, 1))
		return
	}
	line := app.editor.current_line().runes()
	start := min_int(app.edit_col_start, line.len)
	end := min_int(max_int(app.editor.cursor_x, start), line.len)
	x := app.line_number_gutter_width() + editor_display_width(line[start..end].string())
	y := app.editor.cursor_y - app.scroll + 2
	app.tui.set_cursor_position(x, y)
}

fn fit_editor_display(input string, width int) string {
	if width <= 0 || input.len == 0 {
		return ''
	}
	mut used := 0
	mut out := []rune{}
	for r in input.runes() {
		rune_width := max_int(east_asian.display_width(r.str(), 1), 0)
		if used + rune_width > width {
			break
		}
		out << r
		used += rune_width
	}
	return out.string()
}

fn editor_display_width(text string) int {
	return east_asian.display_width(text.replace('\t', '    '), 1)
}

fn editor_mode_label(mode EditorMode) string {
	return match mode {
		.normal { 'NORMAL' }
		.insert { 'INSERT' }
		.command { 'COMMAND' }
	}
}

fn build_editor_footer_line(editor MarkdownEditor, width int) string {
	safe_width := max_int(width - 2, 1)
	mode_plain := ' ${editor_mode_label(editor.mode)} '
	dirty_plain := if editor.dirty { ' [+]' } else { '' }
	total := max_int(editor.lines.len, 1)
	covered := (editor.cursor_y + 1) * 100 + total - 1
	percent := min_int(covered / total, 100)
	right_plain := ' ${editor.cursor_y + 1}:${editor.cursor_x + 1} ${percent}% '
	left_plain := mode_plain + dirty_plain
	filler_plain := ' '.repeat(max_int(safe_width - left_plain.len - right_plain.len, 0))
	mode_text := match editor.mode {
		.normal { term.bg_rgb(32, 39, 45, term.bright_white(mode_plain)) }
		.insert { term.bg_rgb(45, 125, 70, term.bright_white(mode_plain)) }
		.command { term.bg_rgb(35, 105, 125, term.bright_white(mode_plain)) }
	}
	dirty_text := term.bg_rgb(18, 24, 28, term.hex(0xe6b450, dirty_plain))
	filler := term.bg_rgb(18, 24, 28, filler_plain)
	right := term.bg_rgb(32, 39, 45, term.bright_black(right_plain))
	return mode_text + dirty_text + filler + right
}

fn build_editor_command_line(editor MarkdownEditor) string {
	plain := if editor.mode == .command {
		':' + editor.command + '_'
	} else if editor.status.len > 0 {
		editor.status
	} else {
		'-- ${editor_mode_label(editor.mode)} --'
	}
	return term.bg_rgb(32, 39, 45, term.bright_cyan(if plain.len > 0 { ' ${plain} ' } else { ' ' }))
}
