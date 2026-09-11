module vmarkdown

fn test_lint_enriches_findings_in_visit_and_rule_order() {
	source := '# bad\n\nbad'
	doc := parse(source) or { panic(err) }
	rules := [
		LintRule{
			id: 'example.bad-text'
			severity: .warning
			check: fn (visit AstVisit) []LintFinding {
				if visit.node is TextNode && visit.node.text == 'bad' {
					return [LintFinding{
						message: 'replace bad text'
						edits: [MarkdownTextEdit{
							span: visit.span
							replacement: 'good'
						}]
					}]
				}
				return []LintFinding{}
			}
		},
		LintRule{
			id: 'example.text-info'
			severity: .info
			check: fn (visit AstVisit) []LintFinding {
				if visit.kind == .text {
					return [LintFinding{ message: 'text node' }]
				}
				return []LintFinding{}
			}
		},
	]
	diagnostics := doc.lint(rules) or { panic(err) }

	assert diagnostics.len == 4
	assert diagnostics.map(it.rule_id) == ['example.bad-text', 'example.text-info', 'example.bad-text',
		'example.text-info']
	assert diagnostics[0].severity == .warning
	assert diagnostics[0].kind == .text
	assert diagnostics[0].path == 'document.children[0].children[0]'
	assert apply_lint_fixes(source, diagnostics) or { panic(err) } == '# good\n\ngood'
}

fn test_lint_rejects_invalid_rule_contracts() {
	doc := parse('text') or { panic(err) }
	invalid_id := LintRule{
		id: 'Bad Rule'
		check: fn (visit AstVisit) []LintFinding {
			return []LintFinding{}
		}
	}
	assert_lint_error(doc, [LintRule{
		id: ''
		check: invalid_id.check
	}], .empty_rule_id)
	assert_lint_error(doc, [invalid_id], .invalid_rule_id)
	assert_lint_error(doc, [LintRule{
		id: 'same'
		check: invalid_id.check
	}, LintRule{
		id: 'same'
		check: invalid_id.check
	}], .duplicate_rule_id)
	empty_message := LintRule{
		id: 'empty-message'
		check: fn (visit AstVisit) []LintFinding {
			return [LintFinding{}]
		}
	}
	assert_lint_error(doc, [empty_message], .empty_message)
	invalid_edit := LintRule{
		id: 'invalid-edit'
		check: fn (visit AstVisit) []LintFinding {
			return [LintFinding{
				message: 'bad edit'
				edits: [MarkdownTextEdit{ span: SourceSpan{ start: -1, end: 2 } }]
			}]
		}
	}
	assert_lint_error(doc, [invalid_edit], .invalid_edit)
}

fn test_apply_markdown_edits_handles_utf8_and_adjacent_ranges() {
	source := 'héllo bad'
	edited := apply_markdown_edits(source, [
		MarkdownTextEdit{ span: SourceSpan{ start: 7, end: 10 }, replacement: 'good' },
		MarkdownTextEdit{ span: SourceSpan{ start: 1, end: 3 }, replacement: 'a' },
		MarkdownTextEdit{ span: SourceSpan{ start: 3, end: 6 }, replacement: 'y' },
	]) or { panic(err) }
	assert edited == 'hay good'
}

fn test_apply_markdown_edits_rejects_unsafe_sets() {
	assert_edit_error('hé', [MarkdownTextEdit{
		span: SourceSpan{ start: 2, end: 3 }
		replacement: 'x'
	}], .edit_not_utf8_boundary)
	assert_edit_error('text', [MarkdownTextEdit{
		span: SourceSpan{ start: 0, end: 3 }
	}, MarkdownTextEdit{
		span: SourceSpan{ start: 2, end: 4 }
	}], .overlapping_edits)
	assert_edit_error('text', [MarkdownTextEdit{
		span: SourceSpan{ start: 4, end: 5 }
	}], .edit_out_of_bounds)
	assert_edit_error('text', [MarkdownTextEdit{
		span: SourceSpan{ start: 2, end: 2 }
	}, MarkdownTextEdit{
		span: SourceSpan{ start: 2, end: 2 }
	}], .overlapping_edits)
}

fn assert_lint_error(doc Document, rules []LintRule, expected LintContractErrorKind) {
	if _ := doc.lint(rules) {
		assert false
	} else {
		assert err is LintContractError
		contract_error := err as LintContractError
		assert contract_error.kind == expected
	}
}

fn assert_edit_error(source string, edits []MarkdownTextEdit, expected LintContractErrorKind) {
	if _ := apply_markdown_edits(source, edits) {
		assert false
	} else {
		assert err is LintContractError
		contract_error := err as LintContractError
		assert contract_error.kind == expected
	}
}

fn test_lint_with_limits_uses_caller_validation_budget() {
	doc := parse('text') or { panic(err) }
	rules := [LintRule{
		id: 'example.text'
		check: fn (visit AstVisit) []LintFinding {
			return if visit.kind == .text {
				[LintFinding{ message: 'text' }]
			} else {
				[]LintFinding{}
			}
		}
	}]
	assert doc.lint_with_limits(rules, AstValidationLimits{
		max_nodes: 3
		max_nesting_depth: 2
	}) or { panic(err) }.len == 1
	if _ := doc.lint_with_limits(rules, AstValidationLimits{ max_nodes: 2 }) {
		assert false
	} else {
		assert (err as AstValidationError).kind == .validation_limit
	}
}
