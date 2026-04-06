module vmarkdown

pub fn render_mermaid_ascii(input string, width int) !string {
	return parse_mermaid(input)!.render_ascii(width)
}

pub fn (diagram MermaidDiagram) render_ascii(width int) string {
	if diagram.kind in [.sequence, .state, .class, .er, .gantt, .mindmap, .journey, .git_graph, .timeline] {
		if payload := diagram.to_diagram_payload() {
			return render_diagram_payload(payload, max_int(width,
				if diagram.kind in [.class, .er, .gantt] { 40 } else { 32 }))
		}
	}
	if diagram.kind == .flowchart && diagram.can_render_flow_via_diagram_payload() {
		if payload := diagram.to_diagram_payload() {
			return render_diagram_payload(payload, max_int(width, 24))
		}
	}
	match diagram.kind {
		.sequence { return diagram.render_sequence_ascii(max_int(width, 32)) }
		.state { return diagram.render_state_ascii(max_int(width, 32)) }
		.class { return diagram.render_class_ascii(max_int(width, 40)) }
		.er { return diagram.render_er_ascii(max_int(width, 40)) }
		.gantt { return diagram.render_gantt_ascii(max_int(width, 40)) }
		.mindmap { return diagram.render_mindmap_ascii(max_int(width, 32)) }
		.journey { return diagram.render_journey_ascii(max_int(width, 40)) }
		.git_graph { return diagram.render_git_graph_ascii(max_int(width, 40)) }
		.timeline { return diagram.render_timeline_ascii(max_int(width, 40)) }
		else {}
	}
	safe_width := max_int(width, 24)
	mut parts := []string{}
	mut rendered_subgraphs := map[string]string{}
	mut consumed := map[int]bool{}
	if diagram.paths.len > 0 {
		for i, path in diagram.paths {
			if i in consumed {
				continue
			}
			if branch_merge_group := diagram.collect_lr_branch_merge_group(i) {
				for idx in branch_merge_group.path_indices {
					consumed[idx] = true
				}
				rendered := diagram.render_lr_branch_merge_group(branch_merge_group)
				if rendered.len > 0 {
					if branch_merge_group.subgraph.len > 0 {
						if branch_merge_group.subgraph !in rendered_subgraphs {
							rendered_subgraphs[branch_merge_group.subgraph] = rendered
						} else {
							rendered_subgraphs[branch_merge_group.subgraph] += '\n\n' + rendered
						}
					} else {
						parts << rendered
					}
				}
				continue
			}
			if branch_group := diagram.collect_lr_branch_group(i) {
				for idx in branch_group.path_indices {
					consumed[idx] = true
				}
				rendered := diagram.render_lr_branch_group(branch_group)
				if rendered.len > 0 {
					if branch_group.subgraph.len > 0 {
						if branch_group.subgraph !in rendered_subgraphs {
							rendered_subgraphs[branch_group.subgraph] = rendered
						} else {
							rendered_subgraphs[branch_group.subgraph] += '\n\n' + rendered
						}
					} else {
						parts << rendered
					}
				}
				continue
			}
			if merge_group := diagram.collect_lr_merge_group(i) {
				for idx in merge_group.path_indices {
					consumed[idx] = true
				}
				rendered := diagram.render_lr_merge_group(merge_group)
				if rendered.len > 0 {
					if merge_group.subgraph.len > 0 {
						if merge_group.subgraph !in rendered_subgraphs {
							rendered_subgraphs[merge_group.subgraph] = rendered
						} else {
							rendered_subgraphs[merge_group.subgraph] += '\n\n' + rendered
						}
					} else {
						parts << rendered
					}
				}
				continue
			}
			if branch_merge_group := diagram.collect_td_branch_merge_group(i) {
				for idx in branch_merge_group.path_indices {
					consumed[idx] = true
				}
				rendered := diagram.render_td_branch_merge_group(branch_merge_group)
				if rendered.len > 0 {
					if branch_merge_group.subgraph.len > 0 {
						if branch_merge_group.subgraph !in rendered_subgraphs {
							rendered_subgraphs[branch_merge_group.subgraph] = rendered
						} else {
							rendered_subgraphs[branch_merge_group.subgraph] += '\n\n' + rendered
						}
					} else {
						parts << rendered
					}
				}
				continue
			}
			if branch_group := diagram.collect_td_branch_group(i) {
				for idx in branch_group.path_indices {
					consumed[idx] = true
				}
				rendered := diagram.render_td_branch_group(branch_group)
				if rendered.len > 0 {
					if branch_group.subgraph.len > 0 {
						if branch_group.subgraph !in rendered_subgraphs {
							rendered_subgraphs[branch_group.subgraph] = rendered
						} else {
							rendered_subgraphs[branch_group.subgraph] += '\n\n' + rendered
						}
					} else {
						parts << rendered
					}
				}
				continue
			}
			if merge_group := diagram.collect_td_merge_group(i) {
				for idx in merge_group.path_indices {
					consumed[idx] = true
				}
				rendered := diagram.render_td_merge_group(merge_group)
				if rendered.len > 0 {
					if merge_group.subgraph.len > 0 {
						if merge_group.subgraph !in rendered_subgraphs {
							rendered_subgraphs[merge_group.subgraph] = rendered
						} else {
							rendered_subgraphs[merge_group.subgraph] += '\n\n' + rendered
						}
					} else {
						parts << rendered
					}
				}
				continue
			}
			rendered := diagram.render_path(path, safe_width)
			if rendered.len > 0 {
				if path.subgraph.len > 0 {
					if path.subgraph !in rendered_subgraphs {
						rendered_subgraphs[path.subgraph] = rendered
					} else {
						rendered_subgraphs[path.subgraph] += '\n\n' + rendered
					}
				} else {
					parts << rendered
				}
			}
		}
	} else {
		for node in diagram.nodes {
			rendered := render_mermaid_node_block(node).join('\n')
			if node.subgraph.len > 0 {
				if node.subgraph !in rendered_subgraphs {
					rendered_subgraphs[node.subgraph] = rendered
				}
			} else {
				parts << rendered
			}
		}
	}
	for subgraph in diagram.subgraphs {
		if subgraph.title in rendered_subgraphs {
			parts << render_mermaid_subgraph_box(subgraph.title, rendered_subgraphs[subgraph.title], safe_width)
		}
	}
	return parts.join('\n\n')
}

fn (diagram MermaidDiagram) can_render_flow_via_diagram_payload() bool {
	if diagram.kind != .flowchart {
		return false
	}
	if diagram.edges.len == 0 {
		return false
	}
	if diagram.subgraphs.len > 1 {
		return false
	}
	mut supported_grouped_crossing := false
	if diagram.subgraphs.len == 1 {
		group_title := diagram.subgraphs[0].title
		if diagram.nodes.len == 0 {
			return false
		}
		mut crossing_edges := 0
		mut incoming_crossing := 0
		mut outgoing_crossing := 0
		mut outside_edges := []MermaidEdge{}
		mut outside_nodes := map[string]bool{}
		for edge in diagram.edges {
			from_node := diagram.nodes.filter(it.id == edge.from)
			to_node := diagram.nodes.filter(it.id == edge.to)
			if from_node.len == 0 || to_node.len == 0 {
				return false
			}
			from_in_group := from_node[0].subgraph == group_title
			to_in_group := to_node[0].subgraph == group_title
			if from_in_group != to_in_group {
				crossing_edges++
				if from_in_group {
					outgoing_crossing++
				} else {
					incoming_crossing++
				}
			} else if !from_in_group && !to_in_group {
				outside_edges << edge
				outside_nodes[edge.from] = true
				outside_nodes[edge.to] = true
			}
		}
		if crossing_edges > 4 {
			return false
		}
		if crossing_edges == 1 && !mermaid_edges_form_linear_chain(outside_edges, outside_nodes.len) {
			return false
		}
		if crossing_edges == 2 {
			if incoming_crossing == 1 && outgoing_crossing == 1 {
				if !mermaid_edges_have_max_degree_one(outside_edges) {
					return false
				}
			} else if incoming_crossing == 2 || outgoing_crossing == 2 {
				if !mermaid_crossing_edges_share_signature(diagram, group_title) {
					return false
				}
				if outside_edges.len > 0 && !mermaid_edges_have_max_degree_one(outside_edges) {
					return false
				}
			} else {
				return false
			}
		}
		if crossing_edges == 3 {
			if !((incoming_crossing == 2 && outgoing_crossing == 1)
				|| (incoming_crossing == 1 && outgoing_crossing == 2)) {
				return false
			}
			if incoming_crossing == 2 {
				mut incoming := []MermaidEdge{}
				for edge in diagram.edges {
					from_node := diagram.nodes.filter(it.id == edge.from)
					to_node := diagram.nodes.filter(it.id == edge.to)
					if from_node.len == 0 || to_node.len == 0 {
						return false
					}
					if from_node[0].subgraph != group_title && to_node[0].subgraph == group_title {
						incoming << edge
					}
				}
				if incoming.len != 2 || incoming[0].kind != incoming[1].kind
					|| incoming[0].label != incoming[1].label {
					return false
				}
			}
			if outgoing_crossing == 2 {
				mut outgoing := []MermaidEdge{}
				for edge in diagram.edges {
					from_node := diagram.nodes.filter(it.id == edge.from)
					to_node := diagram.nodes.filter(it.id == edge.to)
					if from_node.len == 0 || to_node.len == 0 {
						return false
					}
					if from_node[0].subgraph == group_title && to_node[0].subgraph != group_title {
						outgoing << edge
					}
				}
				if outgoing.len != 2 || outgoing[0].kind != outgoing[1].kind
					|| outgoing[0].label != outgoing[1].label {
					return false
				}
			}
			if outside_edges.len > 0 && !mermaid_edges_have_max_degree_one(outside_edges) {
				return false
			}
		}
		if crossing_edges == 4 {
			if incoming_crossing != 2 || outgoing_crossing != 2 {
				return false
			}
			if !mermaid_crossing_edges_share_directional_signatures(diagram, group_title) {
				return false
			}
			if outside_edges.len > 0 && !mermaid_edges_have_max_degree_one(outside_edges) {
				return false
			}
		}
		supported_grouped_crossing = crossing_edges > 0
	}
	if diagram.direction !in [.left_right, .top_down] {
		return false
	}
	if supported_grouped_crossing {
		return true
	}
	if diagram.direction == .top_down {
		if diagram.paths.len == 1 {
			path := diagram.paths[0]
			return path.nodes.len == diagram.edges.len + 1 && path.edge_kinds.len == diagram.edges.len
		}
		return diagram.paths.len > 0 && diagram.paths.all(it.nodes.len == 2 && it.edge_kinds.len == 1)
	}
	if diagram.paths.len == 1 {
		path := diagram.paths[0]
		if path.nodes.len == diagram.edges.len + 1 && path.edge_kinds.len == diagram.edges.len {
			return true
		}
	}
	return diagram.paths.len > 0 && diagram.paths.all(it.nodes.len == 2 && it.edge_kinds.len == 1)
}

fn mermaid_edges_form_linear_chain(edges []MermaidEdge, node_count int) bool {
	if edges.len == 0 {
		return true
	}
	mut out_degree := map[string]int{}
	mut in_degree := map[string]int{}
	for edge in edges {
		out_degree[edge.from] = out_degree[edge.from] + 1
		in_degree[edge.to] = in_degree[edge.to] + 1
		if out_degree[edge.from] > 1 || in_degree[edge.to] > 1 {
			return false
		}
	}
	mut starts := 0
	for node_id in out_degree.keys() {
		if (in_degree[node_id] or { 0 }) == 0 {
			starts++
		}
	}
	for node_id in in_degree.keys() {
		if node_id !in out_degree && (in_degree[node_id] or { 0 }) == 0 {
			starts++
		}
	}
	return starts <= 1 && node_count <= edges.len + 1
}

fn mermaid_edges_have_max_degree_one(edges []MermaidEdge) bool {
	mut out_degree := map[string]int{}
	mut in_degree := map[string]int{}
	for edge in edges {
		out_degree[edge.from] = out_degree[edge.from] + 1
		in_degree[edge.to] = in_degree[edge.to] + 1
		if out_degree[edge.from] > 1 || in_degree[edge.to] > 1 {
			return false
		}
	}
	return true
}

fn mermaid_crossing_edges_share_signature(diagram MermaidDiagram, group_title string) bool {
	mut crossing := []MermaidEdge{}
	for edge in diagram.edges {
		from_node := diagram.nodes.filter(it.id == edge.from)
		to_node := diagram.nodes.filter(it.id == edge.to)
		if from_node.len == 0 || to_node.len == 0 {
			return false
		}
		from_in_group := from_node[0].subgraph == group_title
		to_in_group := to_node[0].subgraph == group_title
		if from_in_group != to_in_group {
			crossing << edge
		}
	}
	if crossing.len != 2 {
		return false
	}
	return crossing[0].kind == crossing[1].kind && crossing[0].label == crossing[1].label
}

fn mermaid_crossing_edges_share_directional_signatures(diagram MermaidDiagram, group_title string) bool {
	mut incoming := []MermaidEdge{}
	mut outgoing := []MermaidEdge{}
	for edge in diagram.edges {
		from_node := diagram.nodes.filter(it.id == edge.from)
		to_node := diagram.nodes.filter(it.id == edge.to)
		if from_node.len == 0 || to_node.len == 0 {
			return false
		}
		from_in_group := from_node[0].subgraph == group_title
		to_in_group := to_node[0].subgraph == group_title
		if from_in_group != to_in_group {
			if from_in_group {
				outgoing << edge
			} else {
				incoming << edge
			}
		}
	}
	if incoming.len != 2 || outgoing.len != 2 {
		return false
	}
	return incoming[0].kind == incoming[1].kind && incoming[0].label == incoming[1].label
		&& outgoing[0].kind == outgoing[1].kind && outgoing[0].label == outgoing[1].label
}

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
		return ascii_dual_relation(left, right, relation.left_card + '--' + relation.right_card,
			AsciiRelationOptions{
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
		lines << truncate_display_width('─'.repeat(min_int(max_int(display_width(diagram.title), 8), width)),
			width)
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
		lines << truncate_display_width('─'.repeat(min_int(max_int(display_width(diagram.title), 8), width)), width)
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
		lines << truncate_display_width('─'.repeat(min_int(max_int(display_width(diagram.title), 8), width)),
			width)
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
				lines << render_sequence_block_boundary(event, lane_width, diagram.participants.len, width)
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
	total_width := diagram.participants.len * lane_width + max_int((diagram.participants.len - 1) * 2, 0)
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
		return truncate_display_width('╰' + '─'.repeat(max_int(total_width - 2, 0)) + '╯', width)
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

struct MermaidBranchGroup {
	path_indices []int
	source_id    string
	subgraph     string
	kind         MermaidEdgeKind
	label        string
	target_ids   []string
}

struct MermaidMergeGroup {
	path_indices []int
	target_id    string
	subgraph     string
	kind         MermaidEdgeKind
	label        string
	source_ids   []string
}

struct MermaidBranchMergeGroup {
	path_indices  []int
	source_id     string
	mid_ids       []string
	target_id     string
	subgraph      string
	branch_kind   MermaidEdgeKind
	branch_label  string
	merge_kind    MermaidEdgeKind
	merge_label   string
}

fn (diagram MermaidDiagram) render_path(path MermaidPath, width int) string {
	return if diagram.direction == .left_right {
		diagram.render_lr_path(path, width)
	} else {
		diagram.render_td_path(path)
	}
}

fn (diagram MermaidDiagram) collect_td_branch_group(start int) ?MermaidBranchGroup {
	if diagram.direction != .top_down || start < 0 || start >= diagram.paths.len {
		return none
	}
	base := diagram.paths[start]
	if base.nodes.len != 2 || base.edge_kinds.len != 1 {
		return none
	}
	mut indices := []int{}
	mut targets := []string{}
	for i := start; i < diagram.paths.len; i++ {
		path := diagram.paths[i]
		if path.nodes.len != 2 || path.edge_kinds.len != 1 {
			continue
		}
		if path.nodes[0] != base.nodes[0] || path.subgraph != base.subgraph || path.edge_kinds[0] != base.edge_kinds[0] {
			continue
		}
		label := if path.edge_labels.len > 0 { path.edge_labels[0] } else { '' }
		base_label := if base.edge_labels.len > 0 { base.edge_labels[0] } else { '' }
		if label != base_label {
			continue
		}
		indices << i
		targets << path.nodes[1]
	}
	if indices.len < 2 {
		return none
	}
	return MermaidBranchGroup{
		path_indices: indices
		source_id: base.nodes[0]
		subgraph: base.subgraph
		kind: base.edge_kinds[0]
		label: if base.edge_labels.len > 0 { base.edge_labels[0] } else { '' }
		target_ids: targets
	}
}

fn (diagram MermaidDiagram) collect_lr_branch_group(start int) ?MermaidBranchGroup {
	if diagram.direction != .left_right || start < 0 || start >= diagram.paths.len {
		return none
	}
	base := diagram.paths[start]
	if base.nodes.len != 2 || base.edge_kinds.len != 1 {
		return none
	}
	mut indices := []int{}
	mut targets := []string{}
	for i := start; i < diagram.paths.len; i++ {
		path := diagram.paths[i]
		if path.nodes.len != 2 || path.edge_kinds.len != 1 {
			continue
		}
		if path.nodes[0] != base.nodes[0] || path.subgraph != base.subgraph || path.edge_kinds[0] != base.edge_kinds[0] {
			continue
		}
		label := if path.edge_labels.len > 0 { path.edge_labels[0] } else { '' }
		base_label := if base.edge_labels.len > 0 { base.edge_labels[0] } else { '' }
		if label != base_label {
			continue
		}
		indices << i
		targets << path.nodes[1]
	}
	if indices.len < 2 {
		return none
	}
	return MermaidBranchGroup{
		path_indices: indices
		source_id: base.nodes[0]
		subgraph: base.subgraph
		kind: base.edge_kinds[0]
		label: if base.edge_labels.len > 0 { base.edge_labels[0] } else { '' }
		target_ids: targets
	}
}

fn (diagram MermaidDiagram) collect_td_branch_merge_group(start int) ?MermaidBranchMergeGroup {
	if diagram.direction != .top_down || start < 0 || start >= diagram.paths.len {
		return none
	}
	branch := diagram.collect_td_branch_group(start) or { return none }
	if branch.target_ids.len < 2 {
		return none
	}
	mut merge_path_indices := []int{}
	mut merge_sources := []string{}
	mut merge_target_id := ''
	mut merge_kind := MermaidEdgeKind.arrow
	mut merge_label := ''
	for i, path in diagram.paths {
		if path.subgraph != branch.subgraph || path.nodes.len != 2 || path.edge_kinds.len != 1 {
			continue
		}
		if path.nodes[0] !in branch.target_ids {
			continue
		}
		label := if path.edge_labels.len > 0 { path.edge_labels[0] } else { '' }
		if merge_target_id.len == 0 {
			merge_target_id = path.nodes[1]
			merge_kind = path.edge_kinds[0]
			merge_label = label
		}
		if path.nodes[1] != merge_target_id || path.edge_kinds[0] != merge_kind || label != merge_label {
			return none
		}
		merge_path_indices << i
		merge_sources << path.nodes[0]
	}
	if merge_path_indices.len != branch.target_ids.len {
		return none
	}
	for target_id in branch.target_ids {
		if target_id !in merge_sources {
			return none
		}
	}
	mut indices := branch.path_indices.clone()
	for idx in merge_path_indices {
		if idx !in indices {
			indices << idx
		}
	}
	return MermaidBranchMergeGroup{
		path_indices: indices
		source_id: branch.source_id
		mid_ids: branch.target_ids.clone()
		target_id: merge_target_id
		subgraph: branch.subgraph
		branch_kind: branch.kind
		branch_label: branch.label
		merge_kind: merge_kind
		merge_label: merge_label
	}
}

fn (diagram MermaidDiagram) collect_lr_branch_merge_group(start int) ?MermaidBranchMergeGroup {
	if diagram.direction != .left_right || start < 0 || start >= diagram.paths.len {
		return none
	}
	branch := diagram.collect_lr_branch_group(start) or { return none }
	if branch.target_ids.len < 2 {
		return none
	}
	mut merge_path_indices := []int{}
	mut merge_sources := []string{}
	mut merge_target_id := ''
	mut merge_kind := MermaidEdgeKind.arrow
	mut merge_label := ''
	for i, path in diagram.paths {
		if path.subgraph != branch.subgraph || path.nodes.len != 2 || path.edge_kinds.len != 1 {
			continue
		}
		if path.nodes[0] !in branch.target_ids {
			continue
		}
		label := if path.edge_labels.len > 0 { path.edge_labels[0] } else { '' }
		if merge_target_id.len == 0 {
			merge_target_id = path.nodes[1]
			merge_kind = path.edge_kinds[0]
			merge_label = label
		}
		if path.nodes[1] != merge_target_id || path.edge_kinds[0] != merge_kind || label != merge_label {
			return none
		}
		merge_path_indices << i
		merge_sources << path.nodes[0]
	}
	if merge_path_indices.len != branch.target_ids.len {
		return none
	}
	for target_id in branch.target_ids {
		if target_id !in merge_sources {
			return none
		}
	}
	mut indices := branch.path_indices.clone()
	for idx in merge_path_indices {
		if idx !in indices {
			indices << idx
		}
	}
	return MermaidBranchMergeGroup{
		path_indices: indices
		source_id: branch.source_id
		mid_ids: branch.target_ids.clone()
		target_id: merge_target_id
		subgraph: branch.subgraph
		branch_kind: branch.kind
		branch_label: branch.label
		merge_kind: merge_kind
		merge_label: merge_label
	}
}

fn (diagram MermaidDiagram) collect_td_merge_group(start int) ?MermaidMergeGroup {
	if diagram.direction != .top_down || start < 0 || start >= diagram.paths.len {
		return none
	}
	base := diagram.paths[start]
	if base.nodes.len != 2 || base.edge_kinds.len != 1 {
		return none
	}
	base_label := if base.edge_labels.len > 0 { base.edge_labels[0] } else { '' }
	mut indices := []int{}
	mut sources := []string{}
	for i := start; i < diagram.paths.len; i++ {
		path := diagram.paths[i]
		if path.nodes.len != 2 || path.edge_kinds.len != 1 {
			continue
		}
		if path.nodes[1] != base.nodes[1] || path.subgraph != base.subgraph || path.edge_kinds[0] != base.edge_kinds[0] {
			continue
		}
		label := if path.edge_labels.len > 0 { path.edge_labels[0] } else { '' }
		if label != base_label {
			continue
		}
		indices << i
		sources << path.nodes[0]
	}
	if indices.len < 2 {
		return none
	}
	return MermaidMergeGroup{
		path_indices: indices
		target_id: base.nodes[1]
		subgraph: base.subgraph
		kind: base.edge_kinds[0]
		label: base_label
		source_ids: sources
	}
}

fn (diagram MermaidDiagram) collect_lr_merge_group(start int) ?MermaidMergeGroup {
	if diagram.direction != .left_right || start < 0 || start >= diagram.paths.len {
		return none
	}
	base := diagram.paths[start]
	if base.nodes.len != 2 || base.edge_kinds.len != 1 {
		return none
	}
	base_label := if base.edge_labels.len > 0 { base.edge_labels[0] } else { '' }
	mut indices := []int{}
	mut sources := []string{}
	for i := start; i < diagram.paths.len; i++ {
		path := diagram.paths[i]
		if path.nodes.len != 2 || path.edge_kinds.len != 1 {
			continue
		}
		if path.nodes[1] != base.nodes[1] || path.subgraph != base.subgraph || path.edge_kinds[0] != base.edge_kinds[0] {
			continue
		}
		label := if path.edge_labels.len > 0 { path.edge_labels[0] } else { '' }
		if label != base_label {
			continue
		}
		indices << i
		sources << path.nodes[0]
	}
	if indices.len < 2 {
		return none
	}
	return MermaidMergeGroup{
		path_indices: indices
		target_id: base.nodes[1]
		subgraph: base.subgraph
		kind: base.edge_kinds[0]
		label: base_label
		source_ids: sources
	}
}

fn (diagram MermaidDiagram) render_td_path(path MermaidPath) string {
	mut lines := []string{}
	for i, node_id in path.nodes {
		node := diagram.node_by_id(node_id) or { continue }
		node_lines := render_mermaid_node_block(node)
		lines << node_lines
		if i < path.edge_kinds.len {
			label := if i < path.edge_labels.len { path.edge_labels[i] } else { '' }
			lines << ascii_vertical_edge(ascii_block_width(node_lines[0]), path.edge_kinds[i] == .arrow,
				label)
		}
	}
	return flatten_mermaid_lines(lines)
}

fn (diagram MermaidDiagram) render_td_branch_group(group MermaidBranchGroup) string {
	source := diagram.node_by_id(group.source_id) or { return '' }
	source_block := render_mermaid_node_block(source).join('\n')
	mut targets := []string{}
	for i, target_id in group.target_ids {
		target := diagram.node_by_id(target_id) or { continue }
		_ := i
		targets << render_mermaid_node_inline(target)
	}
	return ascii_td_branch(source_block, group.label, targets, group.kind == .arrow)
}

fn (diagram MermaidDiagram) render_lr_branch_group(group MermaidBranchGroup) string {
	source := diagram.node_by_id(group.source_id) or { return '' }
	source_inline := render_mermaid_node_inline(source)
	mut targets := []string{}
	for _, target_id in group.target_ids {
		target := diagram.node_by_id(target_id) or { continue }
		targets << render_mermaid_node_inline(target)
	}
	return ascii_lr_branch(source_inline, group.label, targets)
}

fn (diagram MermaidDiagram) render_td_branch_merge_group(group MermaidBranchMergeGroup) string {
	source := diagram.node_by_id(group.source_id) or { return '' }
	target := diagram.node_by_id(group.target_id) or { return '' }
	source_block := render_mermaid_node_block(source).join('\n')
	target_inline := render_mermaid_node_inline(target)
	mut mids := []string{}
	for _, mid_id in group.mid_ids {
		mid := diagram.node_by_id(mid_id) or { continue }
		mids << render_mermaid_node_inline(mid)
	}
	return ascii_td_branch_merge(source_block, group.branch_label, mids, group.merge_label,
		target_inline, group.merge_kind == .arrow)
}

fn (diagram MermaidDiagram) render_lr_branch_merge_group(group MermaidBranchMergeGroup) string {
	source := diagram.node_by_id(group.source_id) or { return '' }
	target := diagram.node_by_id(group.target_id) or { return '' }
	source_inline := render_mermaid_node_inline(source)
	target_inline := render_mermaid_node_inline(target)
	mut mids := []string{}
	for _, mid_id in group.mid_ids {
		mid := diagram.node_by_id(mid_id) or { continue }
		mids << render_mermaid_node_inline(mid)
	}
	return ascii_lr_branch_merge(source_inline, group.branch_label, mids, group.merge_label,
		target_inline)
}

fn (diagram MermaidDiagram) render_td_merge_group(group MermaidMergeGroup) string {
	target := diagram.node_by_id(group.target_id) or { return '' }
	target_inline := render_mermaid_node_inline(target)
	mut sources := []string{}
	for _, source_id in group.source_ids {
		source := diagram.node_by_id(source_id) or { continue }
		sources << render_mermaid_node_inline(source)
	}
	return ascii_td_merge(sources, group.label, target_inline, group.kind == .arrow)
}

fn (diagram MermaidDiagram) render_lr_merge_group(group MermaidMergeGroup) string {
	target := diagram.node_by_id(group.target_id) or { return '' }
	target_inline := render_mermaid_node_inline(target)
	mut sources := []string{}
	for _, source_id in group.source_ids {
		source := diagram.node_by_id(source_id) or { continue }
		sources << render_mermaid_node_inline(source)
	}
	return ascii_lr_merge(sources, group.label, target_inline)
}

fn (diagram MermaidDiagram) render_lr_path(path MermaidPath, width int) string {
	mut segments := []string{}
	for i, node_id in path.nodes {
		node := diagram.node_by_id(node_id) or { continue }
		segments << render_mermaid_node_inline(node)
		if i < path.edge_kinds.len {
			label := if i < path.edge_labels.len { path.edge_labels[i] } else { '' }
			segments << ascii_inline_edge(path.edge_kinds[i] == .arrow, label)
		}
	}
	return ascii_wrap_segments(segments, max_int(width, 24)).join('\n')
}

fn render_mermaid_node_block(node MermaidNode) []string {
	label := if node.label.len > 0 { node.label } else { node.id }
	frame := display_width(label) + 2
	return match node.shape {
		.round {
			[
				'╭' + '─'.repeat(frame) + '╮',
				'│ ' + label + ' │',
				'╰' + '─'.repeat(frame) + '╯',
			]
		}
		.diamond {
			padding := ' '.repeat(frame / 2 + 1)
			[
				padding + '╱╲',
				'╱ ' + label + ' ╲',
				padding + '╲╱',
			]
		}
		else {
			[
				'╭' + '─'.repeat(frame) + '╮',
				'│ ' + label + ' │',
				'╰' + '─'.repeat(frame) + '╯',
			]
		}
	}
}

fn render_mermaid_node_inline(node MermaidNode) string {
	label := if node.label.len > 0 { node.label } else { node.id }
	return match node.shape {
		.round { '(' + label + ')' }
		.diamond { '{' + label + '}' }
		else { '[' + label + ']' }
	}
}

fn flatten_mermaid_lines(parts []string) string {
	mut out := []string{}
	for part in parts {
		if part.len == 0 {
			continue
		}
		if part.contains('\n') {
			for line in part.split_into_lines() {
				out << line
			}
		} else {
			out << part
		}
	}
	return out.join('\n')
}

fn render_mermaid_subgraph_box(title string, body string, width int) string {
	body_lines := body.split_into_lines()
	mut inner_width := display_width(title) + 2
	for line in body_lines {
		inner_width = max_int(inner_width, display_width(line))
	}
	inner_width = min_int(inner_width, max_int(width - 4, inner_width))
	top := '╭ ' + title + ' ' + '─'.repeat(max_int(inner_width - display_width(title) - 1, 0)) + '╮'
	bottom := '╰' + '─'.repeat(display_width(top) - 2) + '╯'
	mut lines := [top]
	for line in body_lines {
		content := truncate_display_width(line, inner_width)
		padding := ' '.repeat(max_int(inner_width - display_width(content), 0))
		lines << '│ ' + content + padding + ' │'
	}
	lines << bottom
	return lines.join('\n')
}
