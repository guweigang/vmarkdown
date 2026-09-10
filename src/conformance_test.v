module vmarkdown

import os

struct MarkdownSpecExample {
	fixture string
	number  int
	input   string
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
