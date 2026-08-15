module vmarkdown

fn test_mermaid_timeline_to_diagram_payload() {
	diagram := parse_mermaid('timeline
title Product History
2024 : Parser
     : Preview
') or {
		assert false
		return
	}
	payload := diagram.to_diagram_payload() or {
		assert false
		return
	}
	match payload {
		DiagramTimeline {
			assert payload.entries.len == 2
			assert payload.entries[0].point == '2024'
			assert payload.entries[0].text == 'Parser'
			assert payload.entries[1].text == 'Preview'
		}
		else {
			assert false
		}
	}
}

fn test_mermaid_sequence_to_diagram_payload() {
	diagram := parse_mermaid('sequenceDiagram
participant Alice
participant Bob
activate Bob
Note right of Bob: working
Bob->>Alice: done
deactivate Bob
') or {
		assert false
		return
	}
	payload := diagram.to_diagram_payload() or {
		assert false
		return
	}
	match payload {
		DiagramSequence {
			assert payload.participants == ['Alice', 'Bob']
			assert payload.events.len == 4
			assert payload.events[0] is DiagramSequenceActivation
			assert payload.events[1] is DiagramSequenceNote
			assert payload.events[2] is DiagramSequenceMessage
			assert payload.events[3] is DiagramSequenceActivation
		}
		else {
			assert false
		}
	}
}

fn test_mermaid_mindmap_to_diagram_payload() {
	diagram := parse_mermaid('mindmap
root
  parser
  preview
') or {
		assert false
		return
	}
	payload := diagram.to_diagram_payload() or {
		assert false
		return
	}
	match payload {
		DiagramTree {
			assert payload.root.label == 'root'
			assert payload.root.children.len == 2
			assert payload.root.children[0].label == 'parser'
		}
		else {
			assert false
		}
	}
}

fn test_mermaid_flowchart_to_diagram_payload() {
	diagram := parse_mermaid('flowchart LR
subgraph Core
A[Start] -->|ok| B(Parse)
end
B --> C{Render}
') or {
		assert false
		return
	}
	payload := diagram.to_diagram_payload() or {
		assert false
		return
	}
	match payload {
		DiagramGraph {
			assert payload.kind == .flow
			assert payload.direction == .left_right
			assert payload.nodes.len >= 3
			assert payload.edges.len == 2
			assert payload.edges[0].from == 'A'
			assert payload.edges[0].to == 'B'
			assert payload.edges[0].label == 'ok'
			assert payload.edges[0].kind == .arrow
			assert payload.edges[1].to == 'C'
			assert payload.nodes[0].label == 'Start'
			assert payload.nodes[0].group == 'Core'
			assert payload.nodes[1].shape == .round
			assert payload.nodes[2].shape == .diamond
			assert payload.groups.len == 1
			assert payload.groups[0].title == 'Core'
		}
		else {
			assert false
		}
	}
}

fn test_mermaid_journey_to_diagram_payload() {
	diagram := parse_mermaid('journey
title Checkout
section Buyer
Search: 3: Alice
Pay: 5: Alice, Bob
') or {
		assert false
		return
	}
	payload := diagram.to_diagram_payload() or {
		assert false
		return
	}
	match payload {
		DiagramJourney {
			assert payload.title == 'Checkout'
			assert payload.sections.len == 1
			assert payload.sections[0].title == 'Buyer'
			assert payload.sections[0].steps.len == 2
			assert payload.sections[0].steps[1].score == 5
		}
		else {
			assert false
		}
	}
}

fn test_mermaid_git_graph_to_diagram_payload() {
	diagram := parse_mermaid('gitGraph
commit id: "c1"
branch feat
checkout feat
commit id: "c2"
') or {
		assert false
		return
	}
	payload := diagram.to_diagram_payload() or {
		assert false
		return
	}
	match payload {
		DiagramGitGraph {
			assert payload.events.len >= 3
			assert payload.events[0].kind == .commit
			assert payload.events[1].kind == .branch
		}
		else {
			assert false
		}
	}
}

fn test_mermaid_class_to_diagram_payload() {
	diagram := parse_mermaid('classDiagram
class Animal {
+name string
+speak()
}
Animal <|-- Dog : inherits
') or {
		assert false
		return
	}
	payload := diagram.to_diagram_payload() or {
		assert false
		return
	}
	match payload {
		DiagramClassDiagram {
			assert payload.classes.len >= 1
			assert payload.classes[0].name == 'Animal'
			assert payload.relations.len == 1
			assert payload.relations[0].kind == '<|--'
			assert payload.relations[0].label == 'inherits'
		}
		else {
			assert false
		}
	}
}

fn test_mermaid_er_to_diagram_payload() {
	diagram := parse_mermaid('erDiagram
USER {
string id
}
ORDER {
string id
}
USER ||--o{ ORDER : places
') or {
		assert false
		return
	}
	payload := diagram.to_diagram_payload() or {
		assert false
		return
	}
	match payload {
		DiagramERDiagram {
			assert payload.entities.len == 2
			assert payload.relations.len == 1
			assert payload.relations[0].left_card == '||'
			assert payload.relations[0].right_card == 'o{'
			assert payload.relations[0].label == 'places'
		}
		else {
			assert false
		}
	}
}

fn test_mermaid_gantt_to_diagram_payload() {
	diagram := parse_mermaid('gantt
title Release Plan
section Build
Compile :done, a1, 2026-04-01, 1d
Ship :active, after a1, 2d
') or {
		assert false
		return
	}
	payload := diagram.to_diagram_payload() or {
		assert false
		return
	}
	match payload {
		DiagramGantt {
			assert payload.title == 'Release Plan'
			assert payload.sections.len == 1
			assert payload.sections[0].tasks.len == 2
			assert payload.sections[0].tasks[0].state == 'done'
			assert payload.sections[0].tasks[1].metadata[0] == 'after a1'
		}
		else {
			assert false
		}
	}
}

fn test_render_flow_diagram_payload_uses_direction_and_labels() {
	payload := DiagramGraph{
		kind:      .flow
		direction: .left_right
		nodes:     [
			DiagramNode{
				id:    'A'
				label: 'Start'
				shape: .box
			},
			DiagramNode{
				id:    'B'
				label: 'Go'
				shape: .round
			},
		]
		edges:     [
			DiagramEdge{
				from:  'A'
				to:    'B'
				kind:  .arrow
				label: 'ok'
			},
		]
	}
	rendered := render_diagram_payload(payload, 80)
	assert rendered.contains('[Start]')
	assert rendered.contains('(Go)')
	assert rendered.contains('ok')
}

fn test_render_sequence_diagram_payload() {
	payload := DiagramSequence{
		participants: ['Alice', 'Bob']
		events:       [
			DiagramSequenceBlockBoundary{
				kind:  .alt
				label: 'success'
				start: true
			},
			DiagramSequenceMessage{
				from: 'Alice'
				to:   'Bob'
				text: 'ok'
				kind: .arrow
			},
			DiagramSequenceBlockBoundary{
				kind:  .else_branch
				label: 'miss'
				start: true
			},
			DiagramSequenceMessage{
				from: 'Bob'
				to:   'Bob'
				text: 'cache'
				kind: .arrow
			},
			DiagramSequenceBlockBoundary{
				kind:  .alt
				label: ''
				start: false
			},
		]
	}
	rendered := render_diagram_payload(payload, 96)
	assert rendered.contains('Alice')
	assert rendered.contains('Bob')
	assert rendered.contains('alt success')
	assert rendered.contains('else miss')
	assert rendered.contains('╭─↺ cache')
}

fn test_render_class_diagram_payload() {
	payload := DiagramClassDiagram{
		classes:   [
			DiagramClass{
				name:    'Animal'
				members: ['+name string', '+speak()']
			},
			DiagramClass{
				name: 'Dog'
			},
		]
		relations: [
			DiagramClassRelation{
				left:  'Animal'
				right: 'Dog'
				kind:  '<|--'
				label: 'inherits'
			},
		]
	}
	rendered := render_diagram_payload(payload, 80)
	assert rendered.contains('Animal')
	assert rendered.contains('Dog')
	assert rendered.contains('inherits')
}

fn test_render_er_diagram_payload() {
	payload := DiagramERDiagram{
		entities:  [
			DiagramEntity{
				name:       'USER'
				attributes: ['string id']
			},
			DiagramEntity{
				name:       'ORDER'
				attributes: ['string id']
			},
		]
		relations: [
			DiagramEntityRelation{
				left:       'USER'
				right:      'ORDER'
				left_card:  '||'
				right_card: 'o{'
				label:      'places'
			},
		]
	}
	rendered := render_diagram_payload(payload, 80)
	assert rendered.contains('USER')
	assert rendered.contains('ORDER')
	assert rendered.contains('places')
}

fn test_render_gantt_diagram_payload() {
	payload := DiagramGantt{
		title:    'Release Plan'
		sections: [
			DiagramGanttSection{
				title: 'Build'
				tasks: [
					DiagramGanttTask{
						title:    'Compile'
						state:    'done'
						metadata: ['a1', '1d']
					},
				]
			},
		]
	}
	rendered := render_diagram_payload(payload, 80)
	assert rendered.contains('Release Plan')
	assert rendered.contains('Compile')
	assert rendered.contains('█████')
}
