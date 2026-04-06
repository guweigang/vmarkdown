import vmarkdown

fn main() {
	markdown := '# JSON Diagram Demo\n\n```json diagram\n{\n  "version": 1,\n  "kind": "timeline",\n  "entries": [\n    { "point": "2024", "text": "Parser" },\n    { "point": "2025", "text": "Preview" },\n    { "point": "2026", "text": "Diagram AST" }\n  ]\n}\n```\n'

	doc := vmarkdown.parse(markdown) or { panic(err) }

	println('=== AST ===')
	println(doc.pretty())
	println('')
	println('=== Terminal ===')
	println(doc.to_terminal_with_options(vmarkdown.TerminalRenderOptions{
		width: 60
		color: false
	}))
}
