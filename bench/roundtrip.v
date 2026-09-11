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
	rewritten := reparsed.rewrite_inlines(fn (visit vmarkdown.AstInlineRewrite) ![]vmarkdown.InlineNode {
		return [visit.node]
	}) or {
		eprintln('benchmark identity rewrite failed: ${err}')
		exit(1)
	}
	diagnostics := rewritten.lint(vmarkdown.recommended_lint_rules()) or {
		eprintln('benchmark lint failed: ${err}')
		exit(1)
	}
	encoded := rewritten.binary_encode_checked() or {
		eprintln('benchmark binary encode failed: ${err}')
		exit(1)
	}
	decoded := vmarkdown.binary_decode(encoded) or {
		eprintln('benchmark binary decode failed: ${err}')
		exit(1)
	}
	index := vmarkdown.new_source_index(normalized) or {
		eprintln('benchmark source indexing failed: ${err}')
		exit(1)
	}
	last_text_range := index.range(text_nodes.last().span) or {
		eprintln('benchmark source lookup failed: ${err}')
		exit(1)
	}
	elapsed := time.since(started)
	if doc.stable_id() != reparsed.stable_id() || reparsed.stable_id() != rewritten.stable_id()
		|| rewritten.stable_id() != decoded.stable_id() {
		eprintln('benchmark document changed after semantic or binary round trip')
		exit(1)
	}
	if text_nodes.len < 2048 {
		eprintln('benchmark traversal returned only ${text_nodes.len} text nodes')
		exit(1)
	}
	if diagnostics.len != 0 {
		eprintln('benchmark recommended lint unexpectedly returned diagnostics')
		exit(1)
	}
	if last_text_range.start.line < 1 {
		eprintln('benchmark source lookup returned an invalid line')
		exit(1)
	}
	println('${source.len} input bytes, ${doc.children.len} blocks, parse/render/reparse/query/rewrite/lint/index/binary round trip in ${elapsed.milliseconds()} ms')
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
