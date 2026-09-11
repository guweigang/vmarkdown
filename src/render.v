module vmarkdown

import strings

@[inline]
pub fn (doc Document) to_text() string {
	return doc.render_text()
}

// to_text_checked validates an application-assembled AST before rendering.
pub fn (doc Document) to_text_checked() !string {
	return doc.to_text_checked_with_limits(AstValidationLimits{})
}

// to_text_checked_with_limits validates with caller-selected traversal limits.
pub fn (doc Document) to_text_checked_with_limits(limits AstValidationLimits) !string {
	doc.validate_with_limits(limits)!
	return doc.render_text()
}

pub fn render_text(markdown string) !string {
	return render_text_with_options(markdown, ParseOptions{})
}

pub fn render_text_with_options(markdown string, options ParseOptions) !string {
	return render_text_with_limits(markdown, options, ParseLimits{})
}

pub fn render_text_with_limits(markdown string, options ParseOptions, limits ParseLimits) !string {
	return parse_with_limits(markdown, options, limits)!.render_text()
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
		RawHtmlBlockNode {
			return node.html
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
		TableNode {
			mut lines := []string{}
			mut rows := node.head.clone()
			rows << node.body
			for row in rows {
				lines << row.cells.map(render_inline_text(it.children)).join('\t')
			}
			return lines.join('\n')
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
		StrikethroughNode {
			return render_inline_text(node.children)
		}
		UnderlineNode {
			return render_inline_text(node.children)
		}
		CodeSpanNode {
			return node.text
		}
		LatexMathNode {
			return node.content
		}
		LinkNode {
			return render_inline_text(node.text)
		}
		WikiLinkNode {
			return render_inline_text(node.text)
		}
		ImageNode {
			return render_inline_text(node.alt)
		}
		SoftBreakNode {
			return '\n'
		}
		HardBreakNode {
			return '\n'
		}
		RawHtmlInlineNode {
			return node.html
		}
	}
}
