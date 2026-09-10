module vmarkdown

const max_ast_validation_nodes = 1_000_000
const max_ast_validation_depth = 256

struct AstValidator {
mut:
	nodes int
}

// validate checks structural invariants required by the stable binary format
// and normalized Markdown renderer.
pub fn (doc Document) validate() ! {
	mut validator := AstValidator{}
	validator.count('document', 0)!
	validate_source_span(doc.span, 'document.span')!
	for index, child in doc.children {
		validator.validate_block(child, 'document.children[${index}]', 1, 0)!
	}
}

// validate checks a standalone block and all of its descendants.
pub fn (node BlockNode) validate() ! {
	mut validator := AstValidator{}
	validator.validate_block(node, 'block', 0, 0)!
}

// validate checks a standalone inline node and all of its descendants.
pub fn (node InlineNode) validate() ! {
	mut validator := AstValidator{}
	validator.validate_inline(node, 'inline', 0, false)!
}

fn (mut validator AstValidator) count(path string, depth int) ! {
	if depth > max_ast_validation_depth {
		return error('${path} exceeds maximum AST depth ${max_ast_validation_depth}')
	}
	validator.nodes++
	if validator.nodes > max_ast_validation_nodes {
		return error('${path} exceeds maximum AST node count ${max_ast_validation_nodes}')
	}
}

fn (mut validator AstValidator) validate_block(node BlockNode, path string, depth int, list_depth int) ! {
	validator.count(path, depth)!
	validate_source_span(node.source_span(), '${path}.span')!
	match node {
		HeadingNode {
			if node.level < 1 || node.level > 6 {
				return error('${path}.level must be between 1 and 6')
			}
			validator.validate_inlines(node.children, '${path}.children', depth + 1, false)!
		}
		ParagraphNode {
			validator.validate_inlines(node.children, '${path}.children', depth + 1, false)!
		}
		BlockquoteNode {
			for index, child in node.children {
				validator.validate_block(child, '${path}.children[${index}]', depth + 1, list_depth)!
			}
		}
		ListNode {
			validator.validate_list(node, path, depth, list_depth + 1)!
		}
		MetaNode {
			mut normalized_keys := map[string]string{}
			for key, _ in node.data {
				normalized := normalize_text(key)
				if normalized.len == 0 {
					return error('${path}.data contains an empty normalized key')
				}
				if previous := normalized_keys[normalized] {
					return error('${path}.data keys `${previous}` and `${key}` normalize to the same value')
				}
				normalized_keys[normalized] = key
			}
		}
		CodeBlockNode {
			if node.lang.contains_any('\r\n') {
				return error('${path}.lang cannot contain a line break')
			}
		}
		TableNode {
			if node.columns <= 0 {
				return error('${path}.columns must be positive')
			}
			if node.head.len != 1 {
				return error('${path}.head must contain exactly one row')
			}
			for row_index, row in node.head {
				validator.validate_table_row(row, '${path}.head[${row_index}]', depth + 1, node.columns)!
			}
			for row_index, row in node.body {
				validator.validate_table_row(row, '${path}.body[${row_index}]', depth + 1, node.columns)!
			}
		}
		HorizontalRuleNode, RawHtmlBlockNode {}
	}
}

fn (mut validator AstValidator) validate_list(node ListNode, path string, depth int, expected_level int) ! {
	if node.start < 0 {
		return error('${path}.start cannot be negative')
	}
	if !node.is_ordered && node.start != 1 {
		return error('${path}.start must be 1 for an unordered list')
	}
	for index, item in node.items {
		item_path := '${path}.items[${index}]'
		validator.count(item_path, depth + 1)!
		validate_source_span(item.span, '${item_path}.span')!
		if item.level != expected_level {
			return error('${item_path}.level must be ${expected_level}')
		}
		expected_number := if node.is_ordered { node.start + index } else { 0 }
		if item.number != expected_number {
			return error('${item_path}.number must be ${expected_number}')
		}
		if item.checked && !item.is_task {
			return error('${item_path}.checked requires is_task')
		}
		for child_index, child in item.children {
			validator.validate_block(child, '${item_path}.children[${child_index}]', depth + 2, expected_level)!
		}
	}
}

fn (mut validator AstValidator) validate_table_row(row TableRowNode, path string, depth int, columns int) ! {
	validator.count(path, depth)!
	validate_source_span(row.span, '${path}.span')!
	if row.cells.len != columns {
		return error('${path}.cells has ${row.cells.len} entries, expected ${columns}')
	}
	for index, cell in row.cells {
		cell_path := '${path}.cells[${index}]'
		validator.count(cell_path, depth + 1)!
		validate_source_span(cell.span, '${cell_path}.span')!
		validator.validate_inlines(cell.children, '${cell_path}.children', depth + 2, false)!
	}
}

fn (mut validator AstValidator) validate_inlines(nodes []InlineNode, path string, depth int, inside_link bool) ! {
	mut previous_was_text := false
	for index, node in nodes {
		if node is TextNode && previous_was_text {
			return error('${path}[${index}] is adjacent to another text node')
		}
		validator.validate_inline(node, '${path}[${index}]', depth, inside_link)!
		previous_was_text = node is TextNode
	}
}

fn (mut validator AstValidator) validate_inline(node InlineNode, path string, depth int, inside_link bool) ! {
	validator.count(path, depth)!
	validate_source_span(node.source_span(), '${path}.span')!
	match node {
		TextNode {
			if node.text.len == 0 {
				return error('${path}.text cannot be empty')
			}
		}
		EmphasisNode {
			validate_nonempty_inline_container(node.children, '${path}.children')!
			validator.validate_inlines(node.children, '${path}.children', depth + 1, inside_link)!
		}
		StrongNode {
			validate_nonempty_inline_container(node.children, '${path}.children')!
			validator.validate_inlines(node.children, '${path}.children', depth + 1, inside_link)!
		}
		StrikethroughNode {
			validate_nonempty_inline_container(node.children, '${path}.children')!
			validator.validate_inlines(node.children, '${path}.children', depth + 1, inside_link)!
		}
		LinkNode {
			if inside_link {
				return error('${path} cannot nest a link inside another link')
			}
			validator.validate_inlines(node.text, '${path}.text', depth + 1, true)!
		}
		ImageNode {
			validator.validate_inlines(node.alt, '${path}.alt', depth + 1, inside_link)!
		}
		CodeSpanNode, SoftBreakNode, HardBreakNode, RawHtmlInlineNode {}
	}
}

fn validate_nonempty_inline_container(children []InlineNode, path string) ! {
	if children.len == 0 {
		return error('${path} cannot be empty')
	}
}

fn validate_source_span(span SourceSpan, path string) ! {
	if span.is_valid() || (span.start < 0 && span.end < 0) {
		return
	}
	return error('${path} must be a valid half-open range or an unavailable negative range')
}
