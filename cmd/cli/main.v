module main

import os
import vmarkdown

fn main() {
	args := os.args
	if args.len < 2 {
		println(usage())
		return
	}
	match args[1] {
		'preview' {
			if args.len < 3 {
				eprintln('preview requires a markdown file path')
				exit(1)
			}
			vmarkdown.preview_file(args[2]) or {
				eprintln(err)
				exit(1)
			}
		}
		'terminal' {
			if args.len < 3 {
				eprintln('terminal requires a markdown file path')
				exit(1)
			}
			markdown := os.read_file(args[2]) or {
				eprintln(err)
				exit(1)
			}
			output := vmarkdown.render_terminal(markdown) or {
				eprintln(err)
				exit(1)
			}
			println(output)
		}
		'markdown' {
			if args.len < 3 {
				eprintln('markdown requires a markdown file path')
				exit(1)
			}
			markdown := os.read_file(args[2]) or {
				eprintln(err)
				exit(1)
			}
			output := vmarkdown.render_markdown(markdown) or {
				eprintln(err)
				exit(1)
			}
			println(output)
		}
		'html' {
			if args.len < 3 {
				eprintln('html requires a markdown file path')
				exit(1)
			}
			markdown := os.read_file(args[2]) or {
				eprintln(err)
				exit(1)
			}
			output := vmarkdown.render_html(markdown) or {
				eprintln(err)
				exit(1)
			}
			println(output)
		}
		'ast' {
			if args.len < 3 {
				eprintln('ast requires a markdown file path')
				exit(1)
			}
			markdown := os.read_file(args[2]) or {
				eprintln(err)
				exit(1)
			}
			doc := vmarkdown.parse(markdown) or {
				eprintln(err)
				exit(1)
			}
			println(doc.pretty())
		}
		'mermaid' {
			if args.len < 3 {
				eprintln('mermaid requires a .mmd file path or `diff before.mmd after.mmd`')
				exit(1)
			}
			if args[2] == 'diff' {
				if args.len < 5 {
					eprintln('mermaid diff requires before.mmd and after.mmd')
					exit(1)
				}
				summary := vmarkdown.diff_mermaid_files_summary(args[3], args[4]) or {
					eprintln(err)
					exit(1)
				}
				println(summary.lines.join('\n'))
				return
			}
			if args[2] == 'diff-preview' {
				if args.len < 5 {
					eprintln('mermaid diff-preview requires before.mmd and after.mmd')
					exit(1)
				}
				summary := vmarkdown.diff_mermaid_files_summary(args[3], args[4]) or {
					eprintln(err)
					exit(1)
				}
				vmarkdown.preview_diff_lines('mermaid diff', summary.lines) or {
					eprintln(err)
					exit(1)
				}
				return
			}
			input := os.read_file(args[2]) or {
				eprintln(err)
				exit(1)
			}
			width := width_arg(args[3..], 80)
			output := vmarkdown.render_mermaid_ascii(input, width) or {
				eprintln(err)
				exit(1)
			}
			println(output)
		}
		'mermaid-preview' {
			if args.len < 3 {
				eprintln('mermaid-preview requires a .mmd file path')
				exit(1)
			}
			vmarkdown.preview_mermaid_file(args[2]) or {
				eprintln(err)
				exit(1)
			}
		}
		'mermaid-diff' {
			if args.len < 4 {
				eprintln('mermaid-diff requires before.mmd and after.mmd')
				exit(1)
			}
			summary := vmarkdown.diff_mermaid_files_summary(args[2], args[3]) or {
				eprintln(err)
				exit(1)
			}
			println(summary.lines.join('\n'))
		}
		'diagrams-demo' {
			println(build_diagrams_demo())
		}
		'diagram' {
			if args.len < 3 {
				eprintln('diagram requires a kind: tree|dependency|call|org|timeline|pipeline|state|schema|validate|preview|diff')
				exit(1)
			}
			if args[2] == 'schema' {
				if args.len < 4 {
					eprintln('diagram schema requires a kind: all|tree|dependency|call|org|timeline|pipeline|state')
					exit(1)
				}
				println(vmarkdown.diagram_schema(args[3]))
				return
			}
			if args[2] == 'validate' {
				if args.len < 5 {
					eprintln('diagram validate requires a kind and input path')
					exit(1)
				}
				println(vmarkdown.validate_diagram_json(args[3], args[4]) or {
					eprintln(err)
					exit(1)
				})
				return
			}
			if args[2] == 'preview' {
				if args.len < 4 {
					eprintln('diagram preview requires a kind')
					exit(1)
				}
				width := width_arg(args[4..], 80)
				input_path := diagram_input_path(args[4..]) or { '' }
				title := '${args[3]} diagram'
				if input_path.len > 0 {
					payload := vmarkdown.load_diagram_json(args[3], input_path) or {
						eprintln(err)
						exit(1)
					}
					vmarkdown.preview_diagram_payload(title, payload, width) or {
						eprintln(err)
						exit(1)
					}
				} else {
					vmarkdown.preview_diagram_rendered(title, build_diagram_sample(args[3], width)) or {
						eprintln(err)
						exit(1)
					}
				}
				return
			}
			if args[2] == 'diff' {
				if args.len < 6 {
					eprintln('diagram diff requires a kind, before.json, and after.json')
					exit(1)
				}
				summary := vmarkdown.diff_diagram_json_summary(args[3], args[4], args[5]) or {
					eprintln(err)
					exit(1)
				}
				println(summary.lines.join('\n'))
				return
			}
			if args[2] == 'diff-preview' {
				if args.len < 6 {
					eprintln('diagram diff-preview requires a kind, before.json, and after.json')
					exit(1)
				}
				summary := vmarkdown.diff_diagram_json_summary(args[3], args[4], args[5]) or {
					eprintln(err)
					exit(1)
				}
				vmarkdown.preview_diff_lines('${args[3]} diff', summary.lines) or {
					eprintln(err)
					exit(1)
				}
				return
			}
			width := width_arg(args[3..], 80)
			input_path := diagram_input_path(args[3..]) or { '' }
			if input_path.len > 0 {
				output := vmarkdown.render_diagram_json(args[2], input_path, width) or {
					eprintln(err)
					exit(1)
				}
				println(output)
			} else {
				println(build_diagram_sample(args[2], width))
			}
		}
		else {
			println(usage())
		}
	}
}

fn usage() string {
	return 'vmarkdown commands:
  v run cmd/cli preview <file.md>
  v run cmd/cli terminal <file.md>
  v run cmd/cli markdown <file.md>
  v run cmd/cli html <file.md>
  v run cmd/cli ast <file.md>
  v run cmd/cli mermaid <file.mmd> [--width N]
  v run cmd/cli mermaid diff <before.mmd> <after.mmd>
  v run cmd/cli mermaid diff-preview <before.mmd> <after.mmd>
  v run cmd/cli mermaid-preview <file.mmd>
  v run cmd/cli mermaid-diff <before.mmd> <after.mmd>
  v run cmd/cli diagrams-demo
  v run cmd/cli diagram <tree|dependency|call|org|timeline|pipeline|state> [input.json] [--width N]
  v run cmd/cli diagram preview <tree|dependency|call|org|timeline|pipeline|state> [input.json] [--width N]
  v run cmd/cli diagram diff <tree|dependency|call|org|timeline|pipeline|state> <before.json> <after.json>
  v run cmd/cli diagram diff-preview <tree|dependency|call|org|timeline|pipeline|state> <before.json> <after.json>
  v run cmd/cli diagram schema <all|tree|dependency|call|org|timeline|pipeline|state>
  v run cmd/cli diagram validate <tree|dependency|call|org|timeline|pipeline|state> <input.json>'
}

fn build_diagrams_demo() string {
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
	return [
		'ASCII Diagram Demo',
		'──────────────────',
		'',
		tree,
		'',
		deps,
		'',
		org,
		'',
		timeline,
		'',
		pipeline,
		'',
		state_machine,
	].join('\n')
}

fn build_diagram_sample(kind string, width int) string {
	safe_width := if width > 0 { width } else { 80 }
	return match kind {
		'tree' { sample_tree(safe_width) }
		'dependency' { sample_dependency_graph(safe_width) }
		'call' { sample_call_graph(safe_width) }
		'org' { sample_org_chart(org_width(safe_width)) }
		'timeline' { sample_timeline(safe_width) }
		'pipeline' { sample_pipeline(safe_width) }
		'state' { sample_state_machine(safe_width) }
		else { 'unknown diagram kind: ${kind}' }
	}
}

fn sample_tree(width int) string {
	return vmarkdown.render_ascii_tree(vmarkdown.AsciiTreeNode{
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
	}, width)
}

fn sample_dependency_graph(width int) string {
	return vmarkdown.render_ascii_dependency_graph([
		vmarkdown.AsciiGraphEdge{ from: 'root', to: 'preview' },
		vmarkdown.AsciiGraphEdge{ from: 'root', to: 'lexer' },
		vmarkdown.AsciiGraphEdge{ from: 'preview', to: 'parser' },
		vmarkdown.AsciiGraphEdge{ from: 'lexer', to: 'parser' },
		vmarkdown.AsciiGraphEdge{ from: 'parser', to: 'renderer' },
	], width)
}

fn sample_call_graph(width int) string {
	return vmarkdown.render_ascii_call_graph([
		vmarkdown.AsciiGraphEdge{ from: 'main', to: 'parse' },
		vmarkdown.AsciiGraphEdge{ from: 'main', to: 'render' },
	], width)
}

fn sample_org_chart(width int) string {
	return vmarkdown.render_ascii_org_chart(vmarkdown.AsciiOrgNode{
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
	}, org_width(width))
}

fn sample_timeline(width int) string {
	return vmarkdown.render_ascii_timeline([
		vmarkdown.AsciiTimelineEntry{ point: '2024', text: 'Parser' },
		vmarkdown.AsciiTimelineEntry{ point: '2024', text: 'Preview' },
		vmarkdown.AsciiTimelineEntry{ point: '2025', text: 'Preview' },
		vmarkdown.AsciiTimelineEntry{ point: '2026', text: 'Mermaid + ASCII layout' },
	], width)
}

fn sample_pipeline(width int) string {
	return vmarkdown.render_ascii_pipeline([
		vmarkdown.AsciiPipelineStage{ name: 'Parse', status: 'done' },
		vmarkdown.AsciiPipelineStage{ name: 'Render', status: 'active' },
		vmarkdown.AsciiPipelineStage{ name: 'Ship', status: 'pending' },
	], width)
}

fn sample_state_machine(width int) string {
	return vmarkdown.render_ascii_state_machine([
		vmarkdown.AsciiStateTransition{ from: 'Idle', to: 'Running', label: 'start' },
		vmarkdown.AsciiStateTransition{ from: 'Running', to: 'Done', label: 'finish' },
	], width)
}

fn org_width(width int) int {
	return if width < 40 { 40 } else { width }
}

fn width_arg(args []string, fallback int) int {
	for i, arg in args {
		if arg == '--width' && i + 1 < args.len {
			return args[i + 1].int()
		}
	}
	return fallback
}

fn diagram_input_path(args []string) !string {
	for i, arg in args {
		if arg == '--width' {
			if i + 1 < args.len {
				continue
			}
			break
		}
		if i > 0 && args[i - 1] == '--width' {
			continue
		}
		if !arg.starts_with('--') {
			return arg
		}
	}
	return error('no input path')
}
