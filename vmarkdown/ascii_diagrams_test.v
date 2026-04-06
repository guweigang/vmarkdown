module vmarkdown

fn test_render_ascii_tree() {
	out := render_ascii_tree(AsciiTreeNode{
		label: 'Root'
		children: [
			AsciiTreeNode{
				label: 'Parser'
			},
			AsciiTreeNode{
				label: 'Preview'
				children: [
					AsciiTreeNode{
						label: 'Search'
					},
				]
			},
		]
	}, 80)
	assert out.contains('◉ Root')
	assert out.contains('Parser')
	assert out.contains('Preview')
	assert out.contains('Search')
}

fn test_render_ascii_dependency_graph() {
	out := render_ascii_dependency_graph([
		AsciiGraphEdge{from: 'api', to: 'db'},
		AsciiGraphEdge{from: 'api', to: 'cache'},
	], 80)
	assert out.contains('◈ dependency graph')
	assert out.contains('[api]')
	assert out.contains('[db]')
	assert out.contains('[cache]')
}

fn test_render_ascii_dependency_graph_merge() {
	out := render_ascii_dependency_graph([
		AsciiGraphEdge{from: 'root', to: 'parser'},
		AsciiGraphEdge{from: 'root', to: 'lexer'},
		AsciiGraphEdge{from: 'parser', to: 'ast'},
		AsciiGraphEdge{from: 'lexer', to: 'ast'},
	], 80)
	assert out.contains('[root]')
	assert out.contains('[parser]')
	assert out.contains('[lexer]')
	assert out.contains('[ast]')
	assert out.contains('┴')
}

fn test_render_ascii_dependency_graph_branch_merge_then_forward() {
	out := render_ascii_dependency_graph([
		AsciiGraphEdge{from: 'root', to: 'preview'},
		AsciiGraphEdge{from: 'root', to: 'lexer'},
		AsciiGraphEdge{from: 'preview', to: 'parser'},
		AsciiGraphEdge{from: 'lexer', to: 'parser'},
		AsciiGraphEdge{from: 'parser', to: 'renderer'},
	], 96)
	assert out.contains('[root]')
	assert out.contains('[preview]')
	assert out.contains('[lexer]')
	assert out.contains('[parser] ─▶ [renderer]')
}

fn test_render_ascii_call_graph() {
	out := render_ascii_call_graph([
		AsciiGraphEdge{from: 'main', to: 'parse'},
		AsciiGraphEdge{from: 'main', to: 'render'},
	], 80)
	assert out.contains('◈ call graph')
	assert out.contains('[main]')
	assert out.contains('[parse]')
	assert out.contains('[render]')
}

fn test_render_ascii_org_chart() {
	out := render_ascii_org_chart(AsciiOrgNode{
		name: 'Guwei'
		title: 'Founder'
		reports: [
			AsciiOrgNode{
				name: 'Parser Team'
				title: 'Core'
				reports: [
					AsciiOrgNode{
						name: 'Lexer Squad'
						title: 'Infra'
					},
				]
			},
			AsciiOrgNode{
				name: 'Preview Team'
				title: 'UI'
			},
		]
	}, 96)
	assert out.contains('Guwei')
	assert out.contains('Founder')
	assert out.contains('Parser Team')
	assert out.contains('Preview Team')
	assert out.contains('Lexer Squad')
	assert out.contains('┬')
	assert out.contains('┴')
}

fn test_render_ascii_timeline() {
	out := render_ascii_timeline([
		AsciiTimelineEntry{point: '2024', text: 'Parser'},
		AsciiTimelineEntry{point: '2024', text: 'Preview'},
		AsciiTimelineEntry{point: '2025', text: 'Preview'},
	], 80)
	assert out.contains('2024')
	assert out.contains('Parser')
	assert out.contains('2025')
	assert out.contains('Preview')
	assert out.contains('│ ') || out.contains('└─')
}

fn test_render_ascii_pipeline() {
	out := render_ascii_pipeline([
		AsciiPipelineStage{name: 'Parse', status: 'done'},
		AsciiPipelineStage{name: 'Render', status: 'active'},
		AsciiPipelineStage{name: 'Ship', status: 'pending'},
	], 80)
	assert out.contains('[✓ Parse]')
	assert out.contains('[▸ Render]')
	assert out.contains('[· Ship]')
	assert out.contains('─▶')
}

fn test_render_ascii_state_machine() {
	out := render_ascii_state_machine([
		AsciiStateTransition{from: 'Idle', to: 'Running', label: 'start'},
		AsciiStateTransition{from: 'Running', to: 'Done', label: 'finish'},
	], 80)
	assert out.contains('[Idle] ─▶ [Running]')
	assert out.contains('· start')
	assert out.contains('[Running] ─▶ [Done]')
}
