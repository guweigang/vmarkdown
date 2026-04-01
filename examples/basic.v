module main

import vmarkdown

fn main() {
	markdown := '# PollyDB\n\n- fast\n- structured\n\n```v\nprintln("hi")\n```\n'
	doc := vmarkdown.parse(markdown) or {
		eprintln(err)
		return
	}
	println(doc.pretty())
	println(doc)
	println(vmarkdown.render_html(markdown) or { '' })
	println(doc.to_text())
	println(doc.to_json())
	println(doc.to_markdown())
	println(vmarkdown.html_to_markdown(vmarkdown.render_html(markdown) or { '' }) or { '' })
	println(doc.to_terminal())
}
