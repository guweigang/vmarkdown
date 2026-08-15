module vmarkdown

pub enum DiagramKind {
	tree
	flow
	dependency
	call
	org
	timeline
	pipeline
	state
	sequence
	journey
	git
}

pub enum DiagramDirection {
	top_down
	left_right
}

pub enum DiagramNodeShape {
	box
	round
	diamond
}

pub enum DiagramEdgeKind {
	line
	arrow
}

pub struct DiagramTree {
pub:
	root DiagramTreeNode
}

pub struct DiagramTreeNode {
pub mut:
	label    string
	children []DiagramTreeNode
}

pub struct DiagramGraph {
pub:
	kind      DiagramKind
	direction DiagramDirection
	nodes     []DiagramNode
	edges     []DiagramEdge
	groups    []DiagramGroup
}

pub struct DiagramEdge {
pub:
	from  string
	to    string
	kind  DiagramEdgeKind
	label string
}

pub struct DiagramNode {
pub:
	id    string
	label string
	shape DiagramNodeShape
	group string
}

pub struct DiagramGroup {
pub:
	id       string
	title    string
	node_ids []string
}

pub struct DiagramOrgChart {
pub:
	root DiagramOrgNode
}

pub struct DiagramOrgNode {
pub mut:
	name    string
	title   string
	reports []DiagramOrgNode
}

pub struct DiagramTimeline {
pub:
	title   string
	entries []DiagramTimelineEntry
}

pub struct DiagramTimelineEntry {
pub:
	point string
	text  string
}

pub struct DiagramPipeline {
pub:
	stages []DiagramPipelineStage
}

pub struct DiagramPipelineStage {
pub:
	name   string
	status string
}

pub struct DiagramStateMachine {
pub:
	transitions []DiagramStateTransition
}

pub struct DiagramStateTransition {
pub:
	from  string
	to    string
	label string
}

pub enum DiagramSequenceNoteSide {
	left
	right
}

pub enum DiagramSequenceBlockKind {
	alt
	else_branch
	opt
	loop
	par
}

pub struct DiagramSequence {
pub:
	participants []string
	events       []DiagramSequenceEvent
}

pub struct DiagramSequenceMessage {
pub:
	from string
	to   string
	text string
	kind DiagramEdgeKind
}

pub struct DiagramSequenceNote {
pub:
	participant string
	text        string
	side        DiagramSequenceNoteSide
}

pub struct DiagramSequenceActivation {
pub:
	participant string
	active      bool
}

pub struct DiagramSequenceBlockBoundary {
pub:
	kind  DiagramSequenceBlockKind
	label string
	start bool
}

pub type DiagramSequenceEvent = DiagramSequenceActivation
	| DiagramSequenceBlockBoundary
	| DiagramSequenceMessage
	| DiagramSequenceNote

pub struct DiagramJourney {
pub:
	title    string
	sections []DiagramJourneySection
}

pub struct DiagramClassDiagram {
pub:
	classes   []DiagramClass
	relations []DiagramClassRelation
}

pub struct DiagramClass {
pub:
	name    string
	members []string
}

pub struct DiagramClassRelation {
pub:
	left  string
	right string
	kind  string
	label string
}

pub struct DiagramERDiagram {
pub:
	entities  []DiagramEntity
	relations []DiagramEntityRelation
}

pub struct DiagramEntity {
pub:
	name       string
	attributes []string
}

pub struct DiagramEntityRelation {
pub:
	left       string
	right      string
	left_card  string
	right_card string
	label      string
}

pub struct DiagramGantt {
pub:
	title    string
	sections []DiagramGanttSection
}

pub struct DiagramGanttSection {
pub:
	title string
	tasks []DiagramGanttTask
}

pub struct DiagramGanttTask {
pub:
	title    string
	state    string
	metadata []string
}

pub struct DiagramJourneySection {
pub:
	title string
	steps []DiagramJourneyStep
}

pub struct DiagramJourneyStep {
pub:
	title  string
	score  int
	actors []string
}

pub struct DiagramGitGraph {
pub:
	events []DiagramGitEvent
}

pub enum DiagramGitEventKind {
	commit
	branch
	checkout
	merge
}

pub struct DiagramGitEvent {
pub:
	kind   DiagramGitEventKind
	name   string
	target string
}

pub type DiagramPayload = DiagramClassDiagram
	| DiagramERDiagram
	| DiagramGantt
	| DiagramGitGraph
	| DiagramGraph
	| DiagramJourney
	| DiagramOrgChart
	| DiagramPipeline
	| DiagramSequence
	| DiagramStateMachine
	| DiagramTimeline
	| DiagramTree

pub fn (tree DiagramTree) to_ascii_tree() AsciiTreeNode {
	return tree.root.to_ascii_tree()
}

pub fn (node DiagramTreeNode) to_ascii_tree() AsciiTreeNode {
	return AsciiTreeNode{
		label:    node.label
		children: node.children.map(it.to_ascii_tree())
	}
}

pub fn (graph DiagramGraph) to_ascii_edges() []AsciiGraphEdge {
	return graph.edges.map(AsciiGraphEdge{
		from: it.from
		to:   it.to
	})
}

pub fn (chart DiagramOrgChart) to_ascii_org() AsciiOrgNode {
	return chart.root.to_ascii_org()
}

pub fn (node DiagramOrgNode) to_ascii_org() AsciiOrgNode {
	return AsciiOrgNode{
		name:    node.name
		title:   node.title
		reports: node.reports.map(it.to_ascii_org())
	}
}

pub fn (timeline DiagramTimeline) to_ascii_timeline() []AsciiTimelineEntry {
	return timeline.entries.map(AsciiTimelineEntry{
		point: it.point
		text:  it.text
	})
}

pub fn (pipeline DiagramPipeline) to_ascii_pipeline() []AsciiPipelineStage {
	return pipeline.stages.map(AsciiPipelineStage{
		name:   it.name
		status: it.status
	})
}

pub fn (machine DiagramStateMachine) to_ascii_state_machine() []AsciiStateTransition {
	return machine.transitions.map(AsciiStateTransition{
		from:  it.from
		to:    it.to
		label: it.label
	})
}

pub fn render_diagram_payload(payload DiagramPayload, width int) string {
	safe_width := if width > 0 { width } else { 80 }
	return match payload {
		DiagramTree {
			render_ascii_tree(payload.to_ascii_tree(), safe_width)
		}
		DiagramGraph {
			match payload.kind {
				.flow { render_ascii_flow_graph(payload, safe_width) }
				.dependency { render_ascii_dependency_graph(payload.to_ascii_edges(), safe_width) }
				.call { render_ascii_call_graph(payload.to_ascii_edges(), safe_width) }
				else { '' }
			}
		}
		DiagramOrgChart {
			render_ascii_org_chart(payload.to_ascii_org(), if safe_width < 40 {
				40
			} else {
				safe_width
			})
		}
		DiagramTimeline {
			render_ascii_timeline_diagram(payload, safe_width)
		}
		DiagramPipeline {
			render_ascii_pipeline(payload.to_ascii_pipeline(), safe_width)
		}
		DiagramStateMachine {
			render_ascii_state_machine(payload.to_ascii_state_machine(), safe_width)
		}
		DiagramSequence {
			render_ascii_sequence(payload, max_int(safe_width, 32))
		}
		DiagramJourney {
			render_ascii_journey(payload, safe_width)
		}
		DiagramClassDiagram {
			render_ascii_class_diagram(payload, max_int(safe_width, 40))
		}
		DiagramERDiagram {
			render_ascii_er_diagram(payload, max_int(safe_width, 40))
		}
		DiagramGantt {
			render_ascii_gantt(payload, max_int(safe_width, 40))
		}
		DiagramGitGraph {
			render_ascii_git_graph(payload, safe_width)
		}
	}
}
