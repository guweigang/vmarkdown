module vmarkdown

import strings

// Normalized Markdown rendering for vmarkdown AST nodes.

@[inline]
pub fn (doc Document) to_markdown() string {
	return doc.render_markdown()
}

// to_markdown_checked validates an application-assembled AST before rendering.
pub fn (doc Document) to_markdown_checked() !string {
	return doc.to_markdown_checked_with_limits(AstValidationLimits{})
}

// to_markdown_checked_with_limits validates with caller-selected traversal limits.
pub fn (doc Document) to_markdown_checked_with_limits(limits AstValidationLimits) !string {
	doc.validate_with_limits(limits)!
	return doc.render_markdown()
}

pub fn render_markdown(markdown string) !string {
	return render_markdown_with_options(markdown, ParseOptions{})
}

pub fn render_markdown_with_options(markdown string, options ParseOptions) !string {
	return render_markdown_with_limits(markdown, options, ParseLimits{})
}

pub fn render_markdown_with_limits(markdown string, options ParseOptions, limits ParseLimits) !string {
	return parse_with_limits(markdown, options, limits)!.render_markdown()
}

fn (doc Document) render_markdown() string {
	if doc.preserve_blank_lines || has_explicit_blank_lines(doc.children) {
		return join_preserved_lines(render_preserved_markdown_lines(doc.children, 0))
	}
	mut parts := []string{}
	for child_index, child in doc.children {
		rendered := child.render_markdown_block('', 0, list_run_variant(doc.children, child_index), false)
		if rendered.len > 0 {
			parts << rendered
		}
	}
	return parts.join('\n\n')
}

fn (node BlockNode) render_markdown_block(prefix string, depth int, list_variant int, preserve_blank_lines bool) string {
	match node {
		BlankLinesNode { return '' }
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
		FootnoteDefinitionNode {
			body := render_inline_markdown(node.children)
			marker := markdown_footnote_label(node.label) + ':'
			return if body.len > 0 { marker + ' ' + body.replace('\n', '\n  ') } else { marker }
		}
		AdmonitionNode {
			return render_quoted_markdown(node.children, depth, ['> [!${node.kind.str().to_upper()}]'], preserve_blank_lines)
		}
		BlockquoteNode {
			return render_quoted_markdown(node.children, depth, [], preserve_blank_lines)
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
				item_lines := item.render_markdown_item(depth + 1, preserve_blank_lines)
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
			if preserve_blank_lines && node.html.ends_with('\n') {
				return node.html[..node.html.len - 1]
			}
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
	return render_inline_markdown_depth(nodes, 0, true).replace('\n', '<br>')
}

fn (item ListItemNode) render_markdown_item(depth int, preserve_blank_lines bool) []string {
	if preserve_blank_lines || has_explicit_blank_lines(item.children) {
		return render_preserved_markdown_lines(item.children, depth)
	}

	mut lines := []string{}
	for child_index, child in item.children {
		rendered := child.render_markdown_block('', depth, list_run_variant(item.children, child_index), false)
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

fn render_inline_markdown(nodes []InlineNode) string {
	return render_inline_markdown_depth(nodes, 0, false)
}

fn render_inline_markdown_depth(nodes []InlineNode, emphasis_depth int, in_table_cell bool) string {
	mut sb := strings.new_builder(64)
	for node in nodes {
		sb.write_string(node.render_markdown_inline(emphasis_depth, in_table_cell))
	}
	return sb.str()
}

fn (node InlineNode) render_markdown_inline(emphasis_depth int, in_table_cell bool) string {
	match node {
		TextNode {
			return escape_table_pipes(escape_markdown_inline_text(node.text, in_table_cell), in_table_cell)
		}
		EmphasisNode {
			marker := if emphasis_depth % 2 == 0 { '*' } else { '_' }
			return marker + render_inline_markdown_depth(node.children, emphasis_depth + 1, in_table_cell) + marker
		}
		StrongNode {
			return '**' + render_inline_markdown_depth(node.children, emphasis_depth, in_table_cell) + '**'
		}
		StrikethroughNode {
			return '~~' + render_inline_markdown_depth(node.children, emphasis_depth, in_table_cell) + '~~'
		}
		InlineStyleNode {
			marker := node.kind.markdown_delimiter()
			return marker + render_inline_markdown_depth(node.children, emphasis_depth, in_table_cell) + marker
		}
		UnderlineNode {
			return '_' + render_inline_markdown_depth(node.children, emphasis_depth, in_table_cell) + '_'
		}
		CodeSpanNode {
			return markdown_code_span(node.text)
		}
		LatexMathNode {
			delimiter := if node.display { '\$\$' } else { '\$' }
			return delimiter + escape_table_pipes(node.content, in_table_cell) + delimiter
		}
		LinkNode {
			plain_text := render_inline_text(node.text)
			if node.url.len > 0 && plain_text == node.url && !node.url.contains_any(' <>\t\n') {
				return '<' + escape_table_pipes(node.url, in_table_cell) + '>'
			}
			label := render_inline_markdown_depth(node.text, emphasis_depth, in_table_cell)
			destination := escape_table_pipes(markdown_link_destination(node.url), in_table_cell)
			return '[' + label + '](' + destination + ')'
		}
		FootnoteReferenceNode {
			return markdown_footnote_label(node.label)
		}
		WikiLinkNode {
			target := markdown_wiki_target(node.target)
			label := render_inline_markdown_depth(node.text, emphasis_depth, in_table_cell)
			if render_inline_text(node.text) == node.target {
				return '[[' + target + ']]'
			}
			return '[[' + target + '|' + label + ']]'
		}
		ImageNode {
			label := render_inline_markdown_depth(node.alt, emphasis_depth, in_table_cell)
			destination := escape_table_pipes(markdown_link_destination(node.url), in_table_cell)
			return '![' + label + '](' + destination + ')'
		}
		SoftBreakNode {
			return '\n'
		}
		HardBreakNode {
			return '  \n'
		}
		RawHtmlInlineNode {
			return escape_table_pipes(node.html, in_table_cell)
		}
	}
}

fn (kind InlineStyleKind) markdown_delimiter() string {
	return match kind {
		.highlight { '==' }
		.insertion { '++' }
		.superscript { '^' }
		.subscript { '~' }
		.spoiler { '||' }
	}
}

fn escape_table_pipes(text string, in_table_cell bool) string {
	return if in_table_cell { text.replace('|', '\\|') } else { text }
}

fn markdown_footnote_label(label string) string {
	// The definition must use the same spelling as a reference in a table.
	escaped := label.replace('\\', '\\\\').replace('|', '\\|')
	return '[^' + if escaped.len <= max_footnote_label_bytes { escaped } else { label } + ']'
}

fn markdown_wiki_target(target string) string {
	return target.replace('\\', '\\\\').replace('|', '\\|').replace(']', '\\]')
}

fn escape_markdown_text(input string) string {
	return escape_markdown_inline_text(input, false)
}

fn escape_markdown_inline_text(input string, in_table_cell bool) string {
	mut escaped := strings.new_builder(input.len)
	for index, byte in input {
		if byte in [`\\`, `[`, `]`, `!`, `*`, `_`, `\``, `<`, `^`, `~`]
			|| ((byte in [`=`, `+`] || (byte == `|` && !in_table_cell)) && (index == 0 || index == input.len - 1
				|| input[index - 1] == byte || input[index + 1] == byte)) {
			escaped.write_u8(`\\`)
		}
		escaped.write_u8(byte)
	}
	return escape_markdown_block_start(escaped.str())
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

fn render_quoted_markdown(children []BlockNode, depth int, initial_lines []string, preserve_blank_lines bool) string {
	mut lines := initial_lines.clone()
	if preserve_blank_lines || has_explicit_blank_lines(children) {
		for line in render_preserved_markdown_lines(children, depth) {
			lines << if line.len > 0 { '> ' + line } else { '>' }
		}
		return if lines.len == 0 { '>' } else { lines.join('\n') }
	}
	for child_index, child in children {
		rendered := child.render_markdown_block('', depth, list_run_variant(children, child_index), false)
		if rendered.len == 0 {
			continue
		}
		if child_index > 0 && lines.len > 0 {
			lines << '>'
		}
		for line in rendered.split_into_lines() {
			lines << '> ' + line
		}
	}
	return if lines.len == 0 { '>' } else { lines.join('\n') }
}

fn render_preserved_markdown_lines(children []BlockNode, depth int) []string {
	mut lines := []string{}
	for index, child in children {
		if child is BlankLinesNode {
			lines << []string{len: child.line_count}
			continue
		}
		rendered := child.render_markdown_block('', depth, list_run_variant(children, index), true)
		if rendered.len > 0 {
			lines << rendered.split('\n')
		}
	}
	return lines
}
