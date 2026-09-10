module vmarkdown

pub struct AstBlockRewrite {
pub:
	node  BlockNode
	path  string
	depth int
	span  SourceSpan = SourceSpan{ start: -1, end: -1 }
}

pub struct AstInlineRewrite {
pub:
	node  InlineNode
	path  string
	depth int
	span  SourceSpan = SourceSpan{ start: -1, end: -1 }
}

// rewrite_blocks rewrites block nodes in post-order. Returning no nodes removes
// the current node; returning multiple nodes expands it. Paths describe the
// original tree, and replacement nodes are not visited again in the same pass.
// The completed document is validated before it is returned.
pub fn (doc Document) rewrite_blocks(rewriter fn (AstBlockRewrite) ![]BlockNode) !Document {
	doc.validate()!
	mut children := []BlockNode{}
	for index, child in doc.children {
		children << rewrite_block(child, 'document.children[${index}]', 1, rewriter)!
	}
	rewritten := Document{
		span: doc.span
		children: children
	}
	rewritten.validate()!
	return rewritten
}

// rewrite_inlines rewrites inline nodes in post-order throughout the document.
// Returning no nodes removes the current node; returning multiple nodes expands
// it. Paths describe the original tree, and replacements are not revisited.
// The completed document is validated before it is returned.
pub fn (doc Document) rewrite_inlines(rewriter fn (AstInlineRewrite) ![]InlineNode) !Document {
	doc.validate()!
	mut children := []BlockNode{cap: doc.children.len}
	for index, child in doc.children {
		children << rewrite_block_inlines(child, 'document.children[${index}]', 1, rewriter)!
	}
	rewritten := Document{
		span: doc.span
		children: children
	}
	rewritten.validate()!
	return rewritten
}

fn rewrite_block(node BlockNode, path string, depth int, rewriter fn (AstBlockRewrite) ![]BlockNode) ![]BlockNode {
	rewritten := match node {
		BlockquoteNode {
			mut children := []BlockNode{}
			for index, child in node.children {
				children << rewrite_block(child, '${path}.children[${index}]', depth + 1, rewriter)!
			}
			BlockNode(BlockquoteNode{
				span: node.span
				children: children
			})
		}
		ListNode {
			mut items := []ListItemNode{cap: node.items.len}
			for item_index, item in node.items {
				mut children := []BlockNode{}
				for child_index, child in item.children {
					children << rewrite_block(child, '${path}.items[${item_index}].children[${child_index}]', depth + 2, rewriter)!
				}
				items << ListItemNode{
					span: item.span
					level: item.level
					number: item.number
					is_task: item.is_task
					checked: item.checked
					children: children
				}
			}
			BlockNode(ListNode{
				span: node.span
				is_ordered: node.is_ordered
				start: node.start
				items: items
			})
		}
		CodeBlockNode, HeadingNode, HorizontalRuleNode, MetaNode, ParagraphNode, RawHtmlBlockNode, TableNode {
			node
		}
	}
	return rewriter(AstBlockRewrite{
		node: rewritten
		path: path
		depth: depth
		span: rewritten.source_span()
	})
}

fn rewrite_block_inlines(node BlockNode, path string, depth int, rewriter fn (AstInlineRewrite) ![]InlineNode) !BlockNode {
	return match node {
		HeadingNode {
			BlockNode(HeadingNode{
				span: node.span
				level: node.level
				children: rewrite_inline_nodes(node.children, '${path}.children', depth + 1, rewriter)!
			})
		}
		ParagraphNode {
			BlockNode(ParagraphNode{
				span: node.span
				children: rewrite_inline_nodes(node.children, '${path}.children', depth + 1, rewriter)!
			})
		}
		BlockquoteNode {
			mut children := []BlockNode{cap: node.children.len}
			for index, child in node.children {
				children << rewrite_block_inlines(child, '${path}.children[${index}]', depth + 1, rewriter)!
			}
			BlockNode(BlockquoteNode{
				span: node.span
				children: children
			})
		}
		ListNode {
			mut items := []ListItemNode{cap: node.items.len}
			for item_index, item in node.items {
				mut children := []BlockNode{cap: item.children.len}
				for child_index, child in item.children {
					children << rewrite_block_inlines(child, '${path}.items[${item_index}].children[${child_index}]', depth + 2, rewriter)!
				}
				items << ListItemNode{
					span: item.span
					level: item.level
					number: item.number
					is_task: item.is_task
					checked: item.checked
					children: children
				}
			}
			BlockNode(ListNode{
				span: node.span
				is_ordered: node.is_ordered
				start: node.start
				items: items
			})
		}
		TableNode {
			BlockNode(TableNode{
				span: node.span
				columns: node.columns
				head: rewrite_table_rows_inlines(node.head, '${path}.head', depth + 1, rewriter)!
				body: rewrite_table_rows_inlines(node.body, '${path}.body', depth + 1, rewriter)!
			})
		}
		CodeBlockNode, HorizontalRuleNode, MetaNode, RawHtmlBlockNode {
			node
		}
	}
}

fn rewrite_table_rows_inlines(rows []TableRowNode, path string, depth int, rewriter fn (AstInlineRewrite) ![]InlineNode) ![]TableRowNode {
	mut rewritten := []TableRowNode{cap: rows.len}
	for row_index, row in rows {
		mut cells := []TableCellNode{cap: row.cells.len}
		for cell_index, cell in row.cells {
			cell_path := '${path}[${row_index}].cells[${cell_index}]'
			cells << TableCellNode{
				span: cell.span
				alignment: cell.alignment
				children: rewrite_inline_nodes(cell.children, '${cell_path}.children', depth + 2, rewriter)!
			}
		}
		rewritten << TableRowNode{
			span: row.span
			cells: cells
		}
	}
	return rewritten
}

fn rewrite_inline_nodes(nodes []InlineNode, path string, depth int, rewriter fn (AstInlineRewrite) ![]InlineNode) ![]InlineNode {
	mut rewritten := []InlineNode{}
	for index, node in nodes {
		rewritten << rewrite_inline(node, '${path}[${index}]', depth, rewriter)!
	}
	return merge_adjacent_rewritten_text(rewritten)
}

fn merge_adjacent_rewritten_text(nodes []InlineNode) []InlineNode {
	mut merged := []InlineNode{cap: nodes.len}
	for node in nodes {
		if node is TextNode && merged.len > 0 && merged.last() is TextNode {
			previous := merged.last() as TextNode
			merged[merged.len - 1] = InlineNode(TextNode{
				span: merge_rewrite_spans(previous.span, node.span)
				text: previous.text + node.text
			})
			continue
		}
		merged << node
	}
	return merged
}

fn merge_rewrite_spans(left SourceSpan, right SourceSpan) SourceSpan {
	if !left.is_valid() || !right.is_valid() || left.end != right.start {
		return SourceSpan{}
	}
	return SourceSpan{
		start: left.start
		end: right.end
	}
}

fn rewrite_inline(node InlineNode, path string, depth int, rewriter fn (AstInlineRewrite) ![]InlineNode) ![]InlineNode {
	rewritten := match node {
		EmphasisNode {
			InlineNode(EmphasisNode{
				span: node.span
				children: rewrite_inline_nodes(node.children, '${path}.children', depth + 1, rewriter)!
			})
		}
		StrongNode {
			InlineNode(StrongNode{
				span: node.span
				children: rewrite_inline_nodes(node.children, '${path}.children', depth + 1, rewriter)!
			})
		}
		StrikethroughNode {
			InlineNode(StrikethroughNode{
				span: node.span
				children: rewrite_inline_nodes(node.children, '${path}.children', depth + 1, rewriter)!
			})
		}
		UnderlineNode {
			InlineNode(UnderlineNode{
				span: node.span
				children: rewrite_inline_nodes(node.children, '${path}.children', depth + 1, rewriter)!
			})
		}
		LinkNode {
			InlineNode(LinkNode{
				span: node.span
				text: rewrite_inline_nodes(node.text, '${path}.text', depth + 1, rewriter)!
				url: node.url
			})
		}
		WikiLinkNode {
			InlineNode(WikiLinkNode{
				span: node.span
				text: rewrite_inline_nodes(node.text, '${path}.text', depth + 1, rewriter)!
				target: node.target
			})
		}
		ImageNode {
			InlineNode(ImageNode{
				span: node.span
				alt: rewrite_inline_nodes(node.alt, '${path}.alt', depth + 1, rewriter)!
				url: node.url
			})
		}
		CodeSpanNode, HardBreakNode, LatexMathNode, RawHtmlInlineNode, SoftBreakNode, TextNode {
			node
		}
	}
	return rewriter(AstInlineRewrite{
		node: rewritten
		path: path
		depth: depth
		span: rewritten.source_span()
	})
}
