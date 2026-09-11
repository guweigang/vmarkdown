module vmarkdown

import term

struct MarkdownSourceBlock {
	start_line int
	end_line   int
	text       string
}

struct PreviewLineSource {
	start_line     int
	end_line       int
	source_line    int
	source_columns []int
	exact_columns  []bool
}

struct PreviewColumnMatch {
	source_index int
	render_index int
}

fn scan_markdown_source_blocks(markdown string) []MarkdownSourceBlock {
	lines := markdown.split('\n')
	mut blocks := []MarkdownSourceBlock{}
	mut i := 0
	for i < lines.len {
		if lines[i].trim_space().len == 0 {
			i++
			continue
		}
		start := i
		trimmed := lines[i].trim_space()
		if trimmed.starts_with('```') || trimmed.starts_with('~~~') {
			fence := trimmed[..3]
			i++
			for i < lines.len {
				closing := lines[i].trim_space().starts_with(fence)
				i++
				if closing {
					break
				}
			}
		} else if is_single_line_markdown_block(trimmed) {
			i++
		} else if is_markdown_list_line(trimmed) || trimmed.starts_with('>') {
			i++
			for i < lines.len && lines[i].trim_space().len > 0 {
				i++
			}
		} else if i + 1 < lines.len && is_markdown_table_separator(lines[i + 1]) {
			i += 2
			for i < lines.len && lines[i].contains('|') && lines[i].trim_space().len > 0 {
				i++
			}
		} else {
			i++
			for i < lines.len && lines[i].trim_space().len > 0
				&& !starts_new_markdown_block(lines[i]) {
				i++
			}
		}
		end := max_int(i - 1, start)
		blocks << MarkdownSourceBlock{
			start_line: start
			end_line: end
			text: lines[start..end + 1].join('\n')
		}
	}
	return blocks
}

// ast_markdown_source_blocks uses parser-provided byte spans as the primary
// source of block boundaries. The syntax scanner is retained only for nodes
// such as thematic breaks for which md4c emits no source-bearing callback.
fn ast_markdown_source_blocks(markdown string) []MarkdownSourceBlock {
	doc := parse(markdown) or { return scan_markdown_source_blocks(markdown) }
	lines := markdown.split('\n')
	fallback := scan_markdown_source_blocks(markdown)
	mut blocks := []MarkdownSourceBlock{cap: doc.children.len}
	mut previous_end := -1
	for node in doc.children {
		span := node.source_span()
		mut start_line := -1
		mut end_line := -1
		if span.is_valid() && span.start < markdown.len {
			start_line = source_line_for_byte_offset(markdown, span.start)
			last_byte := if span.end > span.start { span.end - 1 } else { span.start }
			end_line = source_line_for_byte_offset(markdown, last_byte)
			if node is CodeBlockNode {
				start_line, end_line = expand_fenced_code_lines(lines, start_line, end_line)
			}
		}
		if start_line < 0 {
			for candidate in fallback {
				if candidate.start_line > previous_end {
					start_line = candidate.start_line
					end_line = candidate.end_line
					break
				}
			}
		}
		if start_line < 0 || start_line >= lines.len {
			continue
		}
		end_line = min_int(max_int(end_line, start_line), lines.len - 1)
		blocks << MarkdownSourceBlock{
			start_line: start_line
			end_line: end_line
			text: lines[start_line..end_line + 1].join('\n')
		}
		previous_end = end_line
	}
	return if blocks.len == doc.children.len { blocks } else { fallback }
}

fn source_line_for_byte_offset(markdown string, offset int) int {
	mut line := 0
	limit := min_int(max_int(offset, 0), markdown.len)
	for i, byte in markdown.bytes() {
		if i >= limit {
			break
		}
		if byte == `\n` {
			line++
		}
	}
	return line
}

fn expand_fenced_code_lines(lines []string, content_start int, content_end int) (int, int) {
	mut start := content_start
	mut end := content_end
	mut fence := ''
	if start > 0 {
		candidate := lines[start - 1].trim_space()
		if candidate.starts_with('```') || candidate.starts_with('~~~') {
			start--
			fence = candidate[..3]
		}
	}
	if fence.len > 0 {
		for i := end + 1; i < lines.len; i++ {
			if lines[i].trim_space().starts_with(fence) {
				end = i
				break
			}
		}
	}
	return start, end
}

fn is_single_line_markdown_block(line string) bool {
	if line.starts_with('#') {
		return true
	}
	compact := line.replace(' ', '')
	return compact.len >= 3 && compact.bytes().all(it in [`-`, `*`, `_`])
}

fn is_markdown_list_line(line string) bool {
	if line.starts_with('- ') || line.starts_with('* ') || line.starts_with('+ ') {
		return true
	}
	mut digit_count := 0
	for b in line.bytes() {
		if b >= `0` && b <= `9` {
			digit_count++
			continue
		}
		break
	}
	return digit_count > 0 && line.len > digit_count + 1 && line[digit_count] == `.`
		&& line[digit_count + 1] == ` `
}

fn is_markdown_table_separator(line string) bool {
	trimmed := line.trim_space()
	return trimmed.contains('|') && trimmed.contains('---')
}

fn starts_new_markdown_block(line string) bool {
	trimmed := line.trim_space()
	return is_single_line_markdown_block(trimmed) || is_markdown_list_line(trimmed)
		|| trimmed.starts_with('>') || trimmed.starts_with('```') || trimmed.starts_with('~~~')
}

fn build_preview_line_sources(markdown string, mode PreviewMode, width int, actual_lines []string) []PreviewLineSource {
	if actual_lines.len == 0 {
		return []PreviewLineSource{}
	}
	blocks := ast_markdown_source_blocks(markdown)
	if blocks.len == 0 {
		return []PreviewLineSource{len: actual_lines.len, init: PreviewLineSource{}}
	}
	mut starts := []int{len: blocks.len, init: -1}
	mut search_from := 0
	for block_index, block in blocks {
		block_lines := preview_lines(block.text, mode, width) or { []string{} }
		anchor := first_preview_anchor(block_lines, mode)
		found := find_preview_anchor(actual_lines, anchor, search_from, mode)
		starts[block_index] = if found >= 0 { found } else { search_from }
		search_from = min_int(starts[block_index] + 1, actual_lines.len)
	}
	for i := 1; i < starts.len; i++ {
		starts[i] = max_int(starts[i], starts[i - 1])
	}
	mut result := []PreviewLineSource{len: actual_lines.len}
	source_lines := markdown.split('\n')
	mut block_index := 0
	mut previous_block_index := -1
	mut current_source_line := 0
	mut source_offsets := map[int]int{}
	for line_index in 0 .. actual_lines.len {
		for block_index + 1 < blocks.len && line_index >= starts[block_index + 1] {
			block_index++
		}
		block := blocks[block_index]
		if block_index != previous_block_index {
			current_source_line = block.start_line
			previous_block_index = block_index
		}
		mut source_line := current_source_line
		mut columns := []int{}
		mut exact := []bool{}
		mut best_score := -1
		for candidate in current_source_line .. block.end_line + 1 {
			source_text := if candidate >= 0 && candidate < source_lines.len {
				source_lines[candidate]
			} else {
				''
			}
			candidate_columns, candidate_exact := build_preview_source_columns_from(source_text, actual_lines[line_index], mode, source_offsets[candidate])
			mut score := 0
			for is_exact in candidate_exact {
				if is_exact {
					score++
				}
			}
			if score > best_score {
				best_score = score
				source_line = candidate
				columns = candidate_columns.clone()
				exact = candidate_exact.clone()
			}
		}
		if best_score > 0 {
			current_source_line = source_line
			mut next_offset := source_offsets[source_line]
			for i, is_exact in exact {
				if is_exact && i < columns.len {
					next_offset = max_int(next_offset, columns[i] + 1)
				}
			}
			source_offsets[source_line] = next_offset
		}
		result[line_index] = PreviewLineSource{
			start_line: block.start_line
			end_line: block.end_line
			source_line: source_line
			source_columns: columns
			exact_columns: exact
		}
	}
	return result
}

fn build_preview_source_columns(source string, rendered string, mode PreviewMode) ([]int, []bool) {
	return build_preview_source_columns_from(source, rendered, mode, 0)
}

fn build_preview_source_columns_from(source string, rendered string, mode PreviewMode, start_source_column int) ([]int, []bool) {
	source_runes := source.runes()
	render_runes := term.strip_ansi(rendered).runes()
	matchable := preview_matchable_rune_indices(render_runes, mode)
	start := min_int(max_int(start_source_column, 0), source_runes.len)
	matches := preview_column_matches(source_runes[start..], render_runes, matchable)
	mut rune_columns := []int{len: render_runes.len, init: -1}
	mut rune_exact := []bool{len: render_runes.len}
	for item in matches {
		rune_columns[item.render_index] = item.source_index + start
		rune_exact[item.render_index] = true
	}
	fill_nearest_source_columns(mut rune_columns, source_runes.len, start)
	mut columns := []int{}
	mut exact := []bool{}
	for i, r in render_runes {
		width := max_int(editor_display_width(r.str()), 1)
		for _ in 0 .. width {
			columns << rune_columns[i]
			exact << rune_exact[i]
		}
	}
	mut end_column := start
	for i, is_exact in rune_exact {
		if is_exact {
			end_column = max_int(end_column, rune_columns[i] + 1)
		}
	}
	end_column = min_int(end_column, source_runes.len)
	columns << end_column
	exact << false
	return columns, exact
}

fn preview_matchable_rune_indices(rendered []rune, mode PreviewMode) []int {
	mut indices := []int{}
	if mode == .html {
		mut inside_tag := false
		for i, r in rendered {
			if r == `<` {
				inside_tag = true
				continue
			}
			if r == `>` {
				inside_tag = false
				continue
			}
			if !inside_tag {
				indices << i
			}
		}
		return indices
	}
	if mode == .ast {
		mut quotes := []int{}
		for i, r in rendered {
			if r == `"` {
				quotes << i
			}
		}
		if quotes.len >= 2 {
			for i in quotes[0] + 1 .. quotes.last() {
				indices << i
			}
			return indices
		}
		if quotes.len == 1 {
			quote := quotes[0]
			if quote == rendered.len - 1 {
				for i in 0 .. quote {
					indices << i
				}
			} else {
				for i in quote + 1 .. rendered.len {
					indices << i
				}
			}
			return indices
		}
		plain := rendered.string().trim_space()
		if plain == 'Document' || plain.starts_with('├') || plain.starts_with('└')
			|| plain.starts_with('│') {
			return indices
		}
	}
	for i in 0 .. rendered.len {
		indices << i
	}
	return indices
}

fn preview_column_matches(source []rune, rendered []rune, matchable []int) []PreviewColumnMatch {
	if source.len == 0 || matchable.len == 0 {
		return []PreviewColumnMatch{}
	}
	return greedy_preview_column_matches(source, rendered, matchable)
}

fn greedy_preview_column_matches(source []rune, rendered []rune, matchable []int) []PreviewColumnMatch {
	mut result := []PreviewColumnMatch{}
	mut source_index := 0
	for render_index in matchable {
		mut found := -1
		for candidate := source_index; candidate < source.len; candidate++ {
			if source[candidate] == rendered[render_index] {
				found = candidate
				break
			}
		}
		if found >= 0 {
			result << PreviewColumnMatch{
				source_index: found
				render_index: render_index
			}
			source_index = found + 1
		}
	}
	return result
}

fn fill_nearest_source_columns(mut columns []int, source_len int, fallback int) {
	mut first := -1
	for value in columns {
		if value >= 0 {
			first = value
			break
		}
	}
	if first < 0 {
		for i in 0 .. columns.len {
			columns[i] = min_int(max_int(fallback, 0), source_len)
		}
		return
	}
	mut current := first
	for i in 0 .. columns.len {
		if columns[i] >= 0 {
			current = columns[i]
		} else {
			columns[i] = current
		}
	}
}

fn source_column_at(source PreviewLineSource, display_column int) int {
	if source.source_columns.len == 0 {
		return max_int(display_column, 0)
	}
	index := min_int(max_int(display_column, 0), source.source_columns.len - 1)
	return source.source_columns[index]
}

fn source_column_is_exact(source PreviewLineSource, display_column int) bool {
	if source.exact_columns.len == 0 {
		return true
	}
	index := min_int(max_int(display_column, 0), source.exact_columns.len - 1)
	return source.exact_columns[index]
}

fn preview_column_for_source(source PreviewLineSource, source_column int) int {
	if source.source_columns.len == 0 {
		return max_int(source_column, 0)
	}
	mut best := 0
	mut distance := int(1 << 30)
	for i, column in source.source_columns {
		candidate := abs_int(column - source_column)
		if candidate < distance
			|| (candidate == distance && i < source.exact_columns.len && source.exact_columns[i]) {
			best = i
			distance = candidate
		}
		if candidate == 0 && i < source.exact_columns.len && source.exact_columns[i] {
			return i
		}
	}
	return best
}

fn first_preview_anchor(lines []string, mode PreviewMode) string {
	for line in lines {
		normalized := normalize_preview_anchor(line, mode)
		if normalized.len > 0 && normalized != 'Document' {
			return normalized
		}
	}
	return ''
}

fn find_preview_anchor(lines []string, anchor string, start int, mode PreviewMode) int {
	if anchor.len == 0 {
		return -1
	}
	for i := max_int(start, 0); i < lines.len; i++ {
		candidate := normalize_preview_anchor(lines[i], mode)
		if candidate == anchor || (candidate.len >= 6 && anchor.contains(candidate))
			|| (anchor.len >= 6 && candidate.contains(anchor)) {
			return i
		}
	}
	return -1
}

fn normalize_preview_anchor(line string, mode PreviewMode) string {
	mut normalized := term.strip_ansi(line).trim_space()
	if mode == .ast {
		normalized = normalized.trim_left(' │├└─')
	}
	return normalized
}

fn find_preview_line_for_source(sources []PreviewLineSource, source_line int) int {
	return find_preview_line_for_source_position(sources, source_line, 0)
}

fn find_preview_line_for_source_position(sources []PreviewLineSource, source_line int, source_column int) int {
	if sources.len == 0 {
		return 0
	}
	mut closest := 0
	mut closest_line_rank := int(1 << 30)
	mut closest_column_rank := int(1 << 30)
	mut closest_column_distance := int(1 << 30)
	for i, source in sources {
		line_rank := if source.source_line == source_line {
			0
		} else if source_line >= source.start_line && source_line <= source.end_line {
			1 + abs_int(source.source_line - source_line)
		} else {
			1000 + abs_int(source.source_line - source_line)
		}
		column_distance, exact := preview_source_column_distance(source, source_column)
		column_rank := if exact { 0 } else { 1 }
		if line_rank < closest_line_rank
			|| (line_rank == closest_line_rank && column_rank < closest_column_rank)
			|| (line_rank == closest_line_rank && column_rank == closest_column_rank
				&& column_distance < closest_column_distance) {
			closest = i
			closest_line_rank = line_rank
			closest_column_rank = column_rank
			closest_column_distance = column_distance
		}
	}
	return closest
}

fn preview_source_column_distance(source PreviewLineSource, source_column int) (int, bool) {
	if source.source_columns.len == 0 {
		return abs_int(source_column), false
	}
	mut closest := int(1 << 30)
	mut exact := false
	for i, column in source.source_columns {
		distance := abs_int(column - source_column)
		if distance < closest {
			closest = distance
		}
		if distance == 0 && i < source.exact_columns.len && source.exact_columns[i] {
			exact = true
		}
	}
	return closest, exact
}

fn abs_int(value int) int {
	return if value < 0 { -value } else { value }
}
