module vmarkdown

import os
import v.vmod

fn test_version_matches_vmod() {
	vm := vmod.decode(@VMOD_FILE) or { panic(err) }
	assert version == vm.version
}

fn test_parse_heading_list_and_code_block() {
	input := '# Title

- alpha
- beta

```v
println("ok")
```
'
	doc := parse(input) or { panic(err) }
	assert doc.children.len == 3

	assert doc.children[0] is HeadingNode
	heading := doc.children[0] as HeadingNode
	assert heading.level == 1
	assert heading.children.len == 1
	assert heading.children[0] is TextNode
	assert (heading.children[0] as TextNode).text == 'Title'

	assert doc.children[1] is ListNode
	list := doc.children[1] as ListNode
	assert !list.is_ordered
	assert list.items.len == 2
	assert list.items[0].children.len == 1
	assert list.items[0].children[0] is ParagraphNode

	assert doc.children[2] is CodeBlockNode
	code := doc.children[2] as CodeBlockNode
	assert code.lang == 'v'
	assert code.content.contains('println("ok")')
}

fn test_parse_code_block_preserves_full_info_string() {
	input := '```json diagram\n{"version":1,"kind":"timeline","entries":[]}\n```\n'
	doc := parse(input) or { panic(err) }
	assert doc.children.len == 1
	assert doc.children[0] is CodeBlockNode
	code := doc.children[0] as CodeBlockNode
	assert code.lang == 'json diagram'
}

fn test_parse_table_ast_with_alignment_and_inline_children() {
	input := '| Name | Score | Note |\n| :--- | ---: | :---: |\n| **Ada** | 10 | [ok](https://example.com) |\n'
	doc := parse(input) or { panic(err) }
	assert doc.children.len == 1
	assert doc.children[0] is TableNode
	table := doc.children[0] as TableNode
	assert table.columns == 3
	assert table.head.len == 1
	assert table.body.len == 1
	assert table.head[0].cells.map(it.alignment) == [.left, .right, .center]
	assert table.head[0].cells[0].children[0] is TextNode
	assert table.body[0].cells[0].children[0] is StrongNode
	assert table.body[0].cells[2].children[0] is LinkNode
	assert BlockNode(table).binary_encode()[0] == u8(0x08)
	assert BlockNode(table).stable_id().starts_with('table:')
}

fn test_parse_with_tables_disabled_keeps_pipe_text_as_paragraph() {
	doc := parse_with_options('| A | B |\n| --- | --- |\n| x | y |\n', ParseOptions{
		tables: false
	}) or { panic(err) }
	assert doc.children.len == 1
	assert doc.children[0] is ParagraphNode
}

fn test_parse_block_html_preserves_verbatim_content() {
	input := '<p align="center">\n  <img src="brand.jpg" alt="Brand" />\n</p>\n'
	doc := parse(input) or { panic(err) }
	assert doc.children.len == 1
	assert doc.children[0] is RawHtmlBlockNode
	html := doc.children[0] as RawHtmlBlockNode
	assert html.html == input
	assert html.span == SourceSpan{ start: 0, end: input.len }
}

fn test_parse_preserves_default_extension_semantics() {
	input := '- [x] shipped\n- [ ] pending\n\n~~removed~~ and a  \nhard break\nand soft\n'
	doc := parse(input) or { panic(err) }
	list := doc.children[0] as ListNode
	assert list.items[0].is_task
	assert list.items[0].checked
	assert list.items[1].is_task
	assert !list.items[1].checked
	paragraph := doc.children[1] as ParagraphNode
	assert paragraph.children[0] is StrikethroughNode
	assert paragraph.children.any(it is HardBreakNode)
	assert paragraph.children.any(it is SoftBreakNode)
}

fn test_named_dialects_make_extension_behavior_explicit() {
	input := '| A | B |\n| --- | --- |\n| ~~x~~ | y |\n'
	commonmark := parse_with_dialect(input, .commonmark) or { panic(err) }
	assert commonmark.children.len == 1
	assert commonmark.children[0] is ParagraphNode

	gfm := parse_with_dialect(input, .gfm) or { panic(err) }
	assert gfm.children.len == 1
	assert gfm.children[0] is TableNode
	table := gfm.children[0] as TableNode
	assert table.body[0].cells[0].children[0] is StrikethroughNode
}

fn test_parse_wiki_links_as_typed_nodes_when_enabled() {
	input := 'before [[docs|**Guide**]] after'
	doc := parse_with_options(input, ParseOptions{
		wiki_links: true
	}) or { panic(err) }
	paragraph := doc.children[0] as ParagraphNode
	assert paragraph.children.len == 3
	assert paragraph.children[1] is WikiLinkNode
	wiki := paragraph.children[1] as WikiLinkNode
	assert wiki.target == 'docs'
	assert wiki.text.len == 1
	assert wiki.text[0] is StrongNode
	assert render_inline_text(wiki.text) == 'Guide'
	assert wiki.span.is_valid()

	default_doc := parse(input) or { panic(err) }
	default_paragraph := default_doc.children[0] as ParagraphNode
	assert !default_paragraph.children.any(it is WikiLinkNode)
}

fn test_parse_latex_math_as_typed_nodes_when_enabled() {
	input := r'$a+b=c$ and $$\int_a^b x dx$$'
	doc := parse_with_options(input, ParseOptions{
		latex_math: true
	}) or { panic(err) }
	paragraph := doc.children[0] as ParagraphNode
	assert paragraph.children.len == 3
	assert paragraph.children[0] is LatexMathNode
	inline_math := paragraph.children[0] as LatexMathNode
	assert inline_math.content == 'a+b=c'
	assert !inline_math.display
	assert inline_math.span.is_valid()
	assert paragraph.children[2] is LatexMathNode
	display_math := paragraph.children[2] as LatexMathNode
	assert display_math.content == r'\int_a^b x dx'
	assert display_math.display

	default_doc := parse(input) or { panic(err) }
	default_paragraph := default_doc.children[0] as ParagraphNode
	assert !default_paragraph.children.any(it is LatexMathNode)
}

fn test_parse_underline_as_typed_recursive_nodes_when_enabled() {
	input := '_foo_ and ___bar___'
	doc := parse_with_options(input, ParseOptions{
		underline: true
	}) or { panic(err) }
	paragraph := doc.children[0] as ParagraphNode
	assert paragraph.children.len == 3
	assert paragraph.children[0] is UnderlineNode
	underline := paragraph.children[0] as UnderlineNode
	assert underline.children[0] is TextNode
	assert (underline.children[0] as TextNode).text == 'foo'
	assert underline.span.is_valid()
	assert paragraph.children[2] is UnderlineNode
	level_1 := paragraph.children[2] as UnderlineNode
	assert level_1.children[0] is UnderlineNode
	level_2 := level_1.children[0] as UnderlineNode
	assert level_2.children[0] is UnderlineNode

	default_doc := parse('_foo_') or { panic(err) }
	default_paragraph := default_doc.children[0] as ParagraphNode
	assert default_paragraph.children[0] is EmphasisNode
	assert !default_paragraph.children.any(it is UnderlineNode)
}

fn test_parse_rejects_input_over_configured_byte_budget() {
	if _ := parse_with_limits('12345', ParseOptions{}, ParseLimits{
		max_input_bytes: 4
	}) {
		assert false, 'oversized Markdown input must fail'
	} else {
		assert err is MarkdownParseError
		assert (err as MarkdownParseError).kind == .resource_limit
		assert err.msg().contains('maximum size 4 bytes')
	}
}

fn test_parse_rejects_ast_over_configured_node_budget() {
	if _ := parse_with_limits('text', ParseOptions{}, ParseLimits{
		max_nodes: 2
	}) {
		assert false, 'Markdown over the node budget must fail'
	} else {
		assert err is MarkdownParseError
		parse_error := err as MarkdownParseError
		assert parse_error.kind == .resource_limit
		assert parse_error.native_code != 0
		assert err.msg().contains('maximum node count 2')
	}
}

fn test_parse_node_budget_includes_document_root() {
	doc := parse_with_limits('text', ParseOptions{}, ParseLimits{
		max_nodes: 3
	}) or { panic(err) }
	assert doc.children.len == 1
}

fn test_parse_rejects_ast_over_configured_nesting_budget() {
	if _ := parse_with_limits('> > nested', ParseOptions{}, ParseLimits{
		max_nesting_depth: 2
	}) {
		assert false, 'deeply nested Markdown must fail'
	} else {
		assert err is MarkdownParseError
		assert (err as MarkdownParseError).kind == .resource_limit
		assert err.msg().contains('maximum nesting depth 2')
	}
}

fn test_parse_rejects_negative_limits() {
	if _ := parse_with_limits('text', ParseOptions{}, ParseLimits{
		max_nodes: -1
	}) {
		assert false, 'negative parse limits must fail'
	} else {
		assert err is MarkdownParseError
		parse_error := err as MarkdownParseError
		assert parse_error.kind == .invalid_limits
		assert parse_error.offset == -1
		assert parse_error.native_code == 0
		assert err.msg() == 'max_nodes cannot be negative'
	}
}

fn test_parse_rejects_invalid_utf8_with_exact_byte_offset() {
	for input, expected_offset in {
		[u8(0xff), u8(`a`)].bytestr():   0
		[u8(`a`), 0xe2, 0x82].bytestr(): 1
		[u8(0xc0), 0x80].bytestr():      0
	} {
		if _ := parse(input) {
			assert false, 'invalid UTF-8 Markdown must fail'
		} else {
			assert err is MarkdownParseError
			parse_error := err as MarkdownParseError
			assert parse_error.kind == .invalid_utf8
			assert parse_error.offset == expected_offset
			assert parse_error.native_code == 0
			assert parse_error.message.contains('byte ${expected_offset}')
			assert parse_error.code() >= 5000
		}
	}

	valid := parse('�') or { panic(err) }
	assert valid.to_text() == '�'
}

fn test_parse_preserves_inline_raw_html_without_treating_it_as_text() {
	doc := parse('before <mark>inside</mark> after') or { panic(err) }
	paragraph := doc.children[0] as ParagraphNode
	assert paragraph.children.filter(it is RawHtmlInlineNode).len == 2
	assert (paragraph.children[1] as RawHtmlInlineNode).html == '<mark>'
}

fn test_source_spans_are_utf8_byte_ranges() {
	input := '# hé\n\nleft\nright\n'
	doc := parse(input) or { panic(err) }
	assert doc.span == SourceSpan{ start: 0, end: input.len }
	heading := doc.children[0] as HeadingNode
	assert heading.span == SourceSpan{ start: 2, end: 5 }
	assert doc.children[0].source_span() == heading.span
	assert heading.span.len() == 3
	text := heading.children[0] as TextNode
	assert text.span == SourceSpan{ start: 2, end: 5 }
	paragraph := doc.children[1] as ParagraphNode
	assert paragraph.children[1] is SoftBreakNode
	assert (paragraph.children[1] as SoftBreakNode).span == SourceSpan{ start: 11, end: 12 }
	assert paragraph.children[1].source_span() == SourceSpan{ start: 11, end: 12 }
}

fn test_binary_encoding_uses_protocol_type_tags() {
	heading := HeadingNode{
		level: 2
		children: [InlineNode(TextNode{
			text: 'Hello'
		})]
	}
	encoded := BlockNode(heading).binary_encode()
	assert encoded[0] == u8(0x01)
	assert encoded[1] == u8(2)

	paragraph := ParagraphNode{
		children: [InlineNode(TextNode{
			text: 'Hello'
		})]
	}
	assert BlockNode(paragraph).binary_encode()[0] == u8(0x02)
	assert BlockNode(paragraph).stable_id() != BlockNode(paragraph).semantic_stable_id()
}

fn test_parse_list_item_starting_with_code_span() {
	input := '- `Document` owns `[]BlockNode`\n'
	doc := parse(input) or { panic(err) }
	assert doc.children.len == 1
	assert doc.children[0] is ListNode
	list := doc.children[0] as ListNode
	assert list.items.len == 1
	assert list.items[0].children.len == 1
	assert list.items[0].children[0] is ParagraphNode
	paragraph := list.items[0].children[0] as ParagraphNode
	assert paragraph.children.len == 3
	assert paragraph.children[0] is CodeSpanNode
	assert paragraph.children[1] is TextNode
	assert paragraph.children[2] is CodeSpanNode
}

fn test_parse_readme_smoke() {
	readme := os.read_file(os.join_path(@VMODROOT, 'README.md')) or { panic(err) }
	doc := parse(readme) or { panic(err) }
	assert doc.children.len > 0
}
