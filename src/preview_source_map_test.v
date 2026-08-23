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
