module vmarkdown

import json2
import os

pub struct TreeInput {
pub:
	version int
	root    DiagramTreeNode
}

pub struct EdgeInput {
pub:
	version int
	edges   []DiagramEdge
}

pub struct OrgInput {
pub:
	version int
	root    DiagramOrgNode
}

pub struct TimelineInput {
pub:
	version int
	title   string
	entries []DiagramTimelineEntry
}

pub struct PipelineInput {
pub:
	version int
	stages  []DiagramPipelineStage
}

pub struct StateMachineInput {
pub:
	version     int
	transitions []DiagramStateTransition
}

struct DiagramDocumentHeader {
pub:
	kind string
}

pub fn render_diagram_json(kind string, path string, width int) !string {
	payload := load_diagram_json(kind, path)!
	return render_diagram_payload(payload, width)
}

pub fn validate_diagram_json(kind string, path string) !string {
	raw := os.read_file(path)!
	return validate_diagram_json_raw(kind, raw)
}

pub fn validate_diagram_json_raw(kind string, raw string) !string {
	return match kind {
		'tree' {
			input := json2.decode[TreeInput](raw)!
			validate_schema_version(input.version, 'tree')!
			validate_tree_node(input.root, 'root')!
			'valid tree schema: root=' + input.root.label
		}
		'dependency', 'call' {
			input := json2.decode[EdgeInput](raw)!
			validate_schema_version(input.version, kind)!
			if input.edges.len == 0 {
				return error('${kind} edges cannot be empty')
			}
			validate_graph_edges(input.edges, 'edges')!
			'valid ${kind} schema: ${input.edges.len} edge(s)'
		}
		'org' {
			input := json2.decode[OrgInput](raw)!
			validate_schema_version(input.version, 'org')!
			validate_org_node(input.root, 'root')!
			'valid org schema: root=' + input.root.name
		}
		'timeline' {
			input := json2.decode[TimelineInput](raw)!
			validate_schema_version(input.version, 'timeline')!
			if input.entries.len == 0 {
				return error('timeline entries cannot be empty')
			}
			validate_timeline_entries(input.entries)!
			mut label := 'entries'
			if input.entries.len == 1 {
				label = 'entry'
			}
			'valid timeline schema: ${input.entries.len} ${label}'
		}
		'pipeline' {
			input := json2.decode[PipelineInput](raw)!
			validate_schema_version(input.version, 'pipeline')!
			if input.stages.len == 0 {
				return error('pipeline stages cannot be empty')
			}
			validate_pipeline_stages(input.stages)!
			'valid pipeline schema: ${input.stages.len} stage(s)'
		}
		'state' {
			input := json2.decode[StateMachineInput](raw)!
			validate_schema_version(input.version, 'state')!
			if input.transitions.len == 0 {
				return error('state transitions cannot be empty')
			}
			validate_state_transitions(input.transitions)!
			'valid state schema: ${input.transitions.len} transition(s)'
		}
		else {
			return error('unknown diagram kind: ${kind}')
		}
	}
}

pub fn validate_diagram_document_raw(raw string) !string {
	header := json2.decode[DiagramDocumentHeader](raw)!
	kind := header.kind.trim_space()
	if kind.len == 0 {
		return error('diagram.kind cannot be empty')
	}
	return validate_diagram_json_raw(kind, raw)
}

pub fn load_diagram_json(kind string, path string) !DiagramPayload {
	raw := os.read_file(path)!
	return decode_diagram_json(kind, raw)
}

pub fn decode_diagram_json(kind string, raw string) !DiagramPayload {
	validate_diagram_json_raw(kind, raw)!
	return match kind {
		'tree' {
			input := json2.decode[TreeInput](raw)!
			DiagramTree{
				root: input.root
			}
		}
		'dependency' {
			input := json2.decode[EdgeInput](raw)!
			DiagramGraph{
				kind:  .dependency
				edges: input.edges
			}
		}
		'call' {
			input := json2.decode[EdgeInput](raw)!
			DiagramGraph{
				kind:  .call
				edges: input.edges
			}
		}
		'org' {
			input := json2.decode[OrgInput](raw)!
			DiagramOrgChart{
				root: input.root
			}
		}
		'timeline' {
			input := json2.decode[TimelineInput](raw)!
			DiagramTimeline{
				title:   input.title
				entries: input.entries
			}
		}
		'pipeline' {
			input := json2.decode[PipelineInput](raw)!
			DiagramPipeline{
				stages: input.stages
			}
		}
		'state' {
			input := json2.decode[StateMachineInput](raw)!
			DiagramStateMachine{
				transitions: input.transitions
			}
		}
		else {
			return error('unknown diagram kind: ${kind}')
		}
	}
}

pub fn decode_diagram_document(raw string) !DiagramPayload {
	header := json2.decode[DiagramDocumentHeader](raw)!
	kind := header.kind.trim_space()
	if kind.len == 0 {
		return error('diagram.kind cannot be empty')
	}
	return decode_diagram_json(kind, raw)
}

pub fn diagram_schema(kind string) string {
	return match kind {
		'all' { all_schemas() }
		'tree' { tree_schema() }
		'dependency', 'call' { edge_schema(kind) }
		'org' { org_schema() }
		'timeline' { timeline_schema() }
		'pipeline' { pipeline_schema() }
		'state' { state_schema() }
		else { 'unknown diagram kind: ${kind}' }
	}
}

fn validate_schema_version(version int, kind string) ! {
	if version == 0 || version == 1 {
		return
	}
	return error('${kind}.version must be 1 when provided')
}

fn validate_tree_node(node DiagramTreeNode, path string) ! {
	if node.label.len == 0 {
		return error('${path}.label cannot be empty')
	}
	for i, child in node.children {
		validate_tree_node(child, '${path}.children[${i}]')!
	}
}

fn validate_graph_edges(edges []DiagramEdge, path string) ! {
	mut seen := map[string]bool{}
	for i, edge in edges {
		from := edge.from.trim_space()
		to := edge.to.trim_space()
		if from.len == 0 {
			return error('${path}[${i}].from cannot be empty')
		}
		if to.len == 0 {
			return error('${path}[${i}].to cannot be empty')
		}
		if from == to {
			return error('${path}[${i}] self loops are not supported: ${from} -> ${to}')
		}
		key := from + '->' + to
		if key in seen {
			return error('${path}[${i}] duplicates an earlier edge: ${from} -> ${to}')
		}
		seen[key] = true
	}
}

fn validate_org_node(node DiagramOrgNode, path string) ! {
	name := node.name.trim_space()
	if name.len == 0 {
		return error('${path}.name cannot be empty')
	}
	for i, child in node.reports {
		validate_org_node(child, '${path}.reports[${i}]')!
	}
}

fn validate_timeline_entries(entries []DiagramTimelineEntry) ! {
	for i, entry in entries {
		point := entry.point.trim_space()
		text := entry.text.trim_space()
		if point.len == 0 {
			return error('entries[${i}].point cannot be empty')
		}
		if text.len == 0 {
			return error('entries[${i}].text cannot be empty')
		}
		if point.len > 32 {
			return error('entries[${i}].point is too long; keep it under 33 characters')
		}
	}
}

fn validate_pipeline_stages(stages []DiagramPipelineStage) ! {
	for i, stage in stages {
		name := stage.name.trim_space()
		if name.len == 0 {
			return error('stages[${i}].name cannot be empty')
		}
		status := stage.status.trim_space()
		if status.len > 0 && status !in ['done', 'active', 'pending'] {
			return error('stages[${i}].status must be one of: done, active, pending')
		}
	}
}

fn validate_state_transitions(transitions []DiagramStateTransition) ! {
	mut seen := map[string]bool{}
	for i, transition in transitions {
		from := transition.from.trim_space()
		to := transition.to.trim_space()
		if from.len == 0 {
			return error('transitions[${i}].from cannot be empty')
		}
		if to.len == 0 {
			return error('transitions[${i}].to cannot be empty')
		}
		key := from + '->' + to + '|' + transition.label.trim_space()
		if key in seen {
			return error('transitions[${i}] duplicates an earlier transition: ${from} -> ${to}')
		}
		seen[key] = true
	}
}

fn all_schemas() string {
	return [
		'vmarkdown diagram schema kinds:',
		'',
		'- tree',
		'- dependency',
		'- call',
		'- org',
		'- timeline',
		'- pipeline',
		'- state',
		'',
		'Use `v run cmd/vmarkdown diagram schema <kind>` to inspect required fields, optional fields, and an example payload.',
	].join('\n')
}

fn tree_schema() string {
	return 'vmarkdown diagram schema: tree

This is a vmarkdown-internal JSON payload, not a Mermaid or industry-standard schema.

Version:
- optional `version`
- current version: 1

Required:
- root.label

Optional:
- version
- root.children

Shape:
{
  "version": 1,
  "root": {
    "label": "vmarkdown",
    "children": [
      {"label": "parser"},
      {"label": "preview", "children": [{"label": "search"}]}
    ]
  }
}'
}

fn edge_schema(kind string) string {
	title := if kind == 'call' { 'call' } else { 'dependency' }
	return 'vmarkdown diagram schema: ${title}

This is a vmarkdown-internal JSON payload, not a Mermaid or industry-standard schema.

Version:
- optional `version`
- current version: 1

Required:
- edges[].from
- edges[].to

Optional:
- version

Shape:
{
  "version": 1,
  "edges": [
    {"from": "root", "to": "preview"},
    {"from": "root", "to": "lexer"},
    {"from": "preview", "to": "parser"},
    {"from": "lexer", "to": "parser"},
    {"from": "parser", "to": "renderer"}
  ]
}'
}

fn org_schema() string {
	return 'vmarkdown diagram schema: org

This is a vmarkdown-internal JSON payload, not a Mermaid or industry-standard schema.

Version:
- optional `version`
- current version: 1

Required:
- root.name

Optional:
- version
- root.title
- root.reports

Shape:
{
  "version": 1,
  "root": {
    "name": "Guwei",
    "title": "Founder",
    "reports": [
      {
        "name": "Parser Team",
        "title": "Core",
        "reports": [
          {"name": "Lexer Squad", "title": "Infra"}
        ]
      },
      {
        "name": "Preview Team",
        "title": "UI"
      }
    ]
  }
}'
}

fn timeline_schema() string {
	return 'vmarkdown diagram schema: timeline

This is a vmarkdown-internal JSON payload, not a Mermaid or industry-standard schema.

Version:
- optional `version`
- current version: 1

Required:
- entries[].point
- entries[].text

Optional:
- version
- title

Shape:
{
  "version": 1,
  "title": "Product History",
  "entries": [
    {"point": "2024", "text": "Parser"},
    {"point": "2024", "text": "Preview"},
    {"point": "2025", "text": "Mermaid"}
  ]
}'
}

fn pipeline_schema() string {
	return 'vmarkdown diagram schema: pipeline

This is a vmarkdown-internal JSON payload, not a Mermaid or industry-standard schema.

Version:
- optional `version`
- current version: 1

Required:
- stages[].name

Optional:
- version
- stages[].status
  allowed values: done, active, pending

Shape:
{
  "version": 1,
  "stages": [
    {"name": "Parse", "status": "done"},
    {"name": "Render", "status": "active"},
    {"name": "Ship", "status": "pending"}
  ]
}'
}

fn state_schema() string {
	return 'vmarkdown diagram schema: state

This is a vmarkdown-internal JSON payload, not a Mermaid or industry-standard schema.

Version:
- optional `version`
- current version: 1

Required:
- transitions[].from
- transitions[].to

Optional:
- version
- transitions[].label

Shape:
{
  "version": 1,
  "transitions": [
    {"from": "Idle", "to": "Running", "label": "start"},
    {"from": "Running", "to": "Done", "label": "finish"}
  ]
}'
}
