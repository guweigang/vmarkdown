module vmarkdown

fn test_parsed_ast_satisfies_validation_contract() {
	doc := parse('# Title\n\n- [x] one\n  - nested\n\n| A | B |\n| --- | ---: |\n| x | y |\n') or {
		panic(err)
	}
	doc.validate() or { panic(err) }
	for child in doc.children {
		child.validate() or { panic(err) }
	}
}

fn test_validation_rejects_invalid_heading_and_source_span() {
	heading := Document{
		children: [BlockNode(HeadingNode{
			span: SourceSpan{ start: 4, end: 2 }
			level: 7
		})]
	}
	assert document_validation_error(heading).contains('.span must be a valid half-open range')

	bad_level := Document{
		children: [BlockNode(HeadingNode{ level: 7 })]
	}
	assert document_validation_error(bad_level).contains('.level must be between 1 and 6')
}

fn test_validation_rejects_noncanonical_list_state() {
	bad_number := Document{
		children: [BlockNode(ListNode{
			is_ordered: true
			start: 3
			items: [ListItemNode{ level: 1, number: 4 }]
		})]
	}
	assert document_validation_error(bad_number).contains('.number must be 3')

	bad_task := Document{
		children: [BlockNode(ListNode{
			start: 1
			items: [ListItemNode{ level: 1, checked: true }]
		})]
	}
	assert document_validation_error(bad_task).contains('.checked requires is_task')
}

fn test_validation_rejects_table_shape_mismatch() {
	doc := Document{
		children: [BlockNode(TableNode{
			columns: 2
			head: [TableRowNode{
				cells: [TableCellNode{}]
			}]
		})]
	}
	assert document_validation_error(doc).contains('.cells has 1 entries, expected 2')
}

fn test_validation_rejects_unstable_inline_shapes() {
	adjacent_text := Document{
		children: [BlockNode(ParagraphNode{
			children: [InlineNode(TextNode{ text: 'a' }), InlineNode(TextNode{ text: 'b' })]
		})]
	}
	assert document_validation_error(adjacent_text).contains('is adjacent to another text node')

	nested_link := InlineNode(LinkNode{
		url: 'outer'
		text: [InlineNode(LinkNode{ url: 'inner' })]
	})
	if _ := nested_link.validate() {
		assert false, 'nested links must fail validation'
	} else {
		assert err.msg().contains('cannot nest a link inside another link')
	}
}

fn test_validation_rejects_invalid_and_nested_wiki_links() {
	empty_target := InlineNode(WikiLinkNode{
		target: '  '
		text: [InlineNode(TextNode{ text: 'label' })]
	})
	if _ := empty_target.validate() {
		assert false, 'empty wiki-link targets must fail validation'
	} else {
		assert err is AstValidationError
		assert (err as AstValidationError).kind == .wiki_link_target
	}

	nested := InlineNode(LinkNode{
		url: 'outer'
		text: [InlineNode(WikiLinkNode{
			target: 'inner'
			text: [InlineNode(TextNode{ text: 'inner' })]
		})]
	})
	if _ := nested.validate() {
		assert false, 'wiki links nested inside links must fail validation'
	} else {
		assert (err as AstValidationError).kind == .nested_link
	}
}

fn test_validation_rejects_noncanonical_latex_math_content() {
	for content in ['line\nbreak', 'bare \$ delimiter'] {
		math := InlineNode(LatexMathNode{ content: content })
		if _ := math.validate() {
			assert false, 'noncanonical LaTeX math content must fail validation'
		} else {
			assert err is AstValidationError
			assert (err as AstValidationError).kind == .latex_math_content
		}
	}
	InlineNode(LatexMathNode{ content: r'price \$5' }).validate() or { panic(err) }
}

fn test_validation_rejects_empty_underline_container() {
	underline := InlineNode(UnderlineNode{})
	if _ := underline.validate() {
		assert false, 'empty underline containers must fail validation'
	} else {
		assert err is AstValidationError
		assert (err as AstValidationError).kind == .empty_inline_container
	}
}

fn test_validation_rejects_metadata_key_collisions_and_multiline_info() {
	metadata := Document{
		children: [BlockNode(MetaNode{
			data: {
				'a':   'one'
				' a ': 'two'
			}
		})]
	}
	assert document_validation_error(metadata).contains('normalize to the same value')

	code := Document{
		children: [BlockNode(CodeBlockNode{ lang: 'v\nunsafe' })]
	}
	assert document_validation_error(code).contains('.lang cannot contain a line break')
}

fn test_binary_decode_rejects_semantically_invalid_ast() {
	doc := Document{
		children: [BlockNode(ListNode{
			start: 2
		})]
	}
	if _ := binary_decode(doc.binary_encode()) {
		assert false, 'binary decoder must reject invalid AST semantics'
	} else {
		assert err.msg().contains('invalid binary AST')
		assert err.msg().contains('start must be 1 for an unordered list')
	}
}

fn test_ast_validation_supports_configurable_resource_limits() {
	doc := Document{
		children: [BlockNode(ParagraphNode{
			children: [InlineNode(TextNode{ text: 'text' })]
		})]
	}
	doc.validate_with_limits(AstValidationLimits{
		max_nodes: 3
		max_nesting_depth: 2
	}) or { panic(err) }
	doc.validate_with_limits(AstValidationLimits{
		max_nodes: 0
		max_nesting_depth: 0
	}) or { panic(err) }

	if _ := doc.validate_with_limits(AstValidationLimits{ max_nodes: 2 }) {
		assert false, 'document root must count toward the node budget'
	} else {
		assert err is AstValidationError
		assert err.kind == .validation_limit
		assert err.msg().contains('maximum AST node count 2')
	}
	if _ := doc.validate_with_limits(AstValidationLimits{ max_nesting_depth: 1 }) {
		assert false, 'deep AST must exceed the configured depth budget'
	} else {
		assert err is AstValidationError
		assert err.kind == .validation_limit
		assert err.msg().contains('maximum AST depth 1')
	}
}

fn test_ast_validation_rejects_negative_resource_limits() {
	doc := Document{}
	for limits in [
		AstValidationLimits{ max_nodes: -1 },
		AstValidationLimits{ max_nesting_depth: -1 },
	] {
		if _ := doc.validate_with_limits(limits) {
			assert false, 'negative validation limits must fail'
		} else {
			assert err.msg().contains('cannot be negative')
		}
	}
}

fn test_ast_validation_rejects_invalid_utf8_in_every_string_field() {
	invalid := [u8(0xff)].bytestr()
	for node in [
		BlockNode(CodeBlockNode{ lang: invalid }),
		BlockNode(CodeBlockNode{ content: invalid }),
		BlockNode(RawHtmlBlockNode{ html: invalid }),
		BlockNode(MetaNode{
			data: {
				invalid: 'value'
			}
		}),
		BlockNode(MetaNode{
			data: {
				'key': invalid
			}
		}),
	] {
		assert_invalid_utf8_error(node)
	}
	for node in [
		InlineNode(TextNode{ text: invalid }),
		InlineNode(LinkNode{ url: invalid }),
		InlineNode(WikiLinkNode{ target: invalid }),
		InlineNode(ImageNode{ url: invalid }),
		InlineNode(LatexMathNode{ content: invalid }),
		InlineNode(CodeSpanNode{ text: invalid }),
		InlineNode(RawHtmlInlineNode{ html: invalid }),
	] {
		assert_invalid_utf8_inline_error(node)
	}
}

fn test_checked_binary_encode_rejects_invalid_utf8_without_replacement() {
	invalid := [u8(0xff)].bytestr()
	doc := Document{
		children: [BlockNode(ParagraphNode{
			children: [InlineNode(TextNode{ text: invalid })]
		})]
	}
	if _ := doc.binary_encode_checked() {
		assert false, 'checked encoding must reject invalid UTF-8'
	} else {
		assert err is AstValidationError
		validation := err as AstValidationError
		assert validation.kind == .invalid_utf8
		assert validation.path == 'document.children[0].children[0].text'
	}
}

fn assert_invalid_utf8_error(node BlockNode) {
	if _ := node.validate() {
		assert false, 'invalid UTF-8 block field must fail validation'
	} else {
		assert err is AstValidationError
		assert (err as AstValidationError).kind == .invalid_utf8
	}
}

fn assert_invalid_utf8_inline_error(node InlineNode) {
	if _ := node.validate() {
		assert false, 'invalid UTF-8 inline field must fail validation'
	} else {
		assert err is AstValidationError
		assert (err as AstValidationError).kind == .invalid_utf8
	}
}

fn document_validation_error(doc Document) string {
	doc.validate() or { return err.msg() }
	return ''
}
