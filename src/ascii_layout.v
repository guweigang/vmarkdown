module vmarkdown

pub struct AsciiRelationOptions {
pub:
	gap          int = 4
	width        int = 80
	label        string
	with_stubs   bool
	align_in_gap bool
	align_y      string = 'bottom'
}

pub struct AsciiTripleRelationOptions {
pub:
	left_gap    int = 8
	right_gap   int = 8
	width       int = 80
	left_label  string
	right_label string
	align_y     string = 'middle'
}

pub fn ascii_box(title string, rows []string, width int) string {
	mut inner_width := display_width(title)
	for row in rows {
		inner_width = max_int(inner_width, display_width(row))
	}
	inner_width = min_int(inner_width + 2, max_int(width - 4, inner_width + 2))
	mut lines := []string{}
	lines << '╭' + '─'.repeat(inner_width + 2) + '╮'
	title_line := truncate_display_width(title, inner_width)
	lines << '│ ' + title_line + ' '.repeat(max_int(inner_width - display_width(title_line), 0)) +
		' │'
	if rows.len > 0 {
		lines << '├' + '─'.repeat(inner_width + 2) + '┤'
		for row in rows {
			content := truncate_display_width(row, inner_width)
			lines << '│ ' + content + ' '.repeat(max_int(inner_width -
				display_width(content), 0)) + ' │'
		}
	}
	lines << '╰' + '─'.repeat(inner_width + 2) + '╯'
	return lines.join('\n')
}

pub fn ascii_row(blocks []string, gap int, width int) string {
	if blocks.len == 0 {
		return ''
	}
	if blocks.len == 1 {
		return blocks[0]
	}
	block_lines := blocks.map(it.split_into_lines())
	mut widths := []int{}
	mut max_height := 0
	for lines in block_lines {
		mut block_width := 0
		for line in lines {
			block_width = max_int(block_width, ascii_block_width(line))
		}
		widths << block_width
		max_height = max_int(max_height, lines.len)
	}
	gap_text := ' '.repeat(gap)
	mut out := []string{}
	for row in 0 .. max_height {
		mut parts := []string{}
		for i, lines in block_lines {
			top_pad := max_int(max_height - lines.len, 0)
			adjusted_row := row - top_pad
			line := if adjusted_row >= 0 && adjusted_row < lines.len {
				lines[adjusted_row]
			} else {
				''
			}
			padding := ' '.repeat(max_int(widths[i] - ascii_block_width(line), 0))
			parts << line + padding
		}
		out << truncate_display_width(parts.join(gap_text), width)
	}
	return out.join('\n')
}

pub fn ascii_dual_relation(left string, right string, relation string, options AsciiRelationOptions) string {
	left_lines := left.split_into_lines()
	right_lines := right.split_into_lines()
	left_width := ascii_block_width(left)
	right_width := ascii_block_width(right)
	max_height := max_int(left_lines.len, right_lines.len)
	row_width := min_int(left_width + options.gap + right_width, options.width)
	gap_text := ' '.repeat(options.gap)
	mut out := []string{}
	mut left_center_row := 0
	mut right_center_row := 0
	for row in 0 .. max_height {
		left_delta := max_int(max_height - left_lines.len, 0)
		right_delta := max_int(max_height - right_lines.len, 0)
		left_top_pad := if options.align_y == 'middle' { left_delta / 2 } else { left_delta }
		right_top_pad := if options.align_y == 'middle' { right_delta / 2 } else { right_delta }
		left_center_row = left_top_pad + left_lines.len / 2
		right_center_row = right_top_pad + right_lines.len / 2
		left_row := row - left_top_pad
		right_row := row - right_top_pad
		left_line := if left_row >= 0 && left_row < left_lines.len {
			left_lines[left_row]
		} else {
			''
		}
		right_line := if right_row >= 0 && right_row < right_lines.len {
			right_lines[right_row]
		} else {
			''
		}
		left_padding := ' '.repeat(max_int(left_width - ascii_block_width(left_line), 0))
		right_padding := ' '.repeat(max_int(right_width - ascii_block_width(right_line), 0))
		out << truncate_display_width(left_line + left_padding + gap_text + right_line +
			right_padding, row_width)
	}
	rel_core := if options.label.len > 0 { relation + '  ' + options.label } else { relation }
	if options.align_in_gap {
		gap_width := max_int(min_int(options.gap, row_width - left_width), display_width(rel_core))
		gap_start := left_width + max_int((options.gap - gap_width) / 2, 0)
		rel_runes := rel_core.runes()
		rel_start := gap_start + max_int((gap_width - rel_runes.len) / 2, 0)
		relation_row := min_int(max_int((left_center_row + right_center_row) / 2, 0), out.len - 1)
		mut relation_chars := out[relation_row].runes()
		if relation_chars.len < row_width {
			relation_chars << []rune{len: row_width - relation_chars.len, init: ` `}
		}
		for i, ch in rel_runes {
			pos := rel_start + i
			if pos >= 0 && pos < relation_chars.len {
				relation_chars[pos] = ch
			}
		}
		out[relation_row] = relation_chars.string().trim_right(' ')
		return out.join('\n')
	}
	if !options.with_stubs {
		out << ascii_center_line(truncate_display_width(rel_core, row_width), row_width)
		return out.join('\n')
	}
	left_center := left_width / 2
	right_center := left_width + options.gap + right_width / 2
	mut relation_chars := []rune{len: row_width, init: ` `}
	core_width := display_width(relation)
	mut core_start := max_int((left_center + right_center - core_width) / 2, left_center + 1)
	if core_start + core_width >= row_width {
		core_start = max_int(row_width - core_width, 0)
	}
	for i in left_center + 1 .. core_start {
		if i >= 0 && i < relation_chars.len {
			relation_chars[i] = `─`
		}
	}
	core_runes := relation.runes()
	for i, ch in core_runes {
		pos := core_start + i
		if pos >= 0 && pos < relation_chars.len {
			relation_chars[pos] = ch
		}
	}
	core_end := core_start + core_runes.len
	for i in core_end .. right_center {
		if i >= 0 && i < relation_chars.len {
			relation_chars[i] = `─`
		}
	}
	out << relation_chars.string().trim_right(' ')
	if options.label.len > 0 {
		label_pos := core_start + max_int((core_width - display_width(options.label)) / 2, 0)
		out << ' '.repeat(max_int(label_pos, 0)) + options.label
	}
	return out.join('\n')
}

pub fn ascii_td_branch(source_block string, label string, targets []string, arrow bool) string {
	if targets.len == 0 {
		return source_block
	}
	source_lines := source_block.split_into_lines()
	source_width := ascii_block_width(source_block)
	center := max_int(source_width / 2, 0)
	mut out := []string{}
	for line in source_lines {
		out << line
	}
	out << ' '.repeat(center) + '│'
	if label.len > 0 {
		out << ' '.repeat(max_int(center - display_width(label) / 2, 0)) + label
	}
	edge := if arrow { '─▶' } else { '──' }
	for i, target in targets {
		connector := if i == targets.len - 1 { '└' } else { '├' }
		out << ' '.repeat(center) + connector + edge + ' ' + target
	}
	return out.join('\n')
}

pub fn ascii_td_branch_merge(source_block string, branch_label string, mids []string, merge_label string, target string, merge_arrow bool) string {
	if mids.len == 0 {
		return source_block
	}
	source_lines := source_block.split_into_lines()
	source_width := ascii_block_width(source_block)
	center := max_int(source_width / 2, 0)
	mut out := []string{}
	for line in source_lines {
		out << line
	}
	out << ' '.repeat(center) + '│'
	if branch_label.len > 0 {
		out << ' '.repeat(max_int(center - display_width(branch_label) / 2, 0)) + branch_label
	}
	mut branch_lines := []string{}
	mut max_branch_width := 0
	for i, mid in mids {
		connector := if i == mids.len - 1 { '└' } else { '├' }
		line := ' '.repeat(center) + connector + '─▶ ' + mid
		branch_lines << line
		max_branch_width = max_int(max_branch_width, display_width(line))
	}
	merge_edge := if merge_arrow { '─▶' } else { '──' }
	merge_suffix := if merge_label.len > 0 {
		' ─ ' + merge_label + ' ' + merge_edge + ' ' + target
	} else {
		' ' + merge_edge + ' ' + target
	}
	for i, branch_line in branch_lines {
		padding := ' '.repeat(max_int(max_branch_width - display_width(branch_line), 0))
		connector := if i == branch_lines.len - 1 { '┴' } else { '┐' }
		line := if i == branch_lines.len - 1 {
			branch_line + padding + ' ' + connector + merge_suffix
		} else {
			branch_line + padding + ' ' + connector
		}
		out << line
	}
	return out.join('\n')
}

pub fn ascii_td_merge(sources []string, label string, target string, arrow bool) string {
	if sources.len < 2 {
		return ''
	}
	mut max_source_width := 0
	for source in sources {
		max_source_width = max_int(max_source_width, display_width(source))
	}
	suffix := if label.len > 0 {
		' ─ ' + label + ' ' + if arrow { '─▶ ' } else { '── ' } + target
	} else {
		' ' + if arrow { '─▶ ' } else { '── ' } + target
	}
	mut out := []string{}
	for i, source in sources {
		padding := ' '.repeat(max_int(max_source_width - display_width(source), 0))
		connector := if i == sources.len - 1 { '┴' } else { '┐' }
		line := if i == sources.len - 1 {
			source + padding + ' ' + connector + suffix
		} else {
			source + padding + ' ' + connector
		}
		out << line
	}
	return out.join('\n')
}

pub fn ascii_lr_branch(source string, label string, targets []string) string {
	if targets.len == 0 {
		return source
	}
	mut lines := []string{}
	if label.len > 0 {
		lines << source + ' ─ ' + label
		lines << ' '.repeat(display_width(source) + 1) + '│'
	}
	for i, target in targets {
		connector := if i == 0 {
			'┬'
		} else if i == targets.len - 1 {
			'└'
		} else {
			'├'
		}
		prefix := if i == 0 {
			source + ' ─' + connector + '─▶ '
		} else {
			' '.repeat(display_width(source) + 2) + connector + '─▶ '
		}
		lines << prefix + target
	}
	return lines.join('\n')
}

pub fn ascii_lr_branch_merge(source string, branch_label string, mids []string, merge_label string, target string) string {
	if mids.len == 0 {
		return source
	}
	mut prefix_lines := []string{}
	if branch_label.len > 0 {
		prefix_lines << source + ' ─ ' + branch_label
		prefix_lines << ' '.repeat(display_width(source) + 1) + '│'
	}
	mut branch_lines := []string{}
	mut max_branch_width := 0
	for i, mid in mids {
		connector := if i == 0 {
			'┬'
		} else if i == mids.len - 1 {
			'└'
		} else {
			'├'
		}
		prefix := if i == 0 {
			source + ' ─' + connector + '─▶ '
		} else {
			' '.repeat(display_width(source) + 2) + connector + '─▶ '
		}
		line := prefix + mid
		branch_lines << line
		max_branch_width = max_int(max_branch_width, display_width(line))
	}
	merge_suffix := if merge_label.len > 0 {
		' ─ ' + merge_label + ' ─▶ ' + target
	} else {
		' ─▶ ' + target
	}
	mut lines := prefix_lines.clone()
	for i, branch_line in branch_lines {
		padding := ' '.repeat(max_int(max_branch_width - display_width(branch_line), 0))
		connector := if i == 0 {
			'┐'
		} else if i == branch_lines.len - 1 {
			'┴'
		} else {
			'┤'
		}
		line := if i == branch_lines.len - 1 {
			branch_line + padding + ' ' + connector + merge_suffix
		} else {
			branch_line + padding + ' ' + connector
		}
		lines << line
	}
	return lines.join('\n')
}

pub fn ascii_lr_merge(sources []string, label string, target string) string {
	if sources.len < 2 {
		return ''
	}
	mut max_source_width := 0
	for source in sources {
		max_source_width = max_int(max_source_width, display_width(source))
	}
	suffix := if label.len > 0 {
		' ─ ' + label + ' ─▶ ' + target
	} else {
		' ─▶ ' + target
	}
	mut lines := []string{}
	for i, source in sources {
		padding := ' '.repeat(max_int(max_source_width - display_width(source), 0))
		connector := if i == 0 {
			'┐'
		} else if i == sources.len - 1 {
			'┴'
		} else {
			'┤'
		}
		line := if i == sources.len - 1 {
			source + padding + ' ' + connector + suffix
		} else {
			source + padding + ' ' + connector
		}
		lines << line
	}
	return lines.join('\n')
}

pub fn ascii_inline_edge(arrow bool, label string) string {
	mut edge := if arrow { '──▶' } else { '───' }
	if label.len > 0 {
		edge = '─ ' + label + ' ' + edge
	}
	return edge
}

pub fn ascii_wrap_segments(segments []string, width int) []string {
	if segments.len == 0 {
		return ['']
	}
	mut lines := []string{}
	mut current := []string{}
	mut used := 0
	for segment in segments {
		seg_width := display_width(segment)
		if used > 0 && used + 1 + seg_width > width {
			lines << current.join(' ')
			current = [segment]
			used = seg_width
			continue
		}
		if used > 0 {
			used += 1
		}
		current << segment
		used += seg_width
	}
	if current.len > 0 {
		lines << current.join(' ')
	}
	return lines
}

pub fn ascii_vertical_edge(block_width int, arrow bool, label string) []string {
	center := max_int(block_width / 2, 0)
	padding := ' '.repeat(center)
	mut lines := []string{}
	lines << padding + '│'
	if label.len > 0 {
		label_padding := ' '.repeat(max_int(center - display_width(label) / 2, 0))
		lines << label_padding + label
	}
	lines << if arrow { padding + '▼' } else { padding + '│' }
	return lines
}

pub fn ascii_center_line(line string, width int) string {
	padding := max_int((width - display_width(line)) / 2, 0)
	return ' '.repeat(padding) + line
}

pub fn ascii_titled_frame(title string, body string, width int) string {
	body_lines := body.split_into_lines()
	mut inner_width := display_width(title) + 1
	for line in body_lines {
		inner_width = max_int(inner_width, display_width(line))
	}
	inner_width = min_int(inner_width, max_int(width - 4, inner_width))
	top := '╭ ' + title + ' ' + '─'.repeat(max_int(inner_width - display_width(title), 0)) +
		'╮'
	bottom := '╰' + '─'.repeat(inner_width + 2) + '╯'
	mut lines := [top]
	for line in body_lines {
		content := truncate_display_width(line, inner_width)
		padding := ' '.repeat(max_int(inner_width - display_width(content), 0))
		lines << '│ ' + content + padding + ' │'
	}
	lines << bottom
	return lines.join('\n')
}

pub fn ascii_triple_relation(left string, middle string, right string, left_relation string, right_relation string, options AsciiTripleRelationOptions) string {
	left_lines := left.split_into_lines()
	middle_lines := middle.split_into_lines()
	right_lines := right.split_into_lines()
	left_width := ascii_block_width(left)
	middle_width := ascii_block_width(middle)
	right_width := ascii_block_width(right)
	max_height := max_int(max_int(left_lines.len, middle_lines.len), right_lines.len)
	row_width := min_int(left_width + options.left_gap + middle_width + options.right_gap +
		right_width, options.width)
	mut out := []string{}
	middle_delta := max_int(max_height - middle_lines.len, 0)
	middle_top_pad := if options.align_y == 'middle' { middle_delta / 2 } else { middle_delta }
	relation_row := middle_top_pad + middle_lines.len / 2
	for row in 0 .. max_height {
		left_delta := max_int(max_height - left_lines.len, 0)
		right_delta := max_int(max_height - right_lines.len, 0)
		left_top_pad := if options.align_y == 'middle' { left_delta / 2 } else { left_delta }
		right_top_pad := if options.align_y == 'middle' { right_delta / 2 } else { right_delta }
		left_row := row - left_top_pad
		middle_row := row - middle_top_pad
		right_row := row - right_top_pad
		left_line := if left_row >= 0 && left_row < left_lines.len {
			left_lines[left_row]
		} else {
			''
		}
		middle_line := if middle_row >= 0 && middle_row < middle_lines.len {
			middle_lines[middle_row]
		} else {
			''
		}
		right_line := if right_row >= 0 && right_row < right_lines.len {
			right_lines[right_row]
		} else {
			''
		}
		left_padding := ' '.repeat(max_int(left_width - ascii_block_width(left_line), 0))
		middle_padding := ' '.repeat(max_int(middle_width - ascii_block_width(middle_line), 0))
		right_padding := ' '.repeat(max_int(right_width - ascii_block_width(right_line), 0))
		out << truncate_display_width(left_line + left_padding + ' '.repeat(options.left_gap) +
			middle_line + middle_padding + ' '.repeat(options.right_gap) + right_line +
			right_padding, row_width)
	}
	if out.len == 0 {
		return ''
	}
	mut chars := out[relation_row].runes()
	if chars.len < row_width {
		chars << []rune{len: row_width - chars.len, init: ` `}
	}
	left_text := if options.left_label.len > 0 {
		left_relation + '  ' + options.left_label
	} else {
		left_relation
	}
	right_text := if options.right_label.len > 0 {
		right_relation + '  ' + options.right_label
	} else {
		right_relation
	}
	left_start := left_width + max_int((options.left_gap - display_width(left_text)) / 2, 0)
	for i, ch in left_text.runes() {
		pos := left_start + i
		if pos >= 0 && pos < chars.len {
			chars[pos] = ch
		}
	}
	right_start := left_width + options.left_gap + middle_width + max_int((options.right_gap -
		display_width(right_text)) / 2, 0)
	for i, ch in right_text.runes() {
		pos := right_start + i
		if pos >= 0 && pos < chars.len {
			chars[pos] = ch
		}
	}
	out[relation_row] = chars.string().trim_right(' ')
	return out.join('\n')
}

pub fn ascii_side_by_side_middle(left string, right string, gap int, width int) string {
	left_lines := left.split_into_lines()
	right_lines := right.split_into_lines()
	left_width := ascii_block_width(left)
	right_width := ascii_block_width(right)
	max_height := max_int(left_lines.len, right_lines.len)
	left_delta := max_int(max_height - left_lines.len, 0)
	right_delta := max_int(max_height - right_lines.len, 0)
	// Bias shorter blocks one row lower when heights differ by an odd number.
	left_top_pad := (left_delta + 1) / 2
	right_top_pad := (right_delta + 1) / 2
	mut out := []string{}
	for row in 0 .. max_height {
		left_row := row - left_top_pad
		right_row := row - right_top_pad
		left_line := if left_row >= 0 && left_row < left_lines.len {
			left_lines[left_row]
		} else {
			''
		}
		right_line := if right_row >= 0 && right_row < right_lines.len {
			right_lines[right_row]
		} else {
			''
		}
		left_padding := ' '.repeat(max_int(left_width - ascii_block_width(left_line), 0))
		right_padding := ' '.repeat(max_int(right_width - ascii_block_width(right_line), 0))
		out << truncate_display_width(left_line + left_padding + ' '.repeat(gap) + right_line +
			right_padding, width)
	}
	return out.join('\n')
}

pub fn ascii_lr_merge_to_gap(sources []string, label string) string {
	if sources.len < 2 {
		return ''
	}
	mut max_source_width := 0
	for source in sources {
		max_source_width = max_int(max_source_width, display_width(source))
	}
	suffix := if label.len > 0 { ' ─ ' + label + ' ─▶' } else { ' ─▶' }
	if sources.len == 2 {
		top_padding := ' '.repeat(max_int(max_source_width - display_width(sources[0]), 0))
		bottom_padding := ' '.repeat(max_int(max_source_width - display_width(sources[1]), 0))
		center_prefix := ' '.repeat(max_source_width + 1)
		return [
			sources[0] + top_padding + ' ┐',
			center_prefix + '┼' + suffix,
			sources[1] + bottom_padding + ' ┘',
		].join('\n')
	}
	mut lines := []string{}
	for i, source in sources {
		padding := ' '.repeat(max_int(max_source_width - display_width(source), 0))
		connector := if i == sources.len - 1 { '┴' } else { '┐' }
		line := if i == sources.len - 1 {
			source + padding + ' ' + connector + suffix
		} else {
			source + padding + ' ' + connector
		}
		lines << line
	}
	return lines.join('\n')
}

pub fn ascii_lr_branch_from_gap(label string, targets []string) string {
	if targets.len == 0 {
		return ''
	}
	mut lines := []string{}
	prefix := if label.len > 0 { '─ ' + label + ' ' } else { '' }
	if targets.len == 1 {
		lines << prefix + '──▶ ' + targets[0]
		return lines.join('\n')
	}
	if targets.len == 2 {
		prefix_width := display_width(prefix)
		branch_prefix := ' '.repeat(prefix_width)
		lines << branch_prefix + '┌─▶ ' + targets[0]
		lines << prefix + '┤'
		lines << branch_prefix + '└─▶ ' + targets[1]
		return lines.join('\n')
	}
	for i, target in targets {
		connector := if i == 0 {
			'┬'
		} else if i == targets.len - 1 {
			'└'
		} else {
			'├'
		}
		if i == 0 {
			lines << prefix + connector + '─▶ ' + target
		} else {
			lines << ' '.repeat(display_width(prefix)) + connector + '─▶ ' + target
		}
	}
	return lines.join('\n')
}

pub fn ascii_block_width(block string) int {
	mut max_width := 0
	for line in block.split_into_lines() {
		max_width = max_int(max_width, display_width(line))
	}
	return max_width
}

pub fn ascii_fit_lane(input string, lane_width int) string {
	plain := truncate_display_width(input, lane_width)
	padding := ' '.repeat(max_int(lane_width - display_width(plain), 0))
	return plain + padding
}

pub fn ascii_lane_centers(count int, lane_width int) []int {
	mut centers := []int{}
	for i := 0; i < count; i++ {
		centers << i * (lane_width + 2) + lane_width / 2
	}
	return centers
}

pub fn ascii_lifelines(labels []string, lane_width int, active map[string]bool) string {
	mut parts := []string{}
	for label in labels {
		mut lane := []rune{len: lane_width, init: ` `}
		center := lane_width / 2
		lane[center] = if label in active && active[label] { `║` } else { `│` }
		parts << lane.string()
	}
	return parts.join('  ')
}

pub fn ascii_lane_headers(labels []string, lane_width int) string {
	mut top_parts := []string{}
	mut mid_parts := []string{}
	mut bottom_parts := []string{}
	for label in labels {
		text := truncate_display_width(label, lane_width - 2)
		left_pad := ' '.repeat(max_int((lane_width - 2 - display_width(text)) / 2, 0))
		right_pad := ' '.repeat(max_int(lane_width - 2 - display_width(text) -
			display_width(left_pad), 0))
		top_parts << '┌' + '─'.repeat(lane_width - 2) + '┐'
		mid_parts << '│' + left_pad + text + right_pad + '│'
		center := lane_width / 2
		mut bottom_chars := ('└' + '─'.repeat(lane_width - 2) + '┘').runes()
		if center < bottom_chars.len {
			bottom_chars[center] = `┴`
		}
		bottom_parts << bottom_chars.string()
	}
	return [top_parts.join('  '), mid_parts.join('  '), bottom_parts.join('  ')].join('\n')
}
