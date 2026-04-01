module vmarkdown

import term
import strings

pub struct TerminalRenderOptions {
pub:
	width int
	color bool = true
}

struct TerminalStyle {
	name string
}

struct TerminalSpan {
	plain string
	styled string
}

pub fn render_terminal(markdown string) !string {
	return render_terminal_with_options(markdown, TerminalRenderOptions{})
}

pub fn render_terminal_with_options(markdown string, options TerminalRenderOptions) !string {
	return parse(markdown)!.to_terminal_with_options(options)
}

@[inline]
pub fn (doc Document) to_terminal() string {
	return doc.to_terminal_with_options(TerminalRenderOptions{})
}

pub fn (doc Document) to_terminal_with_options(options TerminalRenderOptions) string {
	width := terminal_width(options)
	color := options.color && term.can_show_color_on_stdout()
	mut ctx := TerminalRenderer{
		width: width
		color: color
	}
	return ctx.render_document(doc)
}

struct TerminalRenderer {
	width int
	color bool
}

fn terminal_width(options TerminalRenderOptions) int {
	if options.width > 0 {
		return options.width
	}
	cols, _ := term.get_terminal_size()
	return if cols > 20 { cols } else { 80 }
}

fn (r TerminalRenderer) render_document(doc Document) string {
	mut blocks := []string{}
	for child in doc.children {
		rendered := r.render_block(child, '', 0)
		if rendered.len > 0 {
			blocks << rendered
		}
	}
	return blocks.join('\n\n')
}

fn (r TerminalRenderer) render_block(node BlockNode, prefix string, depth int) string {
	match node {
		HeadingNode {
			text := r.render_inline_plain(node.children)
			return r.render_heading(text, node.level)
		}
		ParagraphNode {
			return r.render_wrapped_inline(node.children, prefix)
		}
		BlockquoteNode {
			mut parts := []string{}
			for child in node.children {
				rendered := r.render_block(child, '', depth + 1)
				if rendered.len == 0 {
					continue
				}
				for line in rendered.split_into_lines() {
					parts << r.style_line('▎ ', TerminalStyle{'quote_bar'}) + line
				}
			}
			return parts.join('\n')
		}
		ListNode {
			mut lines := []string{}
			for i, item in node.items {
				marker := if node.is_ordered { '${node.start + i}.' } else { '•' }
				item_prefix := prefix + r.style_line(marker, TerminalStyle{'bullet'}) + ' '
				body_prefix := prefix + '  '
				item_lines := r.render_list_item(item, body_prefix, depth + 1)
				if item_lines.len == 0 {
					lines << item_prefix
					continue
				}
				for line_index, line in item_lines {
					if line_index == 0 {
						lines << item_prefix + line
					} else {
						lines << body_prefix + line
					}
				}
			}
			return lines.join('\n')
		}
		CodeBlockNode {
			return r.render_code_block(node)
		}
		HorizontalRuleNode {
			return r.style_line('─'.repeat(min_int(r.width, 48)), TerminalStyle{'rule'})
		}
		MetaNode {
			mut keys := node.data.keys()
			keys.sort()
			mut lines := []string{}
			for key in keys {
				lines << r.style_line(key + ':', TerminalStyle{'meta_key'}) + ' ' + node.data[key]
			}
			return lines.join('\n')
		}
	}
}

fn (r TerminalRenderer) render_heading(text string, level int) string {
	match level {
		1 {
			title := r.style_line(text, TerminalStyle{'heading1'})
			rule := r.style_line('━'.repeat(min_int(max_int(text.len, 12), min_int(r.width, 40))),
				TerminalStyle{'heading1_rule'})
			return '${title}\n${rule}'
		}
		2 {
			title := r.style_line(text, TerminalStyle{'heading2'})
			rule := r.style_line('─'.repeat(min_int(max_int(text.len, 10), min_int(r.width, 32))),
				TerminalStyle{'heading2_rule'})
			return '${title}\n${rule}'
		}
		else {
			mut lines := r.wrap_plain(text, r.width)
			for i, line in lines {
				lines[i] = r.style_line(line, TerminalStyle{'heading'})
			}
			return lines.join('\n')
		}
	}
}

fn (r TerminalRenderer) render_list_item(item ListItemNode, prefix string, depth int) []string {
	mut out := []string{}
	for child_index, child in item.children {
		rendered := r.render_block(child, '', depth)
		if rendered.len == 0 {
			continue
		}
		if child_index > 0 && out.len > 0 {
			out << ''
		}
		for line in rendered.split_into_lines() {
			out << line
		}
	}
	return out
}

fn (r TerminalRenderer) render_code_block(node CodeBlockNode) string {
	code_lines := normalize_code(node.content).trim_right('\n').split_into_lines()
	mut max_content_width := 0
	for line in code_lines {
		max_content_width = max_int(max_content_width, display_width(line))
	}
	content_width := min_int(max_int(max_content_width, 18), max_int(r.width - 6, 18))
	frame_width := content_width + 2
	label := if node.lang.len > 0 { ' ${node.lang} ' } else { '' }
	top_fill := '─'.repeat(max_int(frame_width - display_width(label), 0))
	mut lines := [r.style_line('╭' + label + top_fill + '╮', TerminalStyle{'code_border'})]
	for line in code_lines {
		content := truncate_display_width(line, content_width)
		padding := ' '.repeat(max_int(content_width - display_width(content), 0))
		lines << r.style_line('│ ', TerminalStyle{'code_border'}) +
			r.style_line(content, TerminalStyle{'code'}) + padding + r.style_line(' │',
			TerminalStyle{'code_border'})
	}
	lines << r.style_line('╰' + '─'.repeat(frame_width) + '╯', TerminalStyle{'code_border'})
	return lines.join('\n')
}

fn (r TerminalRenderer) render_wrapped_inline(nodes []InlineNode, prefix string) string {
	spans := r.inline_spans(nodes)
	lines := r.wrap_spans(spans, max_int(r.width - prefix.len, 20))
	mut rendered := []string{}
	for line in lines {
		rendered << prefix + line
	}
	return rendered.join('\n')
}

fn (r TerminalRenderer) render_inline_plain(nodes []InlineNode) string {
	mut sb := strings.new_builder(64)
	for span in r.inline_spans(nodes) {
		sb.write_string(span.plain)
	}
	return sb.str()
}

fn (r TerminalRenderer) inline_spans(nodes []InlineNode) []TerminalSpan {
	mut spans := []TerminalSpan{}
	for node in nodes {
		match node {
			TextNode {
				for token in split_text_tokens(node.text) {
					spans << TerminalSpan{
						plain: token
						styled: token
					}
				}
			}
			EmphasisNode {
				for span in r.inline_spans(node.children) {
					spans << TerminalSpan{
						plain: span.plain
						styled: r.style_line(span.styled, TerminalStyle{'emphasis'})
					}
				}
			}
			StrongNode {
				for span in r.inline_spans(node.children) {
					spans << TerminalSpan{
						plain: span.plain
						styled: r.style_line(span.styled, TerminalStyle{'strong'})
					}
				}
			}
			CodeSpanNode {
				text := node.text
				spans << TerminalSpan{
					plain: text
					styled: r.style_line(' ${text} ', TerminalStyle{'codespan'})
				}
			}
			LinkNode {
				label := r.render_inline_plain(node.text)
				display := if node.url.len > 0 { '${label} ↗ ${node.url}' } else { label }
				spans << TerminalSpan{
					plain: display
					styled: r.style_line(display, TerminalStyle{'link'})
				}
			}
			ImageNode {
				alt := r.render_inline_plain(node.alt)
				display := if alt.len > 0 {
					'▣ image: ${alt}'
				} else {
					'▣ image'
				}
				spans << TerminalSpan{
					plain: display
					styled: r.style_line(display, TerminalStyle{'image'})
				}
			}
		}
	}
	return merge_terminal_spaces(spans)
}

fn merge_terminal_spaces(spans []TerminalSpan) []TerminalSpan {
	mut merged := []TerminalSpan{}
	for span in spans {
		if span.plain.len == 0 {
			continue
		}
		if merged.len > 0 && is_space_only(merged[merged.len - 1].plain) && is_space_only(span.plain) {
			continue
		}
		merged << span
	}
	return merged
}

fn split_text_tokens(input string) []string {
	mut tokens := []string{}
	mut current := strings.new_builder(input.len)
	mut in_space := false
	for ch in input {
		space := ch == ` ` || ch == `\n` || ch == `\t` || ch == `\r`
		if current.len == 0 {
			in_space = space
			current.write_u8(ch)
			continue
		}
		if space == in_space {
			current.write_u8(ch)
		} else {
			tokens << current.str()
			current = strings.new_builder(input.len)
			current.write_u8(ch)
			in_space = space
		}
	}
	if current.len > 0 {
		tokens << current.str()
	}
	return tokens
}

fn (r TerminalRenderer) wrap_plain(input string, width int) []string {
	if width <= 0 || input.len <= width {
		return [input]
	}
	return wrap_terminal_lines([TerminalSpan{
		plain: input
		styled: input
	}], width)
}

fn (r TerminalRenderer) wrap_spans(spans []TerminalSpan, width int) []string {
	return wrap_terminal_lines(spans, width)
}

fn wrap_terminal_lines(spans []TerminalSpan, width int) []string {
	mut lines := []string{}
	mut current_plain := 0
	mut current := strings.new_builder(128)
	for span in spans {
		if span.plain == '\n' {
			lines << current.str().trim_right(' ')
			current = strings.new_builder(128)
			current_plain = 0
			continue
		}
		token_plain := span.plain.replace('\n', ' ')
		token_styled := span.styled.replace('\n', ' ')
		if token_plain.len > width && !is_space_only(token_plain) {
			if current_plain > 0 {
				lines << current.str().trim_right(' ')
				current = strings.new_builder(128)
				current_plain = 0
			}
			for chunk in chunk_string(token_plain, width) {
				lines << chunk
			}
			continue
		}
		if current_plain > 0 && current_plain + token_plain.len > width && !is_space_only(token_plain) {
			lines << current.str().trim_right(' ')
			current = strings.new_builder(128)
			current_plain = 0
		}
		if current_plain == 0 && is_space_only(token_plain) {
			continue
		}
		current.write_string(token_styled)
		current_plain += token_plain.len
	}
	if current.len > 0 {
		lines << current.str().trim_right(' ')
	}
	if lines.len == 0 {
		return ['']
	}
	return lines
}

fn chunk_string(input string, width int) []string {
	if width <= 0 || display_width(input) <= width {
		return [input]
	}
	mut chunks := []string{}
	mut rest := input
	for display_width(rest) > width {
		chunk := truncate_display_width(rest, width)
		chunks << chunk
		rest = rest[chunk.len..]
	}
	chunks << rest
	return chunks
}

fn display_width(input string) int {
	return input.runes().len
}

fn truncate_display_width(input string, width int) string {
	if width <= 0 {
		return ''
	}
	mut out := []rune{}
	for r in input.runes() {
		if out.len >= width {
			break
		}
		out << r
	}
	return out.string()
}

fn is_space_only(input string) bool {
	return input.trim_space().len == 0
}

fn min_int(a int, b int) int {
	return if a < b { a } else { b }
}

fn max_int(a int, b int) int {
	return if a > b { a } else { b }
}

fn (r TerminalRenderer) style_line(input string, style TerminalStyle) string {
	if !r.color {
		return input
	}
	return match style.name {
		'heading1' { term.bold(term.hex(0xe6b450, input)) }
		'heading1_rule' { term.hex(0xe6b450, input) }
		'heading2' { term.bold(term.hex(0x59c2ff, input)) }
		'heading2_rule' { term.hex(0x59c2ff, input) }
		'heading' { term.bold(term.bright_white(input)) }
		'bullet' { term.bright_magenta(input) }
		'quote_bar' { term.hex(0x7dcfff, input) }
		'code_border' { term.bright_black(input) }
		'code' { term.hex(0xa6da95, input) }
		'codespan' { term.bg_rgb(42, 42, 48, term.hex(0xf5a97f, input)) }
		'strong' { term.bold(input) }
		'emphasis' { term.italic(term.hex(0xc6a0f6, input)) }
		'link' { term.underline(term.cyan(input)) }
		'image' { term.dim(term.hex(0xf4a261, input)) }
		'rule' { term.bright_black(input) }
		'meta_key' { term.bold(term.bright_cyan(input)) }
		else { input }
	}
}
