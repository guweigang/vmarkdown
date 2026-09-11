module vmarkdown

// ASCII renderers for non-flow Mermaid diagram families.

fn (diagram MermaidDiagram) render_state_ascii(width int) string {
	mut lines := []string{}
	for transition in diagram.state_transitions {
		from_ref := render_mermaid_state_ref(transition.from)
		to_ref := render_mermaid_state_ref(transition.to)
		mut line := from_ref + ' ─▶ ' + to_ref
		if transition.label.len > 0 {
			line += '  · ' + transition.label
		}
		lines << truncate_display_width(line, width)
	}
	return lines.join('\n')
}

fn render_mermaid_state_ref(name string) string {
	return if name == '[*]' { '◉' } else { '[' + name + ']' }
}

fn (diagram MermaidDiagram) render_class_ascii(width int) string {
	if diagram.classes.len == 2 && diagram.class_relations.len == 1 {
		relation := diagram.class_relations[0]
		gap := max_int(8, display_width(relation.kind) + display_width(relation.label) + 4)
		column_width := max_int((width - gap) / 2, 20)
		left := ascii_box(diagram.classes[0].name, diagram.classes[0].members, column_width)
		right := ascii_box(diagram.classes[1].name, diagram.classes[1].members, column_width)
		return ascii_dual_relation(left, right, relation.kind, AsciiRelationOptions{
			gap:          gap
			width:        width
			label:        relation.label
			align_in_gap: true
			align_y:      'middle'
		})
	}
	mut parts := []string{}
	for class_def in diagram.classes {
		parts << ascii_box(class_def.name, class_def.members, width)
	}
	if diagram.class_relations.len > 0 {
		mut rel_lines := []string{}
		for relation in diagram.class_relations {
			mut line := '[${relation.left}] ${relation.kind} [${relation.right}]'
			if relation.label.len > 0 {
				line += ' : ' + relation.label
			}
			rel_lines << truncate_display_width(line, width)
		}
		parts << rel_lines.join('\n')
	}
	return parts.join('\n\n')
}

fn (diagram MermaidDiagram) render_er_ascii(width int) string {
	if diagram.entities.len == 2 && diagram.entity_relations.len == 1 {
		relation := diagram.entity_relations[0]
		rel_text := relation.left_card + '--' + relation.right_card
		gap := max_int(8, display_width(rel_text) + display_width(relation.label) + 4)
		column_width := max_int((width - gap) / 2, 20)
		left := ascii_box(diagram.entities[0].name, diagram.entities[0].attributes, column_width)
		right := ascii_box(diagram.entities[1].name, diagram.entities[1].attributes, column_width)
		return ascii_dual_relation(left, right, relation.left_card + '--' + relation.right_card, AsciiRelationOptions{
			gap:          gap
			width:        width
			label:        relation.label
			align_in_gap: true
			align_y:      'middle'
		})
	}
	mut parts := []string{}
	for entity in diagram.entities {
		parts << ascii_box(entity.name, entity.attributes, width)
	}
	if diagram.entity_relations.len > 0 {
		mut rel_lines := []string{}
		for relation in diagram.entity_relations {
			mut line := '[${relation.left}] ${relation.left_card}--${relation.right_card} [${relation.right}]'
			if relation.label.len > 0 {
				line += ' : ' + relation.label
			}
			rel_lines << truncate_display_width(line, width)
		}
		parts << rel_lines.join('\n')
	}
	return parts.join('\n\n')
}

fn (diagram MermaidDiagram) render_gantt_ascii(width int) string {
	mut lines := []string{}
	if diagram.title.len > 0 {
		lines << truncate_display_width(diagram.title, width)
		lines << truncate_display_width('─'.repeat(min_int(max_int(display_width(diagram.title), 8),
			width)), width)
		lines << ''
	}
	mut task_label_width := 12
	for section in diagram.gantt_sections {
		for task in section.tasks {
			task_label_width = max_int(task_label_width, display_width(task.title))
		}
	}
	task_label_width = min_int(task_label_width + 1, min_int(max_int(width / 4, 12), 18))
	for section in diagram.gantt_sections {
		lines << '▎ ' + truncate_display_width(section.title, max_int(width - 2, 0))
		for task in section.tasks {
			lines << render_gantt_task(task, task_label_width, width)
		}
		lines << ''
	}
	for lines.len > 0 && lines[lines.len - 1].len == 0 {
		lines.delete(lines.len - 1)
	}
	return lines.join('\n')
}

fn (diagram MermaidDiagram) render_mindmap_ascii(width int) string {
	if diagram.mindmap_root.label.len == 0 {
		return ''
	}
	mut lines := []string{}
	lines << '◉ ' + truncate_display_width(diagram.mindmap_root.label, width - 2)
	render_mindmap_children(diagram.mindmap_root.children, '', mut lines, width)
	return lines.join('\n')
}

fn render_mindmap_children(children []MermaidMindmapNode, prefix string, mut lines []string, width int) {
	for i, child in children {
		connector := if i == children.len - 1 { '└─ ' } else { '├─ ' }
		line := prefix + connector + child.label
		lines << truncate_display_width(line, width)
		next_prefix := prefix + if i == children.len - 1 { '   ' } else { '│  ' }
		render_mindmap_children(child.children, next_prefix, mut lines, width)
	}
}

fn (diagram MermaidDiagram) render_journey_ascii(width int) string {
	mut lines := []string{}
	if diagram.title.len > 0 {
		lines << truncate_display_width(diagram.title, width)
		lines << truncate_display_width('─'.repeat(min_int(max_int(display_width(diagram.title), 8),
			width)), width)
		lines << ''
	}
	for section in diagram.journey_sections {
		lines << '▎ ' + truncate_display_width(section.title, width - 2)
		for step in section.steps {
			score := max_int(0, min_int(step.score, 5))
			bar := '●'.repeat(score) + '·'.repeat(5 - score)
			actors := if step.actors.len > 0 { ' · ' + step.actors.join(', ') } else { '' }
			line := '  ' + step.title + '  ' + bar + actors
			lines << truncate_display_width(line, width)
		}
		lines << ''
	}
	return lines.join('\n').trim_space()
}

fn (diagram MermaidDiagram) render_git_graph_ascii(width int) string {
	mut lines := []string{}
	mut current_branch := 'main'
	mut seen_branches := [current_branch]
	for event in diagram.git_events {
		match event.kind {
			.branch {
				if event.name.len > 0 && event.name !in seen_branches {
					seen_branches << event.name
				}
				lines << '├─ branch ' + event.name
			}
			.checkout {
				current_branch = event.name
				if current_branch !in seen_branches {
					seen_branches << current_branch
				}
				lines << '├─ checkout ' + current_branch
			}
			.commit {
				name := if event.name.len > 0 { event.name } else { 'commit' }
				lines << '● ' + current_branch + '  ' + name
			}
			.merge {
				lines << '└─ merge ' + event.target + ' → ' + current_branch
			}
		}
	}
	return lines.map(truncate_display_width(it, width)).join('\n')
}

fn (diagram MermaidDiagram) render_timeline_ascii(width int) string {
	mut lines := []string{}
	if diagram.title.len > 0 {
		lines << truncate_display_width(diagram.title, width)
		lines << truncate_display_width('─'.repeat(min_int(max_int(display_width(diagram.title), 8),
			width)), width)
		lines << ''
	}
	mut point_width := 0
	for entry in diagram.timeline_entries {
		point_width = max_int(point_width, display_width(entry.point))
	}
	point_width = max_int(point_width, 6)
	for entry in diagram.timeline_entries {
		for i, event in entry.events {
			prefix := if i == 0 { entry.point } else { '' }
			connector := if i == 0 { '●' } else { '·' }
			line := ascii_fit_lane(prefix, point_width) + '  ' + connector + '  ' + event
			lines << truncate_display_width(line, width)
		}
	}
	return lines.join('\n')
}

fn render_gantt_task(task MermaidGanttTask, label_width int, width int) string {
	bar := gantt_task_bar(task)
	label := truncate_display_width(task.title, label_width)
	label_pad := ' '.repeat(max_int(label_width - display_width(label), 0))
	meta := if task.metadata.len > 0 { ' · ' + task.metadata.join(', ') } else { '' }
	line := '  ' + gantt_task_prefix(task) + ' ' + label + label_pad + ' ' + bar + meta
	return truncate_display_width(line, width)
}

fn gantt_task_bar(task MermaidGanttTask) string {
	fill := match task.state {
		'done' { '█████' }
		'active' { '▓▓▓▒▒' }
		'crit' { '█▓█▓█' }
		'milestone' { '◆◆◆' }
		else { '▒▒▒▒▒' }
	}
	return fill
}

fn gantt_task_prefix(task MermaidGanttTask) string {
	return match task.state {
		'done' { '✓' }
		'active' { '▸' }
		'crit' { '!' }
		'milestone' { '◆' }
		else { '·' }
	}
}

fn (diagram MermaidDiagram) render_sequence_ascii(width int) string {
	if diagram.participants.len == 0 {
		return ''
	}
	mut lane_width := 10
	for participant in diagram.participants {
		lane_width = max_int(lane_width, display_width(participant) + 4)
	}
	lane_width = min_int(lane_width, 18)
	mut lines := []string{}
	lines << ascii_lane_headers(diagram.participants, lane_width)
	lines << ascii_lifelines(diagram.participants, lane_width, map[string]bool{})
	mut active := map[string]bool{}
	for event in diagram.sequence_events {
		match event {
			MermaidSequenceMessage {
				lines << diagram.render_sequence_message(event, lane_width, width)
				lines << ascii_lifelines(diagram.participants, lane_width, active)
			}
			MermaidSequenceNote {
				lines << diagram.render_sequence_note(event, lane_width, width)
				lines << ascii_lifelines(diagram.participants, lane_width, active)
			}
			MermaidSequenceActivation {
				active[event.participant] = event.active
				lines << ascii_lifelines(diagram.participants, lane_width, active)
			}
			MermaidSequenceBlockBoundary {
				lines << render_sequence_block_boundary(event, lane_width,
					diagram.participants.len, width)
				lines << ascii_lifelines(diagram.participants, lane_width, active)
			}
		}
	}
	return lines.join('\n')
}

fn (diagram MermaidDiagram) render_sequence_message(message MermaidSequenceMessage, lane_width int, width int) string {
	from_idx := diagram.participants.index(message.from)
	to_idx := diagram.participants.index(message.to)
	if from_idx == -1 || to_idx == -1 {
		return ''
	}
	if from_idx == to_idx {
		mut parts := []string{len: diagram.participants.len, init: ' '.repeat(lane_width)}
		self_msg := '╭─↺ ' + message.text
		parts[from_idx] = ascii_fit_lane(self_msg, lane_width)
		return truncate_display_width(parts.join('  '), width)
	}
	total_width := diagram.participants.len * lane_width + max_int((diagram.participants.len -
		1) * 2, 0)
	centers := ascii_lane_centers(diagram.participants.len, lane_width)
	mut arrow := []rune{len: total_width, init: ` `}
	min_pos := min_int(centers[from_idx], centers[to_idx])
	max_pos := max_int(centers[from_idx], centers[to_idx])
	for i := min_pos; i <= max_pos; i++ {
		arrow[i] = `─`
	}
	if from_idx < to_idx {
		arrow[centers[from_idx]] = `├`
		arrow[centers[to_idx]] = `▶`
	} else {
		arrow[centers[from_idx]] = `┤`
		arrow[centers[to_idx]] = `◀`
	}
	arrow_line := arrow.string()
	if message.text.len == 0 {
		return truncate_display_width(arrow_line, width)
	}
	label_width := display_width(message.text)
	label_center := (centers[from_idx] + centers[to_idx]) / 2
	label_start := max_int(label_center - label_width / 2, 0)
	return truncate_display_width(' '.repeat(label_start) + message.text + '\n' + arrow_line, width)
}

fn (diagram MermaidDiagram) render_sequence_note(note MermaidSequenceNote, lane_width int, width int) string {
	idx := diagram.participants.index(note.participant)
	if idx == -1 {
		return ''
	}
	mut parts := []string{len: diagram.participants.len, init: ' '.repeat(lane_width)}
	text := truncate_display_width('[' + note.text + ']', lane_width)
	if note.side == .left {
		left_idx := max_int(idx - 1, 0)
		parts[left_idx] = ascii_fit_lane(text, lane_width)
	} else {
		right_idx := min_int(idx + 1, diagram.participants.len - 1)
		parts[right_idx] = ascii_fit_lane(text, lane_width)
	}
	return truncate_display_width(parts.join('  '), width)
}

fn render_sequence_block_boundary(boundary MermaidSequenceBlockBoundary, lane_width int, participant_count int, width int) string {
	total_width := participant_count * lane_width + max_int((participant_count - 1) * 2, 0)
	if !boundary.start {
		return truncate_display_width('╰' + '─'.repeat(max_int(total_width - 2, 0)) + '╯',
			width)
	}
	if boundary.kind == .else_branch {
		label := if boundary.label.len > 0 { ' else ${boundary.label} ' } else { ' else ' }
		fill := max_int(total_width - display_width(label) - 2, 0)
		return truncate_display_width('┝' + label + '─'.repeat(fill) + '┥', width)
	}
	label := if boundary.label.len > 0 {
		' ${boundary.kind.str()} ${boundary.label} '
	} else {
		' ${boundary.kind.str()} '
	}
	fill := max_int(total_width - display_width(label) - 2, 0)
	return truncate_display_width('╭' + label + '─'.repeat(fill) + '╮', width)
}
