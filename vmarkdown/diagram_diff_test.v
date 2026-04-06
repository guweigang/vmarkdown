module vmarkdown

import os

fn test_diff_diagram_payloads_for_flow_graph() {
	previous := DiagramGraph{
		kind: .flow
		direction: .left_right
		nodes: [
			DiagramNode{id: 'A', label: 'Start', shape: .box},
			DiagramNode{id: 'B', label: 'Parse', shape: .box},
		]
		edges: [
			DiagramEdge{from: 'A', to: 'B', kind: .arrow},
		]
	}
	current := DiagramGraph{
		kind: .flow
		direction: .left_right
		nodes: [
			DiagramNode{id: 'A', label: 'Start', shape: .box},
			DiagramNode{id: 'B', label: 'Render', shape: .box},
		]
		edges: [
			DiagramEdge{from: 'A', to: 'B', kind: .arrow, label: 'ok'},
		]
	}
	diff := diff_diagram_payloads(previous, current)
	assert diff.any(it.op == .reused && it.kind == 'graph_node' && it.path == 'nodes[0]')
	assert diff.any(it.op == .removed && it.kind == 'graph_node' && it.path == 'nodes[1]')
	assert diff.any(it.op == .added && it.kind == 'graph_node' && it.path == 'nodes[1]')
	assert diff.any(it.op == .removed && it.kind == 'graph_edge' && it.path == 'edges[0]')
	assert diff.any(it.op == .added && it.kind == 'graph_edge' && it.path == 'edges[0]')
}

fn test_diff_diagram_payloads_for_sequence() {
	previous := DiagramSequence{
		participants: ['Alice', 'Bob']
		events: [
			DiagramSequenceMessage{from: 'Alice', to: 'Bob', text: 'hello', kind: .arrow},
		]
	}
	current := DiagramSequence{
		participants: ['Alice', 'Bob']
		events: [
			DiagramSequenceMessage{from: 'Alice', to: 'Bob', text: 'hello', kind: .arrow},
			DiagramSequenceNote{participant: 'Bob', text: 'working', side: .right},
		]
	}
	diff := diff_diagram_payloads(previous, current)
	assert diff.any(it.op == .reused && it.kind == 'sequence_participant' && it.path == 'participants[0]')
	assert diff.any(it.op == .reused && it.kind == 'sequence_message' && it.path == 'events[0]')
	assert diff.any(it.op == .added && it.kind == 'sequence_note' && it.path == 'events[1]')
}

fn test_diagram_diff_summary_groups_entries() {
	previous := DiagramTimeline{
		entries: [
			DiagramTimelineEntry{point: '2024', text: 'Parser'},
		]
	}
	current := DiagramTimeline{
		entries: [
			DiagramTimelineEntry{point: '2024', text: 'Parser'},
			DiagramTimelineEntry{point: '2025', text: 'Preview'},
		]
	}
	summary := diagram_diff_summary(diff_diagram_payloads(previous, current))
	assert summary.changed.len == 0
	assert summary.added.len == 1
	assert summary.added[0].kind == 'timeline_entry'
	assert summary.added[0].count == 1
	assert summary.added[0].paths == ['entries[1]']
	assert summary.reused.len == 1
	assert summary.lines.any(it == 'added timeline_entry at entries[1]')
	assert summary.lines.any(it == 'reused timeline_entry at entries[0]')
}

fn test_diff_diagram_json_summary() {
	before := '{"version":1,"entries":[{"point":"2024","text":"Parser"}]}'
	after := '{"version":1,"entries":[{"point":"2024","text":"Parser"},{"point":"2025","text":"Preview"}]}'
	before_path := os.join_path(os.temp_dir(), 'vmarkdown_timeline_before.json')
	after_path := os.join_path(os.temp_dir(), 'vmarkdown_timeline_after.json')
	os.write_file(before_path, before) or { panic(err) }
	os.write_file(after_path, after) or { panic(err) }
	summary := diff_diagram_json_summary('timeline', before_path, after_path) or { panic(err) }
	assert summary.lines.any(it == 'added timeline_entry at entries[1]')
	assert summary.lines.any(it == 'reused timeline_entry at entries[0]')
}

fn test_diff_mermaid_summary() {
	before := 'timeline
title Product History
2024 : Parser
'
	after := 'timeline
title Product History
2024 : Parser
2025 : Preview
'
	summary := diff_mermaid_summary(before, after) or { panic(err) }
	assert summary.lines.any(it == 'reused timeline_entry at entries[0]')
	assert summary.lines.any(it == 'added timeline_entry at entries[1]')
}

fn test_diagram_diff_summary_reports_changed_for_same_path() {
	previous := DiagramGraph{
		kind: .flow
		direction: .left_right
		nodes: [
			DiagramNode{id: 'A', label: 'Start', shape: .box},
			DiagramNode{id: 'B', label: 'Parse', shape: .box},
		]
		edges: [
			DiagramEdge{from: 'A', to: 'B', kind: .arrow},
		]
	}
	current := DiagramGraph{
		kind: .flow
		direction: .left_right
		nodes: [
			DiagramNode{id: 'A', label: 'Start', shape: .box},
			DiagramNode{id: 'B', label: 'Render', shape: .box},
		]
		edges: [
			DiagramEdge{from: 'A', to: 'B', kind: .arrow, label: 'ok'},
		]
	}
	summary := diagram_diff_summary(diff_diagram_payloads(previous, current))
	assert summary.changed.len == 2
	assert summary.changed.any(it.kind == 'graph_node' && it.paths == ['nodes[1]'])
	assert summary.changed.any(it.kind == 'graph_edge' && it.paths == ['edges[0]'])
	assert summary.lines.any(it == 'changed graph_node label at nodes[1]')
	assert summary.lines.any(it == 'changed graph_edge label at edges[0]')
	assert !summary.lines.any(it == 'added graph_node at nodes[1]')
	assert !summary.lines.any(it == 'removed graph_node at nodes[1]')
}

fn test_diagram_diff_summary_reports_multiple_changed_fields() {
	previous := DiagramPipeline{
		stages: [
			DiagramPipelineStage{name: 'Render', status: 'active'},
		]
	}
	current := DiagramPipeline{
		stages: [
			DiagramPipelineStage{name: 'Ship', status: 'done'},
		]
	}
	summary := diagram_diff_summary(diff_diagram_payloads(previous, current))
	assert summary.lines.any(it == 'changed pipeline_stage name, status at stages[0]')
}
