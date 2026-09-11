module vmarkdown

// Canonical VMDA binary encoding.

const document_type_tag = u8(0x00)
const heading_type_tag = u8(0x01)
const paragraph_type_tag = u8(0x02)
const list_type_tag = u8(0x03)
const meta_type_tag = u8(0x04)
const blockquote_type_tag = u8(0x05)
const code_block_type_tag = u8(0x06)
const horizontal_rule_type_tag = u8(0x07)
const table_type_tag = u8(0x08)
const raw_html_block_type_tag = u8(0x09)
const list_item_type_tag = u8(0x10)
const text_type_tag = u8(0x20)
const emphasis_type_tag = u8(0x21)
const strong_type_tag = u8(0x22)
const code_span_type_tag = u8(0x23)
const link_type_tag = u8(0x24)
const image_type_tag = u8(0x25)
const strikethrough_type_tag = u8(0x26)
const soft_break_type_tag = u8(0x27)
const hard_break_type_tag = u8(0x28)
const raw_html_inline_type_tag = u8(0x29)
const wiki_link_type_tag = u8(0x2a)
const latex_math_type_tag = u8(0x2b)
const underline_type_tag = u8(0x2c)
const binary_format_version = u8(1)

pub fn (doc Document) binary_encode() []u8 {
	mut body := []u8{}
	for child in doc.children {
		body << child.binary_encode()
	}
	mut out := [u8(`V`), `M`, `D`, `A`, binary_format_version, document_type_tag]
	out << encode_varint(body.len)
	out << body
	return out
}

pub fn (node BlockNode) binary_encode() []u8 {
	match node {
		HeadingNode {
			content := encode_inline_sequence(node.children)
			mut out := [heading_type_tag, u8(node.level & 0xff)]
			out << encode_varint(content.len)
			out << content
			return out
		}
		ParagraphNode {
			content := encode_inline_sequence(node.children)
			mut out := [paragraph_type_tag]
			out << encode_varint(content.len)
			out << content
			return out
		}
		ListNode {
			mut out := [list_type_tag, bool_u8(node.is_ordered)]
			out << encode_varint(node.items.len)
			out << encode_varint(node.start)
			for item in node.items {
				item_bytes := item.binary_encode()
				out << encode_varint(item_bytes.len)
				out << item_bytes
			}
			return out
		}
		RawHtmlBlockNode {
			data := node.html.bytes()
			mut out := [raw_html_block_type_tag]
			out << encode_varint(data.len)
			out << data
			return out
		}
		MetaNode {
			mut keys := node.data.keys()
			keys.sort()
			mut out := [meta_type_tag]
			out << encode_varint(keys.len)
			for key in keys {
				key_bytes := normalize_text(key).bytes()
				value_bytes := normalize_text(node.data[key]).bytes()
				out << encode_varint(key_bytes.len)
				out << key_bytes
				out << encode_varint(value_bytes.len)
				out << value_bytes
			}
			return out
		}
		BlockquoteNode {
			mut body := []u8{}
			for child in node.children {
				body << child.binary_encode()
			}
			mut out := [blockquote_type_tag]
			out << encode_varint(body.len)
			out << body
			return out
		}
		CodeBlockNode {
			lang_bytes := normalize_text(node.lang).bytes()
			content_bytes := normalize_code(node.content).bytes()
			mut out := [code_block_type_tag]
			out << encode_varint(lang_bytes.len)
			out << lang_bytes
			out << encode_varint(content_bytes.len)
			out << content_bytes
			return out
		}
		HorizontalRuleNode {
			return [horizontal_rule_type_tag]
		}
		TableNode {
			mut out := [table_type_tag]
			out << encode_varint(node.columns)
			out << encode_varint(node.head.len)
			out << encode_varint(node.body.len)
			mut rows := node.head.clone()
			rows << node.body
			for row in rows {
				row_bytes := row.binary_encode()
				out << encode_varint(row_bytes.len)
				out << row_bytes
			}
			return out
		}
	}
}

fn (row TableRowNode) binary_encode() []u8 {
	mut out := encode_varint(row.cells.len)
	for cell in row.cells {
		content := encode_inline_sequence(cell.children)
		out << u8(cell.alignment)
		out << encode_varint(content.len)
		out << content
	}
	return out
}

pub fn (item ListItemNode) binary_encode() []u8 {
	mut body := []u8{}
	for child in item.children {
		child_bytes := child.binary_encode()
		body << encode_varint(child_bytes.len)
		body << child_bytes
	}
	mut out := [list_item_type_tag]
	out << encode_varint(item.level)
	out << encode_varint(item.number)
	out << bool_u8(item.is_task)
	out << bool_u8(item.checked)
	out << encode_varint(body.len)
	out << body
	return out
}

pub fn (node InlineNode) binary_encode() []u8 {
	match node {
		TextNode {
			data := normalize_text(node.text).bytes()
			mut out := [text_type_tag]
			out << encode_varint(data.len)
			out << data
			return out
		}
		EmphasisNode {
			content := encode_inline_sequence(node.children)
			mut out := [emphasis_type_tag]
			out << encode_varint(content.len)
			out << content
			return out
		}
		StrongNode {
			content := encode_inline_sequence(node.children)
			mut out := [strong_type_tag]
			out << encode_varint(content.len)
			out << content
			return out
		}
		StrikethroughNode {
			content := encode_inline_sequence(node.children)
			mut out := [strikethrough_type_tag]
			out << encode_varint(content.len)
			out << content
			return out
		}
		UnderlineNode {
			content := encode_inline_sequence(node.children)
			mut out := [underline_type_tag]
			out << encode_varint(content.len)
			out << content
			return out
		}
		CodeSpanNode {
			data := normalize_code(node.text).bytes()
			mut out := [code_span_type_tag]
			out << encode_varint(data.len)
			out << data
			return out
		}
		LatexMathNode {
			data := normalize_code(node.content).bytes()
			mut out := [latex_math_type_tag, bool_u8(node.display)]
			out << encode_varint(data.len)
			out << data
			return out
		}
		LinkNode {
			url_bytes := normalize_text(node.url).bytes()
			text_bytes := encode_inline_sequence(node.text)
			mut out := [link_type_tag]
			out << encode_varint(url_bytes.len)
			out << url_bytes
			out << encode_varint(text_bytes.len)
			out << text_bytes
			return out
		}
		WikiLinkNode {
			target_bytes := normalize_text(node.target).bytes()
			text_bytes := encode_inline_sequence(node.text)
			mut out := [wiki_link_type_tag]
			out << encode_varint(target_bytes.len)
			out << target_bytes
			out << encode_varint(text_bytes.len)
			out << text_bytes
			return out
		}
		ImageNode {
			url_bytes := normalize_text(node.url).bytes()
			alt_bytes := encode_inline_sequence(node.alt)
			mut out := [image_type_tag]
			out << encode_varint(url_bytes.len)
			out << url_bytes
			out << encode_varint(alt_bytes.len)
			out << alt_bytes
			return out
		}
		SoftBreakNode {
			return [soft_break_type_tag]
		}
		HardBreakNode {
			return [hard_break_type_tag]
		}
		RawHtmlInlineNode {
			data := node.html.bytes()
			mut out := [raw_html_inline_type_tag]
			out << encode_varint(data.len)
			out << data
			return out
		}
	}
}

fn encode_inline_sequence(nodes []InlineNode) []u8 {
	mut out := []u8{}
	for index, node in nodes {
		child := if node is TextNode {
			encode_text_node(node, index == 0, index == nodes.len - 1)
		} else {
			node.binary_encode()
		}
		if child.len == 0 {
			continue
		}
		out << child
	}
	return out
}

fn encode_text_node(node TextNode, trim_left bool, trim_right bool) []u8 {
	data := normalize_inline_text(node.text, trim_left, trim_right).bytes()
	if data.len == 0 {
		return []u8{}
	}
	mut out := [text_type_tag]
	out << encode_varint(data.len)
	out << data
	return out
}

fn encode_varint(value int) []u8 {
	if value < 0 {
		panic('binary codec cannot encode a negative integer: ${value}')
	}
	mut n := u64(value)
	mut out := []u8{}
	for {
		mut b := u8(n & 0x7f)
		n >>= 7
		if n != 0 {
			b |= 0x80
		}
		out << b
		if n == 0 {
			break
		}
	}
	return out
}

fn bool_u8(value bool) u8 {
	return if value { u8(1) } else { u8(0) }
}
