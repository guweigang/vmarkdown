module vmarkdown

fn first_rune_index(line string, target rune) int {
	for i, ch in line.runes() {
		if ch == target {
			return i
		}
	}
	return -1
}

fn first_line_containing(rendered string, pattern string) string {
	for line in rendered.split_into_lines() {
		if line.contains(pattern) {
			return line
		}
	}
	return ''
}

fn first_line_with_rune(rendered string, target rune) string {
	for line in rendered.split_into_lines() {
		if first_rune_index(line, target) >= 0 {
			return line
		}
	}
	return ''
}

fn test_parse_mermaid_flowchart_td() {
	diagram := parse_mermaid('flowchart TD\nA[Start] --> B[Parse] --> C[Render]\n') or {
		panic(err)
	}
	assert diagram.kind == .flowchart
	assert diagram.direction == .top_down
	assert diagram.nodes.len == 3
	assert diagram.paths.len == 1
	assert diagram.paths[0].nodes == ['A', 'B', 'C']
}

fn test_parse_mermaid_graph_lr_round_nodes() {
	diagram := parse_mermaid('graph LR\nA(Start) --- B(Done)\n') or { panic(err) }
	assert diagram.direction == .left_right
	assert diagram.nodes.len == 2
	assert diagram.nodes[0].shape == .round
	assert diagram.edges[0].kind == .line
}

fn test_render_mermaid_ascii_td() {
	rendered := render_mermaid_ascii('flowchart TD\nA[Start] --> B[Parse]\n', 48) or {
		panic(err)
	}
	assert rendered.contains('Start')
	assert rendered.contains('▼')
	assert rendered.contains('Parse')
}

fn test_render_mermaid_ascii_lr() {
	rendered := render_mermaid_ascii('flowchart LR\nA[Start] --> B[Parse] --> C[Render]\n', 80) or {
		panic(err)
	}
	assert rendered.contains('[Start] ──▶ [Parse] ──▶ [Render]')
}

fn test_parse_mermaid_edge_labels_and_diamond_shape() {
	diagram := parse_mermaid('flowchart TD\nA{Ready} -->|yes| B[Go]\n') or { panic(err) }
	assert diagram.nodes.len == 2
	assert diagram.nodes[0].shape == .diamond
	assert diagram.edges[0].label == 'yes'
	assert diagram.paths[0].edge_labels[0] == 'yes'
}

fn test_render_mermaid_ascii_edge_labels() {
	rendered := render_mermaid_ascii('flowchart LR\nA{Ready} -->|yes| B[Go]\n', 80) or {
		panic(err)
	}
	assert rendered.contains('{Ready}')
	assert rendered.contains('yes')
	assert rendered.contains('[Go]')
}

fn test_render_mermaid_ascii_simple_flow_uses_shared_payload_renderer() {
	rendered := render_mermaid_ascii('flowchart LR\nA[Start] -->|ok| B(Go)\n', 80) or {
		panic(err)
	}
	assert rendered.contains('[Start]')
	assert rendered.contains('(Go)')
	assert rendered.contains('ok')
}

fn test_render_mermaid_ascii_chain_flow_keeps_mermaid_layout() {
	rendered := render_mermaid_ascii('flowchart LR\nA[Start] --> B[Parse] --> C[Render]\n', 80) or {
		panic(err)
	}
	assert rendered.contains('[Start] ──▶ [Parse] ──▶ [Render]')
}

fn test_render_mermaid_ascii_td_chain_uses_shared_payload_renderer() {
	rendered := render_mermaid_ascii('flowchart TD\nA[Start] --> B[Parse] --> C[Render]\n', 64) or {
		panic(err)
	}
	assert rendered.contains('Start')
	assert rendered.contains('Parse')
	assert rendered.contains('Render')
	assert rendered.contains('▼')
}

fn test_parse_mermaid_branch_relation() {
	diagram := parse_mermaid('flowchart TD\nA[Start] --> B[One] & C[Two]\n') or { panic(err) }
	assert diagram.edges.len == 2
	assert diagram.paths.len == 2
	assert diagram.paths[0].nodes == ['A', 'B']
	assert diagram.paths[1].nodes == ['A', 'C']
}

fn test_parse_mermaid_subgraph() {
	diagram := parse_mermaid('flowchart TD\nsubgraph Core\nA[Start] --> B[Parse]\nend\n') or {
		panic(err)
	}
	assert diagram.subgraphs.len == 1
	assert diagram.subgraphs[0].title == 'Core'
	assert diagram.nodes[0].subgraph == 'Core'
	assert diagram.paths[0].subgraph == 'Core'
}

fn test_render_mermaid_ascii_subgraph() {
	rendered := render_mermaid_ascii('flowchart TD\nsubgraph Core\nA[Start] --> B[Parse]\nend\n', 64) or {
		panic(err)
	}
	assert rendered.contains('╭ Core ')
	assert rendered.contains('│')
	assert rendered.contains('Start')
	assert rendered.contains('Parse')
}

fn test_render_mermaid_ascii_partial_subgraph_without_cross_edges() {
	rendered := render_mermaid_ascii('flowchart LR\nsubgraph Core\nA[Start] --> B[Parse]\nend\nD[Ship] --> E[Done]\n', 80) or {
		panic(err)
	}
	assert rendered.contains('╭ Core ')
	assert rendered.contains('Start')
	assert rendered.contains('Parse')
	assert rendered.contains('Ship')
	assert rendered.contains('Done')
}

fn test_render_mermaid_ascii_partial_subgraph_with_single_cross_edge() {
	rendered := render_mermaid_ascii('flowchart LR\nsubgraph Core\nA[Start] --> B[Parse]\nend\nX[Input] -->|feed| A\n', 88) or {
		panic(err)
	}
	assert rendered.contains('╭ Core ')
	assert rendered.contains('Input')
	assert rendered.contains('Start')
	assert rendered.contains('Parse')
	assert rendered.contains('──▶')
	assert rendered.contains('feed')
}

fn test_render_mermaid_ascii_partial_subgraph_with_single_cross_edge_from_outside_chain() {
	rendered := render_mermaid_ascii('flowchart LR\nsubgraph Core\nA[Start] --> B[Parse]\nend\nX[Input] --> Y[Load]\nY -->|feed| A\n', 96) or {
		panic(err)
	}
	assert rendered.contains('╭ Core ')
	assert rendered.contains('Input')
	assert rendered.contains('Load')
	assert rendered.contains('Start')
	assert rendered.contains('Parse')
	assert rendered.contains('feed')
}

fn test_render_mermaid_ascii_partial_subgraph_with_in_and_out_cross_edges() {
	rendered := render_mermaid_ascii('flowchart LR\nX[Input] --> Y[Load]\nsubgraph Core\nA[Start] --> B[Parse]\nend\nY -->|feed| A\nB -->|emit| O[Ship]\nO --> D[Done]\n', 108) or {
		panic(err)
	}
	assert rendered.contains('╭ Core ')
	assert rendered.contains('Input')
	assert rendered.contains('Load')
	assert rendered.contains('Start')
	assert rendered.contains('Parse')
	assert rendered.contains('Ship')
	assert rendered.contains('Done')
	assert rendered.contains('feed')
	assert rendered.contains('emit')
}

fn test_render_mermaid_ascii_partial_subgraph_with_two_incoming_cross_edges() {
	rendered := render_mermaid_ascii('flowchart LR\nsubgraph Core\nA[Start] --> B[Parse]\nend\nX[Input] -->|feed| A\nY[Config] -->|feed| B\n', 108) or {
		panic(err)
	}
	assert rendered.contains('╭ Core ')
	assert rendered.contains('Input')
	assert rendered.contains('Config')
	assert rendered.contains('Start')
	assert rendered.contains('Parse')
	assert rendered.contains('feed')
}

fn test_render_mermaid_ascii_partial_subgraph_with_two_outgoing_cross_edges() {
	rendered := render_mermaid_ascii('flowchart LR\nsubgraph Core\nA[Start] --> B[Parse]\nend\nA -->|emit| X[Ship]\nB -->|emit| Y[Done]\n', 108) or {
		panic(err)
	}
	assert rendered.contains('╭ Core ')
	assert rendered.contains('Ship')
	assert rendered.contains('Done')
	assert rendered.contains('Start')
	assert rendered.contains('Parse')
	assert rendered.contains('emit')
}

fn test_render_mermaid_ascii_partial_subgraph_with_two_incoming_and_two_outgoing_cross_edges() {
	rendered := render_mermaid_ascii('flowchart LR\nX[Input] --> Y[Load]\nU[Config] --> V[Check]\nY -->|feed| A\nV -->|feed| B\nsubgraph Core\nA[Start] --> B[Parse]\nend\nA -->|emit| M[Ship]\nB -->|emit| N[Audit]\nM --> O[Done]\nN --> P[Log]\n', 120) or {
		panic(err)
	}
	assert rendered.contains('Core')
	assert rendered.contains('feed')
	assert rendered.contains('emit')
	assert rendered.contains('Load')
	assert rendered.contains('Check')
	assert rendered.contains('Ship')
	assert rendered.contains('Audit')
	assert rendered.contains('Done')
	assert rendered.contains('Log')
}

fn test_render_mermaid_ascii_partial_subgraph_with_two_incoming_and_one_outgoing_cross_edges() {
	rendered := render_mermaid_ascii('flowchart LR\nX[Input] --> Y[Load]\nU[Config] --> V[Check]\nY -->|feed| A\nV -->|feed| B\nsubgraph Core\nA[Start] --> B[Parse]\nend\nB -->|emit| O[Ship]\nO --> D[Done]\n', 120) or {
		panic(err)
	}
	assert rendered.contains('Core')
	assert rendered.contains('feed')
	assert rendered.contains('emit')
	assert rendered.contains('Load')
	assert rendered.contains('Check')
	assert rendered.contains('Ship')
	assert rendered.contains('Done')
}

fn test_render_mermaid_ascii_partial_subgraph_with_one_incoming_and_two_outgoing_cross_edges() {
	rendered := render_mermaid_ascii('flowchart LR\nX[Input] --> Y[Load]\nY -->|feed| A\nsubgraph Core\nA[Start] --> B[Parse]\nend\nA -->|emit| M[Ship]\nB -->|emit| N[Audit]\nM --> O[Done]\nN --> P[Log]\n', 120) or {
		panic(err)
	}
	assert rendered.contains('Core')
	assert rendered.contains('feed')
	assert rendered.contains('emit')
	assert rendered.contains('Load')
	assert rendered.contains('Ship')
	assert rendered.contains('Audit')
	assert rendered.contains('Done')
	assert rendered.contains('Log')
}

fn test_render_mermaid_ascii_td_partial_subgraph_with_two_incoming_and_one_outgoing_cross_edges() {
	rendered := render_mermaid_ascii('flowchart TD\nX[Input] --> Y[Load]\nU[Config] --> V[Check]\nY -->|feed| A\nV -->|feed| B\nsubgraph Core\nA[Start] --> B[Parse]\nend\nB -->|emit| O[Ship]\nO --> D[Done]\n', 96) or {
		panic(err)
	}
	assert rendered.contains('Core')
	assert rendered.contains('feed')
	assert rendered.contains('emit')
	assert rendered.contains('Load')
	assert rendered.contains('Check')
	assert rendered.contains('Ship')
	assert rendered.contains('Done')
}

fn test_render_mermaid_ascii_td_partial_subgraph_with_two_incoming_and_two_outgoing_cross_edges_aligns_to_one_axis() {
	rendered := render_mermaid_ascii('flowchart TD\nX[Input] --> Y[Load]\nU[Config] --> V[Check]\nY -->|feed| A\nV -->|feed| B\nsubgraph Core\nA[Start] --> B[Parse]\nend\nA -->|emit| M[Ship]\nB -->|emit| N[Audit]\nM --> O[Done]\nN --> P[Log]\n', 96) or {
		panic(err)
	}
	merge_line := first_line_with_rune(rendered, `┼`)
	feed_line := first_line_containing(rendered, 'feed')
	center_line := first_line_containing(rendered, '╭ Core ')
	emit_line := first_line_containing(rendered, 'emit')
	branch_line := first_line_with_rune(rendered, `├`)
	assert merge_line.len > 0
	assert feed_line.len > 0
	assert center_line.len > 0
	assert emit_line.len > 0
	assert branch_line.len > 0
	axis_col := first_rune_index(merge_line, `┼`)
	assert axis_col >= 0
	assert first_rune_index(center_line, `╭`) < axis_col
	assert first_rune_index(center_line, `╮`) > axis_col
	feed_start := feed_line.index('feed') or { -1 }
	emit_start := emit_line.index('emit') or { -1 }
	assert feed_start >= 0
	assert emit_start >= 0
	assert axis_col >= feed_start && axis_col < feed_start + 'feed'.len
	assert axis_col >= emit_start && axis_col < emit_start + 'emit'.len
	assert first_rune_index(branch_line, `├`) == axis_col
}

fn test_render_mermaid_ascii_td_partial_subgraph_with_one_incoming_and_two_outgoing_cross_edges() {
	rendered := render_mermaid_ascii('flowchart TD\nX[Input] --> Y[Load]\nY -->|feed| A\nsubgraph Core\nA[Start] --> B[Parse]\nend\nA -->|emit| M[Ship]\nB -->|emit| N[Audit]\nM --> O[Done]\nN --> P[Log]\n', 96) or {
		panic(err)
	}
	assert rendered.contains('Core')
	assert rendered.contains('feed')
	assert rendered.contains('emit')
	assert rendered.contains('Load')
	assert rendered.contains('Ship')
	assert rendered.contains('Audit')
	assert rendered.contains('Done')
	assert rendered.contains('Log')
}

fn test_render_mermaid_ascii_td_partial_subgraph_with_one_incoming_and_two_outgoing_cross_edges_aligns_branch_to_axis() {
	rendered := render_mermaid_ascii('flowchart TD\nX[Input] --> Y[Load]\nY -->|feed| A\nsubgraph Core\nA[Start] --> B[Parse]\nend\nA -->|emit| M[Ship]\nB -->|emit| N[Audit]\nM --> O[Done]\nN --> P[Log]\n', 96) or {
		panic(err)
	}
	center_line := first_line_containing(rendered, '╭ Core ')
	emit_line := first_line_containing(rendered, 'emit')
	branch_line := first_line_with_rune(rendered, `├`)
	assert center_line.len > 0
	assert emit_line.len > 0
	assert branch_line.len > 0
	axis_col := (first_rune_index(center_line, `╭`) + first_rune_index(center_line, `╮`)) / 2
	emit_start := emit_line.index('emit') or { -1 }
	assert emit_start >= 0
	assert axis_col >= emit_start && axis_col < emit_start + 'emit'.len
	assert first_rune_index(branch_line, `├`) == axis_col
}

fn test_render_mermaid_ascii_branch_group_shares_source_node() {
	rendered := render_mermaid_ascii('flowchart TD\nA[Start] --> B[One] & C[Two]\n', 64) or {
		panic(err)
	}
	assert rendered.count('Start') == 1
	assert rendered.count('One') == 1
	assert rendered.count('Two') == 1
	assert rendered.contains('├─▶')
	assert rendered.contains('╭')
}

fn test_render_mermaid_ascii_merge_group_shares_target_node() {
	rendered := render_mermaid_ascii('flowchart TD\nB[Parse] --> D[Done]\nC[Validate] --> D[Done]\n', 64) or {
		panic(err)
	}
	assert rendered.count('Done') == 1
	assert rendered.contains('[Parse]')
	assert rendered.contains('[Validate]')
	assert rendered.contains('┴')
	assert rendered.contains('[Done]')
}

fn test_render_mermaid_ascii_branch_then_merge_group() {
	rendered := render_mermaid_ascii('flowchart TD\nA[Start] --> B[Parse] & C[Validate]\nB[Parse] --> D[Done]\nC[Validate] --> D[Done]\n', 80) or {
		panic(err)
	}
	assert rendered.count('Start') == 1
	assert rendered.count('Done') == 1
	assert rendered.count('Parse') == 1
	assert rendered.count('Validate') == 1
	assert rendered.contains('├─▶')
	assert rendered.contains('└─▶')
	assert rendered.contains('┴')
}

fn test_render_mermaid_ascii_lr_branch_group() {
	rendered := render_mermaid_ascii('flowchart LR\nA[Start] --> B[Parse] & C[Validate]\n', 80) or {
		panic(err)
	}
	assert rendered.count('Start') == 1
	assert rendered.contains('[Start] ─┬─▶ [Parse]')
	assert rendered.contains('└─▶ [Validate]')
}

fn test_render_mermaid_ascii_lr_merge_group() {
	rendered := render_mermaid_ascii('flowchart LR\nB[Parse] --> D[Done]\nC[Validate] --> D[Done]\n', 80) or {
		panic(err)
	}
	assert rendered.count('Done') == 1
	assert rendered.contains('[Parse]')
	assert rendered.contains('[Validate]')
	assert rendered.contains('┴ ─▶ [Done]')
}

fn test_render_mermaid_ascii_lr_branch_then_merge_group() {
	rendered := render_mermaid_ascii('flowchart LR\nA[Start] --> B[Parse] & C[Validate]\nB[Parse] --> D[Done]\nC[Validate] --> D[Done]\n', 96) or {
		panic(err)
	}
	assert rendered.count('Start') == 1
	assert rendered.count('Done') == 1
	assert rendered.contains('[Start] ─┬─▶ [Parse]')
	assert rendered.contains('└─▶ [Validate]')
	assert rendered.contains('┴ ─▶ [Done]')
}

fn test_parse_mermaid_sequence_diagram() {
	diagram := parse_mermaid('sequenceDiagram\nAlice->>Bob: hello\nBob->>Alice: world\n') or {
		panic(err)
	}
	assert diagram.kind == .sequence
	assert diagram.participants == ['Alice', 'Bob']
	assert diagram.messages.len == 2
	assert diagram.sequence_events.len == 2
	assert diagram.messages[0].text == 'hello'
}

fn test_render_mermaid_sequence_diagram() {
	rendered := render_mermaid_ascii('sequenceDiagram\nparticipant Alice\nparticipant Bob\nAlice->>Bob: hello\n', 80) or {
		panic(err)
	}
	assert rendered.contains('Alice')
	assert rendered.contains('Bob')
	assert rendered.contains('hello')
	assert rendered.contains('▶')
}

fn test_parse_mermaid_sequence_notes_and_activation() {
	diagram := parse_mermaid('sequenceDiagram\nparticipant Alice\nparticipant Bob\nactivate Bob\nNote right of Bob: working\nBob->>Alice: done\ndeactivate Bob\n') or {
		panic(err)
	}
	assert diagram.sequence_events.len == 4
	assert diagram.sequence_events[0] is MermaidSequenceActivation
	assert diagram.sequence_events[1] is MermaidSequenceNote
	assert diagram.sequence_events[2] is MermaidSequenceMessage
	assert diagram.sequence_events[3] is MermaidSequenceActivation
}

fn test_render_mermaid_sequence_notes_and_activation() {
	rendered := render_mermaid_ascii('sequenceDiagram\nparticipant Alice\nparticipant Bob\nactivate Bob\nNote right of Bob: working\nBob->>Alice: done\ndeactivate Bob\n', 96) or {
		panic(err)
	}
	assert rendered.contains('[working]')
	assert rendered.contains('║')
	assert rendered.contains('done')
}

fn test_parse_mermaid_sequence_blocks() {
	diagram := parse_mermaid('sequenceDiagram\nalt success\nAlice->>Bob: ok\nend\nloop retry\nBob->>Alice: again\nend\n') or {
		panic(err)
	}
	assert diagram.sequence_events.len == 6
	assert diagram.sequence_events[0] is MermaidSequenceBlockBoundary
	assert diagram.sequence_events[1] is MermaidSequenceMessage
	assert diagram.sequence_events[2] is MermaidSequenceBlockBoundary
	assert diagram.sequence_events[3] is MermaidSequenceBlockBoundary
}

fn test_render_mermaid_sequence_blocks() {
	rendered := render_mermaid_ascii('sequenceDiagram\nalt success\nAlice->>Bob: ok\nend\n', 96) or {
		panic(err)
	}
	assert rendered.contains('alt success')
	assert rendered.contains('┌')
	assert rendered.contains('┘')
}

fn test_parse_mermaid_sequence_else_and_par() {
	diagram := parse_mermaid('sequenceDiagram\nalt hit\nAlice->>Bob: ok\nelse miss\nBob->>Alice: retry\nend\npar workers\nAlice->>Bob: fanout\nend\n') or {
		panic(err)
	}
	assert diagram.sequence_events[0] is MermaidSequenceBlockBoundary
	assert diagram.sequence_events[2] is MermaidSequenceBlockBoundary
	assert diagram.sequence_events[4] is MermaidSequenceBlockBoundary
}

fn test_render_mermaid_sequence_else_and_self_message() {
	rendered := render_mermaid_ascii('sequenceDiagram\nalt hit\nAlice->>Bob: ok\nelse miss\nBob->>Bob: cache\nend\n', 96) or {
		panic(err)
	}
	assert rendered.contains('else miss')
	assert rendered.contains('╭─↺ cache')
}

fn test_parse_mermaid_state_diagram() {
	diagram := parse_mermaid('stateDiagram-v2\n[*] --> Idle\nIdle --> Running: start\nRunning --> [*]: done\n') or {
		panic(err)
	}
	assert diagram.kind == .state
	assert diagram.state_transitions.len == 3
	assert diagram.state_transitions[1].label == 'start'
}

fn test_render_mermaid_state_diagram() {
	rendered := render_mermaid_ascii('stateDiagram-v2\n[*] --> Idle\nIdle --> Running: start\n', 80) or {
		panic(err)
	}
	assert rendered.contains('◉')
	assert rendered.contains('[Idle]')
	assert rendered.contains('[Running]')
	assert rendered.contains('· start')
}

fn test_parse_mermaid_class_diagram() {
	diagram := parse_mermaid('classDiagram\nclass Animal {\n+name string\n+speak()\n}\nAnimal <|-- Dog : inherits\n') or {
		panic(err)
	}
	assert diagram.kind == .class
	assert diagram.classes.len == 2
	assert diagram.class_relations.len == 1
	assert diagram.classes[0].members.len == 2
}

fn test_render_mermaid_class_diagram() {
	rendered := render_mermaid_ascii('classDiagram\nclass Animal {\n+name string\n+speak()\n}\nAnimal <|-- Dog : inherits\n', 80) or {
		panic(err)
	}
	assert rendered.contains('Animal')
	assert rendered.contains('+name string')
	assert rendered.contains('<|--')
	assert rendered.contains('inherits')
}

fn test_parse_mermaid_er_diagram() {
	diagram := parse_mermaid('erDiagram\nUSER {\nstring id\nstring email\n}\nORDER {\nstring id\n}\nUSER ||--o{ ORDER : places\n') or {
		panic(err)
	}
	assert diagram.kind == .er
	assert diagram.entities.len == 2
	assert diagram.entity_relations.len == 1
	assert diagram.entities[0].attributes.len == 2
}

fn test_render_mermaid_er_diagram() {
	rendered := render_mermaid_ascii('erDiagram\nUSER {\nstring id\n}\nORDER {\nstring id\n}\nUSER ||--o{ ORDER : places\n', 80) or {
		panic(err)
	}
	assert rendered.contains('USER')
	assert rendered.contains('string id')
	assert rendered.contains('||--o{')
	assert rendered.contains('places')
}

fn test_parse_mermaid_mindmap() {
	diagram := parse_mermaid('mindmap\n  Root\n    Origins\n      History\n    Products\n') or {
		panic(err)
	}
	assert diagram.kind == .mindmap
	assert diagram.mindmap_root.label == 'Root'
	assert diagram.mindmap_root.children.len == 2
}

fn test_render_mermaid_mindmap() {
	rendered := render_mermaid_ascii('mindmap\n  Root\n    Origins\n      History\n    Products\n', 80) or {
		panic(err)
	}
	assert rendered.contains('◉ Root')
	assert rendered.contains('├─ Origins') || rendered.contains('└─ Origins')
	assert rendered.contains('History')
}

fn test_parse_mermaid_journey() {
	diagram := parse_mermaid('journey\ntitle User Journey\nsection Morning\nLogin: 5: User\nPay: 3: User, System\n') or {
		panic(err)
	}
	assert diagram.kind == .journey
	assert diagram.title == 'User Journey'
	assert diagram.journey_sections.len == 1
	assert diagram.journey_sections[0].steps.len == 2
}

fn test_render_mermaid_journey() {
	rendered := render_mermaid_ascii('journey\ntitle User Journey\nsection Morning\nLogin: 5: User\nPay: 3: User, System\n', 80) or {
		panic(err)
	}
	assert rendered.contains('User Journey')
	assert rendered.contains('▎ Morning')
	assert rendered.contains('Login')
	assert rendered.contains('●●●●●')
}

fn test_parse_mermaid_git_graph() {
	diagram := parse_mermaid('gitGraph\ncommit id: "Init"\nbranch feature\ncheckout feature\ncommit id: "Work"\ncheckout main\nmerge feature\n') or {
		panic(err)
	}
	assert diagram.kind == .git_graph
	assert diagram.git_events.len == 6
	assert diagram.git_events[0].kind == .commit
	assert diagram.git_events[1].kind == .branch
}

fn test_render_mermaid_git_graph() {
	rendered := render_mermaid_ascii('gitGraph\ncommit id: "Init"\nbranch feature\ncheckout feature\ncommit id: "Work"\ncheckout main\nmerge feature\n', 80) or {
		panic(err)
	}
	assert rendered.contains('● main  Init')
	assert rendered.contains('branch feature')
	assert rendered.contains('merge feature')
}

fn test_parse_mermaid_timeline() {
	diagram := parse_mermaid('timeline\ntitle Product History\n2024 : Parser\n     : Preview\n2025 : Mermaid\n') or {
		panic(err)
	}
	assert diagram.kind == .timeline
	assert diagram.title == 'Product History'
	assert diagram.timeline_entries.len == 2
	assert diagram.timeline_entries[0].events.len == 2
}

fn test_render_mermaid_timeline() {
	rendered := render_mermaid_ascii('timeline\ntitle Product History\n2024 : Parser\n     : Preview\n2025 : Mermaid\n', 80) or {
		panic(err)
	}
	assert rendered.contains('Product History')
	assert rendered.contains('2024')
	assert rendered.contains('├─ Parser')
	assert rendered.contains('└─ Preview')
	assert rendered.contains('2025')
}

fn test_parse_mermaid_gantt_diagram() {
	diagram := parse_mermaid('gantt\ntitle Release Plan\nsection Build\nCompile :done, a1, 2026-04-01, 1d\nShip :active, after a1, 2d\n') or {
		panic(err)
	}
	assert diagram.kind == .gantt
	assert diagram.title == 'Release Plan'
	assert diagram.gantt_sections.len == 1
	assert diagram.gantt_sections[0].tasks.len == 2
	assert diagram.gantt_sections[0].tasks[0].state == 'done'
}

fn test_render_mermaid_gantt_diagram() {
	rendered := render_mermaid_ascii('gantt\ntitle Release Plan\nsection Build\nCompile :done, a1, 2026-04-01, 1d\nShip :active, after a1, 2d\n', 80) or {
		panic(err)
	}
	assert rendered.contains('Release Plan')
	assert rendered.contains('▎ Build')
	assert rendered.contains('Compile')
	assert rendered.contains('█████')
	assert rendered.contains('Ship')
	assert rendered.contains('▓▓▓▒▒')
}
