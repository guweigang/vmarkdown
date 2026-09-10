module vmarkdown

fn test_rewrite_inlines_is_post_order_and_can_replace_remove_and_expand() {
	doc := parse('**old** [drop](https://example.com) tail') or { panic(err) }
	mut paths := []string{}
	mut paths_ref := &paths
	rewritten := doc.rewrite_inlines(fn [mut paths_ref] (visit AstInlineRewrite) ![]InlineNode {
		paths_ref << visit.path
		if visit.node is TextNode && visit.node.text == 'old' {
			return [InlineNode(TextNode{ text: 'new' }), InlineNode(CodeSpanNode{ text: '!' })]
		}
		if visit.node is LinkNode {
			return []InlineNode{}
		}
		return [visit.node]
	}) or { panic(err) }

	assert paths[0] == 'document.children[0].children[0].children[0]'
	assert paths[1] == 'document.children[0].children[0]'
	assert rewritten.to_markdown() == '**new`!`**  tail'
	assert rewritten.find_all(.link).len == 0
}

fn test_rewrite_blocks_visits_nested_nodes_before_parents_and_can_expand() {
	doc := parse('> first\n>\n> second\n\n- item') or { panic(err) }
	mut paths := []string{}
	mut paths_ref := &paths
	rewritten := doc.rewrite_blocks(fn [mut paths_ref] (visit AstBlockRewrite) ![]BlockNode {
		paths_ref << visit.path
		if visit.node is ParagraphNode && visit.path.ends_with('children[0]') {
			return [visit.node, BlockNode(HorizontalRuleNode{})]
		}
		return [visit.node]
	}) or { panic(err) }

	assert paths.last() == 'document.children[1]'
	assert rewritten.find_all(.horizontal_rule).len == 2
	assert rewritten.to_markdown().contains('> * * *')
}

fn test_rewrite_inlines_reaches_tables_and_list_items() {
	doc := parse('| Head |\n| --- |\n| body |\n\n- item') or { panic(err) }
	mut paths := []string{}
	mut paths_ref := &paths
	rewritten := doc.rewrite_inlines(fn [mut paths_ref] (visit AstInlineRewrite) ![]InlineNode {
		paths_ref << visit.path
		if visit.node is TextNode {
			return [InlineNode(TextNode{
				span: visit.node.span
				text: visit.node.text.to_upper()
			})]
		}
		return [visit.node]
	}) or { panic(err) }

	assert paths.contains('document.children[0].head[0].cells[0].children[0]')
	assert paths.contains('document.children[0].body[0].cells[0].children[0]')
	assert paths.contains('document.children[1].items[0].children[0].children[0]')
	assert rewritten.to_text().contains('HEAD\nBODY')
	assert rewritten.to_text().contains('- ITEM')
}

fn test_rewrite_rejects_invalid_completed_document() {
	doc := parse('*text*') or { panic(err) }
	if _ := doc.rewrite_inlines(fn (visit AstInlineRewrite) ![]InlineNode {
		if visit.node is TextNode {
			return []InlineNode{}
		}
		return [visit.node]
	}) {
		assert false
	} else {
		assert err is AstValidationError
		validation := err as AstValidationError
		assert validation.kind == .empty_inline_container
	}
}

fn test_rewrite_propagates_callback_errors() {
	doc := parse('stop') or { panic(err) }
	if _ := doc.rewrite_blocks(fn (visit AstBlockRewrite) ![]BlockNode {
		return error('cannot rewrite ${visit.path}')
	}) {
		assert false
	} else {
		assert err.msg() == 'cannot rewrite document.children[0]'
	}
}

fn test_rewrite_validates_input_before_invoking_callback() {
	doc := Document{
		children: [BlockNode(HeadingNode{ level: 0 })]
	}
	mut invocations := []string{}
	mut invocations_ref := &invocations
	if _ := doc.rewrite_blocks(fn [mut invocations_ref] (visit AstBlockRewrite) ![]BlockNode {
		invocations_ref << visit.path
		return [visit.node]
	}) {
		assert false
	} else {
		assert err is AstValidationError
		assert invocations.len == 0
	}
}
