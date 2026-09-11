module vmarkdown

import crypto.sha256
import strings

// Stable identity and semantic encoding for vmarkdown AST nodes.

pub fn (doc Document) stable_id() string {
	return 'doc:' + hash_bytes(doc.binary_encode())
}

pub fn (doc Document) stable_id_checked() !string {
	return doc.stable_id_checked_with_limits(AstValidationLimits{})
}

pub fn (doc Document) stable_id_checked_with_limits(limits AstValidationLimits) !string {
	doc.validate_with_limits(limits)!
	return doc.stable_id()
}

pub fn (doc Document) root_refs() []string {
	mut refs := []string{cap: doc.children.len}
	for child in doc.children {
		refs << child.stable_id()
	}
	return refs
}

pub fn (doc Document) root_refs_checked() ![]string {
	return doc.root_refs_checked_with_limits(AstValidationLimits{})
}

pub fn (doc Document) root_refs_checked_with_limits(limits AstValidationLimits) ![]string {
	doc.validate_with_limits(limits)!
	return doc.root_refs()
}

pub fn (doc Document) encode() []u8 {
	return doc.binary_encode()
}

pub fn (doc Document) encode_checked() ![]u8 {
	return doc.binary_encode_checked()
}

pub fn (doc Document) encode_checked_with_limits(limits AstValidationLimits) ![]u8 {
	return doc.binary_encode_checked_with_limits(limits)
}

// binary_encode_checked validates an application-assembled AST before
// encoding it as a complete VMDA document. Parser-produced documents are
// already valid and may continue to use binary_encode() directly.
pub fn (doc Document) binary_encode_checked() ![]u8 {
	return doc.binary_encode_checked_with_limits(AstValidationLimits{})
}

// binary_encode_checked_with_limits validates with caller-selected traversal
// budgets before encoding a complete VMDA document.
pub fn (doc Document) binary_encode_checked_with_limits(limits AstValidationLimits) ![]u8 {
	doc.validate_with_limits(limits)!
	return doc.binary_encode()
}

pub fn (doc Document) semantic_stable_id() string {
	return 'doc:' + hash_bytes(doc.normalized_bytes())
}

pub fn (doc Document) semantic_stable_id_checked() !string {
	return doc.semantic_stable_id_checked_with_limits(AstValidationLimits{})
}

pub fn (doc Document) semantic_stable_id_checked_with_limits(limits AstValidationLimits) !string {
	doc.validate_with_limits(limits)!
	return doc.semantic_stable_id()
}

pub fn (doc Document) semantic_encode() []u8 {
	return doc.normalized_bytes()
}

pub fn (doc Document) semantic_encode_checked() ![]u8 {
	return doc.semantic_encode_checked_with_limits(AstValidationLimits{})
}

pub fn (doc Document) semantic_encode_checked_with_limits(limits AstValidationLimits) ![]u8 {
	doc.validate_with_limits(limits)!
	return doc.semantic_encode()
}

pub fn (node BlockNode) stable_id() string {
	encoded := node.binary_encode()
	match node {
		HeadingNode {
			return 'h${node.level}:' + hash_bytes(encoded)
		}
		ParagraphNode {
			return 'para:' + hash_bytes(encoded)
		}
		CodeBlockNode {
			lang := normalize_text(node.lang)
			return 'code:${lang}:' + hash_bytes(encoded)
		}
		BlockquoteNode {
			return 'quote:' + hash_bytes(encoded)
		}
		ListNode {
			return 'list:' + hash_bytes(encoded)
		}
		HorizontalRuleNode {
			return 'hr:' + hash_bytes(encoded)
		}
		MetaNode {
			return 'meta:' + hash_bytes(encoded)
		}
		TableNode {
			return 'table:' + hash_bytes(encoded)
		}
		RawHtmlBlockNode {
			return 'html:' + hash_bytes(encoded)
		}
	}
}

pub fn (node BlockNode) stable_id_checked() !string {
	return node.stable_id_checked_with_limits(AstValidationLimits{})
}

pub fn (node BlockNode) stable_id_checked_with_limits(limits AstValidationLimits) !string {
	node.validate_with_limits(limits)!
	return node.stable_id()
}

pub fn (node BlockNode) encode() []u8 {
	return node.binary_encode()
}

pub fn (node BlockNode) encode_checked() ![]u8 {
	return node.encode_checked_with_limits(AstValidationLimits{})
}

pub fn (node BlockNode) encode_checked_with_limits(limits AstValidationLimits) ![]u8 {
	node.validate_with_limits(limits)!
	return node.encode()
}

pub fn (item ListItemNode) encode() []u8 {
	return item.binary_encode()
}

pub fn (node InlineNode) encode() []u8 {
	return node.binary_encode()
}

pub fn (node InlineNode) encode_checked() ![]u8 {
	return node.encode_checked_with_limits(AstValidationLimits{})
}

pub fn (node InlineNode) encode_checked_with_limits(limits AstValidationLimits) ![]u8 {
	node.validate_with_limits(limits)!
	return node.encode()
}

pub fn (node BlockNode) semantic_stable_id() string {
	normalized := node.normalized_bytes()
	match node {
		HeadingNode {
			return 'h${node.level}:' + hash_bytes(normalized)
		}
		ParagraphNode {
			return 'para:' + hash_bytes(normalized)
		}
		CodeBlockNode {
			lang := normalize_text(node.lang)
			return 'code:${lang}:' + hash_bytes(normalized)
		}
		BlockquoteNode {
			return 'quote:' + hash_bytes(normalized)
		}
		ListNode {
			return 'list:' + hash_bytes(normalized)
		}
		HorizontalRuleNode {
			return 'hr:' + hash_bytes(normalized)
		}
		MetaNode {
			return 'meta:' + hash_bytes(normalized)
		}
		TableNode {
			return 'table:' + hash_bytes(normalized)
		}
		RawHtmlBlockNode {
			return 'html:' + hash_bytes(normalized)
		}
	}
}

pub fn (node BlockNode) semantic_stable_id_checked() !string {
	return node.semantic_stable_id_checked_with_limits(AstValidationLimits{})
}

pub fn (node BlockNode) semantic_stable_id_checked_with_limits(limits AstValidationLimits) !string {
	node.validate_with_limits(limits)!
	return node.semantic_stable_id()
}

pub fn (node BlockNode) semantic_encode() []u8 {
	return node.normalized_bytes()
}

pub fn (node BlockNode) semantic_encode_checked() ![]u8 {
	return node.semantic_encode_checked_with_limits(AstValidationLimits{})
}

pub fn (node BlockNode) semantic_encode_checked_with_limits(limits AstValidationLimits) ![]u8 {
	node.validate_with_limits(limits)!
	return node.semantic_encode()
}

pub fn (item ListItemNode) semantic_encode() []u8 {
	return item.normalized_bytes()
}

pub fn (node InlineNode) semantic_encode() []u8 {
	return node.normalized_bytes()
}

pub fn (node InlineNode) semantic_encode_checked() ![]u8 {
	return node.semantic_encode_checked_with_limits(AstValidationLimits{})
}

pub fn (node InlineNode) semantic_encode_checked_with_limits(limits AstValidationLimits) ![]u8 {
	node.validate_with_limits(limits)!
	return node.semantic_encode()
}

pub fn (doc Document) str() string {
	mut sb := strings.new_builder(256)
	sb.write_string('Document{\n')
	for child in doc.children {
		sb.write_string('  ${child.stable_id()}\n')
	}
	sb.write_string('}')
	return sb.str()
}

fn (doc Document) normalized_bytes() []u8 {
	mut out := []u8{}
	for child in doc.children {
		out << child.stable_id().bytes()
		out << [u8(`\n`)]
	}
	return out
}

fn (node BlockNode) normalized_bytes() []u8 {
	match node {
		HeadingNode {
			mut out := []u8{}
			out << 'heading:'.bytes()
			out << node.level.str().bytes()
			out << [u8(`:`)]
			for child in node.children {
				out << child.normalized_bytes()
			}
			return out
		}
		ParagraphNode {
			mut out := 'paragraph:'.bytes()
			for child in node.children {
				out << child.normalized_bytes()
			}
			return out
		}
		BlockquoteNode {
			mut out := 'blockquote:'.bytes()
			for child in node.children {
				out << child.stable_id().bytes()
				out << [u8(`,`)]
			}
			return out
		}
		ListNode {
			mut out := 'list:'.bytes()
			out << bool_byte(node.is_ordered)
			out << node.start.str().bytes()
			out << [u8(`:`)]
			for item in node.items {
				out << item.normalized_bytes()
				out << [u8(`|`)]
			}
			return out
		}
		CodeBlockNode {
			mut out := 'code:'.bytes()
			out << normalize_text(node.lang).bytes()
			out << [u8(`:`)]
			out << normalize_code(node.content).bytes()
			return out
		}
		HorizontalRuleNode {
			return 'hr'.bytes()
		}
		MetaNode {
			mut keys := node.data.keys()
			keys.sort()
			mut out := 'meta:'.bytes()
			for key in keys {
				out << normalize_text(key).bytes()
				out << [u8(`=`)]
				out << normalize_text(node.data[key]).bytes()
				out << [u8(`;`)]
			}
			return out
		}
		TableNode {
			mut out := 'table:'.bytes()
			out << node.columns.str().bytes()
			out << [u8(`:`)]
			for row in node.head {
				out << row.normalized_bytes()
				out << [u8(`;`)]
			}
			out << [u8(`|`)]
			for row in node.body {
				out << row.normalized_bytes()
				out << [u8(`;`)]
			}
			return out
		}
		RawHtmlBlockNode {
			mut out := 'raw_html:'.bytes()
			out << node.html.bytes()
			return out
		}
	}
}

fn (row TableRowNode) normalized_bytes() []u8 {
	mut out := 'row:'.bytes()
	for cell in row.cells {
		out << cell.alignment.str().bytes()
		out << [u8(`:`)]
		for child in cell.children {
			out << child.normalized_bytes()
		}
		out << [u8(`,`)]
	}
	return out
}

fn (item ListItemNode) normalized_bytes() []u8 {
	mut out := 'item:'.bytes()
	out << item.level.str().bytes()
	out << [u8(`:`)]
	out << item.number.str().bytes()
	out << [u8(`:`)]
	out << bool_byte(item.is_task)
	out << bool_byte(item.checked)
	out << [u8(`:`)]
	for child in item.children {
		out << child.stable_id().bytes()
		out << [u8(`,`)]
	}
	return out
}

fn (node InlineNode) normalized_bytes() []u8 {
	match node {
		TextNode {
			mut out := 'text:'.bytes()
			out << normalize_text(node.text).bytes()
			return out
		}
		EmphasisNode {
			mut out := 'em:'.bytes()
			for child in node.children {
				out << child.normalized_bytes()
			}
			return out
		}
		StrongNode {
			mut out := 'strong:'.bytes()
			for child in node.children {
				out << child.normalized_bytes()
			}
			return out
		}
		StrikethroughNode {
			mut out := 'strikethrough:'.bytes()
			for child in node.children {
				out << child.normalized_bytes()
			}
			return out
		}
		UnderlineNode {
			mut out := 'underline:'.bytes()
			for child in node.children {
				out << child.normalized_bytes()
			}
			return out
		}
		CodeSpanNode {
			mut out := 'codespan:'.bytes()
			out << normalize_code(node.text).bytes()
			return out
		}
		LatexMathNode {
			mut out := 'latex_math:'.bytes()
			out << bool_byte(node.display)
			out << [u8(`:`)]
			out << normalize_code(node.content).bytes()
			return out
		}
		LinkNode {
			mut out := 'link:'.bytes()
			out << normalize_text(node.url).bytes()
			out << [u8(`:`)]
			for child in node.text {
				out << child.normalized_bytes()
			}
			return out
		}
		WikiLinkNode {
			mut out := 'wiki_link:'.bytes()
			out << normalize_text(node.target).bytes()
			out << [u8(`:`)]
			for child in node.text {
				out << child.normalized_bytes()
			}
			return out
		}
		ImageNode {
			mut out := 'image:'.bytes()
			out << normalize_text(node.url).bytes()
			out << [u8(`:`)]
			for child in node.alt {
				out << child.normalized_bytes()
			}
			return out
		}
		SoftBreakNode {
			return 'soft_break'.bytes()
		}
		HardBreakNode {
			return 'hard_break'.bytes()
		}
		RawHtmlInlineNode {
			mut out := 'raw_html_inline:'.bytes()
			out << node.html.bytes()
			return out
		}
	}
}

fn (node BlockNode) kind_name() string {
	match node {
		HeadingNode {
			return 'heading'
		}
		ParagraphNode {
			return 'paragraph'
		}
		BlockquoteNode {
			return 'blockquote'
		}
		ListNode {
			return 'list'
		}
		CodeBlockNode {
			return 'code_block'
		}
		HorizontalRuleNode {
			return 'horizontal_rule'
		}
		MetaNode {
			return 'meta'
		}
		TableNode {
			return 'table'
		}
		RawHtmlBlockNode {
			return 'raw_html_block'
		}
	}
}

fn normalize_text(input string) string {
	return collapse_text_whitespace(input).trim_space()
}

fn normalize_inline_text(input string, trim_left bool, trim_right bool) string {
	mut normalized := collapse_text_whitespace(input)
	if trim_left && normalized.starts_with(' ') {
		normalized = normalized[1..]
	}
	if trim_right && normalized.ends_with(' ') {
		normalized = normalized[..normalized.len - 1]
	}
	return normalized
}

fn collapse_text_whitespace(input string) string {
	mut sb := strings.new_builder(input.len)
	mut last_space := false
	for r in input.runes() {
		if is_space_rune(r) {
			if !last_space {
				sb.write_rune(` `)
				last_space = true
			}
			continue
		}
		sb.write_rune(r)
		last_space = false
	}
	return sb.str()
}

fn is_space_rune(r rune) bool {
	return r == ` ` || r == `\t` || r == `\n` || r == `\r` || r == `\v` || r == `\f`
}

fn normalize_code(input string) string {
	return input.replace('\r\n', '\n').replace('\r', '\n')
}

fn bool_byte(value bool) []u8 {
	return if value { [u8(`1`)] } else { [u8(`0`)] }
}

fn hash_bytes(data []u8) string {
	digest := sha256.sum256(data)
	return digest.hex()
}
