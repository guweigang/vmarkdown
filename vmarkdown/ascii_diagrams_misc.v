module vmarkdown

pub struct AsciiTimelineEntry {
pub:
	point string
	text  string
}

pub struct AsciiPipelineStage {
pub:
	name   string
	status string
}

pub struct AsciiStateTransition {
pub:
	from  string
	to    string
	label string
}

pub fn render_ascii_timeline(entries []AsciiTimelineEntry, width int) string {
	if entries.len == 0 {
		return ''
	}
	mut point_width := 0
	for entry in entries {
		point_width = max_int(point_width, display_width(entry.point))
	}
	point_width = max_int(point_width, 6)
	mut lines := []string{}
	for i, entry in entries {
		same_as_prev := i > 0 && entries[i - 1].point == entry.point
		same_as_next := i < entries.len - 1 && entries[i + 1].point == entry.point
		prefix := if same_as_prev { '' } else { entry.point }
		connector := if same_as_prev {
			if same_as_next { '│ ' } else { '└─' }
		} else {
			if same_as_next { '├─' } else if i == entries.len - 1 { '└─' } else { '├─' }
		}
		line := ascii_fit_lane(prefix, point_width) + '  ' + connector + ' ' + entry.text
		lines << truncate_display_width(line, width)
	}
	return lines.join('\n')
}

pub fn render_ascii_timeline_diagram(timeline DiagramTimeline, width int) string {
	mut lines := []string{}
	if timeline.title.len > 0 {
		lines << truncate_display_width(timeline.title, width)
		lines << truncate_display_width('─'.repeat(min_int(max_int(display_width(timeline.title), 8), width)),
			width)
		lines << ''
	}
	body := render_ascii_timeline(timeline.to_ascii_timeline(), width)
	if body.len > 0 {
		lines << body
	}
	return lines.join('\n').trim_space()
}

pub fn render_ascii_pipeline(stages []AsciiPipelineStage, width int) string {
	if stages.len == 0 {
		return ''
	}
	mut segments := []string{}
	for i, stage in stages {
		status := match stage.status.to_lower() {
			'done', 'ok', 'success' { '✓' }
			'active', 'running', 'progress' { '▸' }
			'blocked', 'fail', 'failed' { '✕' }
			else { '·' }
		}
		segments << '[${status} ${stage.name}]'
		if i < stages.len - 1 {
			segments << '─▶'
		}
	}
	return ascii_wrap_segments(segments, max_int(width, 24)).join('\n')
}

pub fn render_ascii_state_machine(transitions []AsciiStateTransition, width int) string {
	if transitions.len == 0 {
		return ''
	}
	mut lines := []string{}
	for transition in transitions {
		from_ref := render_ascii_state_ref(transition.from)
		to_ref := render_ascii_state_ref(transition.to)
		mut line := from_ref + ' ─▶ ' + to_ref
		if transition.label.len > 0 {
			line += '  · ' + transition.label
		}
		lines << truncate_display_width(line, width)
	}
	return lines.join('\n')
}

pub fn render_ascii_sequence(sequence DiagramSequence, width int) string {
	if sequence.participants.len == 0 {
		return ''
	}
	mut lane_width := 10
	for participant in sequence.participants {
		lane_width = max_int(lane_width, display_width(participant) + 4)
	}
	lane_width = min_int(lane_width, 18)
	mut lines := []string{}
	lines << ascii_lane_headers(sequence.participants, lane_width)
	lines << ascii_lifelines(sequence.participants, lane_width, map[string]bool{})
	mut active := map[string]bool{}
	for event in sequence.events {
		match event {
			DiagramSequenceMessage {
				lines << render_ascii_sequence_message(sequence.participants, event, lane_width, width)
				lines << ascii_lifelines(sequence.participants, lane_width, active)
			}
			DiagramSequenceNote {
				lines << render_ascii_sequence_note(sequence.participants, event, lane_width, width)
				lines << ascii_lifelines(sequence.participants, lane_width, active)
			}
			DiagramSequenceActivation {
				active[event.participant] = event.active
				lines << ascii_lifelines(sequence.participants, lane_width, active)
			}
			DiagramSequenceBlockBoundary {
				lines << render_ascii_sequence_block_boundary(event, lane_width, sequence.participants.len,
					width)
				lines << ascii_lifelines(sequence.participants, lane_width, active)
			}
		}
	}
	return lines.join('\n')
}

fn render_ascii_sequence_message(participants []string, message DiagramSequenceMessage, lane_width int, width int) string {
	from_idx := participants.index(message.from)
	to_idx := participants.index(message.to)
	if from_idx == -1 || to_idx == -1 {
		return ''
	}
	if from_idx == to_idx {
		mut parts := []string{len: participants.len, init: ' '.repeat(lane_width)}
		self_msg := '╭─↺ ' + message.text
		parts[from_idx] = ascii_fit_lane(self_msg, lane_width)
		return truncate_display_width(parts.join('  '), width)
	}
	total_width := participants.len * lane_width + max_int((participants.len - 1) * 2, 0)
	centers := ascii_lane_centers(participants.len, lane_width)
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

fn render_ascii_sequence_note(participants []string, note DiagramSequenceNote, lane_width int, width int) string {
	idx := participants.index(note.participant)
	if idx == -1 {
		return ''
	}
	mut parts := []string{len: participants.len, init: ' '.repeat(lane_width)}
	text := truncate_display_width('[' + note.text + ']', lane_width)
	if note.side == .left {
		left_idx := max_int(idx - 1, 0)
		parts[left_idx] = ascii_fit_lane(text, lane_width)
	} else {
		right_idx := min_int(idx + 1, participants.len - 1)
		parts[right_idx] = ascii_fit_lane(text, lane_width)
	}
	return truncate_display_width(parts.join('  '), width)
}

fn render_ascii_sequence_block_boundary(boundary DiagramSequenceBlockBoundary, lane_width int, participant_count int, width int) string {
	total_width := participant_count * lane_width + max_int((participant_count - 1) * 2, 0)
	if !boundary.start {
		return truncate_display_width('╰' + '─'.repeat(max_int(total_width - 2, 0)) + '╯', width)
	}
	if boundary.kind == .else_branch {
		label := if boundary.label.len > 0 { ' else ${boundary.label} ' } else { ' else ' }
		fill := max_int(total_width - display_width(label) - 2, 0)
		return truncate_display_width('┝' + label + '─'.repeat(fill) + '┥', width)
	}
	label := if boundary.label.len > 0 {
		' ${ascii_sequence_block_kind_label(boundary.kind)} ${boundary.label} '
	} else {
		' ${ascii_sequence_block_kind_label(boundary.kind)} '
	}
	fill := max_int(total_width - display_width(label) - 2, 0)
	return truncate_display_width('╭' + label + '─'.repeat(fill) + '╮', width)
}

fn ascii_sequence_block_kind_label(kind DiagramSequenceBlockKind) string {
	return match kind {
		.alt { 'alt' }
		.else_branch { 'else' }
		.opt { 'opt' }
		.loop { 'loop' }
		.par { 'par' }
	}
}

fn render_ascii_state_ref(name string) string {
	if name == '[*]' {
		return '◉'
	}
	return '[' + name + ']'
}

pub fn render_ascii_journey(journey DiagramJourney, width int) string {
	mut lines := []string{}
	if journey.title.len > 0 {
		lines << truncate_display_width(journey.title, width)
		lines << truncate_display_width('─'.repeat(min_int(max_int(display_width(journey.title), 8), width)), width)
		lines << ''
	}
	for section in journey.sections {
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

pub fn render_ascii_git_graph(graph DiagramGitGraph, width int) string {
	mut lines := []string{}
	mut current_branch := 'main'
	for event in graph.events {
		match event.kind {
			.branch {
				lines << '├─ branch ' + event.name
			}
			.checkout {
				current_branch = event.name
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

pub fn render_ascii_class_diagram(diagram DiagramClassDiagram, width int) string {
	if diagram.classes.len == 2 && diagram.relations.len == 1 {
		relation := diagram.relations[0]
		gap := max_int(8, display_width(relation.kind) + display_width(relation.label) + 4)
		column_width := max_int((width - gap) / 2, 20)
		left := ascii_box(diagram.classes[0].name, diagram.classes[0].members, column_width)
		right := ascii_box(diagram.classes[1].name, diagram.classes[1].members, column_width)
		return ascii_dual_relation(left, right, relation.kind, AsciiRelationOptions{
			gap: gap
			width: width
			label: relation.label
			align_in_gap: true
			align_y: 'middle'
		})
	}
	mut parts := []string{}
	for class_def in diagram.classes {
		parts << ascii_box(class_def.name, class_def.members, width)
	}
	if diagram.relations.len > 0 {
		mut rel_lines := []string{}
		for relation in diagram.relations {
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

pub fn render_ascii_er_diagram(diagram DiagramERDiagram, width int) string {
	if diagram.entities.len == 2 && diagram.relations.len == 1 {
		relation := diagram.relations[0]
		rel_text := relation.left_card + '--' + relation.right_card
		gap := max_int(8, display_width(rel_text) + display_width(relation.label) + 4)
		column_width := max_int((width - gap) / 2, 20)
		left := ascii_box(diagram.entities[0].name, diagram.entities[0].attributes, column_width)
		right := ascii_box(diagram.entities[1].name, diagram.entities[1].attributes, column_width)
		return ascii_dual_relation(left, right, rel_text, AsciiRelationOptions{
			gap: gap
			width: width
			label: relation.label
			align_in_gap: true
			align_y: 'middle'
		})
	}
	mut parts := []string{}
	for entity in diagram.entities {
		parts << ascii_box(entity.name, entity.attributes, width)
	}
	if diagram.relations.len > 0 {
		mut rel_lines := []string{}
		for relation in diagram.relations {
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

pub fn render_ascii_gantt(diagram DiagramGantt, width int) string {
	mut lines := []string{}
	if diagram.title.len > 0 {
		lines << truncate_display_width(diagram.title, width)
		lines << truncate_display_width('─'.repeat(min_int(max_int(display_width(diagram.title), 8), width)),
			width)
		lines << ''
	}
	mut task_label_width := 12
	for section in diagram.sections {
		for task in section.tasks {
			task_label_width = max_int(task_label_width, display_width(task.title))
		}
	}
	task_label_width = min_int(task_label_width + 1, min_int(max_int(width / 4, 12), 18))
	for section in diagram.sections {
		lines << '▎ ' + truncate_display_width(section.title, max_int(width - 2, 0))
		for task in section.tasks {
			lines << render_ascii_gantt_task(task, task_label_width, width)
		}
		lines << ''
	}
	for lines.len > 0 && lines[lines.len - 1].len == 0 {
		lines.delete(lines.len - 1)
	}
	return lines.join('\n')
}

fn render_ascii_gantt_task(task DiagramGanttTask, label_width int, width int) string {
	bar := ascii_gantt_task_bar(task)
	label := truncate_display_width(task.title, label_width)
	label_pad := ' '.repeat(max_int(label_width - display_width(label), 0))
	meta := if task.metadata.len > 0 { ' · ' + task.metadata.join(', ') } else { '' }
	line := '  ' + ascii_gantt_task_prefix(task) + ' ' + label + label_pad + ' ' + bar + meta
	return truncate_display_width(line, width)
}

fn ascii_gantt_task_bar(task DiagramGanttTask) string {
	return match task.state {
		'done' { '█████' }
		'active' { '▓▓▓▒▒' }
		'crit' { '█▓█▓█' }
		'milestone' { '◆◆◆' }
		else { '▒▒▒▒▒' }
	}
}

fn ascii_gantt_task_prefix(task DiagramGanttTask) string {
	return match task.state {
		'done' { '✓' }
		'active' { '▸' }
		'crit' { '!' }
		'milestone' { '◆' }
		else { '·' }
	}
}
