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
