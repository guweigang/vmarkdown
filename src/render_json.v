module vmarkdown

import strings

// JSON rendering for vmarkdown AST nodes.

@[inline]
pub fn (doc Document) to_json() string {
	return doc.render_json()
}

// to_json_checked validates an application-assembled AST before rendering.
pub fn (doc Document) to_json_checked() !string {
	return doc.to_json_checked_with_limits(AstValidationLimits{})
}

// to_json_checked_with_limits validates with caller-selected traversal limits.
pub fn (doc Document) to_json_checked_with_limits(limits AstValidationLimits) !string {
	doc.validate_with_limits(limits)!
	return doc.render_json()
}

pub fn render_json(markdown string) !string {
	return render_json_with_options(markdown, ParseOptions{})
}

pub fn render_json_with_options(markdown string, options ParseOptions) !string {
	return render_json_with_limits(markdown, options, ParseLimits{})
}

pub fn render_json_with_limits(markdown string, options ParseOptions, limits ParseLimits) !string {
	return parse_with_limits(markdown, options, limits)!.render_json()
}

fn (doc Document) render_json() string {
	mut sb := strings.new_builder(512)
	sb.write_string('{"type":"document","children":[')
	for i, child in doc.children {
		if i > 0 {
			sb.write_string(',')
		}
		sb.write_string(child.render_json_block())
	}
	sb.write_string(']}')
	return sb.str()
}

fn (node BlockNode) render_json_block() string {
	match node {
		HeadingNode {
			return '{"type":"heading","level":${node.level},"children":${render_inline_json(node.children)}}'
		}
		ParagraphNode {
			return '{"type":"paragraph","children":${render_inline_json(node.children)}}'
		}
		BlockquoteNode {
			mut sb := strings.new_builder(128)
			sb.write_string('{"type":"blockquote","children":[')
			for i, child in node.children {
				if i > 0 {
					sb.write_string(',')
				}
				sb.write_string(child.render_json_block())
			}
			sb.write_string(']}')
			return sb.str()
		}
		ListNode {
			mut sb := strings.new_builder(192)
			sb.write_string('{"type":"list","ordered":')
			sb.write_string(node.is_ordered.str())
			sb.write_string(',"start":${node.start},"items":[')
			for i, item in node.items {
				if i > 0 {
					sb.write_string(',')
				}
				sb.write_string(item.render_json_item())
			}
			sb.write_string(']}')
			return sb.str()
		}
		CodeBlockNode {
			return '{"type":"code_block","lang":"${json_escape(node.lang)}","content":"${json_escape(node.content)}"}'
		}
		RawHtmlBlockNode {
			return '{"type":"raw_html_block","html":"${json_escape(node.html)}"}'
		}
		HorizontalRuleNode {
			return '{"type":"horizontal_rule"}'
		}
		MetaNode {
			mut keys := node.data.keys()
			keys.sort()
			mut sb := strings.new_builder(128)
			sb.write_string('{"type":"meta","data":{')
			for i, key in keys {
				if i > 0 {
					sb.write_string(',')
				}
				sb.write_string('"${json_escape(key)}":"${json_escape(node.data[key])}"')
			}
			sb.write_string('}}')
			return sb.str()
		}
		TableNode {
			mut sb := strings.new_builder(256)
			sb.write_string('{"type":"table","columns":${node.columns},"head":')
			sb.write_string(render_table_rows_json(node.head))
			sb.write_string(',"body":')
			sb.write_string(render_table_rows_json(node.body))
			sb.write_string('}')
			return sb.str()
		}
	}
}

fn render_table_rows_json(rows []TableRowNode) string {
	mut sb := strings.new_builder(128)
	sb.write_string('[')
	for row_index, row in rows {
		if row_index > 0 {
			sb.write_string(',')
		}
		sb.write_string('{"cells":[')
		for cell_index, cell in row.cells {
			if cell_index > 0 {
				sb.write_string(',')
			}
			sb.write_string('{"alignment":"${cell.alignment}","children":${render_inline_json(cell.children)}}')
		}
		sb.write_string(']}')
	}
	sb.write_string(']')
	return sb.str()
}

fn (item ListItemNode) render_json_item() string {
	mut sb := strings.new_builder(128)
	sb.write_string('{"level":${item.level},"number":${item.number},"is_task":${item.is_task},"checked":${item.checked},"children":[')
	for i, child in item.children {
		if i > 0 {
			sb.write_string(',')
		}
		sb.write_string(child.render_json_block())
	}
	sb.write_string(']}')
	return sb.str()
}

fn render_inline_json(nodes []InlineNode) string {
	mut sb := strings.new_builder(128)
	sb.write_string('[')
	for i, node in nodes {
		if i > 0 {
			sb.write_string(',')
		}
		sb.write_string(node.render_json_inline())
	}
	sb.write_string(']')
	return sb.str()
}

fn (node InlineNode) render_json_inline() string {
	match node {
		TextNode {
			return '{"type":"text","text":"${json_escape(node.text)}"}'
		}
		EmphasisNode {
			return '{"type":"emphasis","children":${render_inline_json(node.children)}}'
		}
		StrongNode {
			return '{"type":"strong","children":${render_inline_json(node.children)}}'
		}
		StrikethroughNode {
			return '{"type":"strikethrough","children":${render_inline_json(node.children)}}'
		}
		UnderlineNode {
			return '{"type":"underline","children":${render_inline_json(node.children)}}'
		}
		CodeSpanNode {
			return '{"type":"code_span","text":"${json_escape(node.text)}"}'
		}
		LatexMathNode {
			return '{"type":"latex_math","display":${node.display},"content":"${json_escape(node.content)}"}'
		}
		LinkNode {
			return '{"type":"link","url":"${json_escape(node.url)}","text":${render_inline_json(node.text)}}'
		}
		WikiLinkNode {
			return '{"type":"wiki_link","target":"${json_escape(node.target)}","text":${render_inline_json(node.text)}}'
		}
		ImageNode {
			return '{"type":"image","url":"${json_escape(node.url)}","alt":${render_inline_json(node.alt)}}'
		}
		SoftBreakNode {
			return '{"type":"soft_break"}'
		}
		HardBreakNode {
			return '{"type":"hard_break"}'
		}
		RawHtmlInlineNode {
			return '{"type":"raw_html_inline","html":"${json_escape(node.html)}"}'
		}
	}
}

fn json_escape(input string) string {
	mut out := strings.new_builder(input.len + 16)
	for ch in input {
		match ch {
			`\\` { out.write_string('\\\\') }
			`"` { out.write_string('\\"') }
			`\n` { out.write_string('\\n') }
			`\r` { out.write_string('\\r') }
			`\t` { out.write_string('\\t') }
			else { out.write_u8(ch) }
		}
	}
	return out.str()
}
