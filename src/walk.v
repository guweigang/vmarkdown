module vmarkdown

pub enum AstNodeKind {
	document
	blockquote
	code_block
	heading
	horizontal_rule
	list
	list_item
	meta
	paragraph
	raw_html_block
	table
	table_row
	table_cell
	code_span
	latex_math
	emphasis
	hard_break
	image
	link
	wiki_link
	raw_html_inline
	soft_break
	strikethrough
	strong
	text
	underline
}

pub type AstWalkNode = BlockquoteNode
	| CodeBlockNode
	| CodeSpanNode
	| Document
	| EmphasisNode
	| HardBreakNode
	| HeadingNode
	| HorizontalRuleNode
	| ImageNode
	| LatexMathNode
	| LinkNode
	| WikiLinkNode
	| ListItemNode
	| ListNode
	| MetaNode
	| ParagraphNode
	| RawHtmlBlockNode
	| RawHtmlInlineNode
	| SoftBreakNode
	| StrikethroughNode
	| StrongNode
	| TableCellNode
	| TableNode
	| TableRowNode
	| TextNode
	| UnderlineNode

pub struct AstVisit {
pub:
	kind  AstNodeKind
	node  AstWalkNode
	path  string
	depth int
	span  SourceSpan = SourceSpan{ start: -1, end: -1 }
}

// walk visits the document and every structural and semantic descendant in
// pre-order. Visits contain read-only value snapshots; return false from the
// visitor to stop traversal immediately.
pub fn (doc Document) walk(visitor fn (AstVisit) bool) bool {
	if !visitor(AstVisit{
		kind: .document
		node: AstWalkNode(doc)
		path: 'document'
		depth: 0
		span: doc.span
	}) {
		return false
	}
	for index, child in doc.children {
		if !walk_block(child, 'document.children[${index}]', 1, visitor) {
			return false
		}
	}
	return true
}

// walk_checked validates an application-assembled AST before traversal.
pub fn (doc Document) walk_checked(visitor fn (AstVisit) bool) !bool {
	return doc.walk_checked_with_limits(AstValidationLimits{}, visitor)
}

pub fn (doc Document) walk_checked_with_limits(limits AstValidationLimits, visitor fn (AstVisit) bool) !bool {
	doc.validate_with_limits(limits)!
	return doc.walk(visitor)
}

// find_all returns pre-order value snapshots whose kind matches the requested
// kind.
pub fn (doc Document) find_all(kind AstNodeKind) []AstVisit {
	mut matches := []AstVisit{}
	mut matches_ref := &matches
	doc.walk(fn [kind, mut matches_ref] (visit AstVisit) bool {
		if visit.kind == kind {
			matches_ref << visit
		}
		return true
	})
	return matches
}

// find_all_checked validates an application-assembled AST before querying it.
pub fn (doc Document) find_all_checked(kind AstNodeKind) ![]AstVisit {
	return doc.find_all_checked_with_limits(kind, AstValidationLimits{})
}

pub fn (doc Document) find_all_checked_with_limits(kind AstNodeKind, limits AstValidationLimits) ![]AstVisit {
	doc.validate_with_limits(limits)!
	return doc.find_all(kind)
}

fn walk_block(node BlockNode, path string, depth int, visitor fn (AstVisit) bool) bool {
	if !visitor(AstVisit{
		kind: block_kind(node)
		node: block_walk_node(node)
		path: path
		depth: depth
		span: node.source_span()
	}) {
		return false
	}
	match node {
		HeadingNode {
			return walk_inlines(node.children, '${path}.children', depth + 1, visitor)
		}
		ParagraphNode {
			return walk_inlines(node.children, '${path}.children', depth + 1, visitor)
		}
		BlockquoteNode {
			for index, child in node.children {
				if !walk_block(child, '${path}.children[${index}]', depth + 1, visitor) {
					return false
				}
			}
		}
		ListNode {
			for item_index, item in node.items {
				item_path := '${path}.items[${item_index}]'
				if !visitor(AstVisit{
					kind: .list_item
					node: AstWalkNode(item)
					path: item_path
					depth: depth + 1
					span: item.span
				}) {
					return false
				}
				for child_index, child in item.children {
					if !walk_block(child, '${item_path}.children[${child_index}]', depth + 2, visitor) {
						return false
					}
				}
			}
		}
		TableNode {
			for row_index, row in node.head {
				if !walk_table_row(row, '${path}.head[${row_index}]', depth + 1, visitor) {
					return false
				}
			}
			for row_index, row in node.body {
				if !walk_table_row(row, '${path}.body[${row_index}]', depth + 1, visitor) {
					return false
				}
			}
		}
		CodeBlockNode, HorizontalRuleNode, MetaNode, RawHtmlBlockNode {}
	}
	return true
}

fn walk_table_row(row TableRowNode, path string, depth int, visitor fn (AstVisit) bool) bool {
	if !visitor(AstVisit{
		kind: .table_row
		node: AstWalkNode(row)
		path: path
		depth: depth
		span: row.span
	}) {
		return false
	}
	for index, cell in row.cells {
		cell_path := '${path}.cells[${index}]'
		if !visitor(AstVisit{
			kind: .table_cell
			node: AstWalkNode(cell)
			path: cell_path
			depth: depth + 1
			span: cell.span
		}) {
			return false
		}
		if !walk_inlines(cell.children, '${cell_path}.children', depth + 2, visitor) {
			return false
		}
	}
	return true
}

fn walk_inlines(nodes []InlineNode, path string, depth int, visitor fn (AstVisit) bool) bool {
	for index, node in nodes {
		if !walk_inline(node, '${path}[${index}]', depth, visitor) {
			return false
		}
	}
	return true
}

fn walk_inline(node InlineNode, path string, depth int, visitor fn (AstVisit) bool) bool {
	if !visitor(AstVisit{
		kind: inline_kind(node)
		node: inline_walk_node(node)
		path: path
		depth: depth
		span: node.source_span()
	}) {
		return false
	}
	match node {
		EmphasisNode {
			return walk_inlines(node.children, '${path}.children', depth + 1, visitor)
		}
		StrongNode {
			return walk_inlines(node.children, '${path}.children', depth + 1, visitor)
		}
		StrikethroughNode {
			return walk_inlines(node.children, '${path}.children', depth + 1, visitor)
		}
		UnderlineNode {
			return walk_inlines(node.children, '${path}.children', depth + 1, visitor)
		}
		LinkNode {
			return walk_inlines(node.text, '${path}.text', depth + 1, visitor)
		}
		WikiLinkNode {
			return walk_inlines(node.text, '${path}.text', depth + 1, visitor)
		}
		ImageNode {
			return walk_inlines(node.alt, '${path}.alt', depth + 1, visitor)
		}
		CodeSpanNode, HardBreakNode, LatexMathNode, RawHtmlInlineNode, SoftBreakNode, TextNode {}
	}
	return true
}

fn block_kind(node BlockNode) AstNodeKind {
	return match node {
		BlockquoteNode { .blockquote }
		CodeBlockNode { .code_block }
		HeadingNode { .heading }
		HorizontalRuleNode { .horizontal_rule }
		ListNode { .list }
		MetaNode { .meta }
		ParagraphNode { .paragraph }
		RawHtmlBlockNode { .raw_html_block }
		TableNode { .table }
	}
}

fn inline_kind(node InlineNode) AstNodeKind {
	return match node {
		CodeSpanNode { .code_span }
		EmphasisNode { .emphasis }
		HardBreakNode { .hard_break }
		ImageNode { .image }
		LatexMathNode { .latex_math }
		LinkNode { .link }
		WikiLinkNode { .wiki_link }
		RawHtmlInlineNode { .raw_html_inline }
		SoftBreakNode { .soft_break }
		StrikethroughNode { .strikethrough }
		StrongNode { .strong }
		TextNode { .text }
		UnderlineNode { .underline }
	}
}

fn block_walk_node(node BlockNode) AstWalkNode {
	return match node {
		BlockquoteNode { AstWalkNode(node) }
		CodeBlockNode { AstWalkNode(node) }
		HeadingNode { AstWalkNode(node) }
		HorizontalRuleNode { AstWalkNode(node) }
		ListNode { AstWalkNode(node) }
		MetaNode { AstWalkNode(node) }
		ParagraphNode { AstWalkNode(node) }
		RawHtmlBlockNode { AstWalkNode(node) }
		TableNode { AstWalkNode(node) }
	}
}

fn inline_walk_node(node InlineNode) AstWalkNode {
	return match node {
		CodeSpanNode { AstWalkNode(node) }
		EmphasisNode { AstWalkNode(node) }
		HardBreakNode { AstWalkNode(node) }
		ImageNode { AstWalkNode(node) }
		LatexMathNode { AstWalkNode(node) }
		LinkNode { AstWalkNode(node) }
		WikiLinkNode { AstWalkNode(node) }
		RawHtmlInlineNode { AstWalkNode(node) }
		SoftBreakNode { AstWalkNode(node) }
		StrikethroughNode { AstWalkNode(node) }
		StrongNode { AstWalkNode(node) }
		TextNode { AstWalkNode(node) }
		UnderlineNode { AstWalkNode(node) }
	}
}
