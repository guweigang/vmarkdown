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
	headings := doc.find_all(.heading)
	assert headings.len == 1
	assert headings[0].node is vmarkdown.HeadingNode
	mut visited_paths := []string{}
	mut visited_paths_ref := &visited_paths
	assert doc.walk(fn [mut visited_paths_ref] (visit vmarkdown.AstVisit) bool {
		visited_paths_ref << visit.path
		return visit.kind != .hard_break
	})
	assert visited_paths.len > headings.len
	rewritten := doc.rewrite_inlines(fn (visit vmarkdown.AstInlineRewrite) ![]vmarkdown.InlineNode {
		if visit.node is vmarkdown.TextNode && visit.node.text == 'API' {
			return [vmarkdown.InlineNode(vmarkdown.TextNode{ text: 'renamed' })]
		}
		return [visit.node]
	}) or { panic(err) }
	assert rewritten.to_markdown().starts_with('# renamed')
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
	assert doc.to_json().contains('"type":"heading"')
	assert doc.to_markdown().starts_with('# API')
	assert doc.to_terminal_with_options(vmarkdown.TerminalRenderOptions{
		width: 80
		color: false
	}).contains('API')

	encoded := doc.binary_encode()
	decoded := vmarkdown.binary_decode(encoded) or { panic(err) }
	assert decoded.stable_id() == doc.stable_id()
	assert decoded.encode() == encoded
	assert decoded.semantic_encode().len > 0
	html := vmarkdown.render_html_with_options('line', vmarkdown.HtmlRenderOptions{
		parser: options
	}) or { panic(err) }
	assert html.contains('<p>line</p>')
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
