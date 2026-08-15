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
	doc := parse(markdown)!
	mut app := &PreviewApp{
		markdown:     markdown
		doc:          doc
		mode:         mode
		source_label: if source_label.len > 0 { source_label } else { 'buffer' }
	}
	app.tui = tui.init(
		user_data:      app
		event_fn:       preview_event
		frame_fn:       preview_frame
		hide_cursor:    true
		capture_events: true
		window_title:   'vmarkdown preview'
	)
	app.tui.run()!
}

pub fn preview_terminal_buffer(rendered string, source_label string) ! {
	doc := parse('# Preview\n')!
	mut app := &PreviewApp{
		markdown:     '# Preview\n'
		doc:          doc
		mode:         .terminal
		source_label: if source_label.len > 0 { source_label } else { 'buffer' }
		raw_terminal: rendered
	}
	app.tui = tui.init(
		user_data:      app
		event_fn:       preview_event
		frame_fn:       preview_frame
		hide_cursor:    true
		capture_events: true
		window_title:   'vmarkdown preview'
	)
	app.tui.run()!
}

pub fn preview_file(path string) ! {
	preview_file_with_mode(path, .terminal)!
}

pub fn preview_file_with_mode(path string, mode PreviewMode) ! {
	markdown := os.read_file(path)!
	preview_with_mode(markdown, mode, path)!
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
	markdown string
	doc      Document
mut:
	tui           &tui.Context = unsafe { nil }
	mode          PreviewMode
	scroll        int
	lines         []string
	last_width    int
	last_height   int
	source_label  string
	search_query  string
	search_active bool
	search_status string
	current_match int = -1
	show_help     bool
	raw_terminal  string
}

fn preview_event(e &tui.Event, x voidptr) {
	mut app := unsafe { &PreviewApp(x) }
	if e.typ == .key_down && app.show_help {
		app.handle_help_input(e)
		return
	}
	if e.typ == .key_down && app.search_active {
		app.handle_search_input(e)
		return
	}
	if e.typ == .key_down {
		match e.code {
			.q {
				exit(0)
			}
			.escape {
				app.dismiss_search()
			}
			.h {
				app.show_help = true
			}
			.slash {
				app.start_search()
			}
			.j, .down {
				app.scroll += 1
			}
			.k, .up {
				app.scroll = max_int(app.scroll - 1, 0)
			}
			.page_down, .space {
				app.scroll += max_int(app.viewport_height() - 1, 1)
			}
			.page_up {
				app.scroll = max_int(app.scroll - max_int(app.viewport_height() - 1, 1), 0)
			}
			.d {
				if e.modifiers.has(.ctrl) {
					app.scroll += app.half_page_step()
				}
			}
			.g {
				if e.modifiers.has(.shift) {
					app.scroll = app.max_scroll()
				} else {
					app.scroll = 0
				}
			}
			.u {
				if e.modifiers.has(.ctrl) {
					app.scroll = max_int(app.scroll - app.half_page_step(), 0)
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
	app.ensure_lines()
	app.clamp_scroll()
	app.tui.clear()
	app.draw_content()
	app.draw_header()
	app.draw_footer()
	if app.show_help {
		app.draw_help_overlay()
	}
	app.tui.reset()
	app.tui.flush()
}

fn (mut app PreviewApp) set_mode(mode PreviewMode) {
	if app.mode == mode {
		return
	}
	app.mode = mode
	app.scroll = 0
	app.last_width = 0
	app.search_status = ''
}

fn (mut app PreviewApp) ensure_lines() {
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
	app.last_width = app.tui.window_width
	app.last_height = app.tui.window_height
}

fn (app &PreviewApp) viewport_height() int {
	return max_int(app.tui.window_height - 3, 1)
}

fn (mut app PreviewApp) clamp_scroll() {
	app.scroll = min_int(max_int(app.scroll, 0), app.max_scroll())
}

fn (app &PreviewApp) max_scroll() int {
	return max_int(app.lines.len - app.viewport_height(), 0)
}

fn (app &PreviewApp) half_page_step() int {
	return max_int(app.viewport_height() / 2, 1)
}

fn (mut app PreviewApp) draw_header() {
	line := build_preview_header_line(app.source_label, app.mode, app.current_line_index() + 2,
		app.tui.window_width)
	app.tui.draw_text(0, 0, line)
}

fn (mut app PreviewApp) draw_content() {
	height := app.viewport_height()
	current_line_index := min_int(app.current_line_index() + 1, app.lines.len - 1)
	gutter_width := app.line_number_gutter_width()
	for i in 0 .. height {
		line_index := app.scroll + i
		if line_index >= app.lines.len {
			break
		}
		is_current := line_index == current_line_index
		line_no := format_preview_line_number(line_index + 1, gutter_width, is_current)
		line := highlight_preview_line(app.lines[line_index], app.search_query,
			line_index == app.current_match_line_index())
		app.tui.draw_text(0, i + 1, line_no)
		app.tui.draw_text(gutter_width, i + 1, clip_preview_content_line(line, max_int(
			app.tui.window_width - gutter_width - 1, 1)))
	}
}

fn (mut app PreviewApp) draw_footer() {
	hints_y := max_int(app.tui.window_height - 2, 0)
	command_y := max_int(app.tui.window_height - 1, 0)
	hints := build_preview_footer_line(app.mode, app.scroll, app.viewport_height(), app.lines.len,
		app.tui.window_width)
	command := build_preview_command_line(app.search_query, app.search_active, app.search_status,
		app.current_match, app.lines)
	app.tui.draw_text(0, hints_y, hints)
	app.tui.draw_text(0, command_y, pad_preview_line(command, app.tui.window_width))
}

fn (mut app PreviewApp) draw_help_overlay() {
	lines := preview_help_lines()
	width := preview_help_width(lines)
	height := lines.len + 2
	x := max_int((app.tui.window_width - width) / 2, 0)
	y := max_int((app.tui.window_height - height) / 2, 0)
	app.tui.draw_text(x, y, term.bg_rgb(24, 30, 34, '╭' + '─'.repeat(max_int(width - 2, 0)) +
		'╮'))
	for i, line in lines {
		plain := fit_preview_plain(line, max_int(width - 4, 1))
		padding := ' '.repeat(max_int(width - 2 - plain.runes().len, 0))
		styled := if i == 0 {
			term.bg_rgb(24, 30, 34, '│' + term.bold(term.hex(0xe6b450, plain)) + padding + '│')
		} else {
			term.bg_rgb(24, 30, 34, '│' + plain + padding + '│')
		}
		app.tui.draw_text(x, y + i + 1, styled)
	}
	app.tui.draw_text(x, y + height - 1, term.bg_rgb(24, 30, 34, '╰' +
		'─'.repeat(max_int(width - 2, 0)) + '╯'))
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
	filler_plain := ' '.repeat(max_int(safe_width - left_plain.len - mode_plain.len -
		line_plain.len - source_plain.len, 0))
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
	parts << '[j/k] scroll  [Ctrl+d/u] half-page  [g/G] top/bottom  [/] search  [h] help  [q] quit'
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
	out = out.replace_once('[j/k] scroll  [g] top  [/] search  [n/N] next/prev  [q] quit',
		term.dim('[j/k] scroll  [Ctrl+d/u] half-page  [g/G] top/bottom  [/] search  [h] help  [q] quit'))
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
			key:   '1'
			label: 'terminal'
			mode:  .terminal
		},
		PreviewModeItem{
			key:   '2'
			label: 'markdown'
			mode:  .markdown
		},
		PreviewModeItem{
			key:   '3'
			label: 'html'
			mode:  .html
		},
		PreviewModeItem{
			key:   '4'
			label: 'ast'
			mode:  .ast
		},
	]
}

fn preview_search_label(search_query string, search_active bool, search_status string) string {
	if search_active {
		return '/${search_query}_'
	}
	if search_status.len > 0 {
		return search_status
	}
	if search_query.len > 0 {
		return 'search: ${search_query}'
	}
	return ''
}

fn build_preview_command_line(search_query string, search_active bool, search_status string, current_match int, lines []string) string {
	mut label := preview_search_label(search_query, search_active, search_status)
	if label.len == 0 {
		label = 'ready'
	}
	mut plain := label
	if !search_active && current_match >= 0 {
		total := count_preview_matches(lines, search_query)
		ordinal := preview_match_ordinal(lines, search_query, current_match)
		if total > 0 && ordinal > 0 {
			plain = 'match ${ordinal}/${total}: ${search_query}'
		}
	}
	return term.bg_rgb(32, 39, 45, term.bright_cyan(' ${plain} '))
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
	if input.len <= safe_width {
		return input
	}
	if safe_width <= 1 {
		return input[..1]
	}
	return input[..safe_width - 1] + '…'
}

fn (app &PreviewApp) current_match_line_index() int {
	return app.current_match
}

fn (app &PreviewApp) current_line_index() int {
	if app.current_match >= 0 {
		return app.current_match
	}
	if app.scroll >= 0 && app.scroll < app.lines.len {
		return app.scroll
	}
	return -1
}

fn (mut app PreviewApp) start_search() {
	app.search_active = true
	app.search_status = ''
}

fn (mut app PreviewApp) dismiss_search() {
	if app.search_active {
		app.search_active = false
		app.search_status = if app.search_query.len > 0 { 'search canceled' } else { '' }
		return
	}
	if app.search_query.len > 0 || app.current_match >= 0 || app.search_status.len > 0 {
		app.search_query = ''
		app.search_status = ''
		app.current_match = -1
	}
}

fn (mut app PreviewApp) handle_help_input(e &tui.Event) {
	match e.code {
		.h, .escape, .enter, .q {
			app.show_help = false
		}
		else {}
	}
}

fn (mut app PreviewApp) handle_search_input(e &tui.Event) {
	match e.code {
		.escape {
			app.dismiss_search()
		}
		.enter {
			app.search_active = false
			app.jump_to_next_match()
		}
		.backspace {
			if app.search_query.len > 0 {
				app.search_query = app.search_query[..app.search_query.len - 1]
			}
		}
		else {
			if e.utf8.len > 0 && is_preview_search_char(e) {
				app.search_query += e.utf8
			}
		}
	}
}

fn is_preview_search_char(e &tui.Event) bool {
	if e.code == .space {
		return true
	}
	if e.ascii >= 33 && e.ascii <= 126 {
		return true
	}
	return e.utf8.runes().len == 1 && e.utf8 != '\x00'
}

fn (mut app PreviewApp) jump_to_next_match() {
	if app.search_query.len == 0 {
		app.search_status = 'search: empty'
		return
	}
	start := if app.current_match >= 0 { app.current_match + 1 } else { app.scroll }
	index := find_preview_match(app.lines, app.search_query, start, 1) or {
		find_preview_match(app.lines, app.search_query, 0, 1) or {
			app.current_match = -1
			app.search_status = 'no match'
			return
		}
	}
	app.current_match = index
	app.scroll_match_into_view(index)
	app.search_status = ''
}

fn (mut app PreviewApp) jump_to_previous_match() {
	if app.search_query.len == 0 {
		app.search_status = 'search: empty'
		return
	}
	start := if app.current_match >= 0 { app.current_match - 1 } else { app.scroll }
	index := find_preview_match(app.lines, app.search_query, start, -1) or {
		find_preview_match(app.lines, app.search_query, app.lines.len - 1, -1) or {
			app.current_match = -1
			app.search_status = 'no match'
			return
		}
	}
	app.current_match = index
	app.scroll_match_into_view(index)
	app.search_status = ''
}

fn (mut app PreviewApp) scroll_match_into_view(index int) {
	context := max_int(app.viewport_height() / 3, 2)
	app.scroll = max_int(index - context, 0)
	app.clamp_scroll()
}

fn find_preview_match(lines []string, query string, start int, direction int) !int {
	if lines.len == 0 || query.len == 0 {
		return error('no match')
	}
	if direction >= 0 {
		for i := max_int(start, 0); i < lines.len; i++ {
			if preview_line_matches(lines[i], query) {
				return i
			}
		}
	} else {
		mut i := min_int(start, lines.len - 1)
		for i >= 0 {
			if preview_line_matches(lines[i], query) {
				return i
			}
			i--
		}
	}
	return error('no match')
}

fn preview_line_matches(line string, query string) bool {
	if query.len == 0 {
		return false
	}
	return term.strip_ansi(line).to_lower().contains(query.to_lower())
}

fn highlight_preview_line(line string, query string, is_current bool) string {
	if query.len == 0 {
		return line
	}
	plain := term.strip_ansi(line)
	if !plain.to_lower().contains(query.to_lower()) {
		return line
	}
	return highlight_preview_match_segments(plain, query, is_current)
}

fn highlight_preview_match_segments(line string, query string, is_current bool) string {
	if query.len == 0 {
		return line
	}
	lower_line := line.to_lower()
	lower_query := query.to_lower()
	mut start := 0
	mut parts := []string{}
	for start < line.len {
		match_index := lower_line[start..].index(lower_query) or { break }
		absolute := start + match_index
		if absolute > start {
			parts << line[start..absolute]
		}
		end := absolute + query.len
		matched := line[absolute..end]
		parts << style_preview_match(matched, is_current)
		start = end
	}
	if start < line.len {
		parts << line[start..]
	}
	return parts.join('')
}

fn style_preview_match(text string, is_current bool) string {
	if is_current {
		return term.bg_rgb(255, 214, 102, term.rgb(20, 26, 30, term.bold(text)))
	}
	return term.bg_rgb(103, 232, 249, term.rgb(18, 24, 28, term.bold(text)))
}

fn preview_help_lines() []string {
	return [
		' vmarkdown preview help ',
		'1/2/3/4 switch Terminal, Markdown, HTML, AST views',
		'j/k or arrows scroll by one line',
		'Ctrl+d / Ctrl+u scroll half a page down or up',
		'g goes to the top, G goes to the bottom',
		'/ starts search, Enter confirms, n/N jump matches',
		'Esc leaves search input and clears search on the next press',
		'h toggles this help window',
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

fn count_preview_matches(lines []string, query string) int {
	if query.len == 0 {
		return 0
	}
	mut count := 0
	for line in lines {
		if preview_line_matches(line, query) {
			count++
		}
	}
	return count
}

fn preview_match_ordinal(lines []string, query string, index int) int {
	if query.len == 0 || index < 0 {
		return 0
	}
	mut count := 0
	for i, line in lines {
		if preview_line_matches(line, query) {
			count++
			if i == index {
				return count
			}
		}
	}
	return 0
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
