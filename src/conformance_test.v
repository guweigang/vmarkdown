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
	expected_counts := [652, 12, 5, 5, 2, 14]
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
	assert checked == 690
}

fn test_supported_extension_corpora_have_stable_structural_round_trip() {
	fixtures := [
		ExtensionSpecFixture{
			fixture: 'spec-wiki-links.txt'
			count: 23
			options: ParseOptions{ wiki_links: true }
		},
		ExtensionSpecFixture{
			fixture: 'spec-latex-math.txt'
			count: 6
			options: ParseOptions{ latex_math: true }
		},
		ExtensionSpecFixture{
			fixture: 'spec-underline.txt'
			count: 4
			options: ParseOptions{ underline: true }
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
	assert checked == 33
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
		line := lines[index]
		if !line.starts_with('````') || !line.ends_with(' example') {
			index++
			continue
		}
		index++
		mut input_lines := []string{}
		for index < lines.len && lines[index] != '.' {
			input_lines << lines[index].replace('→', '\t')
			index++
		}
		if index >= lines.len {
			return error('${fixture}: unterminated Markdown example')
		}
		examples << MarkdownSpecExample{
			fixture: fixture
			number: examples.len + 1
			input: input_lines.join('\n') + '\n'
		}
		for index < lines.len && !lines[index].starts_with('````') {
			index++
		}
		index++
	}
	return examples
}
