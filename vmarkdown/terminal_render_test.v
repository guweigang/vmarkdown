module vmarkdown

import term

fn test_render_terminal_basic_blocks() {
	doc := parse('# Title\n\nParagraph with **strong** text.\n\n- alpha\n- beta\n') or {
		panic(err)
	}
	out := doc.to_terminal_with_options(TerminalRenderOptions{
		width: 40
		color: false
	})
	assert out.contains('Title')
	assert out.contains('━')
	assert out.contains('Paragraph with strong text.')
	assert out.contains('• alpha')
	assert out.contains('• beta')
}

fn test_render_terminal_code_and_quote() {
	doc := parse('> quoted line\n\n```v\nprintln("hi")\n```\n') or { panic(err) }
	out := doc.to_terminal_with_options(TerminalRenderOptions{
		width: 50
		color: false
	})
	assert out.contains('▎ quoted line')
	assert out.contains('╭ v ')
	assert out.contains('println("hi")')
	assert out.contains('╰')
}

fn test_render_terminal_code_block_frame_alignment() {
	doc := parse('```text\n├─ Heading(level=1) \"PollyDB\"\n│  └─ Paragraph \"first item\"\n└─ CodeBlock(lang=\"v\") \"println(\\\"hi\\\")\\\\n\"\n```\n') or {
		panic(err)
	}
	out := doc.to_terminal_with_options(TerminalRenderOptions{
		width: 50
		color: false
	})
	lines := out.split_into_lines()
	assert lines.len >= 3
	expected_width := term.strip_ansi(lines[0]).runes().len
	for i, line in lines {
		plain := term.strip_ansi(line)
		assert plain.runes().len == expected_width
		if i > 0 && i < lines.len - 1 {
			assert plain.ends_with(' │')
		}
	}
}

fn test_render_terminal_link_and_image_placeholders() {
	doc := Document{
		children: [BlockNode(ParagraphNode{
			children: [
				InlineNode(LinkNode{
					text: [InlineNode(TextNode{text: 'docs'})]
					url: 'https://example.com'
				}),
				InlineNode(TextNode{text: ' '}),
				InlineNode(ImageNode{
					alt: [InlineNode(TextNode{text: 'diagram'})]
					url: 'https://example.com/image.png'
				}),
			]
		})]
	}
	out := doc.to_terminal_with_options(TerminalRenderOptions{
		width: 80
		color: false
	})
	assert out.contains('docs ↗ https://example.com')
	assert out.contains('▣ image: diagram')
}
