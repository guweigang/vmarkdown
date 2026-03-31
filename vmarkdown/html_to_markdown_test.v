module vmarkdown

fn test_html_to_markdown_heading_paragraph_and_link() {
	markdown := html_to_markdown('<h1>Title</h1><p>Hello <a href="https://example.com/a(b c)">docs</a></p>') or {
		panic(err)
	}
	assert markdown.contains('# Title')
	assert markdown.contains('[docs](<https://example.com/a(b c)>)')
}

fn test_html_to_markdown_list_and_code_block() {
	html := '<ul><li>alpha</li><li>beta</li></ul><pre><code class="language-v">println("ok")
</code></pre>'
	markdown := html_to_markdown(html) or { panic(err) }
	assert markdown.contains('- alpha')
	assert markdown.contains('- beta')
	assert markdown.contains('```v')
	assert markdown.contains('println("ok")')
}

fn test_html_to_markdown_blockquote_and_nested_list() {
	html := '<blockquote><p>quoted</p><ul><li>child</li></ul></blockquote>'
	markdown := html_to_markdown(html) or { panic(err) }
	assert markdown.contains('> quoted')
	assert markdown.contains('> - child')
}

fn test_html_to_markdown_image() {
	markdown := html_to_markdown('<p><img src="https://example.com/a(b c).png" alt="diagram"></p>') or {
		panic(err)
	}
	assert markdown == '![diagram](<https://example.com/a(b c).png>)'
}

fn test_html_to_markdown_decodes_entities_from_render_html() {
	html := render_html('```v\nprintln("hi")\n```\n') or { panic(err) }
	markdown := html_to_markdown(html) or { panic(err) }
	assert markdown.contains('println("hi")')
	assert !markdown.contains('&quot;')
}
