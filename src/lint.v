module vmarkdown

import encoding.utf8
import strings

pub enum LintSeverity {
	info
	warning
	error
}

pub struct MarkdownTextEdit {
pub:
	span        SourceSpan
	replacement string
}

pub struct LintFinding {
pub:
	message string
	edits   []MarkdownTextEdit
}

pub struct LintRule {
pub:
	id       string
	severity LintSeverity = .warning
	check    fn (AstVisit) []LintFinding @[required]
}

pub struct LintDiagnostic {
pub:
	rule_id  string
	severity LintSeverity
	message  string
	kind     AstNodeKind
	path     string
	span     SourceSpan = SourceSpan{ start: -1, end: -1 }
	edits    []MarkdownTextEdit
}

pub enum LintContractErrorKind {
	empty_rule_id
	invalid_rule_id
	duplicate_rule_id
	empty_message
	invalid_edit
	invalid_source
	edit_out_of_bounds
	edit_not_utf8_boundary
	overlapping_edits
}

pub struct LintContractError {
pub:
	kind    LintContractErrorKind
	rule_id string
	message string
}

pub fn (err LintContractError) msg() string {
	return if err.rule_id.len > 0 { '${err.rule_id}: ${err.message}' } else { err.message }
}

pub fn (err LintContractError) code() int {
	return 2000 + int(err.kind)
}

// lint runs rules in their declared order for every AST node in pre-order.
// The document and rule contracts are validated before findings are returned.
pub fn (doc Document) lint(rules []LintRule) ![]LintDiagnostic {
	doc.validate()!
	validate_lint_rules(rules)!
	mut diagnostics := []LintDiagnostic{}
	mut diagnostics_ref := &diagnostics
	mut contract_failures := []LintContractError{}
	mut contract_failures_ref := &contract_failures
	doc.walk(fn [rules, mut diagnostics_ref, mut contract_failures_ref] (visit AstVisit) bool {
		for rule in rules {
			for finding in rule.check(visit) {
				if finding.message.trim_space().len == 0 {
					contract_failures_ref << lint_contract_error(.empty_message, rule.id, 'finding message cannot be empty')
					return false
				}
				for edit in finding.edits {
					if !edit.span.is_valid() || !utf8.validate_str(edit.replacement) {
						contract_failures_ref << lint_contract_error(.invalid_edit, rule.id, 'finding contains an invalid edit span or replacement')
						return false
					}
				}
				diagnostics_ref << LintDiagnostic{
					rule_id: rule.id
					severity: rule.severity
					message: finding.message
					kind: visit.kind
					path: visit.path
					span: visit.span
					edits: finding.edits.clone()
				}
			}
		}
		return true
	})
	if contract_failures.len > 0 {
		return contract_failures[0]
	}
	return diagnostics
}

// apply_lint_fixes applies every diagnostic edit as one atomic set. Invalid,
// out-of-bounds, non-UTF-8-boundary, and overlapping edits are rejected before
// any output is produced.
pub fn apply_lint_fixes(source string, diagnostics []LintDiagnostic) !string {
	mut edits := []MarkdownTextEdit{}
	for diagnostic in diagnostics {
		edits << diagnostic.edits
	}
	return apply_markdown_edits(source, edits)
}

// apply_markdown_edits applies a non-overlapping set of UTF-8 byte-range edits.
pub fn apply_markdown_edits(source string, edits []MarkdownTextEdit) !string {
	if !utf8.validate_str(source) {
		return lint_contract_error(.invalid_source, '', 'source is not valid UTF-8')
	}
	mut ordered := edits.clone()
	ordered.sort_with_compare(fn (left &MarkdownTextEdit, right &MarkdownTextEdit) int {
		if left.span.start < right.span.start {
			return -1
		}
		if left.span.start > right.span.start {
			return 1
		}
		return 0
	})
	for index, edit in ordered {
		if !edit.span.is_valid() || !utf8.validate_str(edit.replacement) {
			return lint_contract_error(.invalid_edit, '', 'edit ${index} has an invalid span or replacement')
		}
		if edit.span.end > source.len {
			return lint_contract_error(.edit_out_of_bounds, '', 'edit ${index} ends at ${edit.span.end}, beyond source length ${source.len}')
		}
		if !is_utf8_boundary(source, edit.span.start) || !is_utf8_boundary(source, edit.span.end) {
			return lint_contract_error(.edit_not_utf8_boundary, '', 'edit ${index} splits a UTF-8 code point')
		}
		if index > 0 {
			previous := ordered[index - 1]
			if edit.span.start < previous.span.end || edit.span.start == previous.span.start {
				return lint_contract_error(.overlapping_edits, '', 'edits ${index - 1} and ${index} overlap or share a start offset')
			}
		}
	}
	mut capacity := source.len
	for edit in ordered {
		capacity += edit.replacement.len - edit.span.len()
	}
	mut out := strings.new_builder(if capacity > 0 { capacity } else { 0 })
	mut cursor := 0
	for edit in ordered {
		out.write_string(source[cursor..edit.span.start])
		out.write_string(edit.replacement)
		cursor = edit.span.end
	}
	out.write_string(source[cursor..])
	return out.str()
}

fn validate_lint_rules(rules []LintRule) ! {
	mut ids := map[string]bool{}
	for rule in rules {
		if rule.id.len == 0 {
			return lint_contract_error(.empty_rule_id, '', 'lint rule id cannot be empty')
		}
		if !is_valid_lint_rule_id(rule.id) {
			return lint_contract_error(.invalid_rule_id, rule.id, 'lint rule id may contain only lowercase ASCII letters, digits, `.`, `_`, and `-`')
		}
		if rule.id in ids {
			return lint_contract_error(.duplicate_rule_id, rule.id, 'lint rule id is duplicated')
		}
		ids[rule.id] = true
	}
}

fn is_valid_lint_rule_id(id string) bool {
	for byte in id.bytes() {
		if !((byte >= `a` && byte <= `z`) || (byte >= `0` && byte <= `9`) || byte in [
			`.`,
			`_`,
			`-`,
		]) {
			return false
		}
	}
	return true
}

fn is_utf8_boundary(source string, offset int) bool {
	return offset == 0 || offset == source.len || source[offset] & 0xc0 != 0x80
}

fn lint_contract_error(kind LintContractErrorKind, rule_id string, message string) LintContractError {
	return LintContractError{
		kind: kind
		rule_id: rule_id
		message: message
	}
}
