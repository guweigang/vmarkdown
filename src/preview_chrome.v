module vmarkdown

import term

// Interactive preview drawing, chrome formatting, and overlays.

fn (mut app PreviewApp) draw_header() {
	line_number := if app.editing { app.editor.cursor_y + 1 } else { app.current_line_index() + 1 }
	encoding := if app.source_path.len > 0 { ' [${app.source_encoding.label()}]' } else { '' }
	label := if app.editor.dirty {
		app.source_label + encoding + ' [+]'
	} else {
		app.source_label + encoding
	}
	line := build_preview_header_line(label, app.mode, line_number, app.tui.window_width)
	app.tui.draw_text(0, 0, line)
}

fn (mut app PreviewApp) draw_content() {
	if app.editing {
		app.draw_editor_content()
		return
	}
	height := app.viewport_height()
	current_line_index := min_int(app.current_line_index(), app.lines.len - 1)
	gutter_width := app.line_number_gutter_width()
	for i in 0 .. height {
		line_index := app.scroll + i
		if line_index >= app.lines.len {
			break
		}
		is_current := line_index == current_line_index
		line_no := format_preview_line_number(line_index + 1, gutter_width, is_current)
		line := highlight_preview_line(app.lines[line_index], app.search_query, line_index == app.current_match_line_index())
		app.tui.draw_text(0, i + 2, line_no)
		app.tui.draw_text(gutter_width, i + 2, clip_preview_content_line(line, max_int(app.tui.window_width - gutter_width - 1, 1)))
	}
}

fn (mut app PreviewApp) draw_footer() {
	hints_y := max_int(app.tui.window_height - 1, 1)
	command_y := max_int(app.tui.window_height, 1)
	hints := if app.editing {
		build_preview_footer_line(.markdown, app.scroll, app.viewport_height(), app.lines.len, app.tui.window_width)
	} else {
		build_preview_footer_line(app.mode, app.scroll, app.viewport_height(), app.lines.len, app.tui.window_width)
	}
	command := if app.editing {
		build_editor_command_line(app.editor)
	} else {
		build_preview_command_line(app.search_query, app.search_active, app.search_status, app.current_match, app.lines)
	}
	app.tui.draw_text(0, hints_y, hints)
	app.tui.draw_text(0, command_y, pad_preview_line(command, app.tui.window_width))
}

fn (mut app PreviewApp) draw_help_overlay() {
	lines := preview_help_lines()
	width := min_int(preview_help_width(lines), max_int(app.tui.window_width, 4))
	height := lines.len + 2
	x := max_int((app.tui.window_width - width) / 2, 0)
	y := max_int((app.tui.window_height - height) / 2, 0)
	app.tui.draw_text(x, y, style_preview_overlay_border('╭' + '─'.repeat(max_int(width - 2, 0)) + '╮'))
	for i, line in lines {
		plain := fit_preview_plain(line, max_int(width - 2, 1))
		padding := ' '.repeat(max_int(width - 2 - plain.runes().len, 0))
		styled := style_preview_overlay_row(plain, padding, i == 0)
		app.tui.draw_text(x, y + i + 1, styled)
	}
	app.tui.draw_text(x, y + height - 1, style_preview_overlay_border('╰' + '─'.repeat(max_int(width - 2, 0)) + '╯'))
}

fn (mut app PreviewApp) draw_quit_confirm_overlay() {
	lines := app.quit_confirm_lines()
	width := min_int(preview_help_width(lines), max_int(app.tui.window_width, 4))
	height := lines.len + 2
	x := max_int((app.tui.window_width - width) / 2, 0)
	y := max_int((app.tui.window_height - height) / 2, 0)
	app.tui.draw_text(x, y, style_preview_overlay_border('╭' + '─'.repeat(max_int(width - 2, 0)) + '╮'))
	for i, line in lines {
		plain := fit_preview_plain(line, max_int(width - 2, 1))
		padding := ' '.repeat(max_int(width - 2 - plain.runes().len, 0))
		styled := style_preview_overlay_row(plain, padding, i == 0)
		app.tui.draw_text(x, y + i + 1, styled)
	}
	app.tui.draw_text(x, y + height - 1, style_preview_overlay_border('╰' + '─'.repeat(max_int(width - 2, 0)) + '╯'))
}

fn style_preview_overlay_border(text string) string {
	return term.bg_rgb(24, 30, 34, term.hex(0x7f8c93, text))
}

fn style_preview_overlay_row(plain string, padding string, is_title bool) string {
	border := term.hex(0x7f8c93, '│')
	content := if is_title {
		term.bold(term.hex(0xe6b450, plain)) + term.hex(0xe8edf2, padding)
	} else {
		term.hex(0xe8edf2, plain + padding)
	}
	return term.bg_rgb(24, 30, 34, border + content + border)
}

fn (app &PreviewApp) quit_confirm_lines() []string {
	mut lines := [
		' Unsaved changes ',
		'The Markdown buffer has changes that have not been saved.',
	]
	if app.editor.status.contains('changed on disk') {
		lines << 'The file changed on disk; use :w! to overwrite it.'
	}
	if app.source_path.len == 0 {
		lines << 'This preview has no writable file.'
		lines << '[q] Quit without saving    [Esc] Cancel'
	} else {
		lines << '[s] Save and quit    [q] Quit without saving    [Esc] Cancel'
	}
	return lines
}

fn (app &PreviewApp) line_number_gutter_width() int {
	digits := max_int('${max_int(app.lines.len, 1)}'.len, 2)
	return digits + 4
}

fn preview_mode_label(mode PreviewMode) string {
	return match mode {
		.terminal { 'Terminal' }
		.markdown { 'Markdown' }
		.html { 'HTML' }
		.ast { 'AST' }
	}
}

fn build_preview_header_line(source_label string, mode PreviewMode, current_line int, width int) string {
	safe_width := max_int(width - 2, 24)
	left_plain := if safe_width >= 36 { ' vmarkdown preview ' } else { ' vmd ' }
	mode_plain := ' ${preview_mode_label(mode)} '
	line_plain := ' Ln ${max_int(current_line, 1)} '
	available := safe_width - left_plain.len - mode_plain.len - line_plain.len
	source_plain := if available > 0 {
		fit_preview_plain(' ${compact_preview_source_label(source_label)} ', available)
	} else {
		''
	}
	filler_plain := ' '.repeat(max_int(safe_width - left_plain.len - mode_plain.len - line_plain.len - source_plain.len, 0))
	left := term.bold(term.hex(0xe6b450, left_plain))
	filler := term.bg_rgb(18, 24, 28, filler_plain)
	source := term.bg_rgb(18, 24, 28, term.bright_black(source_plain))
	line_text := term.bg_rgb(18, 24, 28, term.hex(0xe6b450, term.bold(line_plain)))
	mode_text := term.bg_rgb(32, 39, 45, term.bright_white(mode_plain))
	return left + filler + source + line_text + mode_text + term.bg_rgb(18, 24, 28, '')
}

fn build_preview_footer_line(mode PreviewMode, scroll int, viewport_height int, total_lines int, width int) string {
	safe_width := max_int(width - 2, 24)
	position_plain := ' ${preview_position_label(scroll, viewport_height, total_lines)} '
	left_plain := build_preview_footer_left_plain()
	left_budget := max_int(safe_width - position_plain.len, 1)
	left := style_preview_footer_left(fit_preview_plain(left_plain, left_budget), mode)
	left_visible := term.strip_ansi(left).len
	filler_plain := ' '.repeat(max_int(safe_width - left_visible - position_plain.len, 0))
	filler := term.bg_rgb(18, 24, 28, filler_plain)
	position := term.bg_rgb(32, 39, 45, term.bright_black(position_plain))
	return left + filler + position
}

fn build_preview_footer_left_plain() string {
	mut parts := []string{}
	for item in preview_mode_items() {
		parts << '[${item.key}] ${item.label}'
	}
	parts << '[h/j/k/l] move  [w/b] word  [x/dd] delete  [u/Ctrl+r] undo/redo  [/] search  [i] insert  [?] help  [q] quit'
	return parts.join('  ')
}

fn style_preview_footer_left(input string, mode PreviewMode) string {
	mut out := input
	for item in preview_mode_items() {
		marker := '[${item.key}] ${item.label}'
		replacement := if item.mode == mode {
			term.bg_rgb(32, 39, 45, term.bright_white(marker))
		} else {
			term.dim(marker)
		}
		out = out.replace_once(marker, replacement)
	}
	out = out.replace_once('[h/j/k/l] move  [w/b] word  [x/dd] delete  [u/Ctrl+r] undo/redo  [/] search  [i] insert  [?] help  [q] quit', term.dim('[h/j/k/l] move  [w/b] word  [x/dd] delete  [u/Ctrl+r] undo/redo  [/] search  [i] insert  [?] help  [q] quit'))
	return out
}

fn preview_position_label(scroll int, viewport_height int, total_lines int) string {
	if total_lines <= 0 {
		return '0/0 0%'
	}
	start := min_int(max_int(scroll, 0) + 1, total_lines)
	end := min_int(max_int(scroll, 0) + max_int(viewport_height, 1), total_lines)
	percent := if total_lines <= max_int(viewport_height, 1) {
		100
	} else {
		min_int((end * 100 + total_lines - 1) / total_lines, 100)
	}
	return '${start}-${end}/${total_lines} ${percent}%'
}

struct PreviewModeItem {
	key   string
	label string
	mode  PreviewMode
}

fn preview_mode_items() []PreviewModeItem {
	return [
		PreviewModeItem{
			key: '1'
			label: 'terminal'
			mode: .terminal
		},
		PreviewModeItem{
			key: '2'
			label: 'markdown'
			mode: .markdown
		},
		PreviewModeItem{
			key: '3'
			label: 'html'
			mode: .html
		},
		PreviewModeItem{
			key: '4'
			label: 'ast'
			mode: .ast
		},
	]
}

fn pad_preview_line(line string, width int) string {
	safe_width := max_int(width - 2, 1)
	plain := fit_preview_plain(term.strip_ansi(line), safe_width)
	styled := term.bg_rgb(32, 39, 45, term.bright_cyan(plain))
	visible := term.strip_ansi(styled).len
	if visible >= safe_width {
		return styled
	}
	return styled + term.bg_rgb(32, 39, 45, ' '.repeat(safe_width - visible))
}

fn clip_preview_content_line(line string, width int) string {
	safe_width := max_int(width - 2, 1)
	plain := term.strip_ansi(line)
	if plain.runes().len <= safe_width {
		return line
	}
	return fit_preview_plain(plain, safe_width)
}

fn format_preview_line_number(line_number int, width int, is_current bool) string {
	text := '${line_number}'
	padding := ' '.repeat(max_int(width - text.len - 2, 0))
	plain := padding + text + '  '
	return if is_current {
		term.hex(0xe6b450, term.bold(plain))
	} else {
		term.bright_black(plain)
	}
}

fn compact_preview_source_label(path string) string {
	if path.len == 0 {
		return 'buffer'
	}
	if path.len <= 28 {
		return path
	}
	return '...' + path[path.len - 25..]
}

fn fit_preview_plain(input string, width int) string {
	safe_width := max_int(width, 1)
	runes := input.runes()
	if runes.len <= safe_width {
		return input
	}
	if safe_width <= 1 {
		return runes[..1].string()
	}
	return runes[..safe_width - 1].string() + '…'
}

fn preview_help_lines() []string {
	return [
		' vmarkdown preview help ',
		'1/2/3/4 switch Terminal, Markdown, HTML, AST views',
		'h/j/k/l or arrows move left/down/up/right',
		'w/b move by word; x deletes a character; dd deletes a line',
		'Ctrl+d / Ctrl+u scroll half a page down or up',
		'g goes to the top, G goes to the bottom',
		'/ starts search, Enter confirms, n/N jump matches',
		'mouse wheel scrolls; left click moves the cursor or activates controls',
		'i enters Insert mode for the original Markdown source',
		'in the editor, Esc returns to Normal; 1/2/3/4 open rendered views',
		'Esc leaves search input and clears search on the next press',
		'? toggles this help window',
		'q quits the preview',
	]
}

fn preview_help_width(lines []string) int {
	mut width := 24
	for line in lines {
		width = max_int(width, line.runes().len + 2)
	}
	return width
}
