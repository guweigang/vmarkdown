module vmarkdown

pub fn parse_mermaid(input string) !MermaidDiagram {
	lines := normalize_code(input).split_into_lines()
	mut diagram := MermaidDiagram{
		kind: .flowchart
		direction: .top_down
	}
	mut seen := map[string]int{}
	mut saw_header := false
	mut current_subgraph := ''
	mut current_class := ''
	mut current_entity := ''
	mut current_section := ''
	mut mindmap_stack := []MindmapStackEntry{}
	for raw_line in lines {
		raw := raw_line.trim_right(';')
		line := raw.trim_space()
		if line.len == 0 || line.starts_with('%%') {
			continue
		}
		if current_class.len > 0 {
			if line == '}' {
				current_class = ''
			} else {
				append_mermaid_class_member(current_class, line, mut diagram)
			}
			continue
		}
		if current_entity.len > 0 {
			if line == '}' {
				current_entity = ''
			} else {
				append_mermaid_entity_attribute(current_entity, line, mut diagram)
			}
			continue
		}
		if !saw_header {
			diagram, saw_header = parse_mermaid_header(line, diagram)!
			if saw_header {
				continue
			}
		}
		match diagram.kind {
			.sequence {
				parse_mermaid_sequence_line(line, mut diagram)!
			}
			.state {
				parse_mermaid_state_line(line, mut diagram)!
			}
			.class {
				if next_class := parse_mermaid_class_line(line, mut diagram) {
					current_class = next_class
				}
			}
			.er {
				if next_entity := parse_mermaid_er_line(line, mut diagram) {
					current_entity = next_entity
				}
			}
			.gantt {
				current_section = parse_mermaid_gantt_line(line, current_section, mut diagram)
			}
			.mindmap {
				parse_mermaid_mindmap_line(raw, mut diagram, mut mindmap_stack)
			}
			.journey {
				current_section = parse_mermaid_journey_line(line, current_section, mut diagram)
			}
			.git_graph {
				parse_mermaid_git_graph_line(line, mut diagram)
			}
			.timeline {
				parse_mermaid_timeline_line(line, mut diagram)
			}
			else {
				if parse_mermaid_direction_line(line, mut diagram) {
					continue
				}
				if next_subgraph := parse_mermaid_subgraph_line(line, mut diagram) {
					current_subgraph = next_subgraph
					continue
				}
				if line.to_lower() == 'end' {
					current_subgraph = ''
					continue
				}
				if line.contains('-->') || line.contains('---') {
					parse_mermaid_relation_line(line, mut diagram, mut seen, current_subgraph)!
					continue
				}
				parse_mermaid_node_declaration(line, mut diagram, mut seen, current_subgraph)!
			}
		}
	}
	if !saw_header {
		return error('unsupported mermaid diagram header')
	}
	match diagram.kind {
		.sequence {
			if diagram.participants.len == 0 && diagram.messages.len == 0 {
				return error('unsupported or empty mermaid diagram')
			}
		}
		.state {
			if diagram.state_transitions.len == 0 {
				return error('unsupported or empty mermaid diagram')
			}
		}
		.class {
			if diagram.classes.len == 0 && diagram.class_relations.len == 0 {
				return error('unsupported or empty mermaid diagram')
			}
		}
		.er {
			if diagram.entities.len == 0 && diagram.entity_relations.len == 0 {
				return error('unsupported or empty mermaid diagram')
			}
		}
		.gantt {
			if diagram.gantt_sections.len == 0 {
				return error('unsupported or empty mermaid diagram')
			}
		}
		.mindmap {
			if diagram.mindmap_root.label.len == 0 {
				return error('unsupported or empty mermaid diagram')
			}
		}
		.journey {
			if diagram.journey_sections.len == 0 {
				return error('unsupported or empty mermaid diagram')
			}
		}
		.git_graph {
			if diagram.git_events.len == 0 {
				return error('unsupported or empty mermaid diagram')
			}
		}
		.timeline {
			if diagram.timeline_entries.len == 0 {
				return error('unsupported or empty mermaid diagram')
			}
		}
		else {
			if diagram.nodes.len == 0 {
				return error('unsupported or empty mermaid diagram')
			}
		}
	}
	return diagram
}

fn parse_mermaid_header(line string, diagram MermaidDiagram) !(MermaidDiagram, bool) {
	parts := line.split_any(' \t').filter(it.len > 0)
	if parts.len == 0 {
		return diagram, false
	}
	kind := parts[0].to_lower()
	if kind !in ['flowchart', 'graph', 'sequencediagram', 'statediagram-v2', 'classdiagram', 'erdiagram',
		'gantt', 'mindmap', 'journey', 'gitgraph', 'timeline'] {
		return diagram, false
	}
	mut updated := MermaidDiagram{
		kind: match kind {
			'sequencediagram' { MermaidDiagramKind.sequence }
			'statediagram-v2' { .state }
			'classdiagram' { .class }
			'erdiagram' { .er }
			'gantt' { .gantt }
			'mindmap' { .mindmap }
			'journey' { .journey }
			'gitgraph' { .git_graph }
			'timeline' { .timeline }
			else { .flowchart }
		}
		direction: diagram.direction
		title: diagram.title
		nodes: diagram.nodes.clone()
		edges: diagram.edges.clone()
		paths: diagram.paths.clone()
		subgraphs: diagram.subgraphs.clone()
		participants: diagram.participants.clone()
		messages: diagram.messages.clone()
		sequence_events: diagram.sequence_events.clone()
		state_transitions: diagram.state_transitions.clone()
		classes: diagram.classes.clone()
		class_relations: diagram.class_relations.clone()
		entities: diagram.entities.clone()
		entity_relations: diagram.entity_relations.clone()
		gantt_sections: diagram.gantt_sections.clone()
		mindmap_root: diagram.mindmap_root
		journey_sections: diagram.journey_sections.clone()
		git_events: diagram.git_events.clone()
		timeline_entries: diagram.timeline_entries.clone()
	}
	if updated.kind == .flowchart && parts.len > 1 {
		updated.direction = parse_mermaid_direction(parts[1])!
	}
	return updated, true
}

struct MindmapStackEntry {
	level int
	path  []int
}

fn parse_mermaid_state_line(line string, mut diagram MermaidDiagram) ! {
	if !line.contains('-->') {
		return
	}
	idx := line.index('-->') or { return }
	from := line[..idx].trim_space()
	mut rest := line[idx + 3..].trim_space()
	mut label := ''
	if colon := rest.index(':') {
		label = rest[colon + 1..].trim_space()
		rest = rest[..colon].trim_space()
	}
	if from.len == 0 || rest.len == 0 {
		return
	}
	diagram.state_transitions << MermaidStateTransition{
		from: from
		to: rest
		label: label
	}
}

fn parse_mermaid_sequence_line(line string, mut diagram MermaidDiagram) ! {
	if line.to_lower().starts_with('participant ') {
		name := line['participant '.len..].trim_space()
		if name.len == 0 {
			return
		}
		if name !in diagram.participants {
			diagram.participants << name
		}
		return
	}
	if boundary := parse_mermaid_sequence_block_boundary(line) {
		diagram.sequence_events << MermaidSequenceEvent(boundary)
		return
	}
	if line.to_lower().starts_with('activate ') {
		name := line['activate '.len..].trim_space()
		if name.len == 0 {
			return
		}
		if name !in diagram.participants {
			diagram.participants << name
		}
		diagram.sequence_events << MermaidSequenceEvent(MermaidSequenceActivation{
			participant: name
			active: true
		})
		return
	}
	if line.to_lower().starts_with('deactivate ') {
		name := line['deactivate '.len..].trim_space()
		if name.len == 0 {
			return
		}
		if name !in diagram.participants {
			diagram.participants << name
		}
		diagram.sequence_events << MermaidSequenceEvent(MermaidSequenceActivation{
			participant: name
			active: false
		})
		return
	}
	if note := parse_mermaid_sequence_note(line) {
		if note.participant !in diagram.participants {
			diagram.participants << note.participant
		}
		diagram.sequence_events << MermaidSequenceEvent(note)
		return
	}
	idx := line.index('->>') or { return error('unsupported sequence line: ${line}') }
	from := line[..idx].trim_space()
	rest := line[idx + 3..]
	colon := rest.index(':') or { return error('unsupported sequence line: ${line}') }
	to := rest[..colon].trim_space()
	text := rest[colon + 1..].trim_space()
	if from.len == 0 || to.len == 0 {
		return error('unsupported sequence line: ${line}')
	}
	if from !in diagram.participants {
		diagram.participants << from
	}
	if to !in diagram.participants {
		diagram.participants << to
	}
	diagram.messages << MermaidSequenceMessage{
		from: from
		to: to
		text: text
		kind: .arrow
	}
	diagram.sequence_events << MermaidSequenceEvent(MermaidSequenceMessage{
		from: from
		to: to
		text: text
		kind: .arrow
	})
}

fn parse_mermaid_sequence_block_boundary(line string) ?MermaidSequenceBlockBoundary {
	lower := line.to_lower()
	if lower == 'end' {
		return MermaidSequenceBlockBoundary{
			kind: .alt
			label: ''
			start: false
		}
	}
	if lower.starts_with('else ') {
		return MermaidSequenceBlockBoundary{
			kind: .else_branch
			label: line['else '.len..].trim_space()
			start: true
		}
	}
	for kind, tag in {
		MermaidSequenceBlockKind.alt: 'alt '
		MermaidSequenceBlockKind.opt: 'opt '
		MermaidSequenceBlockKind.loop: 'loop '
		MermaidSequenceBlockKind.par: 'par '
	} {
		if lower.starts_with(tag) {
			return MermaidSequenceBlockBoundary{
				kind: kind
				label: line[tag.len..].trim_space()
				start: true
			}
		}
	}
	return none
}

fn parse_mermaid_sequence_note(line string) ?MermaidSequenceNote {
	lower := line.to_lower()
	if !lower.starts_with('note ') {
		return none
	}
	remainder := line['note '.len..]
	colon := remainder.index(':') or { return none }
	head := remainder[..colon].trim_space()
	text := remainder[colon + 1..].trim_space()
	parts := head.split_any(' \t').filter(it.len > 0)
	if parts.len < 3 || (parts[0].to_lower() != 'left' && parts[0].to_lower() != 'right')
		|| parts[1].to_lower() != 'of' {
		return none
	}
	return MermaidSequenceNote{
		participant: parts[2]
		text: text
		side: if parts[0].to_lower() == 'left' { .left } else { .right }
	}
}

fn parse_mermaid_class_line(line string, mut diagram MermaidDiagram) ?string {
	if line.starts_with('class ') {
		remainder := line['class '.len..].trim_space()
		if remainder.ends_with('{') {
			name := remainder[..remainder.len - 1].trim_space()
			if name.len == 0 {
				return none
			}
			ensure_mermaid_class(mut diagram, name)
			return name
		}
		if colon := remainder.index(':') {
			name := remainder[..colon].trim_space()
			member := remainder[colon + 1..].trim_space()
			if name.len > 0 {
				ensure_mermaid_class(mut diagram, name)
				if member.len > 0 {
					append_mermaid_class_member(name, member, mut diagram)
				}
			}
			return none
		}
		if remainder.len > 0 {
			ensure_mermaid_class(mut diagram, remainder)
		}
		return none
	}
	if relation := parse_mermaid_class_relation(line) {
		ensure_mermaid_class(mut diagram, relation.left)
		ensure_mermaid_class(mut diagram, relation.right)
		diagram.class_relations << relation
	}
	return none
}

fn parse_mermaid_class_relation(line string) ?MermaidClassRelation {
	mut body := line
	mut label := ''
	if colon := line.index(':') {
		body = line[..colon].trim_space()
		label = line[colon + 1..].trim_space()
	}
	for token in ['<|--', '--|>', '*--', 'o--', '..>', '-->', '--', '..'] {
		if idx := body.index(token) {
			left := body[..idx].trim_space()
			right := body[idx + token.len..].trim_space()
			if left.len == 0 || right.len == 0 {
				return none
			}
			return MermaidClassRelation{
				left: left
				right: right
				kind: token
				label: label
			}
		}
	}
	return none
}

fn parse_mermaid_er_line(line string, mut diagram MermaidDiagram) ?string {
	if line.ends_with('{') {
		name := line[..line.len - 1].trim_space()
		if name.len == 0 {
			return none
		}
		ensure_mermaid_entity(mut diagram, name)
		return name
	}
	if relation := parse_mermaid_er_relation(line) {
		ensure_mermaid_entity(mut diagram, relation.left)
		ensure_mermaid_entity(mut diagram, relation.right)
		diagram.entity_relations << relation
	}
	return none
}

fn parse_mermaid_er_relation(line string) ?MermaidEntityRelation {
	mut body := line
	mut label := ''
	if colon := line.index(':') {
		body = line[..colon].trim_space()
		label = line[colon + 1..].trim_space()
	}
	parts := body.split_any(' \t').filter(it.len > 0)
	if parts.len < 3 {
		return none
	}
	relation := parts[1]
	dash_idx := relation.index('--') or { return none }
	left_card := relation[..dash_idx]
	right_card := relation[dash_idx + 2..]
	return MermaidEntityRelation{
		left: parts[0]
		right: parts[2]
		left_card: left_card
		right_card: right_card
		label: label
	}
}

fn parse_mermaid_gantt_line(line string, current_section string, mut diagram MermaidDiagram) string {
	mut next_section := current_section
	lower := line.to_lower()
	if lower.starts_with('title ') {
		diagram.title = line['title '.len..].trim_space()
		return next_section
	}
	if lower.starts_with('section ') {
		next_section = line['section '.len..].trim_space()
		ensure_mermaid_gantt_section(mut diagram, next_section)
		return next_section
	}
	if lower.starts_with('dateformat ') || lower.starts_with('axisformat ') {
		return next_section
	}
	if colon := line.index(':') {
		if next_section.len == 0 {
			next_section = 'Tasks'
			ensure_mermaid_gantt_section(mut diagram, next_section)
		}
		title := line[..colon].trim_space()
		meta := line[colon + 1..].split(',').map(it.trim_space()).filter(it.len > 0)
		if title.len == 0 {
			return next_section
		}
		mut state := ''
		mut metadata := meta.clone()
		if meta.len > 0 && meta[0].to_lower() in ['done', 'active', 'crit', 'milestone'] {
			state = meta[0].to_lower()
			metadata = meta[1..].clone()
		}
		append_mermaid_gantt_task(next_section, MermaidGanttTask{
			title: title
			state: state
			metadata: metadata
		}, mut diagram)
	}
	return next_section
}

fn parse_mermaid_mindmap_line(raw_line string, mut diagram MermaidDiagram, mut stack []MindmapStackEntry) {
	indent := raw_line.len - raw_line.trim_left(' \t').len
	level := indent / 2
	mut label := raw_line.trim_space()
	if label.len == 0 {
		return
	}
	for wrapper in ['((', '))', '((', '))', '[', ']', '(', ')', '{', '}', ':::', '*'] {
		label = label.replace(wrapper, '')
	}
	label = label.trim_space()
	if label.len == 0 {
		return
	}
	node := MermaidMindmapNode{
		label: label
	}
	if diagram.mindmap_root.label.len == 0 {
		diagram.mindmap_root = node
		stack = [MindmapStackEntry{
			level: level
			path: []int{}
		}]
		return
	}
	for stack.len > 0 && stack[stack.len - 1].level >= level {
		stack.delete(stack.len - 1)
	}
	parent_path := if stack.len > 0 { stack[stack.len - 1].path.clone() } else { []int{} }
	child_idx := append_mindmap_child(mut diagram.mindmap_root, parent_path, node)
	mut child_path := parent_path.clone()
	child_path << child_idx
	stack << MindmapStackEntry{
		level: level
		path: child_path
	}
}

fn append_mindmap_child(mut node MermaidMindmapNode, path []int, child MermaidMindmapNode) int {
	if path.len == 0 {
		node.children << child
		return node.children.len - 1
	}
	idx := path[0]
	child_idx := append_mindmap_child(mut node.children[idx], path[1..], child)
	return child_idx
}

fn parse_mermaid_journey_line(line string, current_section string, mut diagram MermaidDiagram) string {
	mut next_section := current_section
	lower := line.to_lower()
	if lower.starts_with('title ') {
		diagram.title = line['title '.len..].trim_space()
		return next_section
	}
	if lower.starts_with('section ') {
		next_section = line['section '.len..].trim_space()
		ensure_mermaid_journey_section(mut diagram, next_section)
		return next_section
	}
	parts := line.split(':').map(it.trim_space())
	if parts.len >= 2 {
		if next_section.len == 0 {
			next_section = 'Journey'
			ensure_mermaid_journey_section(mut diagram, next_section)
		}
		title := parts[0]
		score := parts[1].int()
		actors := if parts.len >= 3 { parts[2..].clone() } else { []string{} }
		append_mermaid_journey_step(next_section, MermaidJourneyStep{
			title: title
			score: score
			actors: actors
		}, mut diagram)
	}
	return next_section
}

fn parse_mermaid_git_graph_line(line string, mut diagram MermaidDiagram) {
	lower := line.to_lower()
	if lower.starts_with('commit') {
		mut name := 'commit'
		if idx := line.index('id:') {
			name = line[idx + 3..].trim_space().trim('"')
		}
		diagram.git_events << MermaidGitEvent{
			kind: .commit
			name: name
		}
		return
	}
	if lower.starts_with('branch ') {
		diagram.git_events << MermaidGitEvent{
			kind: .branch
			name: line['branch '.len..].trim_space()
		}
		return
	}
	if lower.starts_with('checkout ') {
		diagram.git_events << MermaidGitEvent{
			kind: .checkout
			name: line['checkout '.len..].trim_space()
		}
		return
	}
	if lower.starts_with('merge ') {
		diagram.git_events << MermaidGitEvent{
			kind: .merge
			target: line['merge '.len..].trim_space()
		}
	}
}

fn parse_mermaid_timeline_line(line string, mut diagram MermaidDiagram) {
	lower := line.to_lower()
	if lower.starts_with('title ') {
		diagram.title = line['title '.len..].trim_space()
		return
	}
	if colon := line.index(':') {
		head := line[..colon].trim_space()
		event := line[colon + 1..].trim_space()
		if head.len == 0 {
			if diagram.timeline_entries.len == 0 || event.len == 0 {
				return
			}
			mut last := diagram.timeline_entries[diagram.timeline_entries.len - 1]
			last.events << event
			diagram.timeline_entries[diagram.timeline_entries.len - 1] = last
			return
		}
		if event.len == 0 {
			return
		}
		diagram.timeline_entries << MermaidTimelineEntry{
			point: head
			events: [event]
		}
	}
}

fn parse_mermaid_direction_line(line string, mut diagram MermaidDiagram) bool {
	parts := line.split_any(' \t').filter(it.len > 0)
	if parts.len != 2 || parts[0].to_lower() != 'direction' {
		return false
	}
	diagram.direction = parse_mermaid_direction(parts[1]) or { return false }
	return true
}

fn parse_mermaid_direction(input string) !MermaidDirection {
	return match input.to_upper() {
		'TD', 'TB' { .top_down }
		'LR' { .left_right }
		else { return error('unsupported mermaid direction: ${input}') }
	}
}

fn parse_mermaid_subgraph_line(line string, mut diagram MermaidDiagram) ?string {
	if !line.to_lower().starts_with('subgraph ') {
		return none
	}
	title := line['subgraph '.len..].trim_space()
	if title.len == 0 {
		return none
	}
	ensure_mermaid_subgraph(mut diagram, title)
	return title
}

fn parse_mermaid_node_declaration(line string, mut diagram MermaidDiagram, mut seen map[string]int, current_subgraph string) ! {
	node := parse_mermaid_node_spec(line, current_subgraph)!
	upsert_mermaid_node(node, mut diagram, mut seen)
}

fn parse_mermaid_relation_line(line string, mut diagram MermaidDiagram, mut seen map[string]int, current_subgraph string) ! {
	mut specs := []string{}
	mut edge_kinds := []MermaidEdgeKind{}
	mut edge_labels := []string{}
	mut cursor := 0
	for {
		edge_match := find_next_mermaid_edge(line, cursor) or {
			specs << line[cursor..].trim_space()
			break
		}
		specs << line[cursor..edge_match.index].trim_space()
		edge_kinds << edge_match.kind
		label, next_cursor := parse_mermaid_edge_label(line, edge_match.index + edge_match.len)
		edge_labels << label
		cursor = next_cursor
	}
	if specs.len < 2 || edge_kinds.len != specs.len - 1 || edge_labels.len != edge_kinds.len {
		return error('unsupported mermaid relation: ${line}')
	}
	if specs.len == 2 && specs[1].contains('&') {
		parse_mermaid_branch_relation(specs[0], specs[1], edge_kinds[0], edge_labels[0], mut diagram,
			mut seen, current_subgraph)!
		return
	}
	mut path_nodes := []string{}
	for i, spec in specs {
		node := parse_mermaid_node_spec(spec, current_subgraph)!
		upsert_mermaid_node(node, mut diagram, mut seen)
		path_nodes << node.id
		if i > 0 {
			diagram.edges << MermaidEdge{
				from: path_nodes[i - 1]
				to: path_nodes[i]
				kind: edge_kinds[i - 1]
				label: edge_labels[i - 1]
			}
		}
	}
	diagram.paths << MermaidPath{
		nodes: path_nodes
		edge_kinds: edge_kinds
		edge_labels: edge_labels
		subgraph: current_subgraph
	}
}

fn parse_mermaid_branch_relation(source_spec string, target_specs string, kind MermaidEdgeKind, label string, mut diagram MermaidDiagram, mut seen map[string]int, current_subgraph string) ! {
	source := parse_mermaid_node_spec(source_spec, current_subgraph)!
	upsert_mermaid_node(source, mut diagram, mut seen)
	for raw_target in target_specs.split('&') {
		target := parse_mermaid_node_spec(raw_target, current_subgraph)!
		upsert_mermaid_node(target, mut diagram, mut seen)
		diagram.edges << MermaidEdge{
			from: source.id
			to: target.id
			kind: kind
			label: label
		}
		diagram.paths << MermaidPath{
			nodes: [source.id, target.id]
			edge_kinds: [kind]
			edge_labels: [label]
			subgraph: current_subgraph
		}
	}
}

fn find_next_mermaid_edge(line string, start int) ?MermaidEdgeMatch {
	if start >= line.len {
		return none
	}
	rest := line[start..]
	arrow_idx := rest.index('-->') or { -1 }
	line_idx := rest.index('---') or { -1 }
	if arrow_idx == -1 && line_idx == -1 {
		return none
	}
	if arrow_idx != -1 && (line_idx == -1 || arrow_idx <= line_idx) {
		return MermaidEdgeMatch{
			index: start + arrow_idx
			kind: .arrow
			len: 3
		}
	}
	return MermaidEdgeMatch{
		index: start + line_idx
		kind: .line
		len: 3
	}
}

fn parse_mermaid_edge_label(line string, start int) (string, int) {
	mut cursor := start
	for cursor < line.len && (line[cursor] == ` ` || line[cursor] == `\t`) {
		cursor++
	}
	if cursor >= line.len || line[cursor] != `|` {
		return '', cursor
	}
	end := line[cursor + 1..].index('|') or { return '', cursor }
	label_start := cursor + 1
	label_end := label_start + end
	label := line[label_start..label_end].trim_space()
	return label, label_end + 1
}

fn parse_mermaid_node_spec(input string, current_subgraph string) !MermaidNode {
	spec := input.trim_space()
	if spec.len == 0 {
		return error('empty mermaid node')
	}
	if spec.contains('{') && spec.ends_with('}') {
		idx := spec.index('{') or { return error('invalid mermaid node: ${spec}') }
		id := spec[..idx].trim_space()
		label := spec[idx + 1..spec.len - 1].trim_space()
		return MermaidNode{
			id: id
			label: if label.len > 0 { label } else { id }
			shape: .diamond
			subgraph: current_subgraph
		}
	}
	if spec.contains('[') && spec.ends_with(']') {
		idx := spec.index('[') or { return error('invalid mermaid node: ${spec}') }
		id := spec[..idx].trim_space()
		label := spec[idx + 1..spec.len - 1].trim_space()
		return MermaidNode{
			id: id
			label: if label.len > 0 { label } else { id }
			shape: .box
			subgraph: current_subgraph
		}
	}
	if spec.contains('(') && spec.ends_with(')') {
		idx := spec.index('(') or { return error('invalid mermaid node: ${spec}') }
		id := spec[..idx].trim_space()
		label := spec[idx + 1..spec.len - 1].trim_space()
		return MermaidNode{
			id: id
			label: if label.len > 0 { label } else { id }
			shape: .round
			subgraph: current_subgraph
		}
	}
	id := spec.split_any(' \t')[0].trim_space()
	return MermaidNode{
		id: id
		label: id
		shape: .box
		subgraph: current_subgraph
	}
}

fn upsert_mermaid_node(node MermaidNode, mut diagram MermaidDiagram, mut seen map[string]int) {
	if node.id.len == 0 {
		return
	}
	if node.id in seen {
		idx := seen[node.id]
		existing := diagram.nodes[idx]
		label := if existing.label == existing.id && node.label.len > 0 {
			node.label
		} else {
			existing.label
		}
		shape := if existing.shape == .box && node.shape != .box {
			node.shape
		} else {
			existing.shape
		}
		diagram.nodes[idx] = MermaidNode{
			id: existing.id
			label: label
			shape: shape
			subgraph: if existing.subgraph.len > 0 { existing.subgraph } else { node.subgraph }
		}
		if node.subgraph.len > 0 {
			attach_node_to_mermaid_subgraph(mut diagram, node.subgraph, existing.id)
		}
		return
	}
	seen[node.id] = diagram.nodes.len
	diagram.nodes << node
	if node.subgraph.len > 0 {
		attach_node_to_mermaid_subgraph(mut diagram, node.subgraph, node.id)
	}
}

fn ensure_mermaid_subgraph(mut diagram MermaidDiagram, title string) {
	for subgraph in diagram.subgraphs {
		if subgraph.title == title || subgraph.id == title {
			return
		}
	}
	diagram.subgraphs << MermaidSubgraph{
		id: title
		title: title
		node_ids: []string{}
	}
}

fn attach_node_to_mermaid_subgraph(mut diagram MermaidDiagram, title string, node_id string) {
	ensure_mermaid_subgraph(mut diagram, title)
	for i, subgraph in diagram.subgraphs {
		if subgraph.title != title && subgraph.id != title {
			continue
		}
		if node_id !in subgraph.node_ids {
			mut updated := subgraph.node_ids.clone()
			updated << node_id
			diagram.subgraphs[i] = MermaidSubgraph{
				id: subgraph.id
				title: subgraph.title
				node_ids: updated
			}
		}
		return
	}
}

fn ensure_mermaid_class(mut diagram MermaidDiagram, name string) {
	for class_def in diagram.classes {
		if class_def.name == name {
			return
		}
	}
	diagram.classes << MermaidClass{
		name: name
		members: []string{}
	}
}

fn append_mermaid_class_member(name string, member string, mut diagram MermaidDiagram) {
	ensure_mermaid_class(mut diagram, name)
	for i, class_def in diagram.classes {
		if class_def.name != name {
			continue
		}
		if member !in class_def.members {
			mut members := class_def.members.clone()
			members << member
			diagram.classes[i] = MermaidClass{
				name: class_def.name
				members: members
			}
		}
		return
	}
}

fn ensure_mermaid_entity(mut diagram MermaidDiagram, name string) {
	for entity in diagram.entities {
		if entity.name == name {
			return
		}
	}
	diagram.entities << MermaidEntity{
		name: name
		attributes: []string{}
	}
}

fn append_mermaid_entity_attribute(name string, attribute string, mut diagram MermaidDiagram) {
	ensure_mermaid_entity(mut diagram, name)
	for i, entity in diagram.entities {
		if entity.name != name {
			continue
		}
		if attribute !in entity.attributes {
			mut attrs := entity.attributes.clone()
			attrs << attribute
			diagram.entities[i] = MermaidEntity{
				name: entity.name
				attributes: attrs
			}
		}
		return
	}
}

fn ensure_mermaid_gantt_section(mut diagram MermaidDiagram, title string) {
	for section in diagram.gantt_sections {
		if section.title == title {
			return
		}
	}
	diagram.gantt_sections << MermaidGanttSection{
		title: title
		tasks: []MermaidGanttTask{}
	}
}

fn append_mermaid_gantt_task(section_title string, task MermaidGanttTask, mut diagram MermaidDiagram) {
	ensure_mermaid_gantt_section(mut diagram, section_title)
	for i, section in diagram.gantt_sections {
		if section.title != section_title {
			continue
		}
		mut tasks := section.tasks.clone()
		tasks << task
		diagram.gantt_sections[i] = MermaidGanttSection{
			title: section.title
			tasks: tasks
		}
		return
	}
}

fn ensure_mermaid_journey_section(mut diagram MermaidDiagram, title string) {
	for section in diagram.journey_sections {
		if section.title == title {
			return
		}
	}
	diagram.journey_sections << MermaidJourneySection{
		title: title
	}
}

fn append_mermaid_journey_step(section_title string, step MermaidJourneyStep, mut diagram MermaidDiagram) {
	for i, section in diagram.journey_sections {
		if section.title == section_title {
			mut updated := section
			updated.steps << step
			diagram.journey_sections[i] = updated
			return
		}
	}
	diagram.journey_sections << MermaidJourneySection{
		title: section_title
		steps: [step]
	}
}
