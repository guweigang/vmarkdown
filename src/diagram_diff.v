module vmarkdown

import crypto.sha256
import os

pub struct DiagramManifestEntry {
pub:
	id        string
	kind      string
	path      string
	signature string
}

pub struct DiagramDiffEntry {
pub:
	op        DiffOp
	id        string
	kind      string
	path      string
	signature string
}

pub struct DiagramDiffSummaryItem {
pub:
	op   DiffOp
	kind string
pub mut:
	count int
	paths []string
}

pub struct DiagramDiffSummary {
pub:
	changed []DiagramDiffSummaryItem
	added   []DiagramDiffSummaryItem
	removed []DiagramDiffSummaryItem
	reused  []DiagramDiffSummaryItem
	lines   []string
}

pub fn (payload DiagramPayload) manifest() []DiagramManifestEntry {
	return match payload {
		DiagramTree { tree_manifest(payload) }
		DiagramGraph { graph_manifest(payload) }
		DiagramOrgChart { org_manifest(payload) }
		DiagramTimeline { timeline_manifest(payload) }
		DiagramPipeline { pipeline_manifest(payload) }
		DiagramStateMachine { state_manifest(payload) }
		DiagramSequence { sequence_manifest(payload) }
		DiagramJourney { journey_manifest(payload) }
		DiagramClassDiagram { class_manifest(payload) }
		DiagramERDiagram { er_manifest(payload) }
		DiagramGantt { gantt_manifest(payload) }
		DiagramGitGraph { git_manifest(payload) }
	}
}

pub fn diff_diagram_payloads(previous DiagramPayload, current DiagramPayload) []DiagramDiffEntry {
	previous_manifest := previous.manifest()
	current_manifest := current.manifest()
	mut previous_by_path := map[string]DiagramManifestEntry{}
	mut current_by_path := map[string]DiagramManifestEntry{}
	for entry in previous_manifest {
		previous_by_path[entry.path] = entry
	}
	for entry in current_manifest {
		current_by_path[entry.path] = entry
	}
	mut seen_paths := map[string]bool{}
	mut diff := []DiagramDiffEntry{}
	for entry in current_manifest {
		seen_paths[entry.path] = true
		if entry.path in previous_by_path {
			prev := previous_by_path[entry.path]
			if prev.id == entry.id {
				diff << DiagramDiffEntry{
					op:        .reused
					id:        entry.id
					kind:      entry.kind
					path:      entry.path
					signature: entry.signature
				}
			} else {
				diff << DiagramDiffEntry{
					op:        .removed
					id:        prev.id
					kind:      prev.kind
					path:      prev.path
					signature: prev.signature
				}
				diff << DiagramDiffEntry{
					op:        .added
					id:        entry.id
					kind:      entry.kind
					path:      entry.path
					signature: entry.signature
				}
			}
		} else {
			diff << DiagramDiffEntry{
				op:        .added
				id:        entry.id
				kind:      entry.kind
				path:      entry.path
				signature: entry.signature
			}
		}
	}
	for entry in previous_manifest {
		if entry.path in seen_paths {
			continue
		}
		diff << DiagramDiffEntry{
			op:        .removed
			id:        entry.id
			kind:      entry.kind
			path:      entry.path
			signature: entry.signature
		}
	}
	return diff
}

pub fn diagram_diff_summary(entries []DiagramDiffEntry) DiagramDiffSummary {
	return DiagramDiffSummary{
		changed: diagram_changed_items(entries)
		added:   diagram_diff_items(entries, .added)
		removed: diagram_diff_items(entries, .removed)
		reused:  diagram_diff_items(entries, .reused)
		lines:   diagram_diff_lines(entries)
	}
}

pub fn diff_diagram_json(kind string, previous_path string, current_path string) ![]DiagramDiffEntry {
	previous := load_diagram_json(kind, previous_path)!
	current := load_diagram_json(kind, current_path)!
	return diff_diagram_payloads(previous, current)
}

pub fn diff_diagram_json_summary(kind string, previous_path string, current_path string) !DiagramDiffSummary {
	return diagram_diff_summary(diff_diagram_json(kind, previous_path, current_path)!)
}

pub fn diff_mermaid(previous string, current string) ![]DiagramDiffEntry {
	previous_diagram := parse_mermaid(previous)!
	current_diagram := parse_mermaid(current)!
	previous_payload := previous_diagram.to_diagram_payload()!
	current_payload := current_diagram.to_diagram_payload()!
	return diff_diagram_payloads(previous_payload, current_payload)
}

pub fn diff_mermaid_summary(previous string, current string) !DiagramDiffSummary {
	return diagram_diff_summary(diff_mermaid(previous, current)!)
}

pub fn diff_mermaid_files(previous_path string, current_path string) ![]DiagramDiffEntry {
	return diff_mermaid(os.read_file(previous_path)!, os.read_file(current_path)!)
}

pub fn diff_mermaid_files_summary(previous_path string, current_path string) !DiagramDiffSummary {
	return diagram_diff_summary(diff_mermaid_files(previous_path, current_path)!)
}

fn tree_manifest(tree DiagramTree) []DiagramManifestEntry {
	mut out := []DiagramManifestEntry{}
	append_tree_manifest(tree.root, 'root', mut out)
	return out
}

fn append_tree_manifest(node DiagramTreeNode, path string, mut out []DiagramManifestEntry) {
	out << DiagramManifestEntry{
		id:        diagram_manifest_id('tree_node', node.label)
		kind:      'tree_node'
		path:      path
		signature: node.label
	}
	for i, child in node.children {
		append_tree_manifest(child, '${path}.children[${i}]', mut out)
	}
}

fn graph_manifest(graph DiagramGraph) []DiagramManifestEntry {
	mut out := []DiagramManifestEntry{}
	for i, node in graph.nodes {
		out << DiagramManifestEntry{
			id:        diagram_manifest_id('graph_node',
				'${node.id}|${node.label}|${node.shape}|${node.group}')
			kind:      'graph_node'
			path:      'nodes[${i}]'
			signature: '${node.id}|${node.label}|${node.shape}|${node.group}'
		}
	}
	for i, edge in graph.edges {
		out << DiagramManifestEntry{
			id:        diagram_manifest_id('graph_edge',
				'${edge.from}|${edge.to}|${edge.kind}|${edge.label}')
			kind:      'graph_edge'
			path:      'edges[${i}]'
			signature: '${edge.from}|${edge.to}|${edge.kind}|${edge.label}'
		}
	}
	for i, group in graph.groups {
		out << DiagramManifestEntry{
			id:        diagram_manifest_id('graph_group',
				'${group.id}|${group.title}|${group.node_ids.join(',')}')
			kind:      'graph_group'
			path:      'groups[${i}]'
			signature: '${group.id}|${group.title}|${group.node_ids.join(',')}'
		}
	}
	return out
}

fn org_manifest(chart DiagramOrgChart) []DiagramManifestEntry {
	mut out := []DiagramManifestEntry{}
	append_org_manifest(chart.root, 'root', mut out)
	return out
}

fn append_org_manifest(node DiagramOrgNode, path string, mut out []DiagramManifestEntry) {
	out << DiagramManifestEntry{
		id:        diagram_manifest_id('org_node', '${node.name}|${node.title}')
		kind:      'org_node'
		path:      path
		signature: '${node.name}|${node.title}'
	}
	for i, child in node.reports {
		append_org_manifest(child, '${path}.reports[${i}]', mut out)
	}
}

fn timeline_manifest(timeline DiagramTimeline) []DiagramManifestEntry {
	mut out := []DiagramManifestEntry{}
	for i, entry in timeline.entries {
		out << DiagramManifestEntry{
			id:        diagram_manifest_id('timeline_entry', '${entry.point}|${entry.text}')
			kind:      'timeline_entry'
			path:      'entries[${i}]'
			signature: '${entry.point}|${entry.text}'
		}
	}
	return out
}

fn pipeline_manifest(pipeline DiagramPipeline) []DiagramManifestEntry {
	mut out := []DiagramManifestEntry{}
	for i, stage in pipeline.stages {
		out << DiagramManifestEntry{
			id:        diagram_manifest_id('pipeline_stage', '${stage.name}|${stage.status}')
			kind:      'pipeline_stage'
			path:      'stages[${i}]'
			signature: '${stage.name}|${stage.status}'
		}
	}
	return out
}

fn state_manifest(machine DiagramStateMachine) []DiagramManifestEntry {
	mut out := []DiagramManifestEntry{}
	for i, transition in machine.transitions {
		out << DiagramManifestEntry{
			id:        diagram_manifest_id('state_transition',
				'${transition.from}|${transition.to}|${transition.label}')
			kind:      'state_transition'
			path:      'transitions[${i}]'
			signature: '${transition.from}|${transition.to}|${transition.label}'
		}
	}
	return out
}

fn sequence_manifest(sequence DiagramSequence) []DiagramManifestEntry {
	mut out := []DiagramManifestEntry{}
	for i, participant in sequence.participants {
		out << DiagramManifestEntry{
			id:        diagram_manifest_id('sequence_participant', participant)
			kind:      'sequence_participant'
			path:      'participants[${i}]'
			signature: participant
		}
	}
	for i, event in sequence.events {
		match event {
			DiagramSequenceMessage {
				out << DiagramManifestEntry{
					id:        diagram_manifest_id('sequence_message',
						'${event.from}|${event.to}|${event.text}|${event.kind}')
					kind:      'sequence_message'
					path:      'events[${i}]'
					signature: '${event.from}|${event.to}|${event.text}|${event.kind}'
				}
			}
			DiagramSequenceNote {
				out << DiagramManifestEntry{
					id:        diagram_manifest_id('sequence_note',
						'${event.participant}|${event.side}|${event.text}')
					kind:      'sequence_note'
					path:      'events[${i}]'
					signature: '${event.participant}|${event.side}|${event.text}'
				}
			}
			DiagramSequenceActivation {
				out << DiagramManifestEntry{
					id:        diagram_manifest_id('sequence_activation',
						'${event.participant}|${event.active}')
					kind:      'sequence_activation'
					path:      'events[${i}]'
					signature: '${event.participant}|${event.active}'
				}
			}
			DiagramSequenceBlockBoundary {
				out << DiagramManifestEntry{
					id:        diagram_manifest_id('sequence_block',
						'${event.kind}|${event.label}|${event.start}')
					kind:      'sequence_block'
					path:      'events[${i}]'
					signature: '${event.kind}|${event.label}|${event.start}'
				}
			}
		}
	}
	return out
}

fn journey_manifest(journey DiagramJourney) []DiagramManifestEntry {
	mut out := []DiagramManifestEntry{}
	for i, section in journey.sections {
		out << DiagramManifestEntry{
			id:        diagram_manifest_id('journey_section', section.title)
			kind:      'journey_section'
			path:      'sections[${i}]'
			signature: section.title
		}
		for j, step in section.steps {
			out << DiagramManifestEntry{
				id:        diagram_manifest_id('journey_step',
					'${step.title}|${step.score}|${step.actors.join(',')}')
				kind:      'journey_step'
				path:      'sections[${i}].steps[${j}]'
				signature: '${step.title}|${step.score}|${step.actors.join(',')}'
			}
		}
	}
	return out
}

fn class_manifest(diagram DiagramClassDiagram) []DiagramManifestEntry {
	mut out := []DiagramManifestEntry{}
	for i, class_def in diagram.classes {
		out << DiagramManifestEntry{
			id:        diagram_manifest_id('class',
				'${class_def.name}|${class_def.members.join(',')}')
			kind:      'class'
			path:      'classes[${i}]'
			signature: '${class_def.name}|${class_def.members.join(',')}'
		}
	}
	for i, relation in diagram.relations {
		out << DiagramManifestEntry{
			id:        diagram_manifest_id('class_relation',
				'${relation.left}|${relation.right}|${relation.kind}|${relation.label}')
			kind:      'class_relation'
			path:      'relations[${i}]'
			signature: '${relation.left}|${relation.right}|${relation.kind}|${relation.label}'
		}
	}
	return out
}

fn er_manifest(diagram DiagramERDiagram) []DiagramManifestEntry {
	mut out := []DiagramManifestEntry{}
	for i, entity in diagram.entities {
		out << DiagramManifestEntry{
			id:        diagram_manifest_id('entity',
				'${entity.name}|${entity.attributes.join(',')}')
			kind:      'entity'
			path:      'entities[${i}]'
			signature: '${entity.name}|${entity.attributes.join(',')}'
		}
	}
	for i, relation in diagram.relations {
		out << DiagramManifestEntry{
			id:        diagram_manifest_id('entity_relation',
				'${relation.left}|${relation.right}|${relation.left_card}|${relation.right_card}|${relation.label}')
			kind:      'entity_relation'
			path:      'relations[${i}]'
			signature: '${relation.left}|${relation.right}|${relation.left_card}|${relation.right_card}|${relation.label}'
		}
	}
	return out
}

fn gantt_manifest(diagram DiagramGantt) []DiagramManifestEntry {
	mut out := []DiagramManifestEntry{}
	for i, section in diagram.sections {
		out << DiagramManifestEntry{
			id:        diagram_manifest_id('gantt_section', section.title)
			kind:      'gantt_section'
			path:      'sections[${i}]'
			signature: section.title
		}
		for j, task in section.tasks {
			out << DiagramManifestEntry{
				id:        diagram_manifest_id('gantt_task',
					'${task.title}|${task.state}|${task.metadata.join(',')}')
				kind:      'gantt_task'
				path:      'sections[${i}].tasks[${j}]'
				signature: '${task.title}|${task.state}|${task.metadata.join(',')}'
			}
		}
	}
	return out
}

fn git_manifest(graph DiagramGitGraph) []DiagramManifestEntry {
	mut out := []DiagramManifestEntry{}
	for i, event in graph.events {
		out << DiagramManifestEntry{
			id:        diagram_manifest_id('git_event',
				'${event.kind}|${event.name}|${event.target}')
			kind:      'git_event'
			path:      'events[${i}]'
			signature: '${event.kind}|${event.name}|${event.target}'
		}
	}
	return out
}

fn diagram_manifest_id(kind string, input string) string {
	return '${kind}:${sha256.hexhash(input)}'
}

fn diagram_diff_items(entries []DiagramDiffEntry, op DiffOp) []DiagramDiffSummaryItem {
	mut grouped := map[string]DiagramDiffSummaryItem{}
	mut order := []string{}
	for entry in entries {
		if entry.op != op {
			continue
		}
		key := entry.kind
		if key !in grouped {
			grouped[key] = DiagramDiffSummaryItem{
				op:    op
				kind:  entry.kind
				count: 0
				paths: []
			}
			order << key
		}
		mut item := grouped[key]
		item.count++
		item.paths << entry.path
		grouped[key] = item
	}
	mut out := []DiagramDiffSummaryItem{}
	for key in order {
		out << grouped[key]
	}
	return out
}

fn diagram_changed_items(entries []DiagramDiffEntry) []DiagramDiffSummaryItem {
	mut removed_by_key := map[string]DiagramDiffEntry{}
	mut grouped := map[string]DiagramDiffSummaryItem{}
	mut order := []string{}
	for entry in entries {
		key := '${entry.kind}|${entry.path}'
		if entry.op == .removed {
			removed_by_key[key] = entry
			continue
		}
		if entry.op != .added {
			continue
		}
		if key !in removed_by_key {
			continue
		}
		if key !in grouped {
			grouped[key] = DiagramDiffSummaryItem{
				op:    .added
				kind:  entry.kind
				count: 0
				paths: []
			}
			order << key
		}
		mut item := grouped[key]
		item.count++
		item.paths << entry.path
		grouped[key] = item
	}
	mut out := []DiagramDiffSummaryItem{}
	for key in order {
		out << grouped[key]
	}
	return out
}

fn diagram_diff_lines(entries []DiagramDiffEntry) []string {
	changed_details := diagram_changed_detail_map(entries)
	mut lines := []string{}
	for entry in entries {
		key := '${entry.kind}|${entry.path}'
		if key in changed_details && entry.op != .reused {
			if entry.op == .added {
				detail := changed_details[key]
				if detail.len > 0 {
					lines << 'changed ${entry.kind} ${detail} at ${entry.path}'
				} else {
					lines << 'changed ${entry.kind} at ${entry.path}'
				}
			}
			continue
		}
		action := match entry.op {
			.added { 'added' }
			.removed { 'removed' }
			.reused { 'reused' }
		}
		lines << '${action} ${entry.kind} at ${entry.path}'
	}
	return lines
}

fn diagram_changed_detail_map(entries []DiagramDiffEntry) map[string]string {
	mut removed := map[string]DiagramDiffEntry{}
	mut changed := map[string]string{}
	for entry in entries {
		key := '${entry.kind}|${entry.path}'
		match entry.op {
			.removed {
				removed[key] = entry
			}
			.added {
				if key in removed {
					changed[key] = diagram_change_detail(removed[key], entry)
				}
			}
			else {}
		}
	}
	return changed
}

fn diagram_change_detail(previous DiagramDiffEntry, current DiagramDiffEntry) string {
	return match previous.kind {
		'graph_node' {
			graph_node_change_detail(previous.signature, current.signature)
		}
		'graph_edge' {
			graph_edge_change_detail(previous.signature, current.signature)
		}
		'timeline_entry' {
			timeline_entry_change_detail(previous.signature, current.signature)
		}
		'pipeline_stage' {
			pipeline_stage_change_detail(previous.signature, current.signature)
		}
		'state_transition' {
			state_transition_change_detail(previous.signature, current.signature)
		}
		'sequence_participant' {
			scalar_change_detail('name', previous.signature, current.signature)
		}
		'sequence_message' {
			sequence_message_change_detail(previous.signature, current.signature)
		}
		'sequence_note' {
			sequence_note_change_detail(previous.signature, current.signature)
		}
		'sequence_activation' {
			sequence_activation_change_detail(previous.signature, current.signature)
		}
		'sequence_block' {
			sequence_block_change_detail(previous.signature, current.signature)
		}
		'journey_section' {
			scalar_change_detail('title', previous.signature, current.signature)
		}
		'journey_step' {
			journey_step_change_detail(previous.signature, current.signature)
		}
		'class' {
			class_change_detail(previous.signature, current.signature)
		}
		'class_relation' {
			class_relation_change_detail(previous.signature, current.signature)
		}
		'entity' {
			entity_change_detail(previous.signature, current.signature)
		}
		'entity_relation' {
			entity_relation_change_detail(previous.signature, current.signature)
		}
		'gantt_section' {
			scalar_change_detail('title', previous.signature, current.signature)
		}
		'gantt_task' {
			gantt_task_change_detail(previous.signature, current.signature)
		}
		'git_event' {
			git_event_change_detail(previous.signature, current.signature)
		}
		'org_node' {
			org_node_change_detail(previous.signature, current.signature)
		}
		'tree_node' {
			scalar_change_detail('label', previous.signature, current.signature)
		}
		'graph_group' {
			graph_group_change_detail(previous.signature, current.signature)
		}
		else {
			''
		}
	}
}

fn graph_node_change_detail(previous string, current string) string {
	prev := previous.split('|')
	curr := current.split('|')
	return joined_change_detail([
		field_change_detail('id', field_at(prev, 0), field_at(curr, 0)),
		field_change_detail('label', field_at(prev, 1), field_at(curr, 1)),
		field_change_detail('shape', field_at(prev, 2), field_at(curr, 2)),
		field_change_detail('group', field_at(prev, 3), field_at(curr, 3)),
	])
}

fn graph_edge_change_detail(previous string, current string) string {
	prev := previous.split('|')
	curr := current.split('|')
	return joined_change_detail([
		field_change_detail('from', field_at(prev, 0), field_at(curr, 0)),
		field_change_detail('to', field_at(prev, 1), field_at(curr, 1)),
		field_change_detail('kind', field_at(prev, 2), field_at(curr, 2)),
		field_change_detail('label', field_at(prev, 3), field_at(curr, 3)),
	])
}

fn timeline_entry_change_detail(previous string, current string) string {
	prev := previous.split('|')
	curr := current.split('|')
	return joined_change_detail([
		field_change_detail('point', field_at(prev, 0), field_at(curr, 0)),
		field_change_detail('text', field_at(prev, 1), field_at(curr, 1)),
	])
}

fn pipeline_stage_change_detail(previous string, current string) string {
	prev := previous.split('|')
	curr := current.split('|')
	return joined_change_detail([
		field_change_detail('name', field_at(prev, 0), field_at(curr, 0)),
		field_change_detail('status', field_at(prev, 1), field_at(curr, 1)),
	])
}

fn state_transition_change_detail(previous string, current string) string {
	prev := previous.split('|')
	curr := current.split('|')
	return joined_change_detail([
		field_change_detail('from', field_at(prev, 0), field_at(curr, 0)),
		field_change_detail('to', field_at(prev, 1), field_at(curr, 1)),
		field_change_detail('label', field_at(prev, 2), field_at(curr, 2)),
	])
}

fn sequence_message_change_detail(previous string, current string) string {
	prev := previous.split('|')
	curr := current.split('|')
	return joined_change_detail([
		field_change_detail('from', field_at(prev, 0), field_at(curr, 0)),
		field_change_detail('to', field_at(prev, 1), field_at(curr, 1)),
		field_change_detail('text', field_at(prev, 2), field_at(curr, 2)),
		field_change_detail('kind', field_at(prev, 3), field_at(curr, 3)),
	])
}

fn sequence_note_change_detail(previous string, current string) string {
	prev := previous.split('|')
	curr := current.split('|')
	return joined_change_detail([
		field_change_detail('participant', field_at(prev, 0), field_at(curr, 0)),
		field_change_detail('side', field_at(prev, 1), field_at(curr, 1)),
		field_change_detail('text', field_at(prev, 2), field_at(curr, 2)),
	])
}

fn sequence_activation_change_detail(previous string, current string) string {
	prev := previous.split('|')
	curr := current.split('|')
	return joined_change_detail([
		field_change_detail('participant', field_at(prev, 0), field_at(curr, 0)),
		field_change_detail('active', field_at(prev, 1), field_at(curr, 1)),
	])
}

fn sequence_block_change_detail(previous string, current string) string {
	prev := previous.split('|')
	curr := current.split('|')
	return joined_change_detail([
		field_change_detail('kind', field_at(prev, 0), field_at(curr, 0)),
		field_change_detail('label', field_at(prev, 1), field_at(curr, 1)),
		field_change_detail('start', field_at(prev, 2), field_at(curr, 2)),
	])
}

fn journey_step_change_detail(previous string, current string) string {
	prev := previous.split('|')
	curr := current.split('|')
	return joined_change_detail([
		field_change_detail('title', field_at(prev, 0), field_at(curr, 0)),
		field_change_detail('score', field_at(prev, 1), field_at(curr, 1)),
		field_change_detail('actors', field_at(prev, 2), field_at(curr, 2)),
	])
}

fn class_change_detail(previous string, current string) string {
	prev := previous.split('|')
	curr := current.split('|')
	return joined_change_detail([
		field_change_detail('name', field_at(prev, 0), field_at(curr, 0)),
		field_change_detail('members', field_at(prev, 1), field_at(curr, 1)),
	])
}

fn class_relation_change_detail(previous string, current string) string {
	prev := previous.split('|')
	curr := current.split('|')
	return joined_change_detail([
		field_change_detail('left', field_at(prev, 0), field_at(curr, 0)),
		field_change_detail('right', field_at(prev, 1), field_at(curr, 1)),
		field_change_detail('kind', field_at(prev, 2), field_at(curr, 2)),
		field_change_detail('label', field_at(prev, 3), field_at(curr, 3)),
	])
}

fn entity_change_detail(previous string, current string) string {
	prev := previous.split('|')
	curr := current.split('|')
	return joined_change_detail([
		field_change_detail('name', field_at(prev, 0), field_at(curr, 0)),
		field_change_detail('attributes', field_at(prev, 1), field_at(curr, 1)),
	])
}

fn entity_relation_change_detail(previous string, current string) string {
	prev := previous.split('|')
	curr := current.split('|')
	return joined_change_detail([
		field_change_detail('left', field_at(prev, 0), field_at(curr, 0)),
		field_change_detail('right', field_at(prev, 1), field_at(curr, 1)),
		field_change_detail('left_card', field_at(prev, 2), field_at(curr, 2)),
		field_change_detail('right_card', field_at(prev, 3), field_at(curr, 3)),
		field_change_detail('label', field_at(prev, 4), field_at(curr, 4)),
	])
}

fn gantt_task_change_detail(previous string, current string) string {
	prev := previous.split('|')
	curr := current.split('|')
	return joined_change_detail([
		field_change_detail('title', field_at(prev, 0), field_at(curr, 0)),
		field_change_detail('state', field_at(prev, 1), field_at(curr, 1)),
		field_change_detail('metadata', field_at(prev, 2), field_at(curr, 2)),
	])
}

fn git_event_change_detail(previous string, current string) string {
	prev := previous.split('|')
	curr := current.split('|')
	return joined_change_detail([
		field_change_detail('kind', field_at(prev, 0), field_at(curr, 0)),
		field_change_detail('name', field_at(prev, 1), field_at(curr, 1)),
		field_change_detail('target', field_at(prev, 2), field_at(curr, 2)),
	])
}

fn org_node_change_detail(previous string, current string) string {
	prev := previous.split('|')
	curr := current.split('|')
	return joined_change_detail([
		field_change_detail('name', field_at(prev, 0), field_at(curr, 0)),
		field_change_detail('title', field_at(prev, 1), field_at(curr, 1)),
	])
}

fn graph_group_change_detail(previous string, current string) string {
	prev := previous.split('|')
	curr := current.split('|')
	return joined_change_detail([
		field_change_detail('id', field_at(prev, 0), field_at(curr, 0)),
		field_change_detail('title', field_at(prev, 1), field_at(curr, 1)),
		field_change_detail('node_ids', field_at(prev, 2), field_at(curr, 2)),
	])
}

fn scalar_change_detail(name string, previous string, current string) string {
	return field_change_detail(name, previous, current)
}

fn field_change_detail(name string, previous string, current string) string {
	if previous == current {
		return ''
	}
	return name
}

fn joined_change_detail(parts []string) string {
	mut changed := []string{}
	for part in parts {
		if part.len > 0 {
			changed << part
		}
	}
	return changed.join(', ')
}

fn field_at(parts []string, index int) string {
	if index < 0 || index >= parts.len {
		return ''
	}
	return parts[index]
}
