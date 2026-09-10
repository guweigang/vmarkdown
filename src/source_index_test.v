module vmarkdown

fn test_source_index_maps_utf8_and_mixed_line_endings() {
	index := new_source_index('α\r\n中文\nlast\rend') or { panic(err) }
	assert index.source_len() == 19
	assert index.line_count() == 4
	assert index.line_text(1) or { panic(err) } == 'α'
	assert index.line_text(2) or { panic(err) } == '中文'
	assert index.line_text(3) or { panic(err) } == 'last'
	assert index.line_text(4) or { panic(err) } == 'end'

	assert index.position(0) or { panic(err) } == SourcePosition{
		offset: 0
		line: 1
		column: 1
		byte_column: 1
	}
	assert index.position(4) or { panic(err) } == SourcePosition{
		offset: 4
		line: 2
		column: 1
		byte_column: 1
	}
	assert index.position(7) or { panic(err) } == SourcePosition{
		offset: 7
		line: 2
		column: 2
		byte_column: 4
	}
	assert index.range(SourceSpan{ start: 4, end: 10 }) or { panic(err) } == SourceRange{
		start: SourcePosition{ offset: 4, line: 2, column: 1, byte_column: 1 }
		end: SourcePosition{ offset: 10, line: 2, column: 3, byte_column: 7 }
	}
}

fn test_source_index_preserves_trailing_empty_line() {
	index := new_source_index('one\n') or { panic(err) }
	assert index.line_count() == 2
	assert index.line_text(2) or { panic(err) } == ''
	assert index.position(4) or { panic(err) } == SourcePosition{
		offset: 4
		line: 2
		column: 1
		byte_column: 1
	}
}

fn test_source_index_locates_lint_diagnostics_and_preserves_unavailable_spans() {
	diagnostics := [
		LintDiagnostic{
			rule_id: 'example.first'
			message: 'first'
			kind: .text
			path: 'document.children[0]'
			span: SourceSpan{ start: 4, end: 10 }
		},
		LintDiagnostic{
			rule_id: 'example.global'
			message: 'global'
			kind: .document
			path: 'document'
		},
	]
	located := locate_lint_diagnostics('α\r\n中文', diagnostics) or { panic(err) }
	assert located.len == 2
	assert located[0].has_range
	assert located[0].range.start.line == 2
	assert located[0].range.end.column == 3
	assert !located[1].has_range
	assert located[1].diagnostic.rule_id == 'example.global'
}

fn test_source_index_rejects_invalid_coordinates() {
	if _ := new_source_index([u8(0xff)].bytestr()) {
		assert false
	} else {
		assert err is SourceIndexError
		index_error := err as SourceIndexError
		assert index_error.kind == .invalid_utf8
	}
	index := new_source_index('中文') or { panic(err) }
	assert_source_index_position_error(index, 1, .offset_not_utf8_boundary)
	assert_source_index_position_error(index, 7, .offset_out_of_bounds)
	if _ := index.range(SourceSpan{}) {
		assert false
	} else {
		assert err is SourceIndexError
		index_error := err as SourceIndexError
		assert index_error.kind == .invalid_span
	}
	if _ := index.line_text(2) {
		assert false
	} else {
		assert err is SourceIndexError
		index_error := err as SourceIndexError
		assert index_error.kind == .line_out_of_bounds
	}
}

fn assert_source_index_position_error(index SourceIndex, offset int, expected SourceIndexErrorKind) {
	if _ := index.position(offset) {
		assert false
	} else {
		assert err is SourceIndexError
		index_error := err as SourceIndexError
		assert index_error.kind == expected
	}
}
