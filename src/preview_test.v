module vmarkdown

import os
import term
import term.ui as tui

fn test_preview_lines_for_modes() {
	markdown := '# Title\n\nParagraph\n'
	terminal := preview_lines(markdown, .terminal, 40) or { panic(err) }
	md := preview_lines(markdown, .markdown, 40) or { panic(err) }
	html := preview_lines(markdown, .html, 40) or { panic(err) }
	ast := preview_lines(markdown, .ast, 40) or { panic(err) }
	assert terminal.len > 0
	assert md.len > 0
	assert html.len > 0
	assert ast.len > 0
	assert terminal.join('\n').contains('Title')
	assert md.join('\n').contains('# Title')
	assert html.join('\n').contains('<h1>Title</h1>')
	assert ast.join('\n').contains('Heading(level=1)')
}

fn test_build_mermaid_preview_markdown() {
	wrapped := build_mermaid_preview_markdown('flowchart TD\nA[Start] --> B[Done]\n')
	assert wrapped.contains('# Mermaid Preview')
	assert wrapped.contains('```mermaid')
	assert wrapped.contains('flowchart TD')
	assert wrapped.ends_with('```')
}

fn test_build_diagram_preview_markdown() {
	wrapped := build_diagram_preview_markdown('Dependency Diagram',
		'[root] ─┬─▶ [preview] ┐\n        └─▶ [lexer]   ┴ ─▶ [parser]')
	assert wrapped.contains('# Dependency Diagram')
	assert wrapped.contains('```text')
	assert wrapped.contains('[root]')
	assert wrapped.ends_with('```')
}

fn test_build_diff_preview_markdown() {
	wrapped := build_diff_preview_markdown('Mermaid Diff', [
		'reused graph_node at nodes[0]',
		'changed graph_node label at nodes[1]',
	])
	assert wrapped.contains('# Mermaid Diff')
	assert wrapped.contains('```text')
	assert wrapped.contains('changed graph_node label at nodes[1]')
	assert wrapped.ends_with('```')
}

fn test_build_diff_preview_markdown_empty() {
	wrapped := build_diff_preview_markdown('', [])
	assert wrapped.contains('# Diagram Diff Preview')
	assert wrapped.contains('no changes')
}

fn test_render_diff_preview_terminal_styles_status_lines() {
	rendered := render_diff_preview_terminal([
		'added timeline_entry at entries[1]',
		'removed timeline_entry at entries[0]',
		'changed graph_node label at nodes[1]',
		'reused graph_node at nodes[0]',
	])
	lines := rendered.split_into_lines()
	assert lines.len == 4
	assert term.strip_ansi(lines[0]) == 'added timeline_entry at entries[1]'
	assert term.strip_ansi(lines[1]) == 'removed timeline_entry at entries[0]'
	assert term.strip_ansi(lines[2]) == 'changed graph_node label at nodes[1]'
	assert term.strip_ansi(lines[3]) == 'reused graph_node at nodes[0]'
	assert lines[0] != term.strip_ansi(lines[0])
	assert lines[1] != term.strip_ansi(lines[1])
	assert lines[2] != term.strip_ansi(lines[2])
	assert lines[3] != term.strip_ansi(lines[3])
}

fn test_render_diff_preview_terminal_empty() {
	rendered := render_diff_preview_terminal([])
	assert term.strip_ansi(rendered) == 'no changes'
	assert rendered != 'no changes'
}

fn test_preview_header_and_footer_labels() {
	header := term.strip_ansi(build_preview_header_line('/Users/guweigang/Source/vmarkdown/README.md',
		.terminal, 42, 72))
	footer := term.strip_ansi(build_preview_footer_line(.terminal, 10, 20, 100, 200))
	command := term.strip_ansi(build_preview_command_line('needle', false, '', 4, [
		'needle',
		'x',
		'needle',
		'y',
		'needle',
	]))
	assert header.contains('vmarkdown preview')
	assert header.contains('Terminal')
	assert header.contains('README.md')
	assert header.contains('Ln 42')
	assert footer.contains('[1] terminal')
	assert footer.contains('[h/j/k/l] move')
	assert footer.contains('[w/b] word')
	assert footer.contains('[x/dd] delete')
	assert footer.contains('[?] help')
	assert footer.contains('[i] insert')
	assert footer.contains('[/] search')
	assert footer.contains('11-30/100 30%')
	assert command.contains('match 3/3: needle')
}

fn test_preview_header_and_footer_fit_width() {
	header := term.strip_ansi(build_preview_header_line('/Users/guweigang/Source/vmarkdown/README.md',
		.terminal, 99, 32))
	footer := term.strip_ansi(build_preview_footer_line(.terminal, 10, 20, 100, 32))
	command := term.strip_ansi(pad_preview_line(build_preview_command_line('very-long-needle',
		false, '', 0, ['very-long-needle']), 32))
	content :=
		term.strip_ansi(clip_preview_content_line('This is a very long content line that should not wrap into the header row.', 32))
	assert header.runes().len <= 32
	assert footer.runes().len <= 32
	assert command.runes().len <= 32
	assert content.runes().len <= 32
}

fn test_preview_line_number_helpers() {
	app := PreviewApp{
		lines: ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l']
	}
	assert app.line_number_gutter_width() >= 4
	plain := term.strip_ansi(format_preview_line_number(12, 3, false))
	current := term.strip_ansi(format_preview_line_number(12, 3, true))
	assert plain == '12  '
	assert current == '12  '
}

fn test_preview_position_label_for_small_document() {
	assert preview_position_label(0, 20, 3) == '1-3/3 100%'
	assert preview_position_label(2, 5, 10) == '3-7/10 70%'
}

fn test_preview_search_helpers() {
	lines := ['Alpha', 'Beta keyword', 'Gamma KEYWORD']
	assert find_preview_match(lines, 'keyword', 0, 1) or { panic(err) } == 1
	assert find_preview_match(lines, 'keyword', 2, -1) or { panic(err) } == 2
	assert preview_search_label('needle', true, '') == '/needle_'
	assert preview_search_label('needle', false, '') == 'search: needle'
	assert preview_search_label('needle', false, 'match: needle') == 'match: needle'
	assert count_preview_matches(lines, 'keyword') == 2
	assert preview_match_ordinal(lines, 'keyword', 2) == 2
	assert preview_line_matches('\x1b[31mKeyword\x1b[0m here', 'keyword')
	assert term.strip_ansi(highlight_preview_line('Beta keyword', 'keyword', false)).contains('Beta keyword')
	assert highlight_preview_line('Beta keyword', 'keyword', true) != 'Beta keyword'
	assert highlight_preview_match_segments('stable_id() / encode()', 'stable', true) != 'stable_id() / encode()'
	assert term.strip_ansi(highlight_preview_match_segments('stable_id() / encode()', 'stable',
		true)).contains('stable_id() / encode()')
}

fn test_preview_dismiss_search() {
	mut app := PreviewApp{
		search_active: true
		search_query:  'stable'
		search_status: ''
		current_match: 3
	}
	app.dismiss_search()
	assert !app.search_active
	assert app.search_query == 'stable'
	assert app.search_status == 'search canceled'
	assert app.current_match == 3

	app.dismiss_search()
	assert app.search_query == ''
	assert app.search_status == ''
	assert app.current_match == -1
}

fn test_preview_help_lines_and_width() {
	lines := preview_help_lines()
	assert lines.len > 4
	assert lines[0].contains('help')
	assert lines.join('\n').contains('Ctrl+d / Ctrl+u')
	assert lines.join('\n').contains('G goes to the bottom')
	assert lines.join('\n').contains('Esc returns to Normal')
	assert lines.join('\n').contains('h/j/k/l')
	assert lines.join('\n').contains('i enters Insert mode')
	assert lines.join('\n').contains('? toggles')
	assert preview_help_width(lines) >= 24
}

fn test_preview_edit_entry_starts_in_insert_mode() {
	mut app := PreviewApp{
		editor: new_markdown_editor('# Title\n')
	}
	app.start_editing()
	assert app.editing
	assert app.editor.mode == .insert
}

fn test_escape_returns_to_editor_normal_without_moving_cursor() {
	mut app := PreviewApp{
		editing: true
		editor:  new_markdown_editor('jjjj')
	}
	app.editor.mode = .insert
	app.editor.cursor_x = 4
	event := &tui.Event{
		typ:  .key_down
		code: .escape
	}
	app.handle_editor_insert_input(event)
	assert app.editing
	assert app.editor.mode == .normal
	assert app.editor.cursor_x == 4
}

fn test_editor_normal_undo_still_works() {
	mut app := PreviewApp{
		editing: true
		editor:  new_markdown_editor('before')
	}
	app.editor.insert_text('after')
	app.editor.mode = .normal
	event := &tui.Event{
		typ:  .key_down
		code: .u
	}
	app.handle_editor_normal_input(event)
	assert app.editor.text() == 'before'
}

fn test_preview_normal_undo_refreshes_current_view_after_switching_modes() {
	mut app := PreviewApp{
		markdown: '# Before\n'
		doc:      parse('# Before\n') or { panic(err) }
		editor:   new_markdown_editor('# Before\n')
		mode:     .html
	}
	app.editor.cursor_x = app.editor.current_line().runes().len
	app.editor.insert_text(' changed')
	app.editor.mode = .normal
	app.open_editor_view(.html)
	assert !app.editing
	assert app.mode == .html
	app.editor.undo()
	app.refresh_normal_view()
	assert app.mode == .html
	assert app.markdown == '# Before\n'
	assert app.doc.to_markdown().contains('# Before')
}

fn test_editor_status_line_is_compact() {
	mut editor := new_markdown_editor('one\ntwo')
	editor.mode = .insert
	editor.cursor_y = 1
	editor.cursor_x = 2
	editor.dirty = true
	line := term.strip_ansi(build_editor_footer_line(editor, 80))
	command := term.strip_ansi(build_editor_command_line(editor))
	assert line.contains('INSERT')
	assert line.contains('[+]')
	assert line.contains('2:3')
	assert !line.contains('[Esc]')
	assert command.contains('-- INSERT --')
}

fn test_editor_preview_restores_the_original_preview_scroll() {
	mut app := PreviewApp{
		markdown: '# Title\n'
		doc:      parse('# Title\n') or { panic(err) }
		editor:   new_markdown_editor('# Changed\n')
		scroll:   12
	}
	app.start_editing()
	app.scroll = 3
	app.show_editor_preview()
	assert !app.editing
	assert app.mode == .terminal
	assert app.scroll == 12
}

fn test_editor_display_fit_handles_wide_characters() {
	assert fit_editor_display('中文abc', 4) == '中文'
	assert fit_editor_display('中文abc', 5) == '中文a'
}

fn test_preview_editor_save_and_return_to_rendered_view() {
	path := os.join_path(os.temp_dir(), 'vmarkdown-preview-editor-${os.getpid()}.md')
	os.write_file(path, '# Before\n') or { panic(err) }
	defer {
		os.rm(path) or {}
	}
	mut app := PreviewApp{
		markdown:    '# Before\n'
		doc:         parse('# Before\n') or { panic(err) }
		source_path: path
		editor:      new_markdown_editor('# Before\n')
	}
	app.editor.cursor_y = 1
	app.editor.insert_text('After')
	assert app.editor.dirty
	assert app.save_editor()
	written := os.read_file(path) or { panic(err) }
	assert written == '# Before\nAfter'
	assert !app.editor.dirty
	app.editing = true
	app.show_editor_preview()
	assert !app.editing
	assert app.mode == .terminal
}

fn test_preview_editor_refuses_quit_with_unsaved_changes() {
	mut app := PreviewApp{
		editor: new_markdown_editor('before')
	}
	app.editor.insert_text('after')
	app.execute_editor_command('q')
	assert app.editor.status.contains('no write since last change')
}

fn test_preview_q_requests_confirmation_for_unsaved_buffer() {
	mut app := PreviewApp{
		editor: new_markdown_editor('before')
	}
	app.editor.insert_text('after')
	app.request_quit()
	assert app.show_quit_confirm
	lines := app.quit_confirm_lines()
	assert lines.join('\n').contains('Unsaved changes')
	assert lines.join('\n').contains('Quit without saving')
	assert lines.join('\n').contains('no writable file')

	cancel := &tui.Event{
		typ:  .key_down
		code: .escape
	}
	app.handle_quit_confirm_input(cancel)
	assert !app.show_quit_confirm
}

fn test_preview_quit_confirmation_offers_save_for_file_preview() {
	app := PreviewApp{
		source_path: '/tmp/document.md'
	}
	lines := app.quit_confirm_lines().join('\n')
	assert lines.contains('[s] Save and quit')
	assert lines.contains('[q] Quit without saving')
	assert lines.contains('[Esc] Cancel')
}

fn test_preview_scroll_helpers() {
	app := PreviewApp{
		lines: ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h']
	}
	mut app2 := app
	app2.tui = &tui.Context{
		window_height: 13
	}
	assert app2.viewport_height() == 10
	assert app2.half_page_step() == 5
	assert app2.max_scroll() == 0
	app2.lines = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12', '13']
	assert app2.max_scroll() == 3
}

fn test_preview_current_line_index() {
	app := PreviewApp{
		lines:         ['a', 'b', 'c']
		scroll:        1
		view_cursor:   1
		current_match: -1
	}
	assert app.current_line_index() == 1
	app2 := PreviewApp{
		lines:         ['a', 'b', 'c']
		scroll:        1
		current_match: 2
	}
	assert app2.current_line_index() == 2
}

fn test_preview_mode_switch_preserves_cursor_and_viewport() {
	mut app := PreviewApp{
		mode:          .terminal
		scroll:        12
		view_cursor:   17
		view_cursor_x: 9
	}
	app.set_mode(.html)
	assert app.mode == .html
	assert app.scroll == 12
	assert app.view_cursor == 17
	assert app.view_cursor_x == 9
}

fn test_preview_mode_switch_tracks_same_markdown_block() {
	mut source_lines := ['# Title', '']
	for i in 0 .. 12 {
		source_lines << 'Before ${i}.'
		source_lines << ''
	}
	target_source_line := source_lines.len
	source_lines << '## One-Minute Example'
	source_lines << ''
	for i in 0 .. 12 {
		source_lines << 'After ${i}.'
		source_lines << ''
	}
	markdown := source_lines.join('\n')
	mut app := PreviewApp{
		markdown: markdown
		doc:      parse(markdown) or { panic(err) }
		editor:   new_markdown_editor(markdown)
		mode:     .markdown
		tui:      &tui.Context{
			window_width:  80
			window_height: 24
		}
	}
	app.ensure_lines()
	app.view_cursor = find_preview_line_for_source(app.line_sources, target_source_line)
	app.scroll = max_int(app.view_cursor - 5, 0)
	app.sync_source_cursor_from_view()
	expected_row := app.view_cursor - app.scroll
	for mode in [PreviewMode.terminal, .html, .ast, .markdown] {
		app.set_mode(mode)
		app.ensure_lines()
		assert app.source_cursor_line == target_source_line
		assert app.line_sources[app.view_cursor].start_line == target_source_line
		assert app.view_cursor - app.scroll == expected_row
	}
}

fn test_preview_normal_hl_moves_horizontal_cursor() {
	mut app := PreviewApp{
		lines:           ['abcdef']
		view_cursor:     0
		view_cursor_x:   3
		source_cursor_x: 3
	}
	app.move_normal_cursor_horizontal(-1)
	assert app.view_cursor_x == 2
	assert app.source_cursor_x == 2
	app.move_normal_cursor_horizontal(1)
	assert app.view_cursor_x == 3
	assert app.source_cursor_x == 3
}

fn test_preview_normal_word_and_delete_commands_edit_source() {
	markdown := 'one two\nthree'
	mut app := PreviewApp{
		markdown:     markdown
		doc:          parse(markdown) or { panic(err) }
		editor:       new_markdown_editor(markdown)
		mode:         .markdown
		lines:        ['one two', 'three']
		line_sources: [
			PreviewLineSource{
				start_line:  0
				end_line:    0
				source_line: 0
			},
			PreviewLineSource{
				start_line:  1
				end_line:    1
				source_line: 1
			},
		]
		view_cursor:  0
		tui:          &tui.Context{
			window_width:  80
			window_height: 24
		}
	}
	app.move_normal_source_word(true)
	assert app.source_cursor_x == 4
	app.delete_normal_source_char()
	assert app.editor.text() == 'one wo\nthree'
	app.ensure_lines()
	app.view_cursor = find_preview_line_for_source(app.line_sources, 1)
	app.view_cursor_x = 0
	app.delete_normal_source_line()
	assert app.editor.text() == 'one wo'
}
