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
	doc := parse_with_options(source, options)!
	return doc.lint(recommended_lint_rules())
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
