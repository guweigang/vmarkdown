module vmarkdown

fn test_binary_v1_golden_minimal_document() {
	doc := Document{
		children: [BlockNode(ParagraphNode{
			children: [InlineNode(TextNode{ text: 'hi' })]
		})]
	}
	assert doc.binary_encode() == [u8(0x56), 0x4d, 0x44, 0x41, 0x01, 0x00, 0x06, 0x02, 0x04, 0x20,
		0x02, 0x68, 0x69]
}

fn test_binary_v1_round_trip_preserves_core_semantics() {
	input := '- [x] **done**\n\n~~gone~~  \nnext <kbd>key</kbd>\n\n<div>raw</div>\n'
	doc := parse(input) or { panic(err) }
	encoded := doc.binary_encode()
	decoded := binary_decode(encoded) or { panic(err) }
	assert decoded.binary_encode() == encoded
	list := decoded.children[0] as ListNode
	assert list.items[0].is_task
	assert list.items[0].checked
	paragraph := decoded.children[1] as ParagraphNode
	assert paragraph.children[0] is StrikethroughNode
	assert paragraph.children.any(it is HardBreakNode)
	assert paragraph.children.any(it is RawHtmlInlineNode)
	assert decoded.children[2] is RawHtmlBlockNode
}

fn test_binary_v1_round_trip_preserves_wiki_links() {
	doc := parse_with_options('[[docs|**Guide**]]', ParseOptions{
		wiki_links: true
	}) or { panic(err) }
	encoded := doc.binary_encode()
	assert encoded.contains(wiki_link_type_tag)
	decoded := binary_decode(encoded) or { panic(err) }
	assert decoded.binary_encode() == encoded
	wiki := decoded.find_all(.wiki_link)[0].node as WikiLinkNode
	assert wiki.target == 'docs'
	assert render_inline_text(wiki.text) == 'Guide'
}

fn test_binary_v1_round_trip_preserves_latex_math() {
	doc := parse_with_options(r'$$\int_a^b x dx$$', ParseOptions{
		latex_math: true
	}) or { panic(err) }
	encoded := doc.binary_encode()
	assert encoded.contains(latex_math_type_tag)
	decoded := binary_decode(encoded) or { panic(err) }
	assert decoded.binary_encode() == encoded
	math := decoded.find_all(.latex_math)[0].node as LatexMathNode
	assert math.content == r'\int_a^b x dx'
	assert math.display
}

fn test_binary_v1_varint_does_not_truncate_large_values() {
	doc := Document{
		children: [BlockNode(ListNode{
			is_ordered: true
			start: 70_000
			items: []ListItemNode{}
		})]
	}
	decoded := binary_decode(doc.binary_encode()) or { panic(err) }
	list := decoded.children[0] as ListNode
	assert list.start == 70_000
}

fn test_binary_v1_rejects_invalid_envelopes_and_payloads() {
	valid := Document{}.binary_encode()

	mut bad_magic := valid.clone()
	bad_magic[0] = `X`
	if _ := binary_decode(bad_magic) {
		assert false, 'bad magic must fail'
	}

	mut bad_version := valid.clone()
	bad_version[4] = 2
	if _ := binary_decode(bad_version) {
		assert false, 'unknown version must fail'
	}

	if _ := binary_decode(valid[..valid.len - 1]) {
		assert false, 'truncated payload must fail'
	}

	mut trailing := valid.clone()
	trailing << u8(0)
	if _ := binary_decode(trailing) {
		assert false, 'trailing bytes must fail'
	}

	if _ := binary_decode([u8(`V`), `M`, `D`, `A`, 1, 0, 2, 0x02, 0x80]) {
		assert false, 'truncated varint must fail'
	}

	if _ := binary_decode([u8(`V`), `M`, `D`, `A`, 1, 0, 3, 0x02, 0x80, 0x00]) {
		assert false, 'non-canonical varint must fail'
	}
}
