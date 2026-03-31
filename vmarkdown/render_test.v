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
