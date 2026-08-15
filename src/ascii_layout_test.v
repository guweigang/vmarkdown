module vmarkdown

fn test_ascii_box_renders_title_and_rows() {
	box := ascii_box('Animal', ['+name string', '+speak()'], 40)
	assert box.contains('Animal')
	assert box.contains('+name string')
	assert box.contains('╭')
	assert box.contains('╰')
}

fn test_ascii_row_bottom_aligns_shorter_block() {
	left := ascii_box('Animal', ['+name string'], 30)
	right := ascii_box('Dog', []string{}, 20)
	row := ascii_row([left, right], 4, 80)
	lines := row.split_into_lines()
	assert lines.len >= 3
	assert lines[lines.len - 1].contains('╰')
}

fn test_ascii_dual_relation_places_label() {
	left := ascii_box('USER', ['string id'], 30)
	right := ascii_box('ORDER', ['string id'], 30)
	out := ascii_dual_relation(left, right, '||--o{', AsciiRelationOptions{
		gap:   6
		width: 80
		label: 'places'
	})
	assert out.contains('||--o{')
	assert out.contains('places')
}

fn test_ascii_dual_relation_can_align_relation_in_gap() {
	left := ascii_box('Animal', ['+speak()'], 28)
	right := ascii_box('Dog', []string{}, 20)
	out := ascii_dual_relation(left, right, '<|--', AsciiRelationOptions{
		gap:          18
		width:        80
		label:        'inherits'
		align_in_gap: true
	})
	lines := out.split_into_lines()
	assert lines.len >= 2
	assert out.contains('<|--')
	assert out.contains('inherits')
}

fn test_ascii_lane_headers_and_lifelines() {
	headers := ascii_lane_headers(['Alice', 'Bob'], 10)
	assert headers.contains('Alice')
	assert headers.contains('Bob')
	lifelines := ascii_lifelines(['Alice', 'Bob'], 10, {
		'Bob': true
	})
	assert lifelines.contains('│')
	assert lifelines.contains('║')
}

fn test_ascii_td_branch_layout() {
	source := ascii_box('Start', []string{}, 24)
	out := ascii_td_branch(source, '', ['[Parse]', '[Validate]'], true)
	assert out.contains('Start')
	assert out.contains('├─▶ [Parse]')
	assert out.contains('└─▶ [Validate]')
}

fn test_ascii_td_branch_merge_layout() {
	source := ascii_box('Start', []string{}, 24)
	out := ascii_td_branch_merge(source, '', ['[Parse]', '[Validate]'], '', '[Done]', true)
	assert out.contains('Start')
	assert out.contains('[Done]')
	assert out.contains('┴')
}

fn test_ascii_td_merge_layout() {
	out := ascii_td_merge(['[Parse]', '[Validate]'], '', '[Done]', true)
	assert out.contains('[Parse]')
	assert out.contains('[Validate]')
	assert out.contains('[Done]')
}

fn test_ascii_lr_branch_layout() {
	out := ascii_lr_branch('[Start]', '', ['[Parse]', '[Validate]'])
	assert out.contains('[Start] ─┬─▶ [Parse]')
	assert out.contains('└─▶ [Validate]')
}

fn test_ascii_lr_branch_merge_layout() {
	out := ascii_lr_branch_merge('[Start]', '', ['[Parse]', '[Validate]'], '', '[Done]')
	assert out.contains('[Start]')
	assert out.contains('[Done]')
	assert out.contains('┴')
}

fn test_ascii_lr_merge_layout() {
	out := ascii_lr_merge(['[Parse]', '[Validate]'], '', '[Done]')
	assert out.contains('[Parse]')
	assert out.contains('[Validate]')
	assert out.contains('[Done]')
}

fn test_ascii_inline_edge_and_wrap_segments() {
	segments := ['[Start]', ascii_inline_edge(true, ''), '[Parse]', ascii_inline_edge(true, 'yes'),
		'[Done]']
	out := ascii_wrap_segments(segments, 24).join('\n')
	assert out.contains('[Start]')
	assert out.contains('──▶')
	assert out.contains('yes')
}

fn test_ascii_vertical_edge_with_label() {
	lines := ascii_vertical_edge(11, true, 'start')
	assert lines.len >= 3
	assert lines[1].contains('start')
	assert lines[2].contains('▼')
}
