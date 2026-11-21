module vmarkdown

fn test_blank_lines_preserve_leading_trailing_and_nested_spacing() {
	input := '\n\n# A\n\n\n> First\n>\n>\n> Second\n\nLast\n\n\n'
	ordinary := parse(input) or { panic(err) }
	assert ordinary.find_all(.blank_lines).len == 0
	assert ordinary.binary_encode()[4] == binary_format_version
	options := ParseOptions{ preserve_blank_lines: true }
	doc := parse_with_options(input, options) or { panic(err) }
	assert doc.find_all(.blank_lines).map((it.node as BlankLinesNode).line_count) == [
		2,
		2,
		2,
		1,
		2,
	]
	assert doc.to_markdown() == input
	terminal := doc.to_terminal_with_options(TerminalRenderOptions{ color: false })
	assert terminal.starts_with('\n\nA')
	assert terminal.contains('▎ First\n▎\n▎\n▎ Second')
	assert terminal.ends_with('Last\n\n\n')
	html := render_html_with_options(input, HtmlRenderOptions{ parser: options }) or { panic(err) }
	assert html.contains('<p>First</p>\n<br>\n<p>Second</p>')
}

fn test_blank_lines_do_not_add_spacing_between_adjacent_blocks_after_binary_decode() {
	input := '# A\nBody\n# B\nMore'
	options := ParseOptions{ preserve_blank_lines: true }
	doc := parse_with_options(input, options) or { panic(err) }
	assert doc.find_all(.blank_lines).len == 0
	decoded := binary_decode(doc.binary_encode()) or { panic(err) }
	assert decoded.to_markdown() == input
}

fn test_blank_lines_round_trip_after_raw_html() {
	input := '> <div>\n> Raw\n> </div>\n>\n> Paragraph'
	options := ParseOptions{ preserve_blank_lines: true }
	doc := parse_with_options(input, options) or { panic(err) }
	assert doc.to_markdown() == input
	reparsed := parse_with_options(doc.to_markdown(), options) or { panic(err) }
	assert reparsed.stable_id() == doc.stable_id()
}

fn test_blank_lines_and_footnotes_round_trip_when_definitions_move_to_end() {
	input := 'Lead\n\n[^n]: note\n\nLast[^n]\n'
	options := ParseOptions{ preserve_blank_lines: true, footnotes: true }
	doc := parse_with_options(input, options) or { panic(err) }
	assert doc.find_all(.footnote_definition).len == 1
	reparsed := parse_with_options(doc.to_markdown(), options) or { panic(err) }
	assert reparsed.stable_id() == doc.stable_id()
}

fn test_spoiler_table_keeps_explicit_empty_cells_and_escaped_pipes() {
	input := '| A | B | C |\n|---|---|---|\n| ||**secret**|| | | \\|\\|visible\\|\\| |\n'
	options := ParseOptions{ spoilers: true }
	doc := parse_with_options(input, options) or { panic(err) }
	table := doc.children[0] as TableNode
	assert table.body[0].cells.map(render_inline_text(it.children)) == ['secret', '', '||visible||']
	assert doc.find_all(.spoiler).len == 1
	assert doc.find_all(.strong).len == 1
	masked := doc.to_terminal_with_options(TerminalRenderOptions{ color: false })
	revealed := doc.to_terminal_with_options(TerminalRenderOptions{ color: false, reveal_spoilers: true })
	assert masked.contains('[spoiler]')
	assert !masked.contains('secret')
	assert revealed.contains('secret')
	assert masked.contains('||visible||')
	assert doc.binary_encode()[4] == binary_layout_version
	decoded := binary_decode(doc.binary_encode()) or { panic(err) }
	assert decoded.stable_id() == doc.stable_id()
	reparsed := parse_with_options(doc.to_markdown(), options) or { panic(err) }
	assert reparsed.stable_id() == doc.stable_id()
	html := render_html_with_options(input, HtmlRenderOptions{ parser: options }) or { panic(err) }
	assert html.contains('<td><x-spoiler><strong>secret</strong></x-spoiler></td>\n<td></td>\n<td>||visible||</td>')
}

fn test_compact_gfm_empty_cells_follow_upstream_spoiler_precedence() {
	input := '| A | B | C | D | E |\n|---|---|---|---|---|\n| a ||c|| e |\n'
	ordinary := parse_with_dialect(input, .gfm) or { panic(err) }
	assert ordinary.find_all(.spoiler).len == 0
	table := ordinary.children[0] as TableNode
	assert table.body[0].cells.map(render_inline_text(it.children)) == ['a', '', 'c', '', 'e']
	opted_in := parse_with_options(input, ParseOptions{ spoilers: true }) or { panic(err) }
	assert opted_in.find_all(.spoiler).len == 1
	combined := opted_in.children[0] as TableNode
	assert combined.body[0].cells.map(render_inline_text(it.children)) == ['a c e', '', '', '',
		'']
}
