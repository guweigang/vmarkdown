module vmarkdown

import strings

pub struct HtmlRenderOptions {
pub:
	parser            ParseOptions
	xhtml             bool
	debug             bool
	verbatim_entities bool
	skip_utf8_bom     bool = true
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
	rc := C.md_html(markdown.str, u32(markdown.len), html_process_output, &out, options.parser.to_md4c_flags(), render_flags)
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

@[inline]
pub fn (doc Document) to_markdown() string {
	return doc.render_markdown()
}

pub fn render_markdown(markdown string) !string {
	return parse(markdown)!.render_markdown()
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

fn (doc Document) render_markdown() string {
	mut parts := []string{}
	for child_index, child in doc.children {
		rendered := child.render_markdown_block('', 0, list_run_variant(doc.children, child_index))
		if rendered.len > 0 {
			parts << rendered
		}
	}
	return parts.join('\n\n')
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

fn (node BlockNode) render_markdown_block(prefix string, depth int, list_variant int) string {
	match node {
		HeadingNode {
			content := escape_heading_closing_hashes(render_inline_markdown(node.children))
			if content.contains('\n') && node.level in [1, 2] {
				underline := if node.level == 1 { '===' } else { '---' }
				return '${content}\n${underline}'
			}
			hashes := '#'.repeat(node.level)
			return '${hashes} ${content}'
		}
		ParagraphNode {
			return prefix + render_inline_markdown(node.children)
		}
		BlockquoteNode {
			mut parts := []string{}
			for child_index, child in node.children {
				rendered := child.render_markdown_block('', depth, list_run_variant(node.children, child_index))
				if rendered.len == 0 {
					continue
				}
				if child_index > 0 && parts.len > 0 {
					parts << '>'
				}
				for line in rendered.split_into_lines() {
					parts << '> ' + line
				}
			}
			if parts.len == 0 {
				return '>'
			}
			return parts.join('\n')
		}
		ListNode {
			mut lines := []string{}
			for i, item in node.items {
				marker := if node.is_ordered {
					'${node.start + i}${if list_variant % 2 == 0 { '.' } else { ')' }}'
				} else if list_variant % 2 == 0 {
					'-'
				} else {
					'+'
				}
				task := if item.is_task {
					if item.checked { '[x] ' } else { '[ ] ' }
				} else {
					''
				}
				item_prefix := '${prefix}${marker} ${task}'
				body_prefix := prefix + ' '.repeat(marker.len + 1 + task.len)
				block_prefix := prefix + ' '.repeat(marker.len + 1)
				item_lines := item.render_markdown_item(depth + 1)
				if item_lines.len == 0 {
					lines << item_prefix.trim_right(' ')
					continue
				}
				if item.starts_with_nested_list() {
					lines << item_prefix.trim_right(' ')
					for line in item_lines {
						if line.len == 0 {
							lines << ''
						} else {
							lines << body_prefix + line
						}
					}
					continue
				}
				mut in_later_block := false
				for line_index, line in item_lines {
					if line_index == 0 {
						lines << item_prefix + line
					} else if line.len == 0 {
						lines << ''
						in_later_block = true
					} else {
						lines << if in_later_block {
							block_prefix + line
						} else {
							body_prefix + line
						}
					}
				}
			}
			return lines.join('\n')
		}
		CodeBlockNode {
			fence := markdown_fence_with_info(node.content, node.lang)
			lang := if node.lang.len > 0 { node.lang } else { '' }
			content := normalize_code(node.content)
			header := if lang.len > 0 { '${fence}${lang}\n' } else { '${fence}\n' }
			if content.len == 0 {
				return header + fence
			}
			separator := if content.ends_with('\n') { '' } else { '\n' }
			return header + content + separator + fence
		}
		RawHtmlBlockNode {
			return node.html
		}
		HorizontalRuleNode {
			// This form remains a thematic break when used as the first block of a list item.
			return '* * *'
		}
		MetaNode {
			mut keys := node.data.keys()
			keys.sort()
			mut lines := []string{}
			for key in keys {
				lines << '${key}: ${node.data[key]}'
			}
			return lines.join('\n')
		}
		TableNode {
			return render_table_markdown(node)
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

fn render_table_markdown(node TableNode) string {
	if node.head.len == 0 {
		return ''
	}
	mut lines := []string{}
	lines << render_table_markdown_row(node.head[0])
	mut separators := []string{}
	for cell in node.head[0].cells {
		separators << match cell.alignment {
			.left { ':---' }
			.center { ':---:' }
			.right { '---:' }
			.default_ { '---' }
		}
	}
	lines << '| ' + separators.join(' | ') + ' |'
	for row in node.body {
		lines << render_table_markdown_row(row)
	}
	return lines.join('\n')
}

fn render_table_markdown_row(row TableRowNode) string {
	return '| ' + row.cells.map(render_table_cell_markdown(it.children)).join(' | ') + ' |'
}

fn render_table_cell_markdown(nodes []InlineNode) string {
	mut sb := strings.new_builder(32)
	for node in nodes {
		rendered := node.render_markdown_inline(0)
		if node is CodeSpanNode {
			sb.write_string(rendered)
		} else {
			sb.write_string(rendered.replace('|', '\\|'))
		}
	}
	return sb.str().replace('\n', '<br>')
}

fn (item ListItemNode) render_markdown_item(depth int) []string {
	mut lines := []string{}
	for child_index, child in item.children {
		rendered := child.render_markdown_block('', depth, list_run_variant(item.children, child_index))
		if rendered.len == 0 {
			continue
		}
		child_lines := rendered.split_into_lines()
		if child_index > 0 && lines.len > 0 && child_lines.len > 0 {
			lines << ''
		}
		for line in child_lines {
			lines << line
		}
	}
	return lines
}

fn list_run_variant(nodes []BlockNode, index int) int {
	if index < 0 || index >= nodes.len || nodes[index] !is ListNode {
		return 0
	}
	current := nodes[index] as ListNode
	mut variant := 0
	for previous_index := index - 1; previous_index >= 0; previous_index-- {
		previous := nodes[previous_index]
		if previous !is ListNode || previous.is_ordered != current.is_ordered {
			break
		}
		variant++
	}
	return variant
}

fn (item ListItemNode) starts_with_nested_list() bool {
	if item.children.len == 0 {
		return false
	}
	return item.children[0] is ListNode
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

fn render_inline_markdown(nodes []InlineNode) string {
	return render_inline_markdown_depth(nodes, 0)
}

fn render_inline_markdown_depth(nodes []InlineNode, emphasis_depth int) string {
	mut sb := strings.new_builder(64)
	for node in nodes {
		sb.write_string(node.render_markdown_inline(emphasis_depth))
	}
	return sb.str()
}

fn (node InlineNode) render_markdown_inline(emphasis_depth int) string {
	match node {
		TextNode {
			return escape_markdown_text(node.text)
		}
		EmphasisNode {
			marker := if emphasis_depth % 2 == 0 { '*' } else { '_' }
			return marker + render_inline_markdown_depth(node.children, emphasis_depth + 1) + marker
		}
		StrongNode {
			return '**' + render_inline_markdown_depth(node.children, emphasis_depth) + '**'
		}
		StrikethroughNode {
			return '~~' + render_inline_markdown_depth(node.children, emphasis_depth) + '~~'
		}
		UnderlineNode {
			return '_' + render_inline_markdown_depth(node.children, emphasis_depth) + '_'
		}
		CodeSpanNode {
			return markdown_code_span(node.text)
		}
		LatexMathNode {
			delimiter := if node.display { '\$\$' } else { '\$' }
			return delimiter + node.content + delimiter
		}
		LinkNode {
			plain_text := render_inline_text(node.text)
			if node.url.len > 0 && plain_text == node.url && !node.url.contains_any(' <>\t\n') {
				return '<${node.url}>'
			}
			return '[' + render_inline_markdown_depth(node.text, emphasis_depth) + '](' + markdown_link_destination(node.url) + ')'
		}
		WikiLinkNode {
			target := markdown_wiki_target(node.target)
			label := render_inline_markdown_depth(node.text, emphasis_depth)
			if render_inline_text(node.text) == node.target {
				return '[[' + target + ']]'
			}
			return '[[' + target + '|' + label + ']]'
		}
		ImageNode {
			return '![' + render_inline_markdown_depth(node.alt, emphasis_depth) + '](' + markdown_link_destination(node.url) + ')'
		}
		SoftBreakNode {
			return '\n'
		}
		HardBreakNode {
			return '  \n'
		}
		RawHtmlInlineNode {
			return node.html
		}
	}
}

fn markdown_wiki_target(target string) string {
	return target.replace('\\', '\\\\').replace('|', '\\|').replace(']', '\\]')
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

fn escape_markdown_text(input string) string {
	escaped := input.replace('\\', '\\\\').replace('[', '\\[').replace(']', '\\]').replace('!', '\\!').replace('*', '\\*').replace('_', '\\_').replace('`', '\\`').replace('<', '\\<')
	return escape_markdown_block_start(escaped)
}

fn escape_markdown_block_start(input string) string {
	mut marker := 0
	for marker < input.len && marker < 3 && input[marker] == ` ` {
		marker++
	}
	if marker >= input.len {
		return input
	}
	if input[marker] in [`#`, `>`, `-`, `+`, `=`, `~`] {
		return input[..marker] + '\\' + input[marker..]
	}
	mut end := marker
	for end < input.len && end - marker < 9 && input[end] >= `0` && input[end] <= `9` {
		end++
	}
	if end > marker && end < input.len && input[end] in [`.`, `)`]
		&& end + 1 < input.len && input[end + 1] in [` `, `\t`] {
		return input[..end] + '\\' + input[end..]
	}
	return input
}

fn escape_heading_closing_hashes(input string) string {
	mut hash_end := input.len
	for hash_end > 0 && input[hash_end - 1] == ` ` {
		hash_end--
	}
	mut hash_start := hash_end
	for hash_start > 0 && input[hash_start - 1] == `#` {
		hash_start--
	}
	if hash_start == hash_end || (hash_start > 0 && input[hash_start - 1] != ` `) {
		return input
	}
	return input[..hash_start] + '\\#'.repeat(hash_end - hash_start) + input[hash_end..]
}

fn markdown_fence(content string) string {
	mut longest := 2
	mut current := 0
	for ch in content {
		if ch == u8(96) {
			current++
			if current > longest {
				longest = current
			}
		} else {
			current = 0
		}
	}
	return '`'.repeat(longest + 1)
}

fn markdown_fence_with_info(content string, info string) string {
	if !info.contains('`') {
		return markdown_fence(content)
	}
	mut longest := 2
	mut current := 0
	for ch in content {
		if ch == `~` {
			current++
			longest = max_int(longest, current)
		} else {
			current = 0
		}
	}
	return '~'.repeat(longest + 1)
}

fn markdown_code_span(content string) string {
	delimiter := '`'.repeat(longest_backtick_run(content) + 1)
	needs_padding := content.starts_with('`') || content.ends_with('`') || content.starts_with(' ')
		|| content.ends_with(' ')
	if needs_padding && content.trim_space().len > 0 {
		return '${delimiter} ${content} ${delimiter}'
	}
	return '${delimiter}${content}${delimiter}'
}

fn markdown_link_destination(url string) string {
	escaped := url.replace('\\', '\\\\').replace('`', '\\`')
	if needs_wrapped_destination(url) {
		return '<' + escaped.replace('>', '\\>') + '>'
	}
	return escaped.replace(' ', '\\ ')
}

fn needs_wrapped_destination(url string) bool {
	return url.contains(' ') || url.contains('(') || url.contains(')') || url.contains('\t')
		|| url.contains('\n') || url.contains('<') || url.contains('>')
}

fn longest_backtick_run(input string) int {
	mut longest := 0
	mut current := 0
	for ch in input {
		if ch == u8(96) {
			current++
			if current > longest {
				longest = current
			}
		} else {
			current = 0
		}
	}
	return longest
}

@[export: 'html_process_output']
fn html_process_output(text &char, size u32, userdata voidptr) {
	mut out := unsafe { &HtmlOutputBuilder(userdata) }
	if size == 0 {
		return
	}
	out.sb.write_string(unsafe { tos(&u8(text), int(size)).clone() })
}
