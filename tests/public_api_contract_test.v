module main

import vmarkdown

fn test_public_parse_render_and_codec_contract() {
	options := vmarkdown.parse_options_for_dialect(.commonmark)
	doc := vmarkdown.parse_with_limits('# API\n\ntext', options, vmarkdown.ParseLimits{
		max_input_bytes: 1024
		max_nodes: 32
		max_nesting_depth: 16
	}) or { panic(err) }
	doc.validate() or { panic(err) }
	doc.validate_with_limits(vmarkdown.AstValidationLimits{
		max_nodes: 16
		max_nesting_depth: 8
	}) or { panic(err) }
	doc.children[0].validate_with_limits(vmarkdown.AstValidationLimits{
		max_nodes: 8
		max_nesting_depth: 4
	}) or { panic(err) }
	headings := doc.find_all(.heading)
	assert headings.len == 1
	assert headings[0].node is vmarkdown.HeadingNode
	heading := headings[0].node as vmarkdown.HeadingNode
	heading.children[0].validate_with_limits(vmarkdown.AstValidationLimits{
		max_nodes: 4
		max_nesting_depth: 2
	}) or { panic(err) }
	mut visited_paths := []string{}
	mut visited_paths_ref := &visited_paths
	assert doc.walk(fn [mut visited_paths_ref] (visit vmarkdown.AstVisit) bool {
		visited_paths_ref << visit.path
		return visit.kind != .hard_break
	})
	assert visited_paths.len > headings.len
	assert doc.walk_checked(fn (visit vmarkdown.AstVisit) bool {
		return visit.kind != .hard_break
	}) or { panic(err) }
	assert doc.find_all_checked_with_limits(.heading, vmarkdown.AstValidationLimits{
		max_nodes: 16
		max_nesting_depth: 8
	}) or { panic(err) }.len == 1
	rewritten := doc.rewrite_inlines(fn (visit vmarkdown.AstInlineRewrite) ![]vmarkdown.InlineNode {
		if visit.node is vmarkdown.TextNode && visit.node.text == 'API' {
			return [vmarkdown.InlineNode(vmarkdown.TextNode{ text: 'renamed' })]
		}
		return [visit.node]
	}) or { panic(err) }
	assert rewritten.to_markdown().starts_with('# renamed')
	assert doc.rewrite_blocks_with_limits(vmarkdown.AstValidationLimits{
		max_nodes: 16
		max_nesting_depth: 8
	}, fn (visit vmarkdown.AstBlockRewrite) ![]vmarkdown.BlockNode {
		return [visit.node]
	}) or { panic(err) }.stable_id() == doc.stable_id()
	diagnostics := doc.lint([vmarkdown.LintRule{
		id: 'contract.heading'
		severity: .info
		check: fn (visit vmarkdown.AstVisit) []vmarkdown.LintFinding {
			if visit.kind == .heading {
				return [vmarkdown.LintFinding{ message: 'heading found' }]
			}
			return []vmarkdown.LintFinding{}
		}
	}]) or { panic(err) }
	assert doc.lint_with_limits([]vmarkdown.LintRule{}, vmarkdown.AstValidationLimits{
		max_nodes: 16
		max_nesting_depth: 8
	}) or { panic(err) } == []vmarkdown.LintDiagnostic{}
	assert diagnostics.len == 1
	assert diagnostics[0].path == 'document.children[0]'
	assert vmarkdown.lint_markdown('# Good') or { panic(err) } == []vmarkdown.LintDiagnostic{}
	assert vmarkdown.recommended_lint_rules().len == 3
	fixed := vmarkdown.apply_markdown_edits('draft', [vmarkdown.MarkdownTextEdit{
		span: vmarkdown.SourceSpan{ start: 0, end: 5 }
		replacement: 'final'
	}]) or { panic(err) }
	assert fixed == 'final'
	index := vmarkdown.new_source_index('# API\n\n中文') or { panic(err) }
	position := index.position(7) or { panic(err) }
	assert position.line == 3
	assert position.column == 1
	assert position.byte_column == 1
	located := index.locate_diagnostics(diagnostics) or { panic(err) }
	assert located[0].has_range
	assert located[0].range.start.line == 1
	assert doc.to_text() == 'API\n\ntext'
	assert doc.to_text_checked() or { panic(err) } == doc.to_text()
	assert doc.to_json().contains('"type":"heading"')
	assert doc.to_json_checked() or { panic(err) } == doc.to_json()
	assert doc.to_markdown().starts_with('# API')
	assert doc.to_markdown_checked() or { panic(err) } == doc.to_markdown()
	assert doc.to_terminal_with_options(vmarkdown.TerminalRenderOptions{
		width: 80
		color: false
	}).contains('API')
	assert doc.to_terminal_checked_with_options(vmarkdown.TerminalRenderOptions{
		width: 80
		color: false
	}) or { panic(err) } == doc.to_terminal_with_options(vmarkdown.TerminalRenderOptions{
		width: 80
		color: false
	})
	parser_options := vmarkdown.ParseOptions{
		wiki_links: true
		latex_math: true
		underline: true
	}
	assert vmarkdown.render_text_with_options('[[docs|Guide]]', parser_options) or {
		panic(err)
	} == 'Guide'
	assert vmarkdown.render_json_with_options(r'$x$', parser_options) or {
		panic(err)
	}.contains('"type":"latex_math"')
	assert vmarkdown.render_markdown_with_options('_text_', parser_options) or {
		panic(err)
	} == '_text_'
	assert vmarkdown.render_text_with_limits('text', parser_options, vmarkdown.ParseLimits{
		max_input_bytes: 64
		max_nodes: 8
		max_nesting_depth: 4
	}) or { panic(err) } == 'text'
	assert vmarkdown.render_json_with_limits('text', parser_options, vmarkdown.ParseLimits{
		max_nodes: 8
	}) or { panic(err) }.contains('"type":"text"')
	assert vmarkdown.render_markdown_with_limits('text', parser_options, vmarkdown.ParseLimits{
		max_nodes: 8
	}) or { panic(err) } == 'text'
	assert vmarkdown.render_terminal_with_options('[[docs|Guide]]', vmarkdown.TerminalRenderOptions{
		parser: parser_options
		width: 80
		color: false
	}) or { panic(err) } == 'Guide ↗ docs'
	assert vmarkdown.render_terminal_with_limits('text', vmarkdown.TerminalRenderOptions{
		width: 80
		color: false
	}, vmarkdown.ParseLimits{ max_nodes: 8 }) or { panic(err) } == 'text'

	encoded := doc.binary_encode()
	checked_encoded := doc.binary_encode_checked() or { panic(err) }
	assert checked_encoded == encoded
	assert doc.binary_encode_checked_with_limits(vmarkdown.AstValidationLimits{
		max_nodes: 16
		max_nesting_depth: 8
	}) or { panic(err) } == encoded
	decoded := vmarkdown.binary_decode(encoded) or { panic(err) }
	assert decoded.stable_id() == doc.stable_id()
	assert decoded.encode() == encoded
	assert decoded.semantic_encode().len > 0
	limited := vmarkdown.binary_decode_with_limits(encoded, vmarkdown.BinaryDecodeLimits{
		max_input_bytes: 1024
		max_nodes: 32
		max_nesting_depth: 16
	}) or { panic(err) }
	assert limited.stable_id() == doc.stable_id()
	assert doc.stable_id_checked() or { panic(err) } == doc.stable_id()
	assert doc.semantic_stable_id_checked() or { panic(err) } == doc.semantic_stable_id()
	assert doc.root_refs_checked_with_limits(vmarkdown.AstValidationLimits{
		max_nodes: 16
		max_nesting_depth: 8
	}) or { panic(err) } == doc.root_refs()
	assert doc.children[0].stable_id_checked() or { panic(err) } == doc.children[0].stable_id()
	assert doc.encode_checked() or { panic(err) } == doc.encode()
	assert doc.semantic_encode_checked() or { panic(err) } == doc.semantic_encode()
	assert doc.children[0].encode_checked() or { panic(err) } == doc.children[0].encode()
	heading_inline := (doc.children[0] as vmarkdown.HeadingNode).children[0]
	assert heading_inline.semantic_encode_checked() or { panic(err) } == heading_inline.semantic_encode()
	html := vmarkdown.render_html_with_options('line', vmarkdown.HtmlRenderOptions{
		parser: options
	}) or { panic(err) }
	assert html.contains('<p>line</p>')
	assert vmarkdown.render_html_with_limits('line', vmarkdown.HtmlRenderOptions{}, vmarkdown.HtmlRenderLimits{
		max_input_bytes: 64
		max_output_bytes: 64
	}) or { panic(err) } == '<p>line</p>\n'
}

fn test_public_validation_error_contract() {
	invalid := vmarkdown.Document{
		children: [vmarkdown.BlockNode(vmarkdown.HeadingNode{
			span: vmarkdown.SourceSpan{ start: 4, end: 7 }
			level: 0
		})]
	}
	mut matched := false
	invalid.validate() or {
		if err is vmarkdown.AstValidationError {
			matched = true
			assert err.kind == .heading_level
			assert err.path == 'document.children[0].level'
			assert err.span == vmarkdown.SourceSpan{ start: 4, end: 7 }
			assert err.message == 'must be between 1 and 6'
			assert err.code() > 0
		} else {
			assert false, 'expected AstValidationError, got ${typeof(err).name}'
		}
	}
	assert matched
	if _ := invalid.validate_with_limits(vmarkdown.AstValidationLimits{ max_nodes: -1 }) {
		assert false, 'negative validation limits must fail'
	} else {
		assert err is vmarkdown.AstValidationError
		validation := err as vmarkdown.AstValidationError
		assert validation.kind == .invalid_limits
		assert validation.path == 'limits.max_nodes'
	}
}

fn test_public_markdown_parse_error_contract() {
	invalid := [u8(`a`), 0xe2, 0x82].bytestr()
	if _ := vmarkdown.parse(invalid) {
		assert false, 'invalid UTF-8 Markdown must fail'
	} else {
		assert err is vmarkdown.MarkdownParseError
		parse_error := err as vmarkdown.MarkdownParseError
		assert parse_error.kind == .invalid_utf8
		assert parse_error.offset == 1
		assert parse_error.native_code == 0
		assert parse_error.message.contains('byte 1')
		assert parse_error.code() >= 5000
	}
}

fn test_public_invalid_utf8_ast_error_contract() {
	invalid := vmarkdown.InlineNode(vmarkdown.TextNode{
		text: [u8(0xff)].bytestr()
	})
	if _ := invalid.validate() {
		assert false, 'invalid UTF-8 AST field must fail'
	} else {
		assert err is vmarkdown.AstValidationError
		validation := err as vmarkdown.AstValidationError
		assert validation.kind == .invalid_utf8
		assert validation.path == 'inline.text'
	}
}

fn test_public_html_render_error_contract() {
	if _ := vmarkdown.render_html_with_limits('<>&', vmarkdown.HtmlRenderOptions{}, vmarkdown.HtmlRenderLimits{
		max_output_bytes: 8
	}) {
		assert false, 'oversized HTML output must fail'
	} else {
		assert err is vmarkdown.HtmlRenderError
		render_error := err as vmarkdown.HtmlRenderError
		assert render_error.kind == .output_limit
		assert render_error.offset == -1
		assert render_error.native_code == 0
		assert render_error.code() >= 6000
	}
}

fn test_public_binary_decode_error_contract() {
	if _ := vmarkdown.binary_decode([u8(`X`), `M`, `D`, `A`, 0x01, 0x00, 0x00]) {
		assert false, 'invalid VMDA envelope must fail'
	} else {
		assert err is vmarkdown.BinaryDecodeError
		decode_error := err as vmarkdown.BinaryDecodeError
		assert decode_error.kind == .invalid_envelope
		assert decode_error.offset == 0
		assert decode_error.message.contains('expected VMDA')
		assert decode_error.code() >= 4000
	}
}

fn test_public_wiki_link_contract() {
	doc := vmarkdown.parse_with_options('[[docs|Guide]]', vmarkdown.ParseOptions{
		wiki_links: true
	}) or { panic(err) }
	wikis := doc.find_all(.wiki_link)
	assert wikis.len == 1
	assert wikis[0].node is vmarkdown.WikiLinkNode
	wiki := wikis[0].node as vmarkdown.WikiLinkNode
	assert wiki.target == 'docs'
	assert wiki.text.len == 1
	vmarkdown.InlineNode(wiki).validate() or { panic(err) }
}

fn test_public_latex_math_contract() {
	doc := vmarkdown.parse_with_options(r'$$\int_a^b x dx$$', vmarkdown.ParseOptions{
		latex_math: true
	}) or { panic(err) }
	math_nodes := doc.find_all(.latex_math)
	assert math_nodes.len == 1
	assert math_nodes[0].node is vmarkdown.LatexMathNode
	math := math_nodes[0].node as vmarkdown.LatexMathNode
	assert math.content == r'\int_a^b x dx'
	assert math.display
	vmarkdown.InlineNode(math).validate() or { panic(err) }
}

fn test_public_underline_contract() {
	doc := vmarkdown.parse_with_options('_underlined_', vmarkdown.ParseOptions{
		underline: true
	}) or { panic(err) }
	underlines := doc.find_all(.underline)
	assert underlines.len == 1
	assert underlines[0].node is vmarkdown.UnderlineNode
	underline := underlines[0].node as vmarkdown.UnderlineNode
	assert underline.children.len == 1
	vmarkdown.InlineNode(underline).validate() or { panic(err) }
}

fn test_public_ingest_and_encoding_contract() {
	file := vmarkdown.decode_markdown_bytes('hello'.bytes(), 'utf-8') or { panic(err) }
	assert file.text == 'hello'
	assert file.encoding == .utf8
	assert vmarkdown.encode_markdown_text(file.text, file.encoding, file.bom) or { panic(err) } == 'hello'.bytes()

	doc := vmarkdown.parse_with_dialect('- one\n- two', .gfm) or { panic(err) }
	mut store := vmarkdown.new_memory_store()
	plan := vmarkdown.plan_ingest_document_checked(doc, store) or { panic(err) }
	assert plan.root_id == doc.stable_id()
	result := store.ingest_document(doc) or { panic(err) }
	assert result.root_id == doc.stable_id()
	assert store.last_root_id() == result.root_id
}
