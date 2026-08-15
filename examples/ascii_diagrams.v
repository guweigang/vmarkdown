module main

import vmarkdown

fn main() {
	tree := vmarkdown.render_ascii_tree(vmarkdown.AsciiTreeNode{
		label:    'vmarkdown'
		children: [
			vmarkdown.AsciiTreeNode{
				label: 'parser'
			},
			vmarkdown.AsciiTreeNode{
				label:    'preview'
				children: [
					vmarkdown.AsciiTreeNode{
						label: 'search'
					},
				]
			},
		]
	}, 80)
	deps := vmarkdown.render_ascii_dependency_graph([
		vmarkdown.AsciiGraphEdge{ from: 'root', to: 'preview' },
		vmarkdown.AsciiGraphEdge{ from: 'root', to: 'lexer' },
		vmarkdown.AsciiGraphEdge{ from: 'preview', to: 'parser' },
		vmarkdown.AsciiGraphEdge{ from: 'lexer', to: 'parser' },
		vmarkdown.AsciiGraphEdge{ from: 'parser', to: 'renderer' },
	], 80)
	org := vmarkdown.render_ascii_org_chart(vmarkdown.AsciiOrgNode{
		name:    'Guwei'
		title:   'Founder'
		reports: [
			vmarkdown.AsciiOrgNode{
				name:    'Parser Team'
				title:   'Core'
				reports: [
					vmarkdown.AsciiOrgNode{
						name:  'Lexer Squad'
						title: 'Infra'
					},
				]
			},
			vmarkdown.AsciiOrgNode{
				name:  'Preview Team'
				title: 'UI'
			},
		]
	}, 96)
	timeline := vmarkdown.render_ascii_timeline([
		vmarkdown.AsciiTimelineEntry{ point: '2024', text: 'Parser' },
		vmarkdown.AsciiTimelineEntry{ point: '2024', text: 'Preview' },
		vmarkdown.AsciiTimelineEntry{ point: '2025', text: 'Preview' },
		vmarkdown.AsciiTimelineEntry{ point: '2026', text: 'Mermaid + ASCII layout' },
	], 80)
	pipeline := vmarkdown.render_ascii_pipeline([
		vmarkdown.AsciiPipelineStage{ name: 'Parse', status: 'done' },
		vmarkdown.AsciiPipelineStage{ name: 'Render', status: 'active' },
		vmarkdown.AsciiPipelineStage{ name: 'Ship', status: 'pending' },
	], 80)
	state_machine := vmarkdown.render_ascii_state_machine([
		vmarkdown.AsciiStateTransition{ from: 'Idle', to: 'Running', label: 'start' },
		vmarkdown.AsciiStateTransition{ from: 'Running', to: 'Done', label: 'finish' },
	], 80)

	println('ASCII Diagram Demo')
	println('──────────────────')
	println('')
	println(tree)
	println('')
	println(deps)
	println('')
	println(org)
	println('')
	println(timeline)
	println('')
	println(pipeline)
	println('')
	println(state_machine)
}
