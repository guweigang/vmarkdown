module vmarkdown

import encoding.utf8

pub struct SourcePosition {
pub:
	offset      int
	line        int
	column      int
	byte_column int
}

pub struct SourceRange {
pub:
	start SourcePosition
	end   SourcePosition
}

pub struct LocatedLintDiagnostic {
pub:
	diagnostic LintDiagnostic
	has_range  bool
	range      SourceRange
}

pub enum SourceIndexErrorKind {
	invalid_utf8
	invalid_span
	offset_out_of_bounds
	offset_not_utf8_boundary
	line_out_of_bounds
}

pub struct SourceIndexError {
pub:
	kind    SourceIndexErrorKind
	message string
}

pub fn (err SourceIndexError) msg() string {
	return err.message
}

pub fn (err SourceIndexError) code() int {
	return 3000 + int(err.kind)
}

pub struct SourceIndex {
	source      string
	line_starts []int
	line_ends   []int
}

// new_source_index indexes UTF-8 source without normalizing its line endings.
// CRLF and lone CR/LF sequences each delimit one logical line.
pub fn new_source_index(source string) !SourceIndex {
	if !utf8.validate_str(source) {
		return source_index_error(.invalid_utf8, 'source is not valid UTF-8')
	}
	mut starts := [0]
	mut ends := []int{}
	mut offset := 0
	for offset < source.len {
		if source[offset] == `\r` {
			ends << offset
			offset++
			if offset < source.len && source[offset] == `\n` {
				offset++
			}
			starts << offset
			continue
		}
		if source[offset] == `\n` {
			ends << offset
			offset++
			starts << offset
			continue
		}
		offset++
	}
	ends << source.len
	return SourceIndex{
		source: source
		line_starts: starts
		line_ends: ends
	}
}

pub fn (index SourceIndex) source_len() int {
	return index.source.len
}

pub fn (index SourceIndex) line_count() int {
	return index.line_starts.len
}

// position maps a zero-based UTF-8 byte offset to one-based line, Unicode
// code-point column, and byte column coordinates.
pub fn (index SourceIndex) position(offset int) !SourcePosition {
	if offset < 0 || offset > index.source.len {
		return source_index_error(.offset_out_of_bounds, 'offset ${offset} is outside source length ${index.source.len}')
	}
	if !is_utf8_boundary(index.source, offset) {
		return source_index_error(.offset_not_utf8_boundary, 'offset ${offset} splits a UTF-8 code point')
	}
	line_index := index.line_index_for_offset(offset)
	line_start := index.line_starts[line_index]
	return SourcePosition{
		offset: offset
		line: line_index + 1
		column: index.source[line_start..offset].runes().len + 1
		byte_column: offset - line_start + 1
	}
}

// locate_lint_diagnostics maps every available diagnostic span with one shared
// source index. Diagnostics whose spans are unavailable remain in the result.
pub fn locate_lint_diagnostics(source string, diagnostics []LintDiagnostic) ![]LocatedLintDiagnostic {
	index := new_source_index(source)!
	return index.locate_diagnostics(diagnostics)
}

pub fn (index SourceIndex) locate_diagnostics(diagnostics []LintDiagnostic) ![]LocatedLintDiagnostic {
	mut located := []LocatedLintDiagnostic{cap: diagnostics.len}
	for diagnostic in diagnostics {
		if diagnostic.span.start < 0 && diagnostic.span.end < 0 {
			located << LocatedLintDiagnostic{
				diagnostic: diagnostic
			}
			continue
		}
		located << LocatedLintDiagnostic{
			diagnostic: diagnostic
			has_range: true
			range: index.range(diagnostic.span)!
		}
	}
	return located
}

// range maps a valid half-open source span to source coordinates.
pub fn (index SourceIndex) range(span SourceSpan) !SourceRange {
	if !span.is_valid() {
		return source_index_error(.invalid_span, 'source span is unavailable or malformed')
	}
	return SourceRange{
		start: index.position(span.start)!
		end: index.position(span.end)!
	}
}

// line_text returns a one-based logical line without its CR/LF terminator.
pub fn (index SourceIndex) line_text(line int) !string {
	if line < 1 || line > index.line_count() {
		return source_index_error(.line_out_of_bounds, 'line ${line} is outside line count ${index.line_count()}')
	}
	line_index := line - 1
	return index.source[index.line_starts[line_index]..index.line_ends[line_index]]
}

fn (index SourceIndex) line_index_for_offset(offset int) int {
	mut low := 0
	mut high := index.line_starts.len
	for low < high {
		middle := low + (high - low) / 2
		if index.line_starts[middle] <= offset {
			low = middle + 1
		} else {
			high = middle
		}
	}
	return if low > 0 { low - 1 } else { 0 }
}

fn is_utf8_boundary(source string, offset int) bool {
	return offset == 0 || offset == source.len || source[offset] & 0xc0 != 0x80
}

fn source_index_error(kind SourceIndexErrorKind, message string) SourceIndexError {
	return SourceIndexError{
		kind: kind
		message: message
	}
}
