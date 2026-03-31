module vmarkdown

import strings

pub struct HtmlRenderOptions {
pub:
	parser  ParseOptions
	xhtml   bool
	debug   bool
	verbatim_entities bool
	skip_utf8_bom bool = true
}

struct HtmlOutputBuilder {
mut:
	sb strings.Builder
}

pub fn render_html(markdown string) !string {
	return render_html_with_options(markdown, HtmlRenderOptions{})
}

pub fn render_html_with_options(markdown string, options HtmlRenderOptions) !string {
	mut out := HtmlOutputBuilder{
		sb: strings.new_builder(markdown.len + 64)
	}
	mut render_flags := u32(0)
	if options.xhtml {
		render_flags |= u32(C.MD_HTML_FLAG_XHTML)
	}
	if options.debug {
		render_flags |= u32(C.MD_HTML_FLAG_DEBUG)
	}
	if options.verbatim_entities {
		render_flags |= u32(C.MD_HTML_FLAG_VERBATIM_ENTITIES)
	}
	if options.skip_utf8_bom {
		render_flags |= u32(C.MD_HTML_FLAG_SKIP_UTF8_BOM)
	}
	rc := C.md_html(markdown.str, u32(markdown.len), html_process_output, &out,
		options.parser.to_md4c_flags(), render_flags)
	if rc != 0 {
		return error('md4c html render failed with code ${rc}')
	}
	return out.sb.str()
}

@[inline]
pub fn (doc Document) to_text() string {
	return doc.render_text()
}

pub fn render_text(markdown string) !string {
	return parse(markdown)!.render_text()
}

@[inline]
pub fn (doc Document) to_json() string {
	return doc.render_json()
}

pub fn render_json(markdown string) !string {
	return parse(markdown)!.render_json()
}

fn (doc Document) render_text() string {
	mut lines := []string{}
	for child in doc.children {
		text := child.render_text_block()
		if text.len > 0 {
			lines << text
		}
	}
	return lines.join('\n\n')
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

fn (node BlockNode) render_text_block() string {
	match node {
		HeadingNode {
			return render_inline_text(node.children)
		}
		ParagraphNode {
			return render_inline_text(node.children)
		}
		BlockquoteNode {
			mut parts := []string{}
			for child in node.children {
				text := child.render_text_block()
				if text.len > 0 {
					parts << text
				}
			}
			return parts.join('\n')
		}
		ListNode {
			mut lines := []string{}
			for i, item in node.items {
				prefix := if node.is_ordered { '${node.start + i}. ' } else { '- ' }
				item_text := item.render_text_item()
				if item_text.contains('\n') {
					item_lines := item_text.split_into_lines()
					for j, line in item_lines {
						if j == 0 {
							lines << prefix + line
						} else {
							lines << '  ' + line
						}
					}
				} else if item_text.len > 0 {
					lines << prefix + item_text
				}
			}
			return lines.join('\n')
		}
		CodeBlockNode {
			return node.content.trim_right('\n')
		}
		HorizontalRuleNode {
			return '---'
		}
		MetaNode {
			mut keys := node.data.keys()
			keys.sort()
			mut parts := []string{}
			for key in keys {
				parts << '${key}: ${node.data[key]}'
			}
			return parts.join('\n')
		}
	}
}

fn (item ListItemNode) render_text_item() string {
	mut parts := []string{}
	for child in item.children {
		text := child.render_text_block()
		if text.len > 0 {
			parts << text
		}
	}
	return parts.join('\n')
}

fn render_inline_text(nodes []InlineNode) string {
	mut sb := strings.new_builder(64)
	for node in nodes {
		sb.write_string(node.render_text_inline())
	}
	return sb.str()
}

fn (node InlineNode) render_text_inline() string {
	match node {
		TextNode {
			return node.text
		}
		EmphasisNode {
			return render_inline_text(node.children)
		}
		StrongNode {
			return render_inline_text(node.children)
		}
		CodeSpanNode {
			return node.text
		}
		LinkNode {
			return render_inline_text(node.text)
		}
		ImageNode {
			return render_inline_text(node.alt)
		}
	}
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
	}
}

fn (item ListItemNode) render_json_item() string {
	mut sb := strings.new_builder(128)
	sb.write_string('{"level":${item.level},"number":${item.number},"children":[')
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
		CodeSpanNode {
			return '{"type":"code_span","text":"${json_escape(node.text)}"}'
		}
		LinkNode {
			return '{"type":"link","url":"${json_escape(node.url)}","text":${render_inline_json(node.text)}}'
		}
		ImageNode {
			return '{"type":"image","url":"${json_escape(node.url)}","alt":${render_inline_json(node.alt)}}'
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

@[export: 'html_process_output']
fn html_process_output(text &char, size u32, userdata voidptr) {
	mut out := unsafe { &HtmlOutputBuilder(userdata) }
	if size == 0 {
		return
	}
	out.sb.write_string(unsafe { tos(&u8(text), int(size)).clone() })
}
