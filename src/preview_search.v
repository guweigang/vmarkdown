module vmarkdown

import term
import term.ui as tui

// Interactive preview search, match navigation, and highlighting.

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

fn (app &PreviewApp) current_match_line_index() int {
	return app.current_match
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
			runes := app.search_query.runes()
			if runes.len > 0 {
				app.search_query = runes[..runes.len - 1].string()
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
	app.view_cursor = index
	app.scroll = max_int(index - context, 0)
	app.clamp_scroll()
	app.sync_source_cursor_from_view()
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
