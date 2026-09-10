module main

import os
import strings
import time
import vmarkdown

fn main() {
	source := benchmark_document(2048)
	started := time.now()
	doc := vmarkdown.parse(source) or {
		eprintln('benchmark parse failed: ${err}')
		exit(1)
	}
	normalized := doc.to_markdown()
	reparsed := vmarkdown.parse(normalized) or {
		eprintln('benchmark reparse failed: ${err}')
		exit(1)
	}
	text_nodes := reparsed.find_all(.text)
	elapsed := time.since(started)
	if doc.stable_id() != reparsed.stable_id() {
		eprintln('benchmark document changed after Markdown round trip')
		exit(1)
	}
	if text_nodes.len < 2048 {
		eprintln('benchmark traversal returned only ${text_nodes.len} text nodes')
		exit(1)
	}
	println('${source.len} input bytes, ${doc.children.len} blocks, parse/render/reparse/query in ${elapsed.milliseconds()} ms')
	if os.getenv('CI').len > 0 && elapsed.milliseconds() > 15_000 {
		eprintln('benchmark exceeded the 15000 ms CI smoke budget')
		exit(1)
	}
}

fn benchmark_document(section_count int) string {
	mut out := strings.new_builder(section_count * 256)
	for index in 0 .. section_count {
		out.write_string('## Section ${index}\n\n')
		out.write_string('A paragraph with **strong text**, *emphasis*, [a link](https://example.com/${index}), and `inline code`.\n\n')
		out.write_string('- [x] parsed\n- [ ] rendered\n- nested value ${index}\n\n')
		out.write_string('> A quoted line for section ${index}.\n\n')
	}
	return out.str()
}
