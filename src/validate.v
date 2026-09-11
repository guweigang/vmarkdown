module vmarkdown

pub struct AstValidationLimits {
pub:
	max_nodes         int = 1_000_000
	max_nesting_depth int = 256
}

pub enum AstValidationErrorKind {
	validation_limit
	source_span
	heading_level
	list_start
	list_level
	list_number
	task_state
	table_columns
	table_header
	table_row
	metadata_key
	code_info
	adjacent_text
	empty_text
	empty_inline_container
	nested_link
	wiki_link_target
	latex_math_content
}

pub struct AstValidationError {
pub:
	kind    AstValidationErrorKind
	path    string
	span    SourceSpan = SourceSpan{ start: -1, end: -1 }
	message string
}

pub fn (err AstValidationError) msg() string {
	return if err.path.len > 0 { '${err.path} ${err.message}' } else { err.message }
}

pub fn (err AstValidationError) code() int {
	return 1000 + int(err.kind)
}

struct AstValidator {
	limits AstValidationLimits
mut:
	nodes int
}

// validate checks structural invariants required by the stable binary format
// and normalized Markdown renderer.
pub fn (doc Document) validate() ! {
	return doc.validate_with_limits(AstValidationLimits{})
}

// validate_with_limits checks a document with caller-selected traversal
// budgets. A zero limit is unbounded; negative limits are rejected.
pub fn (doc Document) validate_with_limits(limits AstValidationLimits) ! {
	validate_ast_validation_limits(limits)!
	mut validator := AstValidator{ limits: limits }
	validator.count('document', 0)!
	validate_source_span(doc.span, 'document.span')!
	for index, child in doc.children {
		validator.validate_block(child, 'document.children[${index}]', 1, 0)!
	}
}

// validate checks a standalone block and all of its descendants.
pub fn (node BlockNode) validate() ! {
	return node.validate_with_limits(AstValidationLimits{})
}

// validate_with_limits checks a standalone block with caller-selected
// traversal budgets.
pub fn (node BlockNode) validate_with_limits(limits AstValidationLimits) ! {
	validate_ast_validation_limits(limits)!
	mut validator := AstValidator{ limits: limits }
	validator.validate_block(node, 'block', 0, 0)!
}

// validate checks a standalone inline node and all of its descendants.
pub fn (node InlineNode) validate() ! {
	return node.validate_with_limits(AstValidationLimits{})
}

// validate_with_limits checks a standalone inline node with caller-selected
// traversal budgets.
pub fn (node InlineNode) validate_with_limits(limits AstValidationLimits) ! {
	validate_ast_validation_limits(limits)!
	mut validator := AstValidator{ limits: limits }
	validator.validate_inline(node, 'inline', 0, false)!
}

fn validate_ast_validation_limits(limits AstValidationLimits) ! {
	if limits.max_nodes < 0 {
		return error('max_nodes cannot be negative')
	}
	if limits.max_nesting_depth < 0 {
		return error('max_nesting_depth cannot be negative')
	}
}

fn (mut validator AstValidator) count(path string, depth int) ! {
	if validator.limits.max_nesting_depth > 0 && depth > validator.limits.max_nesting_depth {
		return validation_error(.validation_limit, path, 'exceeds maximum AST depth ${validator.limits.max_nesting_depth}', SourceSpan{})
	}
	validator.nodes++
	if validator.limits.max_nodes > 0 && validator.nodes > validator.limits.max_nodes {
		return validation_error(.validation_limit, path, 'exceeds maximum AST node count ${validator.limits.max_nodes}', SourceSpan{})
	}
}

fn (mut validator AstValidator) validate_block(node BlockNode, path string, depth int, list_depth int) ! {
	validator.count(path, depth)!
	validate_source_span(node.source_span(), '${path}.span')!
	match node {
		HeadingNode {
			if node.level < 1 || node.level > 6 {
				return validation_error(.heading_level, '${path}.level', 'must be between 1 and 6', node.span)
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
					return validation_error(.metadata_key, '${path}.data', 'contains an empty normalized key', node.span)
				}
				if previous := normalized_keys[normalized] {
					return validation_error(.metadata_key, '${path}.data', 'keys `${previous}` and `${key}` normalize to the same value', node.span)
				}
				normalized_keys[normalized] = key
			}
		}
		CodeBlockNode {
			if node.lang.contains_any('\r\n') {
				return validation_error(.code_info, '${path}.lang', 'cannot contain a line break', node.span)
			}
		}
		TableNode {
			if node.columns <= 0 {
				return validation_error(.table_columns, '${path}.columns', 'must be positive', node.span)
			}
			if node.head.len != 1 {
				return validation_error(.table_header, '${path}.head', 'must contain exactly one row', node.span)
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
		return validation_error(.list_start, '${path}.start', 'cannot be negative', node.span)
	}
	if !node.is_ordered && node.start != 1 {
		return validation_error(.list_start, '${path}.start', 'must be 1 for an unordered list', node.span)
	}
	for index, item in node.items {
		item_path := '${path}.items[${index}]'
		validator.count(item_path, depth + 1)!
		validate_source_span(item.span, '${item_path}.span')!
		if item.level != expected_level {
			return validation_error(.list_level, '${item_path}.level', 'must be ${expected_level}', item.span)
		}
		expected_number := if node.is_ordered { node.start + index } else { 0 }
		if item.number != expected_number {
			return validation_error(.list_number, '${item_path}.number', 'must be ${expected_number}', item.span)
		}
		if item.checked && !item.is_task {
			return validation_error(.task_state, '${item_path}.checked', 'requires is_task', item.span)
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
		return validation_error(.table_row, '${path}.cells', 'has ${row.cells.len} entries, expected ${columns}', row.span)
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
			return validation_error(.adjacent_text, '${path}[${index}]', 'is adjacent to another text node', node.span)
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
				return validation_error(.empty_text, '${path}.text', 'cannot be empty', node.span)
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
		UnderlineNode {
			validate_nonempty_inline_container(node.children, '${path}.children')!
			validator.validate_inlines(node.children, '${path}.children', depth + 1, inside_link)!
		}
		LinkNode {
			if inside_link {
				return validation_error(.nested_link, path, 'cannot nest a link inside another link', node.span)
			}
			validator.validate_inlines(node.text, '${path}.text', depth + 1, true)!
		}
		WikiLinkNode {
			if inside_link {
				return validation_error(.nested_link, path, 'cannot nest a wiki link inside another link', node.span)
			}
			if normalize_text(node.target).len == 0 || node.target.contains_any('\r\n') {
				return validation_error(.wiki_link_target, '${path}.target', 'must be non-empty and cannot contain a line break', node.span)
			}
			validator.validate_inlines(node.text, '${path}.text', depth + 1, true)!
		}
		ImageNode {
			validator.validate_inlines(node.alt, '${path}.alt', depth + 1, inside_link)!
		}
		LatexMathNode {
			if node.content.contains_any('\r\n') || contains_unescaped_dollar(node.content) {
				return validation_error(.latex_math_content, '${path}.content', 'cannot contain a line break or unescaped dollar sign', node.span)
			}
		}
		CodeSpanNode, SoftBreakNode, HardBreakNode, RawHtmlInlineNode {}
	}
}

fn contains_unescaped_dollar(content string) bool {
	mut backslashes := 0
	for ch in content {
		if ch == `\\` {
			backslashes++
			continue
		}
		if ch == `$` && backslashes % 2 == 0 {
			return true
		}
		backslashes = 0
	}
	return false
}

fn validate_nonempty_inline_container(children []InlineNode, path string) ! {
	if children.len == 0 {
		return validation_error(.empty_inline_container, path, 'cannot be empty', SourceSpan{})
	}
}

fn validate_source_span(span SourceSpan, path string) ! {
	if span.is_valid() || (span.start < 0 && span.end < 0) {
		return
	}
	return validation_error(.source_span, path, 'must be a valid half-open range or an unavailable negative range', span)
}

fn validation_error(kind AstValidationErrorKind, path string, message string, span SourceSpan) IError {
	return AstValidationError{
		kind: kind
		path: path
		span: span
		message: message
	}
}
