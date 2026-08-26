module vmarkdown

fn test_scan_markdown_source_blocks_tracks_common_blocks() {
	markdown := '# Title\n\nParagraph one\ncontinues\n\n- one\n- two\n\n```v\nprintln(1)\n```\n'
	blocks := scan_markdown_source_blocks(markdown)
	assert blocks.len == 4
	assert blocks[0].start_line == 0
	assert blocks[1].start_line == 2
	assert blocks[1].end_line == 3
	assert blocks[2].start_line == 5
	assert blocks[3].start_line == 8
	assert blocks[3].end_line == 10
}

fn test_terminal_source_map_keeps_heading_and_paragraph_identity() {
	markdown := '# Title\n\nFirst paragraph.\n\n## Next\n\nSecond paragraph.\n'
	lines := preview_lines(markdown, .terminal, 60) or { panic(err) }
	sources := build_preview_line_sources(markdown, .terminal, 60, lines)
	assert sources.len == lines.len
	first := find_preview_line_for_source(sources, 2)
	next := find_preview_line_for_source(sources, 4)
	assert first < next
	assert sources[first].start_line == 2
	assert sources[next].start_line == 4
}

fn test_source_map_resolves_same_block_across_views() {
	markdown := '# Title\n\nBefore.\n\n## One-Minute Example\n\nAfter.\n'
	for mode in [PreviewMode.terminal, .markdown, .html, .ast] {
		lines := preview_lines(markdown, mode, 72) or { panic(err) }
		sources := build_preview_line_sources(markdown, mode, 72, lines)
		line := find_preview_line_for_source(sources, 4)
		assert line >= 0
		assert sources[line].start_line == 4
		assert sources[line].end_line == 4
	}
}

fn test_preview_column_map_skips_render_only_markup() {
	columns, exact := build_preview_source_columns('# **Hello** world',
		'<h1><strong>Hello</strong> world</h1>', .html)
	source := PreviewLineSource{
		source_columns: columns
		exact_columns:  exact
	}
	rendered := '<h1><strong>Hello</strong> world</h1>'.runes()
	hello_column := rendered.index(`H`)
	assert source_column_at(source, hello_column) == 4
	assert source_column_is_exact(source, hello_column)
	assert !source_column_is_exact(source, 0)
}

fn test_preview_column_map_prefers_ast_quoted_content() {
	columns, exact := build_preview_source_columns('Paragraph', 'Paragraph "Paragraph"', .ast)
	source := PreviewLineSource{
		source_columns: columns
		exact_columns:  exact
	}
	content_column := 'Paragraph "'.runes().len
	assert source_column_at(source, content_column) == 0
	assert source_column_is_exact(source, content_column)
	assert !source_column_is_exact(source, 0)
}

fn test_preview_column_map_uses_terminal_display_cells_for_wide_text() {
	columns, exact := build_preview_source_columns('中文', '中文', .terminal)
	source := PreviewLineSource{
		source_columns: columns
		exact_columns:  exact
	}
	assert source_column_at(source, 0) == 0
	assert source_column_at(source, 1) == 0
	assert source_column_at(source, 2) == 1
	assert source_column_is_exact(source, 2)
	assert preview_column_for_source(source, 1) == 2
}

fn test_preview_column_map_advances_across_wrapped_repeated_words() {
	source := 'word alpha word beta'
	first_columns, first_exact := build_preview_source_columns_from(source, 'word alpha',
		.terminal, 0)
	mut next_source_column := 0
	for i, is_exact in first_exact {
		if is_exact {
			next_source_column = max_int(next_source_column, first_columns[i] + 1)
		}
	}
	second_columns, second_exact := build_preview_source_columns_from(source, 'word beta',
		.terminal, next_source_column)
	second := PreviewLineSource{
		source_columns: second_columns
		exact_columns:  second_exact
	}
	assert source_column_at(second, 0) == 11
	assert source_column_is_exact(second, 0)
}

fn test_preview_line_map_selects_matching_source_line_in_list_block() {
	markdown := '- first\n- second'
	sources := build_preview_line_sources(markdown, .terminal, 60, ['• first', '• second'])
	assert sources.len == 2
	assert sources[0].source_line == 0
	assert sources[1].source_line == 1
	assert source_column_at(sources[1], 2) == 2
}
