module vmarkdown

fn test_render_html() {
	html := render_html('# Title\n\nParagraph with [link](https://example.com).\n') or {
		panic(err)
	}
	assert html.contains('<h1>Title</h1>')
	assert html.contains('<p>Paragraph with <a href="https://example.com">link</a>.</p>')
}

fn test_render_text() {
	text := render_text('# Title\n\n- alpha\n- beta\n\n`code`\n') or { panic(err) }
	assert text.contains('Title')
	assert text.contains('- alpha')
	assert text.contains('- beta')
	assert text.contains('code')
}

fn test_render_json() {
	json := render_json('# Title\n\nParagraph.\n') or { panic(err) }
	assert json.contains('"type":"document"')
	assert json.contains('"type":"heading"')
	assert json.contains('"level":1')
	assert json.contains('"type":"paragraph"')
	assert json.contains('"text":"Title"')
}

fn test_render_markdown() {
	markdown := render_markdown('# Title\nParagraph with **strong** text.\n\n- alpha\n- beta\n\n```v\nprintln("ok")\n```\n') or {
		panic(err)
	}
	assert markdown.contains('# Title')
	assert markdown.contains('Paragraph with **strong** text.')
	assert markdown.contains('- alpha')
	assert markdown.contains('- beta')
	assert markdown.contains('```v')
	assert markdown.contains('println("ok")')
}

fn test_document_to_markdown() {
	doc := parse('# Title\n\n> quote\n') or { panic(err) }
	markdown := doc.to_markdown()
	assert markdown.contains('# Title')
	assert markdown.contains('> quote')
}

fn test_render_markdown_uses_safe_code_span_delimiter() {
	doc := Document{
		children: [BlockNode(ParagraphNode{
			children: [InlineNode(CodeSpanNode{
				text: 'a`b'
			})]
		})]
	}
	assert doc.to_markdown() == '``a`b``'
}

fn test_render_markdown_wraps_complex_link_destinations() {
	doc := Document{
		children: [BlockNode(ParagraphNode{
			children: [InlineNode(LinkNode{
				text: [InlineNode(TextNode{
					text: 'docs'
				})]
				url: 'https://example.com/a(b c)'
			})]
		})]
	}
	assert doc.to_markdown() == '[docs](<https://example.com/a(b c)>)'
}

fn test_render_markdown_keeps_nested_list_structure_valid() {
	doc := parse('- parent\n  - child\n') or { panic(err) }
	markdown := doc.to_markdown()
	assert markdown.contains('- parent')
	assert markdown.contains('\n  - child')
	assert !markdown.contains('- - child')
}

fn test_render_markdown_keeps_blockquote_nested_list_structure_valid() {
	doc := parse('> quoted\n> - child\n') or { panic(err) }
	markdown := doc.to_markdown()
	assert markdown.contains('> quoted')
	assert markdown.contains('> - child')
}

fn test_render_markdown_handles_mixed_blocks_in_list_item() {
	doc := parse('- parent\n\n  next para\n\n  ```v\n  println("hi")\n  ```\n') or { panic(err) }
	markdown := doc.to_markdown()
	assert markdown.contains('- parent')
	assert markdown.contains('  next para')
	assert markdown.contains('  ```v')
	assert markdown.contains('  println("hi")')
}

fn test_render_markdown_preserves_ordered_list_start() {
	doc := parse('3. third\n4. fourth\n') or { panic(err) }
	markdown := doc.to_markdown()
	assert markdown.contains('3. third')
	assert markdown.contains('4. fourth')
}

fn test_render_markdown_handles_complex_image_alt_and_url() {
	doc := Document{
		children: [BlockNode(ParagraphNode{
			children: [InlineNode(ImageNode{
				alt: [
					InlineNode(TextNode{text: 'see '}),
					InlineNode(StrongNode{
						children: [InlineNode(TextNode{text: 'diagram'})]
					}),
					InlineNode(TextNode{text: ' `v1`'})
				]
				url: 'https://example.com/a(b c).png'
			})]
		})]
	}
	markdown := doc.to_markdown()
	assert markdown.contains('![see **diagram** ')
	assert markdown.contains('\\`v1\\`')
	assert markdown.contains('(<https://example.com/a(b c).png>)')
}

fn test_render_markdown_handles_multilevel_nested_lists() {
	doc := parse('- root\n  - child\n    - grandchild\n') or { panic(err) }
	markdown := doc.to_markdown()
	assert markdown.contains('- root')
	assert markdown.contains('\n  - child')
	assert markdown.contains('\n    - grandchild')
}
