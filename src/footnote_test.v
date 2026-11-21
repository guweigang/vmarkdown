module vmarkdown

import term

fn test_footnotes_number_references_and_preserve_definition_contents() {
	input := 'See[^b], then[^a], then[^b] again.\n\n[^a]: Note A.\n[^b]: Note **B**.\n[^unused]: Unused.\n'
	options := ParseOptions{ footnotes: true }
	doc := parse_with_options(input, options) or { panic(err) }
	refs := doc.find_all(.footnote_reference)
	assert refs.map((it.node as FootnoteReferenceNode).number) == [1, 2, 1]
	assert input[refs[0].span.start..refs[0].span.end] == '[^b]'
	defs := doc.find_all(.footnote_definition)
	assert defs.map((it.node as FootnoteDefinitionNode).label) == ['b', 'a']
	assert doc.to_markdown().contains('[^b]: Note **B**.')
	assert doc.to_json().contains('"type":"footnote_reference","number":1,"label":"b"')
	plain := doc.to_terminal_with_options(TerminalRenderOptions{ color: false })
	assert plain.contains('See[1], then[2], then[1] again.')
	assert plain.contains('Footnotes\n\n[1] Note B.\n\n[2] Note A.')
	html := render_html_with_options(input, HtmlRenderOptions{ parser: options }) or { panic(err) }
	assert html.contains('id="fnref-1-2">1</a>')
	assert html.contains('<section class="footnotes">')
	assert html.contains('Note <strong>B</strong>.')
	assert !html.contains('Unused.')
	ordinary := parse(input) or { panic(err) }
	assert ordinary.find_all(.footnote_reference).len == 0
	assert ordinary.binary_encode()[4] == binary_format_version
}

fn test_table_footnote_and_later_admonition_round_trip_in_version_three() {
	input := '| A | B |\n| --- | --- |\n| One[^a\\|b] | Two |\n\n> [!TIP]\n> Tip.\n\n[^a\\|b]: The note.\n'
	options := ParseOptions{ footnotes: true, admonitions: true }
	doc := parse_with_options(input, options) or { panic(err) }
	assert doc.find_all(.footnote_reference).len == 1
	assert doc.find_all(.admonition).len == 1
	reparsed := parse_with_options(doc.to_markdown(), options) or { panic(err) }
	assert reparsed.stable_id() == doc.stable_id()
	bytes := doc.binary_encode()
	assert bytes[4] == binary_footnote_version
	decoded := binary_decode(bytes) or { panic(err) }
	assert decoded.stable_id() == doc.stable_id()
}

fn test_preview_maps_footnotes_in_reference_order_to_their_source_definitions() {
	input := 'Body[^b] then[^a].\n\n[^a]: Note A.\n[^b]: Note B.\n'
	options := ParseOptions{ footnotes: true }
	lines := preview_lines_with_options(input, .terminal, 80, options) or { panic(err) }
	sources := build_preview_line_sources_with_options(input, .terminal, 80, lines, options)
	mut mapped := []int{}
	for index, line in lines {
		if term.strip_ansi(line) in ['[1] Note B.', '[2] Note A.'] {
			mapped << sources[index].source_line
		}
	}
	assert mapped == [3, 2]
}

fn test_normalized_footnote_labels_keep_distinct_notes_and_respect_length_bound() {
	long_label := '|'.repeat(45)
	input := 'A[^a\\*] and B[^a*], and C[^${long_label}].\n\n[^a\\*]: First.\n[^a*]: Second.\n[^${long_label}]: Third.\n'
	options := ParseOptions{ footnotes: true }
	doc := parse_with_options(input, options) or { panic(err) }
	assert doc.find_all(.footnote_definition).len == 3
	reparsed := parse_with_options(doc.to_markdown(), options) or { panic(err) }
	assert reparsed.stable_id() == doc.stable_id()
}
