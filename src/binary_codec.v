module vmarkdown

import encoding.utf8

pub struct BinaryDecodeLimits {
pub:
	max_input_bytes   int = 64 * 1024 * 1024
	max_nodes         int = 1_000_000
	max_nesting_depth int = 256
}

pub enum BinaryDecodeErrorKind {
	invalid_limits
	resource_limit
	invalid_envelope
	truncated
	invalid_varint
	invalid_utf8
	unknown_tag
	invalid_value
	invalid_framing
	invalid_ast
	non_canonical
}

pub struct BinaryDecodeError {
pub:
	kind    BinaryDecodeErrorKind
	offset  int = -1
	message string
}

pub fn (err BinaryDecodeError) msg() string {
	return err.message
}

pub fn (err BinaryDecodeError) code() int {
	return 4000 + int(err.kind)
}

// binary_decode decodes the versioned VMDA binary format. Source spans are
// intentionally absent from the wire format because they are parse-location
// metadata, not semantic content.
pub fn binary_decode(data []u8) !Document {
	return binary_decode_with_limits(data, BinaryDecodeLimits{})
}

// binary_decode_with_limits decodes VMDA with caller-selected resource
// budgets. A zero limit is unbounded; negative limits are rejected.
pub fn binary_decode_with_limits(data []u8, limits BinaryDecodeLimits) !Document {
	validate_binary_decode_limits(limits)!
	if limits.max_input_bytes > 0 && data.len > limits.max_input_bytes {
		return binary_decode_error(.resource_limit, -1, 'binary document exceeds ${limits.max_input_bytes} bytes')
	}
	if data.len < 4 {
		return binary_decode_error(.truncated, data.len, 'truncated binary document header at byte ${data.len}')
	}
	magic := [u8(`V`), `M`, `D`, `A`]
	if data[..4] != magic {
		offset := first_different_byte(data[..4], magic)
		return binary_decode_error(.invalid_envelope, offset, 'invalid binary document magic; expected VMDA')
	}
	if data.len < 7 {
		return binary_decode_error(.truncated, data.len, 'truncated binary document header at byte ${data.len}')
	}
	if data[4] != binary_format_version {
		return binary_decode_error(.invalid_envelope, 4, 'unsupported binary document version ${data[4]}')
	}
	if data[5] != document_type_tag {
		return binary_decode_error(.invalid_envelope, 5, 'invalid binary document root tag ${data[5]}')
	}
	mut reader := BinaryReader{
		data: data
		pos: 6
		limit: data.len
		limits: limits
		nodes: 1
	}
	body_end := reader.read_sized_end('document payload')!
	mut children := []BlockNode{}
	for reader.pos < body_end {
		children << reader.read_block(body_end, 1)!
	}
	reader.require_end(body_end, 'document payload')!
	reader.require_end(data.len, 'binary document')!
	doc := Document{ children: children }
	doc.validate_with_limits(AstValidationLimits{
		max_nodes: limits.max_nodes
		max_nesting_depth: limits.max_nesting_depth
	}) or { return binary_decode_error(.invalid_ast, -1, 'invalid binary AST: ${err}') }
	canonical := doc.binary_encode()
	if canonical != data {
		offset := first_different_byte(data, canonical)
		return binary_decode_error(.non_canonical, offset, 'non-canonical binary document at byte ${offset}')
	}
	return doc
}

fn first_different_byte(left []u8, right []u8) int {
	common := if left.len < right.len { left.len } else { right.len }
	for index in 0 .. common {
		if left[index] != right[index] {
			return index
		}
	}
	return common
}

fn validate_binary_decode_limits(limits BinaryDecodeLimits) ! {
	if limits.max_input_bytes < 0 {
		return binary_decode_error(.invalid_limits, -1, 'max_input_bytes cannot be negative')
	}
	if limits.max_nodes < 0 {
		return binary_decode_error(.invalid_limits, -1, 'max_nodes cannot be negative')
	}
	if limits.max_nesting_depth < 0 {
		return binary_decode_error(.invalid_limits, -1, 'max_nesting_depth cannot be negative')
	}
}

fn binary_decode_error(kind BinaryDecodeErrorKind, offset int, message string) IError {
	return BinaryDecodeError{
		kind: kind
		offset: offset
		message: message
	}
}

struct BinaryReader {
	data   []u8
	limits BinaryDecodeLimits
mut:
	pos   int
	limit int
	nodes int
}

fn (mut r BinaryReader) read_u8(label string) !u8 {
	if r.pos >= r.limit {
		return binary_decode_error(.truncated, r.pos, 'truncated ${label} at byte ${r.pos}')
	}
	value := r.data[r.pos]
	r.pos++
	return value
}

fn (mut r BinaryReader) read_varint(label string) !int {
	start := r.pos
	mut value := u64(0)
	mut byte_count := 0
	for shift := u32(0); shift < 64; shift += 7 {
		byte := r.read_u8(label)!
		byte_count++
		if shift == 63 && byte > 1 {
			return binary_decode_error(.invalid_varint, r.pos - 1, '${label} varint overflows u64 at byte ${r.pos - 1}')
		}
		value |= u64(byte & 0x7f) << shift
		if byte & 0x80 == 0 {
			if byte_count > 1 && byte == 0 {
				return binary_decode_error(.invalid_varint, r.pos - 1, '${label} uses a non-canonical varint')
			}
			if r.limits.max_input_bytes > 0 && value > u64(r.limits.max_input_bytes)
				&& label.contains('length') {
				return binary_decode_error(.resource_limit, start, '${label} exceeds ${r.limits.max_input_bytes}')
			}
			if value > u64(0x7fff_ffff_ffff_ffff) {
				return binary_decode_error(.invalid_varint, start, '${label} exceeds supported integer range')
			}
			return int(value)
		}
	}
	return binary_decode_error(.invalid_varint, start, '${label} varint is too long')
}

fn (mut r BinaryReader) read_sized_end(label string) !int {
	length := r.read_varint('${label} length')!
	if length < 0 || length > r.limit - r.pos {
		return binary_decode_error(.truncated, r.pos, 'truncated ${label}: need ${length} bytes, have ${r.limit - r.pos}')
	}
	return r.pos + length
}

fn (mut r BinaryReader) read_string(label string) !string {
	end := r.read_sized_end(label)!
	start := r.pos
	value := r.data[r.pos..end].bytestr()
	if !utf8.validate_str(value) {
		return binary_decode_error(.invalid_utf8, start, '${label} is not valid UTF-8')
	}
	r.pos = end
	return value
}

fn (mut r BinaryReader) read_bool(label string) !bool {
	value := r.read_u8(label)!
	if value > 1 {
		return binary_decode_error(.invalid_value, r.pos - 1, 'invalid ${label} value ${value}')
	}
	return value == 1
}

fn (mut r BinaryReader) require_end(expected int, label string) ! {
	if r.pos != expected {
		return binary_decode_error(.invalid_framing, r.pos, '${label} ended at byte ${r.pos}, expected ${expected}')
	}
}

fn (mut r BinaryReader) count_node(depth int) ! {
	if r.limits.max_nesting_depth > 0 && depth > r.limits.max_nesting_depth {
		return binary_decode_error(.resource_limit, r.pos, 'binary AST exceeds maximum depth ${r.limits.max_nesting_depth}')
	}
	r.nodes++
	if r.limits.max_nodes > 0 && r.nodes > r.limits.max_nodes {
		return binary_decode_error(.resource_limit, r.pos, 'binary AST exceeds maximum node count ${r.limits.max_nodes}')
	}
}

fn (mut r BinaryReader) read_block(container_end int, depth int) !BlockNode {
	r.count_node(depth)!
	old_limit := r.limit
	if container_end > old_limit {
		return binary_decode_error(.invalid_framing, r.pos, 'block container exceeds its parent boundary')
	}
	r.limit = container_end
	defer {
		r.limit = old_limit
	}
	if r.pos >= container_end {
		return binary_decode_error(.truncated, r.pos, 'missing block tag at byte ${r.pos}')
	}
	tag := r.read_u8('block tag')!
	match tag {
		heading_type_tag {
			level := int(r.read_u8('heading level')!)
			if level < 1 || level > 6 {
				return binary_decode_error(.invalid_value, r.pos - 1, 'invalid heading level ${level}')
			}
			end := r.read_sized_end('heading children')!
			children := r.read_inlines(end, depth + 1)!
			return BlockNode(HeadingNode{ level: level, children: children })
		}
		paragraph_type_tag {
			end := r.read_sized_end('paragraph children')!
			return BlockNode(ParagraphNode{ children: r.read_inlines(end, depth + 1)! })
		}
		list_type_tag {
			ordered := r.read_bool('list ordered flag')!
			count := r.read_count('list item count')!
			start := r.read_varint('list start')!
			mut items := []ListItemNode{cap: count}
			for _ in 0 .. count {
				end := r.read_sized_end('list item')!
				items << r.read_list_item(end, depth + 1)!
			}
			return BlockNode(ListNode{ is_ordered: ordered, start: start, items: items })
		}
		meta_type_tag {
			count := r.read_count('metadata entry count')!
			mut data := map[string]string{}
			for _ in 0 .. count {
				key := r.read_string('metadata key')!
				if key in data {
					return binary_decode_error(.invalid_value, r.pos, 'duplicate metadata key ${key}')
				}
				data[key] = r.read_string('metadata value')!
			}
			return BlockNode(MetaNode{ data: data })
		}
		blockquote_type_tag {
			end := r.read_sized_end('blockquote children')!
			mut children := []BlockNode{}
			for r.pos < end {
				children << r.read_block(end, depth + 1)!
			}
			r.require_end(end, 'blockquote children')!
			return BlockNode(BlockquoteNode{ children: children })
		}
		code_block_type_tag {
			return BlockNode(CodeBlockNode{
				lang: r.read_string('code block language')!
				content: r.read_string('code block content')!
			})
		}
		horizontal_rule_type_tag {
			return BlockNode(HorizontalRuleNode{})
		}
		table_type_tag {
			columns := r.read_count('table column count')!
			head_count := r.read_count('table head row count')!
			body_count := r.read_count('table body row count')!
			mut rows := []TableRowNode{cap: head_count + body_count}
			for _ in 0 .. head_count + body_count {
				end := r.read_sized_end('table row')!
				row := r.read_table_row(end, depth + 1)!
				if row.cells.len != columns {
					return binary_decode_error(.invalid_value, r.pos, 'table row has ${row.cells.len} cells, expected ${columns}')
				}
				rows << row
			}
			return BlockNode(TableNode{
				columns: columns
				head: rows[..head_count].clone()
				body: rows[head_count..].clone()
			})
		}
		raw_html_block_type_tag {
			return BlockNode(RawHtmlBlockNode{ html: r.read_string('raw HTML block')! })
		}
		else {
			return binary_decode_error(.unknown_tag, r.pos - 1, 'unknown block tag ${tag} at byte ${r.pos - 1}')
		}
	}
}

fn (mut r BinaryReader) read_count(label string) !int {
	value := r.read_varint(label)!
	if r.limits.max_nodes > 0 && value > r.limits.max_nodes {
		return binary_decode_error(.resource_limit, r.pos, '${label} exceeds ${r.limits.max_nodes}')
	}
	if value > r.limit - r.pos {
		return binary_decode_error(.invalid_framing, r.pos, '${label} ${value} exceeds remaining payload capacity ${r.limit - r.pos}')
	}
	return value
}

fn (mut r BinaryReader) read_list_item(end int, depth int) !ListItemNode {
	r.count_node(depth)!
	old_limit := r.limit
	if end > old_limit {
		return binary_decode_error(.invalid_framing, r.pos, 'list item exceeds its parent boundary')
	}
	r.limit = end
	defer {
		r.limit = old_limit
	}
	if r.read_u8('list item tag')! != list_item_type_tag {
		return binary_decode_error(.unknown_tag, r.pos - 1, 'invalid list item tag at byte ${r.pos - 1}')
	}
	level := r.read_varint('list item level')!
	number := r.read_varint('list item number')!
	is_task := r.read_bool('task flag')!
	checked := r.read_bool('task checked flag')!
	if checked && !is_task {
		return binary_decode_error(.invalid_value, r.pos - 1, 'non-task list item cannot be checked')
	}
	body_end := r.read_sized_end('list item children')!
	if body_end != end {
		return binary_decode_error(.invalid_framing, r.pos, 'list item framing mismatch')
	}
	mut children := []BlockNode{}
	for r.pos < body_end {
		child_end := r.read_sized_end('list item child')!
		children << r.read_block(child_end, depth + 1)!
		r.require_end(child_end, 'list item child')!
	}
	r.require_end(end, 'list item')!
	return ListItemNode{
		level: level
		number: number
		is_task: is_task
		checked: checked
		children: children
	}
}

fn (mut r BinaryReader) read_table_row(end int, depth int) !TableRowNode {
	old_limit := r.limit
	if end > old_limit {
		return binary_decode_error(.invalid_framing, r.pos, 'table row exceeds its parent boundary')
	}
	r.limit = end
	defer {
		r.limit = old_limit
	}
	count := r.read_count('table cell count')!
	mut cells := []TableCellNode{cap: count}
	for _ in 0 .. count {
		alignment_value := r.read_u8('table cell alignment')!
		if alignment_value > u8(TableAlignment.right) {
			return binary_decode_error(.invalid_value, r.pos - 1, 'invalid table alignment ${alignment_value}')
		}
		children_end := r.read_sized_end('table cell children')!
		cells << TableCellNode{
			alignment: unsafe { TableAlignment(alignment_value) }
			children: r.read_inlines(children_end, depth + 1)!
		}
	}
	r.require_end(end, 'table row')!
	return TableRowNode{ cells: cells }
}

fn (mut r BinaryReader) read_inlines(end int, depth int) ![]InlineNode {
	mut children := []InlineNode{}
	for r.pos < end {
		children << r.read_inline(end, depth)!
	}
	r.require_end(end, 'inline sequence')!
	return children
}

fn (mut r BinaryReader) read_inline(container_end int, depth int) !InlineNode {
	r.count_node(depth)!
	old_limit := r.limit
	if container_end > old_limit {
		return binary_decode_error(.invalid_framing, r.pos, 'inline container exceeds its parent boundary')
	}
	r.limit = container_end
	defer {
		r.limit = old_limit
	}
	if r.pos >= container_end {
		return binary_decode_error(.truncated, r.pos, 'missing inline tag at byte ${r.pos}')
	}
	tag := r.read_u8('inline tag')!
	match tag {
		text_type_tag {
			return InlineNode(TextNode{ text: r.read_string('text')! })
		}
		emphasis_type_tag {
			end := r.read_sized_end('emphasis children')!
			return InlineNode(EmphasisNode{ children: r.read_inlines(end, depth + 1)! })
		}
		strong_type_tag {
			end := r.read_sized_end('strong children')!
			return InlineNode(StrongNode{ children: r.read_inlines(end, depth + 1)! })
		}
		strikethrough_type_tag {
			end := r.read_sized_end('strikethrough children')!
			return InlineNode(StrikethroughNode{ children: r.read_inlines(end, depth + 1)! })
		}
		underline_type_tag {
			end := r.read_sized_end('underline children')!
			return InlineNode(UnderlineNode{ children: r.read_inlines(end, depth + 1)! })
		}
		code_span_type_tag {
			return InlineNode(CodeSpanNode{ text: r.read_string('code span')! })
		}
		latex_math_type_tag {
			display := r.read_bool('LaTeX math display flag')!
			return InlineNode(LatexMathNode{
				content: r.read_string('LaTeX math content')!
				display: display
			})
		}
		link_type_tag {
			url := r.read_string('link URL')!
			end := r.read_sized_end('link text')!
			return InlineNode(LinkNode{ url: url, text: r.read_inlines(end, depth + 1)! })
		}
		wiki_link_type_tag {
			target := r.read_string('wiki link target')!
			end := r.read_sized_end('wiki link text')!
			return InlineNode(WikiLinkNode{
				target: target
				text: r.read_inlines(end, depth + 1)!
			})
		}
		image_type_tag {
			url := r.read_string('image URL')!
			end := r.read_sized_end('image alt text')!
			return InlineNode(ImageNode{ url: url, alt: r.read_inlines(end, depth + 1)! })
		}
		soft_break_type_tag {
			return InlineNode(SoftBreakNode{})
		}
		hard_break_type_tag {
			return InlineNode(HardBreakNode{})
		}
		raw_html_inline_type_tag {
			return InlineNode(RawHtmlInlineNode{ html: r.read_string('raw inline HTML')! })
		}
		else {
			return binary_decode_error(.unknown_tag, r.pos - 1, 'unknown inline tag ${tag} at byte ${r.pos - 1}')
		}
	}
}
