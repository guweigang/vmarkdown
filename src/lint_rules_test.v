module vmarkdown

fn test_recommended_lint_rules_report_conservative_issues() {
	source := '#\n\n![](image.png)\n\n[label]()\n\n## Good\n\n![alt](image.png)'
	diagnostics := lint_markdown(source) or { panic(err) }
	assert diagnostics.map(it.rule_id) == ['vmarkdown.empty-heading', 'vmarkdown.image-alt-text',
		'vmarkdown.empty-link-destination']
	located := locate_lint_diagnostics(source, diagnostics) or { panic(err) }
	assert !located[0].has_range
	assert !located[1].has_range
	assert located[2].has_range
	assert located[2].range.start.line == 5
}

fn test_recommended_lint_rules_accept_well_formed_content() {
	diagnostics := lint_markdown('# Title\n\n![description](image.png)\n\n[label](target)') or {
		panic(err)
	}
	assert diagnostics.len == 0
}

fn test_lint_markdown_reports_and_fixes_trailing_whitespace() {
	source := 'first  \r\nsecond\t\nthird '
	diagnostics := lint_markdown(source) or { panic(err) }
	assert diagnostics.map(it.rule_id) == ['vmarkdown.trailing-whitespace',
		'vmarkdown.trailing-whitespace', 'vmarkdown.trailing-whitespace']
	assert locate_lint_diagnostics(source, diagnostics) or { panic(err) }.map(it.range.start.line) == [
		1,
		2,
		3,
	]
	assert apply_lint_fixes(source, diagnostics) or { panic(err) } == 'first\r\nsecond\nthird'
}
