module vmarkdown

import term

fn test_nested_admonitions_preserve_children_when_rewritten_and_encoded() {
	input := '- > [!warning]\n  > A **warning**.\n  >\n  > Another paragraph.\n'
	options := ParseOptions{ admonitions: true }
	doc := parse_with_options(input, options) or { panic(err) }
	assert doc.children[0] is ListNode
	alerts := doc.find_all(.admonition)
	assert alerts.len == 1
	assert (alerts[0].node as AdmonitionNode).children.len == 2
	reparsed := parse_with_options(doc.to_markdown(), options) or { panic(err) }
	assert reparsed.stable_id() == doc.stable_id()
	rewritten := doc.rewrite_inlines(fn (visit AstInlineRewrite) ![]InlineNode {
		if visit.node is TextNode && visit.node.text == 'warning' {
			return [InlineNode(TextNode{ text: 'updated' })]
		}
		return [visit.node]
	}) or { panic(err) }
	assert rewritten.find_all(.admonition).len == 1
	assert rewritten.to_markdown().contains('**updated**')
	bytes := rewritten.binary_encode()
	assert bytes[4] == binary_admonition_version
	decoded := binary_decode(bytes) or { panic(err) }
	assert decoded.stable_id() == rewritten.stable_id()
}

fn test_admonition_preview_maps_its_label_and_body_to_source() {
	input := '# Title\n\n> [!NOTE]\n> Alert body\n\nAfter\n'
	options := ParseOptions{ admonitions: true }
	lines := preview_lines_with_options(input, .terminal, 80, options) or { panic(err) }
	sources := build_preview_line_sources_with_options(input, .terminal, 80, lines, options)
	assert lines.len == sources.len
	mut alert_lines := 0
	for index, line in lines {
		match term.strip_ansi(line).trim_space() {
			'▎ NOTE' {
				assert sources[index].source_line == 2
				alert_lines++
			}
			'▎ Alert body' {
				assert sources[index].source_line == 3
				alert_lines++
			}
			else {}
		}
	}
	assert alert_lines == 2
	html := preview_lines_with_options(input, .html, 80, options) or { panic(err) }
	assert html.join('\n').contains('class="admonition-note"')
}
