module vmarkdown

pub enum MermaidDiagramKind {
	flowchart
	sequence
	state
	class
	er
	gantt
	mindmap
	journey
	git_graph
	timeline
}

pub enum MermaidDirection {
	top_down
	left_right
}

pub enum MermaidNodeShape {
	box
	round
	diamond
}

pub enum MermaidEdgeKind {
	line
	arrow
}

pub struct MermaidDiagram {
pub mut:
	kind              MermaidDiagramKind
	direction         MermaidDirection
	title             string
	nodes             []MermaidNode
	edges             []MermaidEdge
	paths             []MermaidPath
	subgraphs         []MermaidSubgraph
	participants      []string
	messages          []MermaidSequenceMessage
	sequence_events   []MermaidSequenceEvent
	state_transitions []MermaidStateTransition
	classes           []MermaidClass
	class_relations   []MermaidClassRelation
	entities          []MermaidEntity
	entity_relations  []MermaidEntityRelation
	gantt_sections    []MermaidGanttSection
	mindmap_root      MermaidMindmapNode
	journey_sections  []MermaidJourneySection
	git_events        []MermaidGitEvent
	timeline_entries  []MermaidTimelineEntry
}

pub struct MermaidStateTransition {
pub:
	from  string
	to    string
	label string
}

pub struct MermaidClass {
pub mut:
	name    string
	members []string
}

pub struct MermaidClassRelation {
pub:
	left  string
	right string
	kind  string
	label string
}

pub struct MermaidEntity {
pub mut:
	name       string
	attributes []string
}

pub struct MermaidEntityRelation {
pub:
	left       string
	right      string
	left_card  string
	right_card string
	label      string
}

pub struct MermaidGanttSection {
pub mut:
	title string
	tasks []MermaidGanttTask
}

pub struct MermaidGanttTask {
pub:
	title    string
	state    string
	metadata []string
}

pub struct MermaidMindmapNode {
pub mut:
	label    string
	children []MermaidMindmapNode
}

pub struct MermaidJourneySection {
pub mut:
	title string
	steps []MermaidJourneyStep
}

pub struct MermaidJourneyStep {
pub:
	title  string
	score  int
	actors []string
}

pub enum MermaidGitEventKind {
	commit
	branch
	checkout
	merge
}

pub struct MermaidGitEvent {
pub:
	kind   MermaidGitEventKind
	name   string
	target string
}

pub struct MermaidTimelineEntry {
pub mut:
	point  string
	events []string
}

pub struct MermaidNode {
pub:
	id       string
	label    string
	shape    MermaidNodeShape
	subgraph string
}

pub struct MermaidEdge {
pub:
	from  string
	to    string
	kind  MermaidEdgeKind
	label string
}

pub struct MermaidPath {
pub:
	nodes       []string
	edge_kinds  []MermaidEdgeKind
	edge_labels []string
	subgraph    string
}

pub struct MermaidSubgraph {
pub:
	id       string
	title    string
	node_ids []string
}

pub struct MermaidSequenceMessage {
pub:
	from string
	to   string
	text string
	kind MermaidEdgeKind
}

pub enum MermaidSequenceNoteSide {
	left
	right
}

pub struct MermaidSequenceNote {
pub:
	participant string
	text        string
	side        MermaidSequenceNoteSide
}

pub struct MermaidSequenceActivation {
pub:
	participant string
	active      bool
}

pub enum MermaidSequenceBlockKind {
	alt
	else_branch
	opt
	loop
	par
}

pub struct MermaidSequenceBlockBoundary {
pub:
	kind  MermaidSequenceBlockKind
	label string
	start bool
}

pub type MermaidSequenceEvent = MermaidSequenceActivation
	| MermaidSequenceBlockBoundary
	| MermaidSequenceMessage
	| MermaidSequenceNote

struct MermaidEdgeMatch {
	index int
	kind  MermaidEdgeKind
	len   int
}

pub fn (kind MermaidDiagramKind) str() string {
	return match kind {
		.flowchart { 'flowchart' }
		.sequence { 'sequenceDiagram' }
		.state { 'stateDiagram-v2' }
		.class { 'classDiagram' }
		.er { 'erDiagram' }
		.gantt { 'gantt' }
		.mindmap { 'mindmap' }
		.journey { 'journey' }
		.git_graph { 'gitGraph' }
		.timeline { 'timeline' }
	}
}

pub fn (direction MermaidDirection) str() string {
	return match direction {
		.top_down { 'TD' }
		.left_right { 'LR' }
	}
}

pub fn (kind MermaidSequenceBlockKind) str() string {
	return match kind {
		.alt { 'alt' }
		.else_branch { 'else' }
		.opt { 'opt' }
		.loop { 'loop' }
		.par { 'par' }
	}
}

fn (diagram MermaidDiagram) node_by_id(id string) ?MermaidNode {
	for node in diagram.nodes {
		if node.id == id {
			return node
		}
	}
	return none
}

fn (diagram MermaidDiagram) class_by_name(name string) ?MermaidClass {
	for class_def in diagram.classes {
		if class_def.name == name {
			return class_def
		}
	}
	return none
}

fn (diagram MermaidDiagram) entity_by_name(name string) ?MermaidEntity {
	for entity in diagram.entities {
		if entity.name == name {
			return entity
		}
	}
	return none
}
