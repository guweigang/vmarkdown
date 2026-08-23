module vmarkdown

import term

struct MarkdownSourceBlock {
	start_line int
	end_line   int
	text       string
}

struct PreviewLineSource {
	start_line  int
	end_line    int
	source_line int
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
			end_line:   end
			text:       lines[start..end + 1].join('\n')
		}
	}
	return blocks
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
	blocks := scan_markdown_source_blocks(markdown)
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
	mut block_index := 0
	for line_index in 0 .. actual_lines.len {
		for block_index + 1 < blocks.len && line_index >= starts[block_index + 1] {
			block_index++
		}
		block := blocks[block_index]
		local_line := max_int(line_index - starts[block_index], 0)
		result[line_index] = PreviewLineSource{
			start_line:  block.start_line
			end_line:    block.end_line
			source_line: min_int(block.start_line + local_line, block.end_line)
		}
	}
	return result
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
	if sources.len == 0 {
		return 0
	}
	mut closest := 0
	mut closest_distance := int(1 << 30)
	for i, source in sources {
		if source_line >= source.start_line && source_line <= source.end_line {
			if source.source_line == source_line {
				return i
			}
			distance := abs_int(source.source_line - source_line)
			if distance < closest_distance {
				closest = i
				closest_distance = distance
			}
		}
	}
	if closest_distance < int(1 << 30) {
		return closest
	}
	for i, source in sources {
		distance := abs_int(source.source_line - source_line)
		if distance < closest_distance {
			closest = i
			closest_distance = distance
		}
	}
	return closest
}

fn abs_int(value int) int {
	return if value < 0 { -value } else { value }
}
