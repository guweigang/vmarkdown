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

fn document_validation_error(doc Document) string {
	doc.validate() or { return err.msg() }
	return ''
}
