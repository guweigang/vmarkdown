module vmarkdown

import encoding.utf8

const max_binary_size = 64 * 1024 * 1024
const max_binary_nodes = 1_000_000
const max_binary_depth = 256

// binary_decode decodes the versioned VMDA binary format. Source spans are
// intentionally absent from the wire format because they are parse-location
// metadata, not semantic content.
pub fn binary_decode(data []u8) !Document {
	if data.len > max_binary_size {
		return error('binary document exceeds ${max_binary_size} bytes')
	}
	if data.len < 7 || data[0] != `V` || data[1] != `M` || data[2] != `D` || data[3] != `A` {
		return error('invalid binary document magic; expected VMDA')
	}
	if data[4] != binary_format_version {
		return error('unsupported binary document version ${data[4]}')
	}
	if data[5] != document_type_tag {
		return error('invalid binary document root tag ${data[5]}')
	}
	mut reader := BinaryReader{
		data: data
		pos: 6
		limit: data.len
	}
	body_end := reader.read_sized_end('document payload')!
	mut children := []BlockNode{}
	for reader.pos < body_end {
		children << reader.read_block(body_end, 1)!
	}
	reader.require_end(body_end, 'document payload')!
	reader.require_end(data.len, 'binary document')!
	doc := Document{ children: children }
	doc.validate() or { return error('invalid binary AST: ${err}') }
	return doc
}

struct BinaryReader {
	data []u8
mut:
	pos   int
	limit int
	nodes int
}

fn (mut r BinaryReader) read_u8(label string) !u8 {
	if r.pos >= r.limit {
		return error('truncated ${label} at byte ${r.pos}')
	}
	value := r.data[r.pos]
	r.pos++
	return value
}

fn (mut r BinaryReader) read_varint(label string) !int {
	mut value := u64(0)
	mut byte_count := 0
	for shift := u32(0); shift < 64; shift += 7 {
		byte := r.read_u8(label)!
		byte_count++
		if shift == 63 && byte > 1 {
			return error('${label} varint overflows u64 at byte ${r.pos - 1}')
		}
		value |= u64(byte & 0x7f) << shift
		if byte & 0x80 == 0 {
			if byte_count > 1 && byte == 0 {
				return error('${label} uses a non-canonical varint')
			}
			if value > u64(max_binary_size) && label.contains('length') {
				return error('${label} exceeds ${max_binary_size}')
			}
			if value > u64(0x7fff_ffff_ffff_ffff) {
				return error('${label} exceeds supported integer range')
			}
			return int(value)
		}
	}
	return error('${label} varint is too long')
}

fn (mut r BinaryReader) read_sized_end(label string) !int {
	length := r.read_varint('${label} length')!
	if length < 0 || length > r.limit - r.pos {
		return error('truncated ${label}: need ${length} bytes, have ${r.limit - r.pos}')
	}
	return r.pos + length
}

fn (mut r BinaryReader) read_string(label string) !string {
	end := r.read_sized_end(label)!
	value := r.data[r.pos..end].bytestr()
	if !utf8.validate_str(value) {
		return error('${label} is not valid UTF-8')
	}
	r.pos = end
	return value
}

fn (mut r BinaryReader) read_bool(label string) !bool {
	value := r.read_u8(label)!
	if value > 1 {
		return error('invalid ${label} value ${value}')
	}
	return value == 1
}

fn (mut r BinaryReader) require_end(expected int, label string) ! {
	if r.pos != expected {
		return error('${label} ended at byte ${r.pos}, expected ${expected}')
	}
}

fn (mut r BinaryReader) count_node(depth int) ! {
	if depth > max_binary_depth {
		return error('binary AST exceeds maximum depth ${max_binary_depth}')
	}
	r.nodes++
	if r.nodes > max_binary_nodes {
		return error('binary AST exceeds maximum node count ${max_binary_nodes}')
	}
}

fn (mut r BinaryReader) read_block(container_end int, depth int) !BlockNode {
	r.count_node(depth)!
	old_limit := r.limit
	if container_end > old_limit {
		return error('block container exceeds its parent boundary')
	}
	r.limit = container_end
	defer {
		r.limit = old_limit
	}
	if r.pos >= container_end {
		return error('missing block tag at byte ${r.pos}')
	}
	tag := r.read_u8('block tag')!
	match tag {
		heading_type_tag {
			level := int(r.read_u8('heading level')!)
			if level < 1 || level > 6 {
				return error('invalid heading level ${level}')
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
					return error('duplicate metadata key ${key}')
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
					return error('table row has ${row.cells.len} cells, expected ${columns}')
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
			return error('unknown block tag ${tag} at byte ${r.pos - 1}')
		}
	}
}

fn (mut r BinaryReader) read_count(label string) !int {
	value := r.read_varint(label)!
	if value > max_binary_nodes {
		return error('${label} exceeds ${max_binary_nodes}')
	}
	return value
}

fn (mut r BinaryReader) read_list_item(end int, depth int) !ListItemNode {
	r.count_node(depth)!
	old_limit := r.limit
	if end > old_limit {
		return error('list item exceeds its parent boundary')
	}
	r.limit = end
	defer {
		r.limit = old_limit
	}
	if r.read_u8('list item tag')! != list_item_type_tag {
		return error('invalid list item tag at byte ${r.pos - 1}')
	}
	level := r.read_varint('list item level')!
	number := r.read_varint('list item number')!
	is_task := r.read_bool('task flag')!
	checked := r.read_bool('task checked flag')!
	if checked && !is_task {
		return error('non-task list item cannot be checked')
	}
	body_end := r.read_sized_end('list item children')!
	if body_end != end {
		return error('list item framing mismatch')
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
		return error('table row exceeds its parent boundary')
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
			return error('invalid table alignment ${alignment_value}')
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
		return error('inline container exceeds its parent boundary')
	}
	r.limit = container_end
	defer {
		r.limit = old_limit
	}
	if r.pos >= container_end {
		return error('missing inline tag at byte ${r.pos}')
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
			return error('unknown inline tag ${tag} at byte ${r.pos - 1}')
		}
	}
}
