module vmarkdown

import os
import term
import term.ui as tui

pub enum PreviewMode {
	terminal
	markdown
	html
	ast
}

pub fn preview(markdown string) ! {
	preview_with_mode(markdown, .terminal, 'buffer')!
}

pub fn preview_with_mode(markdown string, mode PreviewMode, source_label string) ! {
	preview_with_source(markdown, mode, source_label, '')!
}

fn preview_with_source(markdown string, mode PreviewMode, source_label string, source_path string) ! {
	source := MarkdownFile{
		text: markdown
		encoding: .utf8
		raw: markdown.bytes()
	}
	preview_with_markdown_file(source, mode, source_label, source_path)!
}

fn preview_with_markdown_file(source MarkdownFile, mode PreviewMode, source_label string, source_path string) ! {
	prepare_console_for_preview()
	doc := parse(source.text)!
	mut app := &PreviewApp{
		markdown: source.text
		doc: doc
		mode: mode
		source_label: if source_label.len > 0 { source_label } else { 'buffer' }
		source_path: source_path
		source_encoding: source.encoding
		source_bom: source.bom
		source_raw: source.raw.clone()
		source_loaded: source_path.len > 0
		editor: new_markdown_editor(source.text)
	}
	app.tui = tui.init(
		user_data: app
		event_fn: preview_event
		frame_fn: preview_frame
		hide_cursor: true
		capture_events: true
		window_title: 'vmarkdown preview'
	)
	app.tui.run()!
}

pub fn preview_terminal_buffer(rendered string, source_label string) ! {
	prepare_console_for_preview()
	doc := parse('# Preview\n')!
	mut app := &PreviewApp{
		markdown: '# Preview\n'
		doc: doc
		mode: .terminal
		source_label: if source_label.len > 0 { source_label } else { 'buffer' }
		raw_terminal: rendered
	}
	app.tui = tui.init(
		user_data: app
		event_fn: preview_event
		frame_fn: preview_frame
		hide_cursor: true
		capture_events: true
		window_title: 'vmarkdown preview'
	)
	app.tui.run()!
}

pub fn preview_file(path string) ! {
	preview_file_with_mode(path, .terminal)!
}

pub fn preview_file_with_mode(path string, mode PreviewMode) ! {
	preview_file_with_mode_and_encoding(path, mode, 'auto')!
}

pub fn preview_file_with_encoding(path string, requested_encoding string) ! {
	preview_file_with_mode_and_encoding(path, .terminal, requested_encoding)!
}

pub fn preview_file_with_mode_and_encoding(path string, mode PreviewMode, requested_encoding string) ! {
	source := read_markdown_file_with_encoding(path, requested_encoding)!
	preview_with_markdown_file(source, mode, path, path)!
}

pub fn preview_mermaid(input string) ! {
	preview_with_mode(build_mermaid_preview_markdown(input), .terminal, 'mermaid buffer')!
}

pub fn preview_mermaid_file(path string) ! {
	input := os.read_file(path)!
	preview_with_mode(build_mermaid_preview_markdown(input), .terminal, path)!
}

pub fn preview_diagram_rendered(title string, rendered string) ! {
	preview_with_mode(build_diagram_preview_markdown(title, rendered), .terminal, if title.len > 0 {
		title
	} else {
		'diagram buffer'
	})!
}

pub fn preview_diagram_payload(title string, payload DiagramPayload, width int) ! {
	rendered := render_diagram_payload(payload, width)
	preview_diagram_rendered(title, rendered)!
}

pub fn preview_lines(markdown string, mode PreviewMode, width int) ![]string {
	doc := parse(markdown)!
	return preview_lines_from_document(doc, markdown, mode, width)
}

pub fn preview_lines_from_document(doc Document, markdown string, mode PreviewMode, width int) ![]string {
	safe_width := max_int(width, 20)
	text := match mode {
		.terminal {
			doc.to_terminal_with_options(TerminalRenderOptions{
				width: safe_width
				color: true
			})
		}
		.markdown {
			doc.to_markdown()
		}
		.html {
			render_html(markdown)!
		}
		.ast {
			doc.pretty()
		}
	}
	return wrap_preview_text(text, safe_width, mode == .terminal)
}

pub fn build_mermaid_preview_markdown(input string) string {
	return [
		'# Mermaid Preview',
		'',
		'```mermaid',
		input.trim_space(),
		'```',
	].join('\n')
}

pub fn build_diagram_preview_markdown(title string, rendered string) string {
	heading := if title.len > 0 { title } else { 'Diagram Preview' }
	return [
		'# ${heading}',
		'',
		'```text',
		rendered.trim_right('\n'),
		'```',
	].join('\n')
}

pub fn build_diff_preview_markdown(title string, lines []string) string {
	heading := if title.len > 0 { title } else { 'Diagram Diff Preview' }
	body := if lines.len > 0 { lines.join('\n') } else { 'no changes' }
	return [
		'# ${heading}',
		'',
		'```text',
		body,
		'```',
	].join('\n')
}

pub fn preview_diff_lines(title string, lines []string) ! {
	preview_terminal_buffer(render_diff_preview_terminal(lines), if title.len > 0 {
		title
	} else {
		'diff buffer'
	})!
}

fn render_diff_preview_terminal(lines []string) string {
	if lines.len == 0 {
		return style_diff_preview_line('no changes')
	}
	return lines.map(style_diff_preview_line(it)).join('\n')
}

fn style_diff_preview_line(line string) string {
	if line.starts_with('added ') {
		return term.hex(0x7fd962, line)
	}
	if line.starts_with('removed ') {
		return term.hex(0xf07178, line)
	}
	if line.starts_with('changed ') {
		return term.hex(0xe6b450, term.bold(line))
	}
	if line.starts_with('reused ') || line == 'no changes' {
		return term.bright_black(line)
	}
	return line
}

struct PreviewApp {
mut:
	markdown                   string
	doc                        Document
	tui                        &tui.Context = unsafe { nil }
	mode                       PreviewMode
	scroll                     int
	lines                      []string
	last_width                 int
	last_height                int
	source_label               string
	search_query               string
	search_active              bool
	search_status              string
	current_match              int = -1
	show_help                  bool
	show_quit_confirm          bool
	raw_terminal               string
	source_path                string
	source_encoding            MarkdownEncoding
	source_bom                 bool
	source_raw                 []u8
	source_loaded              bool
	editing                    bool
	editor                     MarkdownEditor
	edit_col_start             int
	preview_scroll_before_edit int
	view_cursor                int
	view_cursor_x              int
	line_sources               []PreviewLineSource
	source_cursor_line         int
	source_cursor_x            int
	pending_source_reposition  bool
	desired_cursor_row         int
	needs_redraw               bool = true
}

fn preview_event(e &tui.Event, x voidptr) {
	mut app := unsafe { &PreviewApp(x) }
	if e.typ == .key_down || e.typ == .resized {
		app.needs_redraw = true
	}
	if e.typ == .key_down && app.show_quit_confirm {
		app.handle_quit_confirm_input(e)
		return
	}
	if e.typ == .key_down && app.show_help {
		app.handle_help_input(e)
		return
	}
	if e.typ == .key_down && app.search_active {
		app.handle_search_input(e)
		return
	}
	if e.typ == .key_down && app.editing {
		app.handle_editor_input(e)
		return
	}
	if e.typ == .key_down {
		if app.editor.pending_key == 'd' && (e.code != .d || e.modifiers.has(.ctrl)) {
			app.editor.pending_key = ''
		}
		match e.code {
			.q {
				app.request_quit()
			}
			.i {
				app.start_editing()
			}
			.s {
				if e.modifiers.has(.ctrl) || app.editor.dirty {
					if app.save_editor() {
						app.search_status = 'written'
					}
				}
			}
			.escape {
				app.dismiss_search()
			}
			.question_mark {
				app.show_help = true
			}
			.slash {
				app.start_search()
			}
			.j, .down {
				app.move_normal_cursor(1)
			}
			.k, .up {
				app.move_normal_cursor(-1)
			}
			.h, .left {
				app.move_normal_cursor_horizontal(-1)
			}
			.l, .right {
				app.move_normal_cursor_horizontal(1)
			}
			.w {
				app.move_normal_source_word(true)
			}
			.b {
				app.move_normal_source_word(false)
			}
			.x, .delete {
				app.delete_normal_source_char()
			}
			.page_down, .space {
				app.move_normal_cursor(max_int(app.viewport_height() - 1, 1))
			}
			.page_up {
				app.move_normal_cursor(-max_int(app.viewport_height() - 1, 1))
			}
			.d {
				if e.modifiers.has(.ctrl) {
					app.move_normal_cursor(app.half_page_step())
				} else if app.editor.pending_key == 'd' {
					app.delete_normal_source_line()
					app.editor.pending_key = ''
				} else {
					app.editor.pending_key = 'd'
				}
			}
			.g {
				if e.modifiers.has(.shift) {
					app.view_cursor = max_int(app.lines.len - 1, 0)
				} else {
					app.view_cursor = 0
				}
				app.ensure_normal_cursor_visible()
			}
			.u {
				if e.modifiers.has(.ctrl) {
					app.move_normal_cursor(-app.half_page_step())
				} else {
					app.editor.undo()
					app.refresh_normal_view()
				}
			}
			.r {
				if e.modifiers.has(.ctrl) {
					app.editor.redo()
					app.refresh_normal_view()
				}
			}
			.n {
				if e.modifiers.has(.shift) {
					app.jump_to_previous_match()
				} else {
					app.jump_to_next_match()
				}
			}
			._1 {
				app.set_mode(.terminal)
			}
			._2 {
				app.set_mode(.markdown)
			}
			._3 {
				app.set_mode(.html)
			}
			._4 {
				app.set_mode(.ast)
			}
			else {}
		}
	}
	if e.typ == .resized {
		app.last_width = 0
		app.last_height = 0
	}
}

fn preview_frame(x voidptr) {
	mut app := unsafe { &PreviewApp(x) }
	if !app.needs_redraw {
		return
	}
	app.ensure_lines()
	app.clamp_scroll()
	if !app.editing {
		app.clamp_normal_cursor()
		app.ensure_normal_cursor_visible()
	}
	app.tui.clear()
	app.draw_content()
	app.draw_header()
	app.draw_footer()
	if app.show_help {
		app.draw_help_overlay()
	}
	if app.show_quit_confirm {
		app.draw_quit_confirm_overlay()
	}
	app.position_editor_cursor()
	app.tui.reset()
	app.tui.flush()
	app.needs_redraw = false
}

fn (mut app PreviewApp) set_mode(mode PreviewMode) {
	if app.mode == mode {
		return
	}
	app.prepare_source_reposition()
	app.mode = mode
	app.last_width = 0
	app.search_status = ''
}

fn (mut app PreviewApp) ensure_lines() {
	if app.editing {
		app.lines = app.editor.lines.clone()
		app.line_sources = []PreviewLineSource{cap: app.editor.lines.len}
		for index in 0 .. app.editor.lines.len {
			columns, exact := build_preview_source_columns(app.editor.lines[index], app.editor.lines[index], .markdown)
			app.line_sources << PreviewLineSource{
				start_line: index
				end_line: index
				source_line: index
				source_columns: columns
				exact_columns: exact
			}
		}
		app.last_width = app.tui.window_width
		app.last_height = app.tui.window_height
		return
	}
	if app.tui.window_width == app.last_width && app.tui.window_height == app.last_height
		&& app.lines.len > 0 {
		return
	}
	content_width := max_int(app.tui.window_width - app.line_number_gutter_width() - 2, 20)
	if app.mode == .terminal && app.raw_terminal.len > 0 {
		app.lines = wrap_preview_text(app.raw_terminal, content_width, true)
	} else {
		app.lines = preview_lines_from_document(app.doc, app.markdown, app.mode, content_width) or {
			['preview error: ${err}']
		}
	}
	app.line_sources = build_preview_line_sources(app.markdown, app.mode, content_width, app.lines)
	if app.pending_source_reposition {
		app.reposition_from_source()
	}
	app.last_width = app.tui.window_width
	app.last_height = app.tui.window_height
}

fn (mut app PreviewApp) clamp_normal_cursor() {
	app.view_cursor = min_int(max_int(app.view_cursor, 0), max_int(app.lines.len - 1, 0))
}

fn (mut app PreviewApp) ensure_normal_cursor_visible() {
	if app.view_cursor < app.scroll {
		app.scroll = app.view_cursor
	}
	if app.view_cursor >= app.scroll + app.viewport_height() {
		app.scroll = app.view_cursor - app.viewport_height() + 1
	}
	app.clamp_scroll()
}

fn (mut app PreviewApp) move_normal_cursor(delta int) {
	app.view_cursor = min_int(max_int(app.view_cursor + delta, 0), max_int(app.lines.len - 1, 0))
	app.ensure_normal_cursor_visible()
	app.sync_source_cursor_from_view()
	app.editor.pending_key = ''
}

fn (mut app PreviewApp) move_normal_cursor_horizontal(delta int) {
	line_index := app.current_line_index()
	line_width := if line_index >= 0 && line_index < app.lines.len {
		editor_display_width(term.strip_ansi(app.lines[line_index]))
	} else {
		0
	}
	app.view_cursor_x = min_int(max_int(app.view_cursor_x + delta, 0), line_width)
	if app.view_cursor >= 0 && app.view_cursor < app.line_sources.len {
		app.sync_source_cursor_from_view()
	} else {
		app.source_cursor_x = app.view_cursor_x
	}
	app.editor.pending_key = ''
}

fn (mut app PreviewApp) sync_editor_cursor_from_source() {
	app.editor.cursor_y = min_int(max_int(app.source_cursor_line, 0), max_int(app.editor.lines.len - 1, 0))
	app.editor.cursor_x = min_int(max_int(app.source_cursor_x, 0), app.editor.current_line().runes().len)
}

fn (mut app PreviewApp) move_normal_source_word(forward bool) {
	app.sync_source_cursor_from_view()
	app.sync_editor_cursor_from_source()
	if forward {
		app.editor.move_word_forward()
	} else {
		app.editor.move_word_backward()
	}
	app.source_cursor_line = app.editor.cursor_y
	app.source_cursor_x = app.editor.cursor_x
	app.desired_cursor_row = max_int(app.current_line_index() - app.scroll, 0)
	app.pending_source_reposition = true
	app.reposition_from_source()
	app.editor.pending_key = ''
}

fn (mut app PreviewApp) delete_normal_source_char() {
	if app.view_cursor >= 0 && app.view_cursor < app.line_sources.len
		&& !source_column_is_exact(app.line_sources[app.view_cursor], app.view_cursor_x) {
		app.search_status = 'no source character here; press i to edit the Markdown source'
		app.editor.pending_key = ''
		return
	}
	app.sync_source_cursor_from_view()
	app.sync_editor_cursor_from_source()
	app.editor.delete_forward()
	app.refresh_normal_view()
	app.editor.pending_key = ''
}

fn (mut app PreviewApp) delete_normal_source_line() {
	app.sync_source_cursor_from_view()
	app.sync_editor_cursor_from_source()
	app.editor.delete_line()
	app.refresh_normal_view()
}

fn (mut app PreviewApp) sync_source_cursor_from_view() {
	if app.view_cursor >= 0 && app.view_cursor < app.line_sources.len {
		source := app.line_sources[app.view_cursor]
		app.source_cursor_line = source.source_line
		app.source_cursor_x = source_column_at(source, app.view_cursor_x)
	}
}

fn (mut app PreviewApp) prepare_source_reposition() {
	app.sync_source_cursor_from_view()
	app.desired_cursor_row = max_int(app.current_line_index() - app.scroll, 0)
	app.pending_source_reposition = true
}

fn (mut app PreviewApp) reposition_from_source() {
	app.view_cursor = find_preview_line_for_source(app.line_sources, app.source_cursor_line)
	if app.view_cursor >= 0 && app.view_cursor < app.line_sources.len {
		app.view_cursor_x = preview_column_for_source(app.line_sources[app.view_cursor], app.source_cursor_x)
	} else {
		app.view_cursor_x = app.source_cursor_x
	}
	app.scroll = max_int(app.view_cursor - app.desired_cursor_row, 0)
	app.pending_source_reposition = false
	app.clamp_normal_cursor()
	app.ensure_normal_cursor_visible()
}

fn (app &PreviewApp) viewport_height() int {
	return max_int(app.tui.window_height - 3, 1)
}

fn (mut app PreviewApp) clamp_scroll() {
	app.scroll = min_int(max_int(app.scroll, 0), app.max_scroll())
}

fn (app &PreviewApp) max_scroll() int {
	content_scroll := max_int(app.lines.len - app.viewport_height(), 0)
	cursor_scroll := if app.editing {
		0
	} else {
		min_int(app.view_cursor, max_int(app.lines.len - 1, 0))
	}
	return max_int(content_scroll, cursor_scroll)
}

fn (app &PreviewApp) half_page_step() int {
	return max_int(app.viewport_height() / 2, 1)
}

fn (mut app PreviewApp) request_quit() {
	if app.editor.dirty {
		app.show_quit_confirm = true
		return
	}
	exit(0)
}

fn (mut app PreviewApp) handle_quit_confirm_input(e &tui.Event) {
	match e.code {
		.s {
			if app.save_editor() {
				exit(0)
			}
		}
		.q {
			exit(0)
		}
		.escape {
			app.show_quit_confirm = false
		}
		else {}
	}
}

fn (app &PreviewApp) current_line_index() int {
	if app.current_match >= 0 {
		return app.current_match
	}
	if app.view_cursor >= 0 && app.view_cursor < app.lines.len {
		return app.view_cursor
	}
	return -1
}

fn (mut app PreviewApp) handle_help_input(e &tui.Event) {
	match e.code {
		.question_mark, .escape, .enter, .q {
			app.show_help = false
		}
		else {}
	}
}

fn wrap_preview_text(input string, width int, preserve_ansi bool) []string {
	mut lines := []string{}
	for raw_line in input.split_into_lines() {
		if raw_line.len == 0 {
			lines << ''
			continue
		}
		if preserve_ansi {
			lines << raw_line
			continue
		}
		if raw_line.len <= width {
			lines << raw_line
			continue
		}
		for chunk in chunk_string(raw_line, width) {
			lines << chunk
		}
	}
	if lines.len == 0 {
		return ['']
	}
	return lines
}
