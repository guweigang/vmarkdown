module vmarkdown

// recommended_lint_rules returns conservative structural and accessibility
// checks. The returned rules are stateless and can be reused across documents.
pub fn recommended_lint_rules() []LintRule {
	return [
		LintRule{
			id: 'vmarkdown.empty-heading'
			severity: .warning
			check: check_empty_heading
		},
		LintRule{
			id: 'vmarkdown.image-alt-text'
			severity: .warning
			check: check_image_alt_text
		},
		LintRule{
			id: 'vmarkdown.empty-link-destination'
			severity: .warning
			check: check_empty_link_destination
		},
	]
}

pub fn lint_markdown(source string) ![]LintDiagnostic {
	return lint_markdown_with_options(source, ParseOptions{})
}

pub fn lint_markdown_with_options(source string, options ParseOptions) ![]LintDiagnostic {
	return lint_markdown_with_limits(source, options, ParseLimits{})
}

pub fn lint_markdown_with_limits(source string, options ParseOptions, limits ParseLimits) ![]LintDiagnostic {
	doc := parse_with_limits(source, options, limits)!
	mut diagnostics := doc.lint_with_limits(recommended_lint_rules(), AstValidationLimits{
		max_nodes: limits.max_nodes
		max_nesting_depth: limits.max_nesting_depth
	})!
	diagnostics << trailing_whitespace_diagnostics(source)
	return diagnostics
}

fn trailing_whitespace_diagnostics(source string) []LintDiagnostic {
	mut diagnostics := []LintDiagnostic{}
	mut line_start := 0
	mut offset := 0
	for offset <= source.len {
		at_end := offset == source.len
		at_break := !at_end && source[offset] in [`\r`, `\n`]
		if at_end || at_break {
			mut trailing_start := offset
			for trailing_start > line_start && source[trailing_start - 1] in [` `, `\t`] {
				trailing_start--
			}
			if trailing_start < offset {
				span := SourceSpan{ start: trailing_start, end: offset }
				diagnostics << LintDiagnostic{
					rule_id: 'vmarkdown.trailing-whitespace'
					severity: .warning
					message: 'line has trailing whitespace'
					kind: .document
					path: 'document'
					span: span
					edits: [MarkdownTextEdit{ span: span }]
				}
			}
			if at_end {
				break
			}
			if source[offset] == `\r` && offset + 1 < source.len && source[offset + 1] == `\n` {
				offset++
			}
			line_start = offset + 1
		}
		offset++
	}
	return diagnostics
}

fn check_empty_heading(visit AstVisit) []LintFinding {
	if visit.node is HeadingNode && render_inline_text(visit.node.children).trim_space().len == 0 {
		return [LintFinding{ message: 'heading has no readable text' }]
	}
	return []LintFinding{}
}

fn check_image_alt_text(visit AstVisit) []LintFinding {
	if visit.node is ImageNode && render_inline_text(visit.node.alt).trim_space().len == 0 {
		return [LintFinding{ message: 'image has no alternative text' }]
	}
	return []LintFinding{}
}

fn check_empty_link_destination(visit AstVisit) []LintFinding {
	if visit.node is LinkNode && visit.node.url.trim_space().len == 0 {
		return [LintFinding{ message: 'link destination is empty' }]
	}
	return []LintFinding{}
}
