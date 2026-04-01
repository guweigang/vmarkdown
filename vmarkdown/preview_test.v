module vmarkdown

import term

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

fn test_preview_header_and_footer_labels() {
	header := term.strip_ansi(build_preview_header_line('/Users/guweigang/Source/vmarkdown/README.md',
		.terminal, 72))
	footer := term.strip_ansi(build_preview_footer_line(.terminal, 10, 20, 100, 120))
	command := term.strip_ansi(build_preview_command_line('needle', false, '', 4, ['needle', 'x', 'needle', 'y', 'needle']))
	assert header.contains('vmarkdown preview')
	assert header.contains('Terminal')
	assert header.contains('README.md')
	assert footer.contains('[1] terminal')
	assert footer.contains('[g] top')
	assert footer.contains('[/] search')
	assert footer.contains('[n/N] next/prev')
	assert footer.contains('11-30/100 30%')
	assert command.contains('match 3/3: needle')
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
		search_query: 'stable'
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
