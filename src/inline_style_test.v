module vmarkdown

fn test_inline_styles_are_independent_and_disabled_by_default() {
	input := '==marked== ++inserted++ x^2^ H~2~O'
	kinds := [AstNodeKind.highlight, .insertion, .superscript, .subscript]
	options := [ParseOptions{ highlight: true }, ParseOptions{ insertion: true },
		ParseOptions{ superscript: true }, ParseOptions{ subscript: true }]
	ordinary := parse(input) or { panic(err) }
	for kind in kinds {
		assert ordinary.find_all(kind).len == 0
	}
	assert ordinary.binary_encode()[4] == binary_format_version
	for index, opt in options {
		doc := parse_with_options(input, opt) or { panic(err) }
		for other_index, kind in kinds {
			assert doc.find_all(kind).len == if index == other_index { 1 } else { 0 }
		}
	}
}

fn test_inline_styles_coexist_with_earlier_extensions() {
	input := '==**Mark**== ++new++ x^2^ H~2~O ~~old~~[^n]\n\n> [!NOTE]\n> Tip.\n\n[^n]: A note.\n'
	options := ParseOptions{
		admonitions: true
		footnotes:   true
		highlight:   true
		insertion:   true
		superscript: true
		subscript:   true
	}
	doc := parse_with_options(input, options) or { panic(err) }
	assert doc.find_all(.strong).len == 1
	assert doc.find_all(.strikethrough).len == 1
	assert doc.find_all(.footnote_reference).len == 1
	assert doc.find_all(.admonition).len == 1
	assert doc.to_json().contains('"type":"highlight"')
	assert doc.to_json().contains('"type":"subscript"')
	plain := doc.to_terminal_with_options(TerminalRenderOptions{ color: false })
	assert plain.contains('Mark new x² H₂O old[1]')
	html := render_html_with_options(input, HtmlRenderOptions{ parser: options }) or { panic(err) }
	assert html.contains('<mark><strong>Mark</strong></mark> <ins>new</ins> x<sup>2</sup> H<sub>2</sub>O <del>old</del>')
	reparsed := parse_with_options(doc.to_markdown(), options) or { panic(err) }
	assert reparsed.stable_id() == doc.stable_id()
	bytes := doc.binary_encode()
	assert bytes[4] == binary_inline_style_version
	decoded := binary_decode(bytes) or { panic(err) }
	assert decoded.stable_id() == doc.stable_id()
}

fn test_inline_style_delimiters_remain_literal_in_normalized_output() {
	input := r'\==literal== \++plain++ \^not^ \~sub~. \===marked==.'
	options := ParseOptions{ highlight: true, insertion: true, superscript: true, subscript: true }
	doc := parse_with_options(input, options) or { panic(err) }
	assert doc.find_all(.highlight).len == 1
	assert doc.find_all(.insertion).len == 0
	assert doc.find_all(.superscript).len == 0
	assert doc.find_all(.subscript).len == 0
	reparsed := parse_with_options(doc.to_markdown(), options) or { panic(err) }
	assert reparsed.stable_id() == doc.stable_id()
}
