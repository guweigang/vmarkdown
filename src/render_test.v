module vmarkdown

fn test_render_html() {
	html := render_html('# Title\n\nParagraph with [link](https://example.com).\n') or {
		panic(err)
	}
	assert html.contains('<h1>Title</h1>')
	assert html.contains('<p>Paragraph with <a href="https://example.com">link</a>.</p>')
}

fn test_render_html_enforces_input_contract() {
	for input, expected_offset in {
		[u8(0xff), u8(`a`)].bytestr():   0
		[u8(`a`), 0xe2, 0x82].bytestr(): 1
	} {
		if _ := render_html(input) {
			assert false, 'invalid UTF-8 Markdown must fail HTML rendering'
		} else {
			assert err is HtmlRenderError
			render_error := err as HtmlRenderError
			assert render_error.kind == .invalid_utf8
			assert render_error.offset == expected_offset
			assert render_error.native_code == 0
		}
	}

	if _ := render_html_with_limits('12345', HtmlRenderOptions{}, HtmlRenderLimits{
		max_input_bytes: 4
	}) {
		assert false, 'oversized Markdown must fail HTML rendering'
	} else {
		assert err is HtmlRenderError
		assert (err as HtmlRenderError).kind == .input_limit
	}
}

fn test_render_html_enforces_output_contract() {
	if _ := render_html_with_limits('<>&', HtmlRenderOptions{}, HtmlRenderLimits{
		max_output_bytes: 8
	}) {
		assert false, 'oversized HTML output must fail'
	} else {
		assert err is HtmlRenderError
		render_error := err as HtmlRenderError
		assert render_error.kind == .output_limit
		assert render_error.message.contains('8 bytes')
	}

	html := render_html_with_limits('<>&', HtmlRenderOptions{}, HtmlRenderLimits{
		max_output_bytes: 64
	}) or { panic(err) }
	assert html == '<p>&lt;&gt;&amp;</p>\n'
}

fn test_render_html_rejects_negative_limits() {
	for limits in [
		HtmlRenderLimits{ max_input_bytes: -1 },
		HtmlRenderLimits{ max_output_bytes: -1 },
	] {
		if _ := render_html_with_limits('text', HtmlRenderOptions{}, limits) {
			assert false, 'negative HTML render limits must fail'
		} else {
			assert err is HtmlRenderError
			assert (err as HtmlRenderError).kind == .invalid_limits
		}
	}
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

fn test_one_shot_renderers_accept_parser_options() {
	options := ParseOptions{
		wiki_links: true
		latex_math: true
		underline: true
	}
	input := r'[[docs|Guide]] $x^2$ _underlined_'
	assert render_text_with_options(input, options) or { panic(err) } == 'Guide x^2 underlined'
	json := render_json_with_options(input, options) or { panic(err) }
	assert json.contains('"type":"wiki_link"')
	assert json.contains('"type":"latex_math"')
	assert json.contains('"type":"underline"')
	assert render_markdown_with_options(input, options) or { panic(err) } == input
}

fn test_one_shot_renderers_accept_parse_limits() {
	limits := ParseLimits{
		max_input_bytes: 64
		max_nodes: 8
		max_nesting_depth: 4
	}
	assert render_text_with_limits('text', ParseOptions{}, limits) or { panic(err) } == 'text'
	assert render_json_with_limits('text', ParseOptions{}, limits) or { panic(err) }.contains('"text":"text"')
	assert render_markdown_with_limits('text', ParseOptions{}, limits) or { panic(err) } == 'text'
	assert render_terminal_with_limits('text', TerminalRenderOptions{
		width: 40
		color: false
	}, limits) or { panic(err) } == 'text'

	for kind in ['text', 'json', 'markdown', 'terminal'] {
		if kind == 'text' {
			render_text_with_limits('text', ParseOptions{}, ParseLimits{ max_nodes: 2 }) or {
				assert (err as MarkdownParseError).kind == .resource_limit
				continue
			}
		} else if kind == 'json' {
			render_json_with_limits('text', ParseOptions{}, ParseLimits{ max_nodes: 2 }) or {
				assert (err as MarkdownParseError).kind == .resource_limit
				continue
			}
		} else if kind == 'markdown' {
			render_markdown_with_limits('text', ParseOptions{}, ParseLimits{ max_nodes: 2 }) or {
				assert (err as MarkdownParseError).kind == .resource_limit
				continue
			}
		} else {
			render_terminal_with_limits('text', TerminalRenderOptions{}, ParseLimits{ max_nodes: 2 }) or {
				assert (err as MarkdownParseError).kind == .resource_limit
				continue
			}
		}
		assert false, '${kind} renderer must enforce parse limits'
	}
}

fn test_render_table_text_json_and_markdown() {
	input := '| Name | Value |\n| :--- | ---: |\n| **alpha** | 10 |\n'
	doc := parse(input) or { panic(err) }
	assert doc.to_text() == 'Name\tValue\nalpha\t10'
	json := doc.to_json()
	assert json.contains('"type":"table"')
	assert json.contains('"alignment":"left"')
	assert json.contains('"alignment":"right"')
	markdown := doc.to_markdown()
	assert markdown.contains('| Name | Value |')
	assert markdown.contains('| :--- | ---: |')
	assert markdown.contains('| **alpha** | 10 |')
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

fn test_checked_document_renderers_match_trusted_fast_paths() {
	doc := parse('# Title\n\ntext') or { panic(err) }
	assert doc.to_text_checked() or { panic(err) } == doc.to_text()
	assert doc.to_json_checked() or { panic(err) } == doc.to_json()
	assert doc.to_markdown_checked() or { panic(err) } == doc.to_markdown()
	limits := AstValidationLimits{
		max_nodes: 8
		max_nesting_depth: 4
	}
	assert doc.to_text_checked_with_limits(limits) or { panic(err) } == doc.to_text()
	assert doc.to_json_checked_with_limits(limits) or { panic(err) } == doc.to_json()
	assert doc.to_markdown_checked_with_limits(limits) or { panic(err) } == doc.to_markdown()
	assert doc.to_terminal_checked() or { panic(err) } == doc.to_terminal()
	options := TerminalRenderOptions{
		width: 40
		color: false
	}
	assert doc.to_terminal_checked_with_options(options) or {
		panic(err)
	} == doc.to_terminal_with_options(options)
	assert doc.to_terminal_checked_with_limits(options, limits) or {
		panic(err)
	} == doc.to_terminal_with_options(options)
}

fn test_checked_document_renderers_enforce_validation_limits() {
	doc := parse('text') or { panic(err) }
	limits := AstValidationLimits{ max_nodes: 2 }
	if _ := doc.to_text_checked_with_limits(limits) {
		assert false, 'checked text rendering must enforce validation limits'
	} else {
		assert (err as AstValidationError).kind == .validation_limit
	}
	if _ := doc.to_json_checked_with_limits(limits) {
		assert false, 'checked JSON rendering must enforce validation limits'
	} else {
		assert (err as AstValidationError).kind == .validation_limit
	}
	if _ := doc.to_markdown_checked_with_limits(limits) {
		assert false, 'checked Markdown rendering must enforce validation limits'
	} else {
		assert (err as AstValidationError).kind == .validation_limit
	}
	if _ := doc.to_terminal_checked_with_limits(TerminalRenderOptions{}, limits) {
		assert false, 'checked terminal rendering must enforce validation limits'
	} else {
		assert (err as AstValidationError).kind == .validation_limit
	}
	if _ := doc.to_text_checked_with_limits(AstValidationLimits{ max_nodes: -1 }) {
		assert false, 'checked renderers must reject negative validation limits'
	} else {
		assert (err as AstValidationError).kind == .invalid_limits
	}
}

fn test_checked_document_renderers_reject_invalid_ast() {
	invalid := Document{
		children: [BlockNode(HeadingNode{ level: 0 })]
	}
	if _ := invalid.to_text_checked() {
		assert false, 'checked text rendering must reject an invalid AST'
	} else {
		assert_checked_render_validation_error(err)
	}
	if _ := invalid.to_json_checked() {
		assert false, 'checked JSON rendering must reject an invalid AST'
	} else {
		assert_checked_render_validation_error(err)
	}
	if _ := invalid.to_markdown_checked() {
		assert false, 'checked Markdown rendering must reject an invalid AST'
	} else {
		assert_checked_render_validation_error(err)
	}
	if _ := invalid.to_terminal_checked() {
		assert false, 'checked terminal rendering must reject an invalid AST'
	} else {
		assert_checked_render_validation_error(err)
	}
}

fn assert_checked_render_validation_error(err IError) {
	assert err is AstValidationError
	validation := err as AstValidationError
	assert validation.kind == .heading_level
	assert validation.path == 'document.children[0].level'
}

fn test_render_markdown_uses_safe_code_span_delimiter() {
	doc := Document{
		children: [
			BlockNode(ParagraphNode{
				children: [InlineNode(CodeSpanNode{
					text: 'a`b'
				})]
			}),
		]
	}
	assert doc.to_markdown() == '``a`b``'
}

fn test_render_markdown_wraps_complex_link_destinations() {
	doc := Document{
		children: [
			BlockNode(ParagraphNode{
				children: [
					InlineNode(LinkNode{
						text: [InlineNode(TextNode{
							text: 'docs'
						})]
						url: 'https://example.com/a(b c)'
					}),
				]
			}),
		]
	}
	assert doc.to_markdown() == '[docs](<https://example.com/a(b c)>)'
}

fn test_render_markdown_preserves_backslashes_in_link_destinations() {
	doc := parse('<https://example.com?find=\\*>') or { panic(err) }
	reparsed := parse(doc.to_markdown()) or { panic(err) }
	assert doc.stable_id() == reparsed.stable_id()
}

fn test_render_wiki_link_text_json_and_normalized_markdown() {
	doc := parse_with_options('[[docs|**Guide**]] and [[plain]]', ParseOptions{
		wiki_links: true
	}) or { panic(err) }
	assert doc.to_text() == 'Guide and plain'
	assert doc.to_json().contains('"type":"wiki_link","target":"docs"')
	assert doc.to_markdown() == '[[docs|**Guide**]] and [[plain]]'
	reparsed := parse_with_options(doc.to_markdown(), ParseOptions{
		wiki_links: true
	}) or { panic(err) }
	assert reparsed.stable_id() == doc.stable_id()
}

fn test_render_wiki_link_escapes_target_delimiter() {
	doc := Document{
		children: [BlockNode(ParagraphNode{
			children: [InlineNode(WikiLinkNode{
				target: 'foo|bar'
				text: [InlineNode(TextNode{ text: 'label' })]
			})]
		})]
	}
	assert doc.to_markdown() == '[[foo\\|bar|label]]'
	reparsed := parse_with_options(doc.to_markdown(), ParseOptions{
		wiki_links: true
	}) or { panic(err) }
	assert reparsed.stable_id() == doc.stable_id()
}

fn test_render_table_preserves_wiki_link_delimiters() {
	input := '| A | B |\n| --- | --- |\n| [[foo|*bar*|baz]] | end |\n'
	doc := parse_with_options(input, ParseOptions{
		wiki_links: true
	}) or { panic(err) }
	markdown := doc.to_markdown()
	assert markdown.contains('[[foo|*bar*|baz]]')
	assert !markdown.contains(r'[[foo\|')
	reparsed := parse_with_options(markdown, ParseOptions{
		wiki_links: true
	}) or { panic(err) }
	assert reparsed.stable_id() == doc.stable_id()
}

fn test_render_latex_math_text_json_terminal_and_markdown() {
	input := r'$a+b=c$ and $$\int_a^b x dx$$'
	doc := parse_with_options(input, ParseOptions{
		latex_math: true
	}) or { panic(err) }
	assert doc.to_text() == r'a+b=c and \int_a^b x dx'
	json := doc.to_json()
	assert json.contains('"type":"latex_math","display":false,"content":"a+b=c"')
	assert json.contains('"display":true,"content":"\\\\int_a^b x dx"')
	assert doc.to_markdown() == input
	assert doc.to_terminal_with_options(TerminalRenderOptions{
		width: 80
		color: false
	}).contains(r'\int_a^b x dx')
	reparsed := parse_with_options(doc.to_markdown(), ParseOptions{
		latex_math: true
	}) or { panic(err) }
	assert reparsed.stable_id() == doc.stable_id()

	escaped_dollar := r'$price \$5$'
	escaped_doc := parse_with_options(escaped_dollar, ParseOptions{
		latex_math: true
	}) or { panic(err) }
	assert escaped_doc.to_markdown() == escaped_dollar
	escaped_reparsed := parse_with_options(escaped_doc.to_markdown(), ParseOptions{
		latex_math: true
	}) or { panic(err) }
	assert escaped_reparsed.stable_id() == escaped_doc.stable_id()
}

fn test_render_underline_text_json_terminal_and_markdown() {
	input := '_foo_ and ___bar___'
	doc := parse_with_options(input, ParseOptions{
		underline: true
	}) or { panic(err) }
	assert doc.to_text() == 'foo and bar'
	assert doc.to_json().contains('"type":"underline"')
	assert doc.to_markdown() == input
	assert doc.to_terminal_with_options(TerminalRenderOptions{
		width: 80
		color: false
	}) == 'foo and bar'
	reparsed := parse_with_options(doc.to_markdown(), ParseOptions{
		underline: true
	}) or { panic(err) }
	assert reparsed.stable_id() == doc.stable_id()
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
		children: [
			BlockNode(ParagraphNode{
				children: [
					InlineNode(ImageNode{
						alt: [
							InlineNode(TextNode{
								text: 'see '
							}),
							InlineNode(StrongNode{
								children: [
									InlineNode(TextNode{
										text: 'diagram'
									}),
								]
							}),
							InlineNode(TextNode{
								text: ' `v1`'
							}),
						]
						url: 'https://example.com/a(b c).png'
					}),
				]
			}),
		]
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

fn test_render_markdown_escapes_text_that_would_become_structure_or_html() {
	doc := Document{
		children: [BlockNode(ParagraphNode{
			children: [InlineNode(TextNode{
				text: '1. text <br> # heading'
			})]
		})]
	}
	assert doc.to_markdown() == '1\\. text \\<br> # heading'
	reparsed := parse(doc.to_markdown()) or { panic(err) }
	assert reparsed.children.len == 1
	assert reparsed.children[0] is ParagraphNode
}

fn test_renderers_preserve_new_core_ast_semantics() {
	doc := parse('- [x] done\n\n~~gone~~  \nnext <kbd>key</kbd>\n\n<div>raw</div>\n') or {
		panic(err)
	}
	markdown := doc.to_markdown()
	assert markdown.contains('- [x] done')
	assert markdown.contains('~~gone~~  \nnext <kbd>key</kbd>')
	assert markdown.contains('<div>raw</div>')
	json := doc.to_json()
	assert json.contains('"is_task":true,"checked":true')
	assert json.contains('"type":"strikethrough"')
	assert json.contains('"type":"hard_break"')
	assert json.contains('"type":"raw_html_inline"')
	assert json.contains('"type":"raw_html_block"')
}
