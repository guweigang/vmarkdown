module vmarkdown

import net.html as vhtml
import strings

pub fn html_to_markdown(input string) !string {
	wrapped := '<vmarkdown-root>${input}</vmarkdown-root>'
	doc := vhtml.parse(wrapped)
	root := html_render_root(doc)
	return html_tag_to_markdown(root, .block).trim_space()
}

enum HtmlRenderMode {
	block
	inline
}

fn html_render_root(doc vhtml.DocumentObjectModel) &vhtml.Tag {
	root := doc.get_root()
	if isnil(root) {
		return &vhtml.Tag{}
	}
	if root.name == 'vmarkdown-root' {
		return root
	}
	if wrapped := root.get_tag('vmarkdown-root') {
		return wrapped
	}
	if body := root.get_tag('body') {
		return body
	}
	return root
}

fn html_tag_to_markdown(tag &vhtml.Tag, mode HtmlRenderMode) string {
	if isnil(tag) {
		return ''
	}
	match tag.name {
		'text' {
			return if mode == .inline {
				html_inline_children(tag)
			} else {
				tag.text().trim_space()
			}
		}
		'body', 'html', 'div', 'article', 'section', 'main' {
			return html_render_children(tag.children, .block)
		}
		'p' {
			return html_inline_content(tag).trim_space()
		}
		'h1', 'h2', 'h3', 'h4', 'h5', 'h6' {
			level := tag.name[1..].int()
			return '${'#'.repeat(level)} ${html_inline_content(tag).trim_space()}'
		}
		'blockquote' {
			content := html_render_children(tag.children, .block)
			mut lines := []string{}
			for line in content.split_into_lines() {
				if line.len == 0 {
					lines << '>'
				} else {
					lines << '> ${line}'
				}
			}
			return lines.join('\n')
		}
		'ul' {
			return html_list_to_markdown(tag, false)
		}
		'ol' {
			return html_list_to_markdown(tag, true)
		}
		'li' {
			return html_list_item_to_markdown(tag)
		}
		'pre' {
			code_child := tag.get_tag('code') or { unsafe { nil } }
			if !isnil(code_child) {
				lang := html_code_lang(code_child)
				content := html_entity_decode(code_child.text()).trim_right('\n')
				fence := markdown_fence(content)
				if lang.len > 0 {
					return '${fence}${lang}\n${content}\n${fence}'
				}
				return '${fence}\n${content}\n${fence}'
			}
			content := html_entity_decode(tag.text()).trim_right('\n')
			fence := markdown_fence(content)
			return '${fence}\n${content}\n${fence}'
		}
		'code' {
			return markdown_code_span(html_entity_decode(tag.text()))
		}
		'hr' {
			return '---'
		}
		'br' {
			return if mode == .inline { '  \n' } else { '\n' }
		}
		'a' {
			href := html_entity_decode(tag.attributes['href'])
			text := html_inline_content(tag)
			return '[${text}](${markdown_link_destination(href)})'
		}
		'img' {
			src := html_entity_decode(tag.attributes['src'])
			alt := html_entity_decode(tag.attributes['alt'])
			return '![${escape_markdown_text(alt)}](${markdown_link_destination(src)})'
		}
		'strong', 'b' {
			return '**${html_inline_content(tag)}**'
		}
		'em', 'i' {
			return '*${html_inline_content(tag)}*'
		}
		'span' {
			return if mode == .inline {
				html_inline_content(tag)
			} else {
				html_render_children(tag.children, .block)
			}
		}
		else {
			return if mode == .inline {
				html_inline_content(tag)
			} else {
				html_render_children(tag.children, .block)
			}
		}
	}
}

fn html_render_children(children []&vhtml.Tag, mode HtmlRenderMode) string {
	if mode == .inline {
		mut sb := strings.new_builder(64)
		for child in children {
			sb.write_string(html_tag_to_markdown(child, .inline))
		}
		return sb.str()
	}
	mut parts := []string{}
	for child in children {
		rendered := html_tag_to_markdown(child, .block).trim_space()
		if rendered.len > 0 {
			parts << rendered
		}
	}
	return parts.join('\n\n')
}

fn html_inline_content(tag &vhtml.Tag) string {
	mut sb := strings.new_builder(tag.content.len + 32)
	if tag.children.len == 0 {
		return escape_markdown_text(html_entity_decode(tag.content))
	}
	mut cursor := 0
	for child in tag.children {
		marker := html_child_source_marker(child)
		if marker.len > 0 {
			if relative_index := tag.content[cursor..].index(marker) {
				child_start := cursor + relative_index
				sb.write_string(html_inline_text_segment(tag.content[cursor..child_start]))
				sb.write_string(html_tag_to_markdown(child, .inline))
				cursor = child_start + marker.len
				continue
			}
		}
		sb.write_string(html_tag_to_markdown(child, .inline))
	}
	sb.write_string(html_inline_text_segment(tag.content[cursor..]))
	return sb.str()
}

fn html_inline_children(tag &vhtml.Tag) string {
	return escape_markdown_text(html_entity_decode(tag.text()))
}

fn html_child_source_marker(tag &vhtml.Tag) string {
	source := tag.str()
	if tag.name in ['br', 'hr', 'img'] {
		if end := source.index('>') {
			return source[..end + 1]
		}
	}
	return source
}

fn html_inline_text_segment(input string) string {
	cleaned := input.replace('</br>', '').replace('</hr>', '').replace('</img>', '')
	return escape_markdown_text(html_entity_decode(cleaned))
}

fn html_list_to_markdown(tag &vhtml.Tag, ordered bool) string {
	start := tag.attributes['start'].int()
	base := if ordered && start > 0 { start } else { 1 }
	mut lines := []string{}
	mut item_index := 0
	for child in tag.children {
		if child.name != 'li' {
			continue
		}
		item_markdown := html_list_item_to_markdown(child)
		item_lines := item_markdown.split_into_lines()
		marker := if ordered { '${base + item_index}.' } else { '-' }
		prefix := '${marker} '
		indent := '  '
		if item_lines.len == 0 {
			lines << prefix.trim_right(' ')
			item_index++
			continue
		}
		for i, line in item_lines {
			if i == 0 {
				if line.len == 0 {
					lines << prefix.trim_right(' ')
				} else if html_first_child_is_list(child) {
					lines << prefix.trim_right(' ')
					lines << indent + line
				} else {
					lines << prefix + line
				}
			} else if line.len == 0 {
				lines << ''
			} else {
				lines << indent + line
			}
		}
		item_index++
	}
	return lines.join('\n')
}

fn html_first_child_is_list(tag &vhtml.Tag) bool {
	for child in tag.children {
		if child.name == 'text' && child.text().trim_space().len == 0 {
			continue
		}
		return child.name == 'ul' || child.name == 'ol'
	}
	return false
}

fn html_list_item_to_markdown(tag &vhtml.Tag) string {
	mut parts := []string{}
	if tag.content.trim_space().len > 0 {
		parts << escape_markdown_text(html_entity_decode(tag.content.trim_space()))
	}
	for child in tag.children {
		rendered := if child.name in ['ul', 'ol'] {
			html_tag_to_markdown(child, .block)
		} else if child.name in ['p', 'blockquote', 'pre', 'div'] {
			html_tag_to_markdown(child, .block)
		} else {
			html_tag_to_markdown(child, .inline)
		}
		if rendered.trim_space().len > 0 {
			parts << rendered.trim_space()
		}
	}
	return parts.join('\n\n')
}

fn html_code_lang(tag &vhtml.Tag) string {
	class_name := tag.attributes['class']
	if class_name.starts_with('language-') {
		return class_name.all_after('language-')
	}
	return ''
}

fn html_entity_decode(input string) string {
	mut out := input.replace('&quot;', '"')
		.replace('&#34;', '"')
		.replace('&#x22;', '"')
		.replace('&apos;', "'")
		.replace('&#39;', "'")
		.replace('&#x27;', "'")
		.replace('&lt;', '<')
		.replace('&#60;', '<')
		.replace('&#x3c;', '<')
		.replace('&gt;', '>')
		.replace('&#62;', '>')
		.replace('&#x3e;', '>')
		.replace('&amp;', '&')
		.replace('&#38;', '&')
		.replace('&#x26;', '&')
	return out.replace('&nbsp;', ' ')
		.replace('&#160;', ' ')
		.replace('&#xA0;', ' ')
}
