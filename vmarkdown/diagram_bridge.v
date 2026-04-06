module vmarkdown

pub fn (diagram MermaidDiagram) to_diagram_payload() !DiagramPayload {
	return match diagram.kind {
		.flowchart {
			DiagramGraph{
				kind: .flow
				direction: mermaid_direction_to_diagram(diagram.direction)
				nodes: mermaid_nodes_to_diagram(diagram.nodes)
				edges: mermaid_flow_to_diagram(diagram.edges)
				groups: mermaid_subgraphs_to_diagram(diagram.subgraphs)
			}
		}
		.journey {
			DiagramJourney{
				title: diagram.title
				sections: mermaid_journey_to_diagram(diagram.journey_sections)
			}
		}
		.git_graph {
			DiagramGitGraph{
				events: mermaid_git_to_diagram(diagram.git_events)
			}
		}
		.mindmap {
			DiagramTree{
				root: mermaid_mindmap_to_diagram(diagram.mindmap_root)
			}
		}
		.timeline {
			DiagramTimeline{
				title: diagram.title
				entries: mermaid_timeline_to_diagram(diagram.timeline_entries)
			}
		}
		.state {
			DiagramStateMachine{
				transitions: mermaid_state_to_diagram(diagram.state_transitions)
			}
		}
		.sequence {
			DiagramSequence{
				participants: diagram.participants.clone()
				events: mermaid_sequence_to_diagram(diagram.sequence_events)
			}
		}
		.class {
			DiagramClassDiagram{
				classes: mermaid_class_to_diagram(diagram.classes)
				relations: mermaid_class_relations_to_diagram(diagram.class_relations)
			}
		}
		.er {
			DiagramERDiagram{
				entities: mermaid_entities_to_diagram(diagram.entities)
				relations: mermaid_entity_relations_to_diagram(diagram.entity_relations)
			}
		}
		.gantt {
			DiagramGantt{
				title: diagram.title
				sections: mermaid_gantt_to_diagram(diagram.gantt_sections)
			}
		}
	}
}

fn mermaid_sequence_to_diagram(events []MermaidSequenceEvent) []DiagramSequenceEvent {
	mut out := []DiagramSequenceEvent{}
	for event in events {
		match event {
			MermaidSequenceMessage {
				out << DiagramSequenceMessage{
					from: event.from
					to: event.to
					text: event.text
					kind: match event.kind {
						.arrow { .arrow }
						.line { .line }
					}
				}
			}
			MermaidSequenceNote {
				out << DiagramSequenceNote{
					participant: event.participant
					text: event.text
					side: match event.side {
						.left { .left }
						.right { .right }
					}
				}
			}
			MermaidSequenceActivation {
				out << DiagramSequenceActivation{
					participant: event.participant
					active: event.active
				}
			}
			MermaidSequenceBlockBoundary {
				out << DiagramSequenceBlockBoundary{
					kind: match event.kind {
						.alt { .alt }
						.else_branch { .else_branch }
						.opt { .opt }
						.loop { .loop }
						.par { .par }
					}
					label: event.label
					start: event.start
				}
			}
		}
	}
	return out
}

fn mermaid_flow_to_diagram(edges []MermaidEdge) []DiagramEdge {
	return edges.map(DiagramEdge{
		from: it.from
		to: it.to
		kind: match it.kind {
			.arrow { .arrow }
			.line { .line }
		}
		label: it.label
	})
}

fn mermaid_direction_to_diagram(direction MermaidDirection) DiagramDirection {
	return match direction {
		.left_right { .left_right }
		.top_down { .top_down }
	}
}

fn mermaid_nodes_to_diagram(nodes []MermaidNode) []DiagramNode {
	return nodes.map(DiagramNode{
		id: it.id
		label: it.label
		shape: match it.shape {
			.round { .round }
			.diamond { .diamond }
			.box { .box }
		}
		group: it.subgraph
	})
}

fn mermaid_subgraphs_to_diagram(subgraphs []MermaidSubgraph) []DiagramGroup {
	return subgraphs.map(DiagramGroup{
		id: it.id
		title: it.title
		node_ids: it.node_ids.clone()
	})
}

fn mermaid_mindmap_to_diagram(node MermaidMindmapNode) DiagramTreeNode {
	return DiagramTreeNode{
		label: node.label
		children: node.children.map(mermaid_mindmap_to_diagram(it))
	}
}

fn mermaid_timeline_to_diagram(entries []MermaidTimelineEntry) []DiagramTimelineEntry {
	mut out := []DiagramTimelineEntry{}
	for entry in entries {
		for event in entry.events {
			out << DiagramTimelineEntry{
				point: entry.point
				text: event
			}
		}
	}
	return out
}

fn mermaid_state_to_diagram(transitions []MermaidStateTransition) []DiagramStateTransition {
	return transitions.map(DiagramStateTransition{
		from: it.from
		to: it.to
		label: it.label
	})
}

fn mermaid_journey_to_diagram(sections []MermaidJourneySection) []DiagramJourneySection {
	mut out := []DiagramJourneySection{}
	for section in sections {
		mut steps := []DiagramJourneyStep{}
		for step in section.steps {
			steps << DiagramJourneyStep{
				title: step.title
				score: step.score
				actors: step.actors.clone()
			}
		}
		out << DiagramJourneySection{
			title: section.title
			steps: steps
		}
	}
	return out
}

fn mermaid_git_to_diagram(events []MermaidGitEvent) []DiagramGitEvent {
	return events.map(DiagramGitEvent{
		kind: match it.kind {
			.commit { .commit }
			.branch { .branch }
			.checkout { .checkout }
			.merge { .merge }
		}
		name: it.name
		target: it.target
	})
}

fn mermaid_class_to_diagram(classes []MermaidClass) []DiagramClass {
	return classes.map(DiagramClass{
		name: it.name
		members: it.members.clone()
	})
}

fn mermaid_class_relations_to_diagram(relations []MermaidClassRelation) []DiagramClassRelation {
	return relations.map(DiagramClassRelation{
		left: it.left
		right: it.right
		kind: it.kind
		label: it.label
	})
}

fn mermaid_entities_to_diagram(entities []MermaidEntity) []DiagramEntity {
	return entities.map(DiagramEntity{
		name: it.name
		attributes: it.attributes.clone()
	})
}

fn mermaid_entity_relations_to_diagram(relations []MermaidEntityRelation) []DiagramEntityRelation {
	return relations.map(DiagramEntityRelation{
		left: it.left
		right: it.right
		left_card: it.left_card
		right_card: it.right_card
		label: it.label
	})
}

fn mermaid_gantt_to_diagram(sections []MermaidGanttSection) []DiagramGanttSection {
	return sections.map(DiagramGanttSection{
		title: it.title
		tasks: it.tasks.map(DiagramGanttTask{
			title: it.title
			state: it.state
			metadata: it.metadata.clone()
		})
	})
}
