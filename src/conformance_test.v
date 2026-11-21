module vmarkdown

import os

struct MarkdownSpecExample {
	fixture string
	number  int
	input   string
}

struct ExtensionSpecFixture {
	fixture string
	count   int
	options ParseOptions
}

fn test_supported_commonmark_corpus_has_stable_structural_round_trip() {
	fixtures := [
		'spec.txt',
		'spec-tables.txt',
		'spec-tasklists.txt',
		'spec-strikethrough.txt',
		'spec-hard-soft-breaks.txt',
		'spec-permissive-autolinks.txt',
	]
	expected_counts := [652, 12, 5, 5, 2, 15]
	mut checked := 0
	for fixture_index, fixture in fixtures {
		dialect := if fixture_index == 0 { MarkdownDialect.commonmark } else { MarkdownDialect.gfm }
		path := os.join_path(@VMODROOT, 'thirdparty', 'md4c', 'test', fixture)
		examples := load_markdown_spec_examples(path, fixture) or { panic(err) }
		assert examples.len == expected_counts[fixture_index], '${fixture} corpus size changed'
		for example in examples {
			original := parse_with_dialect(example.input, dialect) or {
				panic('${example.fixture} example ${example.number}: parse failed: ${err}')
			}
			original.validate() or {
				panic('${example.fixture} example ${example.number}: invalid parsed AST: ${err}')
			}
			assert_binary_round_trip(original, example)
			normalized := original.to_markdown()
			reparsed := parse_with_dialect(normalized, dialect) or {
				panic('${example.fixture} example ${example.number}: normalized parse failed: ${err}')
			}
			reparsed.validate() or {
				panic('${example.fixture} example ${example.number}: invalid reparsed AST: ${err}')
			}
			assert original.stable_id() == reparsed.stable_id(), '${example.fixture} example ${example.number} changed after semantic round trip\ninput:\n${example.input}\nnormalized:\n${normalized}\noriginal AST:\n${original.pretty()}\n${original.to_json()}\nreparsed AST:\n${reparsed.pretty()}\n${reparsed.to_json()}'
			checked++
		}
	}
	assert checked == 691
}

fn test_supported_extension_corpora_have_stable_structural_round_trip() {
	fixtures := [
		ExtensionSpecFixture{
			fixture: 'spec-wiki-links.txt'
			count:   23
			options: ParseOptions{ wiki_links: true }
		},
		ExtensionSpecFixture{
			fixture: 'spec-latex-math.txt'
			count:   6
			options: ParseOptions{ latex_math: true }
		},
		ExtensionSpecFixture{
			fixture: 'spec-underline.txt'
			count:   4
			options: ParseOptions{ underline: true }
		},
		ExtensionSpecFixture{
			fixture: 'spec-highlight.txt'
			count:   21
			options: ParseOptions{ highlight: true }
		},
		ExtensionSpecFixture{
			fixture: 'spec-insert.txt'
			count:   22
			options: ParseOptions{ insertion: true }
		},
		ExtensionSpecFixture{
			fixture: 'spec-superscripts.txt'
			count:   16
			options: ParseOptions{ superscript: true }
		},
		ExtensionSpecFixture{
			fixture: 'spec-subscripts.txt'
			count:   12
			options: ParseOptions{ subscript: true }
		},
	]
	mut checked := 0
	for fixture in fixtures {
		path := os.join_path(@VMODROOT, 'thirdparty', 'md4c', 'test', fixture.fixture)
		examples := load_markdown_spec_examples(path, fixture.fixture) or { panic(err) }
		assert examples.len == fixture.count, '${fixture.fixture} corpus size changed'
		for example in examples {
			original := parse_with_options(example.input, fixture.options) or {
				panic('${example.fixture} example ${example.number}: parse failed: ${err}')
			}
			original.validate() or {
				panic('${example.fixture} example ${example.number}: invalid parsed AST: ${err}')
			}
			assert_binary_round_trip(original, example)
			normalized := original.to_markdown()
			reparsed := parse_with_options(normalized, fixture.options) or {
				panic('${example.fixture} example ${example.number}: normalized parse failed: ${err}')
			}
			reparsed.validate() or {
				panic('${example.fixture} example ${example.number}: invalid reparsed AST: ${err}')
			}
			assert original.stable_id() == reparsed.stable_id(), '${example.fixture} example ${example.number} changed after semantic round trip\ninput:\n${example.input}\nnormalized:\n${normalized}\noriginal AST:\n${original.pretty()}\n${original.to_json()}\nreparsed AST:\n${reparsed.pretty()}\n${reparsed.to_json()}'
			checked++
		}
	}
	assert checked == 104
}

fn test_admonitions_are_opt_in_and_round_trip_through_renderers() {
	options := ParseOptions{ admonitions: true }
	fixture := 'spec-admonitions.txt'
	path := os.join_path(@VMODROOT, 'thirdparty', 'md4c', 'test', fixture)
	examples := load_markdown_spec_examples(path, fixture) or { panic(err) }
	kinds := [AdmonitionKind.note, .tip, .important, .warning, .caution]
	assert examples.len == kinds.len
	for index, example in examples {
		kind := kinds[index]
		ordinary := parse(example.input) or { panic(err) }
		assert ordinary.children[0] is BlockquoteNode
		assert ordinary.binary_encode()[4] == binary_format_version
		doc := parse_with_options(example.input, options) or { panic(err) }
		assert doc.children.len == 1
		assert (doc.children[0] as AdmonitionNode).kind == kind
		assert doc.find_all(.admonition).len == 1
		assert doc.find_all(.paragraph).len == 1
		assert doc.to_json().contains('"type":"admonition","kind":"${kind}"')
		rendered := parse_with_options(doc.to_markdown(), options) or { panic(err) }
		assert rendered.stable_id() == doc.stable_id()
		assert_binary_round_trip(doc, example)
		assert doc.binary_encode()[4] == binary_admonition_version
		terminal := doc.to_terminal_with_options(TerminalRenderOptions{ color: false })
		assert terminal.starts_with('▎ ${kind.str().to_upper()}\n')
		assert terminal.contains('▎ My ${kind} text.')
		html := render_html_with_options(example.input, HtmlRenderOptions{ parser: options }) or {
			panic(err)
		}
		assert html.contains('<div class="admonition-${kind}">')
		assert html.contains('<p>My ${kind} text.</p>')
	}
}

fn test_upstream_footnote_corpus_round_trips() {
	fixture := 'spec-footnotes.txt'
	path := os.join_path(@VMODROOT, 'thirdparty', 'md4c', 'test', fixture)
	examples := load_markdown_spec_examples(path, fixture) or { panic(err) }
	assert examples.len == 26
	options := ParseOptions{ footnotes: true }
	for example in examples {
		doc := parse_with_options(example.input, options) or { panic(err) }
		assert_binary_round_trip(doc, example)
		normalized := doc.to_markdown()
		round_trip := parse_with_options(normalized, options) or { panic(err) }
		assert round_trip.stable_id() == doc.stable_id(), '${fixture} example ${example.number}\n${example.input}\n${normalized}'
	}
}

fn test_blank_line_and_spoiler_corpora_round_trip() {
	fixtures := [
		ExtensionSpecFixture{
			fixture: 'spec-preserve-blank-lines.txt'
			count:   10
			options: ParseOptions{ preserve_blank_lines: true }
		},
		ExtensionSpecFixture{
			fixture: 'spec-spoilers.txt'
			count:   38
			options: ParseOptions{ spoilers: true, wiki_links: true }
		},
	]
	for fixture in fixtures {
		path := os.join_path(@VMODROOT, 'thirdparty', 'md4c', 'test', fixture.fixture)
		examples := load_markdown_spec_examples(path, fixture.fixture) or { panic(err) }
		assert examples.len == fixture.count
		for example in examples {
			doc := parse_with_options(example.input, fixture.options) or { panic(err) }
			assert_binary_round_trip(doc, example)
			normalized := doc.to_markdown()
			round_trip := parse_with_options(normalized, fixture.options) or { panic(err) }
			assert round_trip.stable_id() == doc.stable_id(), '${example.fixture} example ${example.number}\n${example.input}\n${normalized}'
		}
	}
}

fn assert_binary_round_trip(doc Document, example MarkdownSpecExample) {
	encoded := doc.binary_encode_checked() or {
		panic('${example.fixture} example ${example.number}: binary encode failed: ${err}')
	}
	decoded := binary_decode(encoded) or {
		panic('${example.fixture} example ${example.number}: binary decode failed: ${err}')
	}
	assert decoded.binary_encode() == encoded, '${example.fixture} example ${example.number} changed after binary round trip'
	assert decoded.stable_id() == doc.stable_id(), '${example.fixture} example ${example.number} changed stable ID after binary round trip'
}

fn load_markdown_spec_examples(path string, fixture string) ![]MarkdownSpecExample {
	lines := os.read_file(path)!.split_into_lines()
	mut examples := []MarkdownSpecExample{}
	mut index := 0
	for index < lines.len {
		line := lines[index].trim_left(' \t')
		if !line.starts_with('````') || !line.ends_with(' example') {
			index++
			continue
		}
		indent := lines[index][..lines[index].len - line.len]
		index++
		mut input_lines := []string{}
		for index < lines.len && lines[index] != indent + '.' {
			input_lines << lines[index].replace('→', '\t')
			index++
		}
		if index >= lines.len {
			return error('${fixture}: unterminated Markdown example')
		}
		examples << MarkdownSpecExample{
			fixture: fixture
			number:  examples.len + 1
			input:   input_lines.join('\n') + '\n'
		}
		for index < lines.len && !lines[index].starts_with(indent + '````') {
			index++
		}
		index++
	}
	return examples
}
