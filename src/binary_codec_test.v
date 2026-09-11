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

fn test_binary_v1_golden_inline_records() {
	text := InlineNode(TextNode{ text: 'a' })
	assert text.binary_encode() == [u8(0x20), 0x01, 0x61]
	assert InlineNode(EmphasisNode{ children: [text] }).binary_encode() == [u8(0x21), 0x03, 0x20,
		0x01, 0x61]
	assert InlineNode(StrongNode{ children: [text] }).binary_encode() == [u8(0x22), 0x03, 0x20,
		0x01, 0x61]
	assert InlineNode(CodeSpanNode{ text: 'a' }).binary_encode() == [u8(0x23), 0x01, 0x61]
	assert InlineNode(LinkNode{ url: 'u', text: [text] }).binary_encode() == [
		u8(0x24),
		0x01,
		0x75,
		0x03,
		0x20,
		0x01,
		0x61,
	]
	assert InlineNode(ImageNode{ url: 'u', alt: [text] }).binary_encode() == [
		u8(0x25),
		0x01,
		0x75,
		0x03,
		0x20,
		0x01,
		0x61,
	]
	assert InlineNode(StrikethroughNode{ children: [text] }).binary_encode() == [
		u8(0x26),
		0x03,
		0x20,
		0x01,
		0x61,
	]
	assert InlineNode(SoftBreakNode{}).binary_encode() == [u8(0x27)]
	assert InlineNode(HardBreakNode{}).binary_encode() == [u8(0x28)]
	assert InlineNode(RawHtmlInlineNode{ html: '<' }).binary_encode() == [u8(0x29), 0x01, 0x3c]
	assert InlineNode(WikiLinkNode{ target: 't', text: [text] }).binary_encode() == [
		u8(0x2a),
		0x01,
		0x74,
		0x03,
		0x20,
		0x01,
		0x61,
	]
	assert InlineNode(LatexMathNode{ content: 'x' }).binary_encode() == [u8(0x2b), 0x00, 0x01, 0x78]
	assert InlineNode(LatexMathNode{ content: 'x', display: true }).binary_encode() == [
		u8(0x2b),
		0x01,
		0x01,
		0x78,
	]
	assert InlineNode(UnderlineNode{ children: [text] }).binary_encode() == [u8(0x2c), 0x03, 0x20,
		0x01, 0x61]
}

fn test_binary_v1_golden_block_and_list_item_records() {
	text := InlineNode(TextNode{ text: 'a' })
	paragraph := BlockNode(ParagraphNode{ children: [text] })
	assert BlockNode(HeadingNode{ level: 2, children: [text] }).binary_encode() == [
		u8(0x01),
		0x02,
		0x03,
		0x20,
		0x01,
		0x61,
	]
	assert paragraph.binary_encode() == [u8(0x02), 0x03, 0x20, 0x01, 0x61]
	item := ListItemNode{
		level: 1
		children: [paragraph]
	}
	assert item.binary_encode() == [u8(0x10), 0x01, 0x00, 0x00, 0x00, 0x06, 0x05, 0x02, 0x03, 0x20,
		0x01, 0x61]
	assert BlockNode(ListNode{ start: 1, items: [item] }).binary_encode() == [
		u8(0x03),
		0x00,
		0x01,
		0x01,
		0x0c,
		0x10,
		0x01,
		0x00,
		0x00,
		0x00,
		0x06,
		0x05,
		0x02,
		0x03,
		0x20,
		0x01,
		0x61,
	]
	assert BlockNode(MetaNode{
		data: {
			' k ': ' v '
		}
	}).binary_encode() == [u8(0x04), 0x01, 0x01, 0x6b, 0x01, 0x76]
	assert BlockNode(BlockquoteNode{ children: [paragraph] }).binary_encode() == [
		u8(0x05),
		0x05,
		0x02,
		0x03,
		0x20,
		0x01,
		0x61,
	]
	assert BlockNode(CodeBlockNode{ lang: 'v', content: 'x' }).binary_encode() == [
		u8(0x06),
		0x01,
		0x76,
		0x01,
		0x78,
	]
	assert BlockNode(HorizontalRuleNode{}).binary_encode() == [u8(0x07)]
	assert BlockNode(TableNode{
		columns: 1
		head: [TableRowNode{
			cells: [TableCellNode{ children: [text] }]
		}]
	}).binary_encode() == [u8(0x08), 0x01, 0x01, 0x00, 0x06, 0x01, 0x00, 0x03, 0x20, 0x01, 0x61]
	assert BlockNode(RawHtmlBlockNode{ html: '<' }).binary_encode() == [u8(0x09), 0x01, 0x3c]
}

fn test_binary_v1_round_trip_covers_every_record_type() {
	inline_nodes := [
		InlineNode(TextNode{ text: 'text' }),
		InlineNode(EmphasisNode{ children: [InlineNode(TextNode{ text: 'em' })] }),
		InlineNode(StrongNode{ children: [InlineNode(TextNode{ text: 'strong' })] }),
		InlineNode(CodeSpanNode{ text: 'code' }),
		InlineNode(LinkNode{
			url: 'https://example.com'
			text: [InlineNode(TextNode{ text: 'link' })]
		}),
		InlineNode(ImageNode{
			url: 'image.png'
			alt: [InlineNode(TextNode{ text: 'image' })]
		}),
		InlineNode(StrikethroughNode{ children: [InlineNode(TextNode{ text: 'strike' })] }),
		InlineNode(SoftBreakNode{}),
		InlineNode(HardBreakNode{}),
		InlineNode(RawHtmlInlineNode{ html: '<kbd>' }),
		InlineNode(WikiLinkNode{
			target: 'docs'
			text: [InlineNode(TextNode{ text: 'wiki' })]
		}),
		InlineNode(LatexMathNode{ content: 'x^2', display: true }),
		InlineNode(UnderlineNode{ children: [InlineNode(TextNode{ text: 'under' })] }),
	]
	doc := Document{
		children: [
			BlockNode(HeadingNode{
				level: 2
				children: [InlineNode(TextNode{ text: 'heading' })]
			}),
			BlockNode(ParagraphNode{ children: inline_nodes }),
			BlockNode(ListNode{
				is_ordered: true
				start: 3
				items: [ListItemNode{
					level: 1
					number: 3
					is_task: true
					checked: true
					children: [BlockNode(ParagraphNode{
						children: [InlineNode(TextNode{ text: 'item' })]
					})]
				}]
			}),
			BlockNode(MetaNode{
				data: {
					'key': 'value'
				}
			}),
			BlockNode(BlockquoteNode{
				children: [BlockNode(ParagraphNode{
					children: [InlineNode(TextNode{ text: 'quote' })]
				})]
			}),
			BlockNode(CodeBlockNode{ lang: 'v', content: 'println(1)\n' }),
			BlockNode(HorizontalRuleNode{}),
			BlockNode(TableNode{
				columns: 1
				head: [TableRowNode{
					cells: [TableCellNode{
						alignment: .center
						children: [InlineNode(TextNode{ text: 'cell' })]
					}]
				}]
			}),
			BlockNode(RawHtmlBlockNode{ html: '<div>raw</div>\n' }),
		]
	}
	doc.validate() or { panic(err) }
	encoded := doc.binary_encode()
	decoded := binary_decode(encoded) or { panic(err) }
	assert decoded.binary_encode() == encoded
	assert decoded.find_all(.latex_math).len == 1
	assert decoded.find_all(.underline).len == 1
	assert decoded.find_all(.wiki_link).len == 1
	assert decoded.children.len == 9
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

fn test_binary_v1_preserves_canonical_whitespace_between_inline_nodes() {
	doc := parse('*a*  **b**') or { panic(err) }
	encoded := doc.binary_encode_checked() or { panic(err) }
	decoded := binary_decode(encoded) or { panic(err) }

	assert decoded.to_text() == 'a b'
	assert decoded.binary_encode() == encoded
	assert encoded == [u8(`V`), `M`, `D`, `A`, 0x01, 0x00, 0x0f, 0x02, 0x0d, 0x21, 0x03, 0x20, 0x01,
		`a`, 0x20, 0x01, ` `, 0x22, 0x03, 0x20, 0x01, `b`]
}

fn test_binary_v1_stable_id_distinguishes_semantic_inline_spacing() {
	spaced := parse('a **b**') or { panic(err) }
	compact := parse('a**b**') or { panic(err) }
	repeated := parse('a  **b**') or { panic(err) }

	assert spaced.stable_id() != compact.stable_id()
	assert spaced.stable_id() == repeated.stable_id()
}

fn test_binary_encode_checked_rejects_invalid_ast_without_panicking() {
	doc := Document{
		children: [BlockNode(ListNode{
			is_ordered: true
			start: -1
		})]
	}
	if _ := doc.binary_encode_checked() {
		assert false, 'checked binary encoding must reject invalid ASTs'
	} else {
		assert err is AstValidationError
		assert err.msg().contains('.start cannot be negative')
	}
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

fn test_binary_v1_round_trip_preserves_underline() {
	doc := parse_with_options('_**important**_', ParseOptions{
		underline: true
	}) or { panic(err) }
	encoded := doc.binary_encode()
	assert encoded.contains(underline_type_tag)
	decoded := binary_decode(encoded) or { panic(err) }
	assert decoded.binary_encode() == encoded
	underline := decoded.find_all(.underline)[0].node as UnderlineNode
	assert underline.children[0] is StrongNode
	assert render_inline_text(underline.children) == 'important'
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

fn test_binary_decode_supports_tighter_resource_limits() {
	data := Document{
		children: [BlockNode(ParagraphNode{
			children: [InlineNode(TextNode{ text: 'hi' })]
		})]
	}.binary_encode()

	if _ := binary_decode_with_limits(data, BinaryDecodeLimits{
		max_input_bytes: data.len - 1
	}) {
		assert false, 'binary data over the configured byte budget must fail'
	} else {
		assert err.msg().contains('exceeds ${data.len - 1} bytes')
	}
	if _ := binary_decode_with_limits(data, BinaryDecodeLimits{
		max_nodes: 1
	}) {
		assert false, 'binary AST over the configured node budget must fail'
	} else {
		assert err.msg().contains('maximum node count 1')
	}
	if _ := binary_decode_with_limits(data, BinaryDecodeLimits{
		max_nesting_depth: 1
	}) {
		assert false, 'binary AST over the configured depth budget must fail'
	} else {
		assert err.msg().contains('maximum depth 1')
	}
	decoded := binary_decode_with_limits(data, BinaryDecodeLimits{
		max_input_bytes: 0
		max_nodes: 0
		max_nesting_depth: 0
	}) or { panic(err) }
	assert decoded.binary_encode() == data
}

fn test_binary_decode_rejects_negative_resource_limits() {
	data := Document{}.binary_encode()
	for limits in [
		BinaryDecodeLimits{ max_input_bytes: -1 },
		BinaryDecodeLimits{ max_nodes: -1 },
		BinaryDecodeLimits{ max_nesting_depth: -1 },
	] {
		if _ := binary_decode_with_limits(data, limits) {
			assert false, 'negative binary decode limits must fail'
		} else {
			assert err.msg().contains('cannot be negative')
		}
	}
}

fn test_unbounded_node_limit_does_not_allow_impossible_count_allocation() {
	data := [u8(`V`), `M`, `D`, `A`, 0x01, 0x00, 0x04, 0x03, 0x00, 0x64, 0x01]
	if _ := binary_decode_with_limits(data, BinaryDecodeLimits{
		max_nodes: 0
	}) {
		assert false, 'impossible collection counts must fail before allocation'
	} else {
		assert err.msg().contains('exceeds remaining payload capacity')
	}
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
