module vmarkdown

import term

fn test_one_shot_terminal_renderer_accepts_parser_options() {
	out := render_terminal_with_options('[[docs|Guide]]', TerminalRenderOptions{
		parser: ParseOptions{ wiki_links: true }
		width: 80
		color: false
	}) or { panic(err) }
	assert out == 'Guide ↗ docs'
}

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

fn test_render_terminal_table() {
	doc := parse('| Name | Value |\n| --- | ---: |\n| alpha | 10 |\n') or { panic(err) }
	out := doc.to_terminal_with_options(TerminalRenderOptions{
		width: 40
		color: false
	})
	assert out.contains('│ Name')
	assert out.contains('Value │')
	assert out.contains('├─')
	assert out.contains('│ alpha')
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
	doc := parse('```text\n├─ Heading(level=1) "PollyDB"\n│  └─ Paragraph "first item"\n└─ CodeBlock(lang="v") "println(\\"hi\\")\\\\n"\n```\n') or {
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
		children: [
			BlockNode(ParagraphNode{
				children: [
					InlineNode(LinkNode{
						text: [InlineNode(TextNode{
							text: 'docs'
						})]
						url: 'https://example.com'
					}),
					InlineNode(TextNode{
						text: ' '
					}),
					InlineNode(ImageNode{
						alt: [InlineNode(TextNode{
							text: 'diagram'
						})]
						url: 'https://example.com/image.png'
					}),
				]
			}),
		]
	}
	out := doc.to_terminal_with_options(TerminalRenderOptions{
		width: 80
		color: false
	})
	assert out.contains('docs ↗ https://example.com')
	assert out.contains('▣ image: diagram')
}

fn test_render_terminal_mermaid_code_block() {
	doc := parse('```mermaid\nflowchart TD\nA[Start] --> B[Parse]\n```\n') or { panic(err) }
	out := doc.to_terminal_with_options(TerminalRenderOptions{
		width: 48
		color: false
	})
	assert out.contains('◈ mermaid flowchart TD')
	assert out.contains('Start')
	assert out.contains('▼')
	assert out.contains('Parse')
}

fn test_render_terminal_mermaid_sequence_diagram() {
	doc := parse('```mermaid\nsequenceDiagram\nAlice->>Bob: hi\n```\n') or { panic(err) }
	out := doc.to_terminal_with_options(TerminalRenderOptions{
		width: 48
		color: false
	})
	assert out.contains('◈ mermaid sequenceDiagram')
	assert out.contains('Alice')
	assert out.contains('Bob')
	assert out.contains('hi')
}

fn test_render_terminal_mermaid_additional_diagrams() {
	doc := parse('```mermaid\nstateDiagram-v2\n[*] --> Idle\nIdle --> Running: start\n```\n\n```mermaid\nclassDiagram\nclass Animal {\n+name string\n}\nAnimal <|-- Dog : inherits\n```\n\n```mermaid\nerDiagram\nUSER {\nstring id\n}\nORDER {\nstring id\n}\nUSER ||--o{ ORDER : places\n```\n\n```mermaid\ngantt\ntitle Release Plan\nsection Build\nCompile :done, a1, 2026-04-01, 1d\n```\n') or {
		panic(err)
	}
	out := doc.to_terminal_with_options(TerminalRenderOptions{
		width: 72
		color: false
	})
	assert out.contains('◈ mermaid stateDiagram-v2')
	assert out.contains('◈ mermaid classDiagram')
	assert out.contains('◈ mermaid erDiagram')
	assert out.contains('◈ mermaid gantt')
	assert out.contains('Release Plan')
}

fn test_render_terminal_json_diagram_code_block() {
	doc := parse('```json diagram\n{\n  "version": 1,\n  "kind": "timeline",\n  "entries": [\n    { "point": "2024", "text": "Parser" },\n    { "point": "2025", "text": "Preview" }\n  ]\n}\n```\n') or {
		panic(err)
	}
	out := doc.to_terminal_with_options(TerminalRenderOptions{
		width: 48
		color: false
	})
	assert out.contains('◈ json diagram')
	assert out.contains('2024')
	assert out.contains('Parser')
	assert out.contains('2025')
	assert out.contains('Preview')
}

fn test_terminal_render_sanitizes_untrusted_control_sequences_by_default() {
	doc := Document{
		children: [
			BlockNode(ParagraphNode{
				children: [InlineNode(TextNode{
					text: 'safe\x1b]0;owned\a text'
				})]
			}),
			BlockNode(CodeBlockNode{
				lang: 'txt\x1b'
				content: 'line\x1b[2J\n'
			}),
			BlockNode(RawHtmlBlockNode{
				html: '<b>raw</b>\x1b[31m\n'
			}),
		]
	}
	rendered := doc.to_terminal_with_options(TerminalRenderOptions{
		width: 60
		color: false
	})
	assert !rendered.contains('\x1b')
	assert !rendered.contains('\a')
	assert rendered.contains('␛]0;owned␇')
	assert rendered.contains('line␛[2J')
	assert rendered.contains('<b>raw</b>␛[31m')
}

fn test_terminal_render_can_explicitly_preserve_control_sequences() {
	doc := Document{
		children: [BlockNode(ParagraphNode{
			children: [InlineNode(TextNode{
				text: 'raw\x1b[31m'
			})]
		})]
	}
	rendered := doc.to_terminal_with_options(TerminalRenderOptions{
		width: 60
		color: false
		sanitize_control_sequences: false
	})
	assert rendered.contains('\x1b[31m')
}

fn test_terminal_renders_task_state_breaks_and_raw_html() {
	doc := parse('- [x] done\n\n~~gone~~  \nnext <kbd>key</kbd>\n\n<div>raw</div>\n') or {
		panic(err)
	}
	out := doc.to_terminal_with_options(TerminalRenderOptions{
		width: 80
		color: false
	})
	assert out.contains('• [x] done')
	assert out.contains('gone\nnext <kbd>key</kbd>')
	assert out.contains('<div>raw</div>')
}
