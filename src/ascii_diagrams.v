module vmarkdown

pub struct AsciiGraphEdge {
pub:
	from string
	to   string
}

pub fn render_ascii_dependency_graph(edges []AsciiGraphEdge, width int) string {
	return render_ascii_grouped_graph(edges, width, 'dependency graph')
}

pub fn render_ascii_call_graph(edges []AsciiGraphEdge, width int) string {
	return render_ascii_grouped_graph(edges, width, 'call graph')
}

pub fn render_ascii_flow_graph(graph DiagramGraph, width int) string {
	if graph.edges.len == 0 {
		return ''
	}
	if grouped := render_ascii_grouped_flow_graph(graph, width) {
		return grouped
	}
	labels := flow_node_label_map(graph.nodes)
	shapes := flow_node_shape_map(graph.nodes)
	if graph.direction == .top_down {
		return render_ascii_flow_graph_td(graph, labels, shapes, width)
	}
	return render_ascii_flow_graph_lr(graph, labels, shapes, width)
}

fn render_ascii_grouped_flow_graph(graph DiagramGraph, width int) ?string {
	if graph.groups.len != 1 || graph.nodes.len == 0 {
		return none
	}
	group := graph.groups[0]
	grouped_ids := group.node_ids.clone()
	mut group_nodes := []DiagramNode{}
	mut outside_nodes := []DiagramNode{}
	for node in graph.nodes {
		if node.id in grouped_ids {
			group_nodes << DiagramNode{
				id:    node.id
				label: node.label
				shape: node.shape
				group: ''
			}
		} else {
			outside_nodes << DiagramNode{
				id:    node.id
				label: node.label
				shape: node.shape
				group: ''
			}
		}
	}
	if group_nodes.len == 0 {
		return none
	}
	mut inside_edges := []DiagramEdge{}
	mut outside_edges := []DiagramEdge{}
	mut crossing_edges := []DiagramEdge{}
	for edge in graph.edges {
		from_in_group := edge.from in grouped_ids
		to_in_group := edge.to in grouped_ids
		if from_in_group && to_in_group {
			inside_edges << edge
		} else if !from_in_group && !to_in_group {
			outside_edges << edge
		} else {
			crossing_edges << edge
		}
	}
	group_body := render_flow_graph_component(DiagramGraph{
		kind:      graph.kind
		direction: graph.direction
		nodes:     group_nodes
		edges:     inside_edges
		groups:    []DiagramGroup{}
	}, width - 4)
	framed_group := ascii_titled_frame(group.title, group_body, width)
	if outside_nodes.len == 0 {
		return framed_group
	}
	if crossing_edges.len == 1 {
		crossing := crossing_edges[0]
		outside_body := if outside_edges.len == 0 && outside_nodes.len == 1 {
			flow_node_inline(outside_nodes[0].id, flow_node_label_map(outside_nodes),
				flow_node_shape_map(outside_nodes))
		} else {
			render_flow_graph_component(DiagramGraph{
				kind:      graph.kind
				direction: graph.direction
				nodes:     outside_nodes.clone()
				edges:     outside_edges.clone()
				groups:    []DiagramGroup{}
			}, width)
		}
		if outside_body.split_into_lines().len != 1 {
			return none
		}
		from_in_group := crossing.from in grouped_ids
		relation := if crossing.kind == .arrow { '──▶' } else { '───' }
		return if from_in_group {
			ascii_dual_relation(framed_group, outside_body, relation, AsciiRelationOptions{
				gap:          max_int(display_width(relation) + display_width(crossing.label) + 4,
					10)
				width:        width
				label:        crossing.label
				align_in_gap: true
				align_y:      'middle'
			})
		} else {
			ascii_dual_relation(outside_body, framed_group, relation, AsciiRelationOptions{
				gap:          max_int(display_width(relation) + display_width(crossing.label) + 4,
					10)
				width:        width
				label:        crossing.label
				align_in_gap: true
				align_y:      'middle'
			})
		}
	}
	if crossing_edges.len == 2 {
		mut incoming := DiagramEdge{}
		mut outgoing := DiagramEdge{}
		mut has_incoming := false
		mut has_outgoing := false
		mut incoming_edges := []DiagramEdge{}
		mut outgoing_edges := []DiagramEdge{}
		for edge in crossing_edges {
			from_in_group := edge.from in grouped_ids
			to_in_group := edge.to in grouped_ids
			if !from_in_group && to_in_group {
				incoming = edge
				has_incoming = true
				incoming_edges << edge
			}
			if from_in_group && !to_in_group {
				outgoing = edge
				has_outgoing = true
				outgoing_edges << edge
			}
		}
		if has_incoming && has_outgoing {
			left_nodes, left_edges := extract_outside_flow_component(outside_nodes, outside_edges,
				incoming.from, true)
			right_nodes, right_edges := extract_outside_flow_component(outside_nodes,
				outside_edges, outgoing.to, false)
			if left_nodes.len > 0 && right_nodes.len > 0
				&& left_edges.len + right_edges.len == outside_edges.len {
				left_body := render_flow_graph_component(DiagramGraph{
					kind:      graph.kind
					direction: graph.direction
					nodes:     left_nodes
					edges:     left_edges
					groups:    []DiagramGroup{}
				}, width)
				right_body := render_flow_graph_component(DiagramGraph{
					kind:      graph.kind
					direction: graph.direction
					nodes:     right_nodes
					edges:     right_edges
					groups:    []DiagramGroup{}
				}, width)
				if left_body.split_into_lines().len == 1 && right_body.split_into_lines().len == 1 {
					left_relation := if incoming.kind == .arrow { '──▶' } else { '───' }
					right_relation := if outgoing.kind == .arrow { '──▶' } else { '───' }
					return ascii_triple_relation(left_body, framed_group, right_body,
						left_relation, right_relation, AsciiTripleRelationOptions{
						left_gap:    max_int(display_width(left_relation) +
							display_width(incoming.label) + 4, 8)
						right_gap:   max_int(display_width(right_relation) +
							display_width(outgoing.label) + 4, 8)
						width:       width
						left_label:  incoming.label
						right_label: outgoing.label
						align_y:     'middle'
					})
				}
			}
		}
		if incoming_edges.len == 2 && outside_edges.len == 0 {
			if incoming_edges[0].label == incoming_edges[1].label
				&& incoming_edges[0].kind == incoming_edges[1].kind && outside_nodes.len == 2 {
				sources := incoming_edges.map(flow_node_inline(it.from,
					flow_node_label_map(outside_nodes), flow_node_shape_map(outside_nodes)))
				left_body := ascii_lr_merge_to_gap(sources, incoming_edges[0].label)
				return ascii_side_by_side_middle(left_body, framed_group, 2, width)
			}
		}
		if incoming_edges.len == 2 && outside_edges.len > 0 {
			mut source_blocks := []string{}
			mut covered_edges := 0
			for edge in incoming_edges {
				component_nodes, component_edges := extract_outside_flow_component(outside_nodes,
					outside_edges, edge.from, true)
				if component_nodes.len == 0 {
					source_blocks = []string{}
					break
				}
				source_blocks << render_flow_graph_component(DiagramGraph{
					kind:      graph.kind
					direction: graph.direction
					nodes:     component_nodes
					edges:     component_edges
					groups:    []DiagramGroup{}
				}, width)
				covered_edges += component_edges.len
			}
			if source_blocks.len == 2 && source_blocks.all(it.split_into_lines().len == 1)
				&& covered_edges == outside_edges.len
				&& incoming_edges[0].label == incoming_edges[1].label
				&& incoming_edges[0].kind == incoming_edges[1].kind {
				left_body := ascii_lr_merge_to_gap(source_blocks, incoming_edges[0].label)
				return ascii_side_by_side_middle(left_body, framed_group, 2, width)
			}
		}
		if outgoing_edges.len == 2 && outside_edges.len == 0 {
			if outgoing_edges[0].label == outgoing_edges[1].label
				&& outgoing_edges[0].kind == outgoing_edges[1].kind && outside_nodes.len == 2 {
				targets := outgoing_edges.map(flow_node_inline(it.to,
					flow_node_label_map(outside_nodes), flow_node_shape_map(outside_nodes)))
				right_body := ascii_lr_branch_from_gap(outgoing_edges[0].label, targets)
				return ascii_side_by_side_middle(framed_group, right_body, 2, width)
			}
		}
		if outgoing_edges.len == 2 && outside_edges.len > 0 {
			mut target_blocks := []string{}
			mut covered_edges := 0
			for edge in outgoing_edges {
				component_nodes, component_edges := extract_outside_flow_component(outside_nodes,
					outside_edges, edge.to, false)
				if component_nodes.len == 0 {
					target_blocks = []string{}
					break
				}
				target_blocks << render_flow_graph_component(DiagramGraph{
					kind:      graph.kind
					direction: graph.direction
					nodes:     component_nodes
					edges:     component_edges
					groups:    []DiagramGroup{}
				}, width)
				covered_edges += component_edges.len
			}
			if target_blocks.len == 2 && target_blocks.all(it.split_into_lines().len == 1)
				&& covered_edges == outside_edges.len
				&& outgoing_edges[0].label == outgoing_edges[1].label
				&& outgoing_edges[0].kind == outgoing_edges[1].kind {
				right_body := ascii_lr_branch_from_gap(outgoing_edges[0].label, target_blocks)
				return ascii_side_by_side_middle(framed_group, right_body, 2, width)
			}
		}
	}
	if crossing_edges.len == 3 {
		mut incoming_edges := []DiagramEdge{}
		mut outgoing_edges := []DiagramEdge{}
		for edge in crossing_edges {
			from_in_group := edge.from in grouped_ids
			to_in_group := edge.to in grouped_ids
			if !from_in_group && to_in_group {
				incoming_edges << edge
			}
			if from_in_group && !to_in_group {
				outgoing_edges << edge
			}
		}
		if incoming_edges.len == 2 && outgoing_edges.len == 1 {
			mut source_blocks := []string{}
			mut covered_edges := 0
			for edge in incoming_edges {
				component_nodes, component_edges := extract_outside_flow_component(outside_nodes,
					outside_edges, edge.from, true)
				if component_nodes.len == 0 {
					source_blocks = []string{}
					break
				}
				source_blocks << if graph.direction == .top_down {
					render_flow_chain_inline(component_nodes, component_edges)
				} else {
					render_flow_graph_component(DiagramGraph{
						kind:      graph.kind
						direction: graph.direction
						nodes:     component_nodes
						edges:     component_edges
						groups:    []DiagramGroup{}
					}, width)
				}
				covered_edges += component_edges.len
			}
			right_nodes, right_edges := extract_outside_flow_component(outside_nodes,
				outside_edges, outgoing_edges[0].to, false)
			if source_blocks.len == 2 && source_blocks.all(it.split_into_lines().len == 1)
				&& right_nodes.len > 0 && covered_edges + right_edges.len == outside_edges.len
				&& incoming_edges[0].label == incoming_edges[1].label
				&& incoming_edges[0].kind == incoming_edges[1].kind {
				right_body := if graph.direction == .top_down {
					render_flow_chain_inline(right_nodes, right_edges)
				} else {
					render_flow_graph_component(DiagramGraph{
						kind:      graph.kind
						direction: graph.direction
						nodes:     right_nodes
						edges:     right_edges
						groups:    []DiagramGroup{}
					}, width)
				}
				if right_body.split_into_lines().len == 1 {
					if graph.direction == .top_down {
						return render_ascii_td_group_merge_out(source_blocks,
							incoming_edges[0].label, framed_group, outgoing_edges[0].label,
							right_body, width)
					}
					left_body := ascii_lr_merge_to_gap(source_blocks, incoming_edges[0].label)
					right_relation := if outgoing_edges[0].kind == .arrow {
						'──▶'
					} else {
						'───'
					}
					return ascii_triple_relation(left_body, framed_group, right_body, '',
						right_relation, AsciiTripleRelationOptions{
						left_gap:    2
						right_gap:   max_int(display_width(right_relation) +
							display_width(outgoing_edges[0].label) + 4, 8)
						width:       width
						right_label: outgoing_edges[0].label
						align_y:     'middle'
					})
				}
			}
		}
		if incoming_edges.len == 1 && outgoing_edges.len == 2 {
			left_nodes, left_edges := extract_outside_flow_component(outside_nodes, outside_edges,
				incoming_edges[0].from, true)
			mut target_blocks := []string{}
			mut covered_edges := 0
			for edge in outgoing_edges {
				component_nodes, component_edges := extract_outside_flow_component(outside_nodes,
					outside_edges, edge.to, false)
				if component_nodes.len == 0 {
					target_blocks = []string{}
					break
				}
				target_blocks << if graph.direction == .top_down {
					render_flow_chain_inline(component_nodes, component_edges)
				} else {
					render_flow_graph_component(DiagramGraph{
						kind:      graph.kind
						direction: graph.direction
						nodes:     component_nodes
						edges:     component_edges
						groups:    []DiagramGroup{}
					}, width)
				}
				covered_edges += component_edges.len
			}
			if left_nodes.len > 0 && target_blocks.len == 2
				&& target_blocks.all(it.split_into_lines().len == 1)
				&& left_edges.len + covered_edges == outside_edges.len
				&& outgoing_edges[0].label == outgoing_edges[1].label
				&& outgoing_edges[0].kind == outgoing_edges[1].kind {
				left_body := if graph.direction == .top_down {
					render_flow_chain_inline(left_nodes, left_edges)
				} else {
					render_flow_graph_component(DiagramGraph{
						kind:      graph.kind
						direction: graph.direction
						nodes:     left_nodes
						edges:     left_edges
						groups:    []DiagramGroup{}
					}, width)
				}
				if left_body.split_into_lines().len == 1 {
					if graph.direction == .top_down {
						return render_ascii_td_group_in_branch(left_body, incoming_edges[0].label,
							framed_group, outgoing_edges[0].label, target_blocks, width)
					}
					right_body := ascii_lr_branch_from_gap(outgoing_edges[0].label, target_blocks)
					left_relation := if incoming_edges[0].kind == .arrow {
						'──▶'
					} else {
						'───'
					}
					return ascii_triple_relation(left_body, framed_group, right_body,
						left_relation, '', AsciiTripleRelationOptions{
						left_gap:   max_int(display_width(left_relation) +
							display_width(incoming_edges[0].label) + 4, 8)
						right_gap:  2
						width:      width
						left_label: incoming_edges[0].label
						align_y:    'middle'
					})
				}
			}
		}
	}
	if crossing_edges.len == 4 {
		mut incoming_edges := []DiagramEdge{}
		mut outgoing_edges := []DiagramEdge{}
		for edge in crossing_edges {
			from_in_group := edge.from in grouped_ids
			to_in_group := edge.to in grouped_ids
			if !from_in_group && to_in_group {
				incoming_edges << edge
			}
			if from_in_group && !to_in_group {
				outgoing_edges << edge
			}
		}
		if incoming_edges.len == 2 && outgoing_edges.len == 2 {
			mut source_blocks := []string{}
			mut target_blocks := []string{}
			mut covered_edges := 0
			if outside_edges.len == 0 {
				source_blocks = incoming_edges.map(flow_node_inline(it.from,
					flow_node_label_map(outside_nodes), flow_node_shape_map(outside_nodes)))
				target_blocks = outgoing_edges.map(flow_node_inline(it.to,
					flow_node_label_map(outside_nodes), flow_node_shape_map(outside_nodes)))
			} else {
				for edge in incoming_edges {
					component_nodes, component_edges := extract_outside_flow_component(outside_nodes,
						outside_edges, edge.from, true)
					if component_nodes.len == 0 {
						source_blocks = []string{}
						break
					}
					source_blocks << if graph.direction == .top_down {
						render_flow_chain_inline(component_nodes, component_edges)
					} else {
						render_flow_graph_component(DiagramGraph{
							kind:      graph.kind
							direction: graph.direction
							nodes:     component_nodes
							edges:     component_edges
							groups:    []DiagramGroup{}
						}, width)
					}
					covered_edges += component_edges.len
				}
				for edge in outgoing_edges {
					component_nodes, component_edges := extract_outside_flow_component(outside_nodes,
						outside_edges, edge.to, false)
					if component_nodes.len == 0 {
						target_blocks = []string{}
						break
					}
					target_blocks << if graph.direction == .top_down {
						render_flow_chain_inline(component_nodes, component_edges)
					} else {
						render_flow_graph_component(DiagramGraph{
							kind:      graph.kind
							direction: graph.direction
							nodes:     component_nodes
							edges:     component_edges
							groups:    []DiagramGroup{}
						}, width)
					}
					covered_edges += component_edges.len
				}
			}
			if source_blocks.len == 2 && target_blocks.len == 2
				&& source_blocks.all(it.split_into_lines().len == 1)
				&& target_blocks.all(it.split_into_lines().len == 1)
				&& covered_edges == outside_edges.len
				&& incoming_edges[0].label == incoming_edges[1].label
				&& incoming_edges[0].kind == incoming_edges[1].kind
				&& outgoing_edges[0].label == outgoing_edges[1].label
				&& outgoing_edges[0].kind == outgoing_edges[1].kind {
				if graph.direction == .top_down {
					return render_ascii_td_group_merge_branch(source_blocks,
						incoming_edges[0].label, framed_group, outgoing_edges[0].label,
						target_blocks, width)
				}
				left_body := ascii_lr_merge_to_gap(source_blocks, incoming_edges[0].label)
				right_body := ascii_lr_branch_from_gap(outgoing_edges[0].label, target_blocks)
				return ascii_triple_relation(left_body, framed_group, right_body, '', '', AsciiTripleRelationOptions{
					left_gap:  2
					right_gap: 2
					width:     width
					align_y:   'middle'
				})
			}
		}
	}
	if crossing_edges.len > 0 {
		return none
	}
	outside_body := render_flow_graph_component(DiagramGraph{
		kind:      graph.kind
		direction: graph.direction
		nodes:     outside_nodes
		edges:     outside_edges
		groups:    []DiagramGroup{}
	}, width)
	first_is_group := graph.nodes[0].id in grouped_ids
	return if first_is_group {
		framed_group + '\n\n' + outside_body
	} else {
		outside_body + '\n\n' + framed_group
	}
}

fn render_ascii_td_group_merge_branch(sources []string, incoming_label string, framed_group string, outgoing_label string, targets []string, width int) string {
	frame_width := ascii_block_width(framed_group)
	branch_block := ascii_td_branch_from_center('', targets)
	required_merge_width := max_source_display_width(sources) * 2 + 3
	total_width := min_int(max_int(max_int(required_merge_width, frame_width),
		ascii_block_width(branch_block)), width)
	center_col := centered_block_mid_column(framed_group, total_width)
	merge_block := ascii_td_merge_to_column(sources, center_col, total_width)
	mut parts := []string{}
	parts << merge_block
	parts << ' '.repeat(center_col) + '│'
	parts << axis_label_line(incoming_label, center_col, total_width)
	parts << ' '.repeat(center_col) + '│'
	parts << ascii_center_block(framed_group, total_width)
	parts << ' '.repeat(center_col) + '│'
	parts << axis_label_line(outgoing_label, center_col, total_width)
	parts << ' '.repeat(center_col) + '│'
	parts << ascii_align_block_to_column(branch_block, [`├`, `└`], center_col, total_width)
	return parts.join('\n')
}

fn render_flow_chain_inline(nodes []DiagramNode, edges []DiagramEdge) string {
	if nodes.len == 0 {
		return ''
	}
	labels := flow_node_label_map(nodes)
	shapes := flow_node_shape_map(nodes)
	mut parts := []string{}
	parts << flow_node_inline(nodes[0].id, labels, shapes)
	for i, edge in edges {
		relation := if edge.kind == .arrow { '──▶' } else { '───' }
		if edge.label.len > 0 {
			parts << '─ ' + edge.label + ' ' + relation
		} else {
			parts << relation
		}
		if i + 1 < nodes.len {
			parts << flow_node_inline(nodes[i + 1].id, labels, shapes)
		}
	}
	return parts.join(' ')
}

// TD grouped-flow helpers intentionally live together so the shared DiagramGraph
// path and Mermaid-specific fallback path can reuse the same center-axis rules.
fn render_ascii_td_group_merge_out(sources []string, incoming_label string, framed_group string, outgoing_label string, target string, width int) string {
	frame_width := ascii_block_width(framed_group)
	required_merge_width := max_source_display_width(sources) * 2 + 3
	total_width := min_int(max_int(max_int(required_merge_width, frame_width),
		display_width(target)), width)
	center_col := centered_block_mid_column(framed_group, total_width)
	merge_block := ascii_td_merge_to_column(sources, center_col, total_width)
	mut parts := []string{}
	parts << merge_block
	parts << ' '.repeat(center_col) + '│'
	parts << axis_label_line(incoming_label, center_col, total_width)
	parts << ' '.repeat(center_col) + '│'
	parts << ascii_center_block(framed_group, total_width)
	parts << ' '.repeat(center_col) + '│'
	if outgoing_label.len > 0 {
		parts << axis_label_line(outgoing_label, center_col, total_width)
	}
	parts << ' '.repeat(center_col) + '│'
	parts << ' '.repeat(center_col) + '▼'
	parts << ascii_center_block(target, total_width)
	return parts.join('\n')
}

fn render_ascii_td_group_in_branch(source string, incoming_label string, framed_group string, outgoing_label string, targets []string, width int) string {
	frame_width := ascii_block_width(framed_group)
	branch_block := ascii_td_branch_from_center('', targets)
	total_width := min_int(max_int(max_int(display_width(source), frame_width),
		ascii_block_width(branch_block)), width)
	center_col := centered_block_mid_column(framed_group, total_width)
	mut parts := []string{}
	parts << ascii_center_block(source, total_width)
	parts << ' '.repeat(center_col) + '│'
	if incoming_label.len > 0 {
		parts << axis_label_line(incoming_label, center_col, total_width)
	}
	parts << ' '.repeat(center_col) + '│'
	parts << ' '.repeat(center_col) + '▼'
	parts << ascii_center_block(framed_group, total_width)
	parts << ' '.repeat(center_col) + '│'
	if outgoing_label.len > 0 {
		parts << axis_label_line(outgoing_label, center_col, total_width)
		parts << ' '.repeat(center_col) + '│'
	}
	parts << ascii_align_block_to_column(branch_block, [`├`, `└`], center_col, total_width)
	return parts.join('\n')
}

// Build the top-side TD merge directly against the target axis column rather than
// generating a free-floating block and trying to re-center it later.
fn max_source_display_width(sources []string) int {
	mut width := 0
	for source in sources {
		width = max_int(width, display_width(source))
	}
	return width
}

fn ascii_td_merge_to_column(sources []string, center_col int, width int) string {
	if sources.len < 2 {
		return ''
	}
	mut lines := []string{}
	for i, source in sources {
		mut chars := []rune{len: width, init: ` `}
		source_width := display_width(source)
		start := max_int(center_col - 1 - source_width, 0)
		for j, ch in source.runes() {
			pos := start + j
			if pos >= 0 && pos < chars.len {
				chars[pos] = ch
			}
		}
		corner := if i == 0 { `┐` } else { `┘` }
		if center_col >= 0 && center_col < chars.len {
			chars[center_col] = corner
		}
		lines << chars.string().trim_right(' ')
		if i == 0 {
			mut middle := []rune{len: width, init: ` `}
			if center_col >= 0 && center_col < middle.len {
				middle[center_col] = `┼`
			}
			lines << middle.string().trim_right(' ')
		}
	}
	return lines.join('\n')
}

fn ascii_td_branch_from_center(label string, targets []string) string {
	if targets.len == 0 {
		return ''
	}
	if targets.len == 1 {
		mut single := []string{}
		if label.len > 0 {
			single << label
		}
		single << '▼'
		single << targets[0]
		return single.join('\n')
	}
	mut lines := []string{}
	if label.len > 0 {
		width := max_int(display_width(label),

			max_int(display_width(targets[0]), display_width(targets[1])) + 4)
		lines << ascii_center_line(label, width)
		lines << ascii_center_line('│', width)
	}
	lines << '├─▶ ' + targets[0]
	lines << '└─▶ ' + targets[1]
	return lines.join('\n')
}

fn ascii_center_block(block string, width int) string {
	block_lines := block.split_into_lines()
	block_width := ascii_block_width(block)
	left_pad := max_int((width - block_width) / 2, 0)
	return block_lines.map(' '.repeat(left_pad) + it).join('\n')
}

fn ascii_align_block_to_column(block string, markers []rune, target_col int, width int) string {
	block_lines := block.split_into_lines()
	mut anchor_col := -1
	for line in block_lines {
		for i, ch in line.runes() {
			if ch in markers {
				anchor_col = i
				break
			}
		}
		if anchor_col >= 0 {
			break
		}
	}
	if anchor_col < 0 {
		return ascii_center_block(block, width)
	}
	left_pad := max_int(target_col - anchor_col, 0)
	return block_lines.map(' '.repeat(left_pad) + it).join('\n')
}

fn axis_label_line(label string, center_col int, width int) string {
	if label.len == 0 {
		return ''
	}
	start := max_int(center_col - display_width(label) / 2, 0)
	mut chars := []rune{len: width, init: ` `}
	for i, ch in label.runes() {
		pos := start + i
		if pos >= 0 && pos < chars.len {
			chars[pos] = ch
		}
	}
	return chars.string().trim_right(' ')
}

fn centered_block_axis_column(block string, marker rune, width int) int {
	lines := block.split_into_lines()
	block_width := ascii_block_width(block)
	left_pad := max_int((width - block_width) / 2, 0)
	for line in lines {
		runes := line.runes()
		for i, ch in runes {
			if ch == marker {
				return left_pad + i
			}
		}
	}
	return width / 2
}

fn centered_block_mid_column(block string, width int) int {
	block_width := ascii_block_width(block)
	left_pad := max_int((width - block_width) / 2, 0)
	return left_pad + block_width / 2
}

fn extract_outside_flow_component(nodes []DiagramNode, edges []DiagramEdge, anchor string, reverse bool) ([]DiagramNode, []DiagramEdge) {
	if nodes.len == 0 {
		return []DiagramNode{}, []DiagramEdge{}
	}
	mut node_map := map[string]DiagramNode{}
	for node in nodes {
		node_map[node.id] = node
	}
	if anchor !in node_map {
		return []DiagramNode{}, []DiagramEdge{}
	}
	mut ordered_nodes := []DiagramNode{}
	mut ordered_edges := []DiagramEdge{}
	ordered_nodes << node_map[anchor]
	if reverse {
		mut incoming := map[string]DiagramEdge{}
		for edge in edges {
			incoming[edge.to] = edge
		}
		mut current := anchor
		for {
			if current !in incoming {
				break
			}
			edge := incoming[current]
			if edge.from !in node_map {
				return []DiagramNode{}, []DiagramEdge{}
			}
			ordered_edges.prepend(edge)
			ordered_nodes.prepend(node_map[edge.from])
			current = edge.from
		}
		return ordered_nodes, ordered_edges
	}
	mut outgoing := map[string]DiagramEdge{}
	for edge in edges {
		outgoing[edge.from] = edge
	}
	mut current := anchor
	for {
		if current !in outgoing {
			break
		}
		edge := outgoing[current]
		if edge.to !in node_map {
			return []DiagramNode{}, []DiagramEdge{}
		}
		ordered_edges << edge
		ordered_nodes << node_map[edge.to]
		current = edge.to
	}
	return ordered_nodes, ordered_edges
}

fn render_flow_graph_component(graph DiagramGraph, width int) string {
	if graph.edges.len > 0 {
		return render_ascii_flow_graph(DiagramGraph{
			kind:      graph.kind
			direction: graph.direction
			nodes:     graph.nodes.clone()
			edges:     graph.edges.clone()
			groups:    []DiagramGroup{}
		}, width)
	}
	mut blocks := []string{}
	for node in graph.nodes {
		blocks << flow_node_block(node.id, flow_node_label_map(graph.nodes),
			flow_node_shape_map(graph.nodes), max_int(width / max_int(graph.nodes.len, 1), 16))
	}
	return blocks.join('\n\n')
}

fn truncate_block_lines(block string, width int) string {
	return block.split_into_lines().map(truncate_display_width(it, width)).join('\n')
}

fn render_ascii_grouped_graph(edges []AsciiGraphEdge, width int, title string) string {
	if edges.len == 0 {
		return ''
	}
	mut grouped := map[string][]string{}
	mut order := []string{}
	mut target_sources := map[string][]string{}
	mut source_counts := map[string]int{}
	for edge in edges {
		if edge.from.len == 0 || edge.to.len == 0 {
			continue
		}
		if edge.from !in grouped {
			grouped[edge.from] = []string{}
			order << edge.from
		}
		grouped[edge.from] << edge.to
		if edge.to !in target_sources {
			target_sources[edge.to] = []string{}
		}
		target_sources[edge.to] << edge.from
		source_counts[edge.from] = source_counts[edge.from] + 1
	}
	mut lines := ['◈ ' + title]
	mut consumed_sources := map[string]bool{}
	for from in order {
		if from in consumed_sources {
			continue
		}
		targets := grouped[from] or { continue }
		if targets.len < 2 {
			continue
		}
		mut sink := ''
		mut mids := []string{}
		mut eligible := true
		for target in targets {
			outgoing := grouped[target] or {
				eligible = false
				break
			}
			if outgoing.len != 1 {
				eligible = false
				break
			}
			if sink.len == 0 {
				sink = outgoing[0]
			} else if outgoing[0] != sink {
				eligible = false
				break
			}
			mids << '[' + target + ']'
		}
		if !eligible || sink.len == 0 {
			continue
		}
		mut rendered := ascii_lr_branch_merge('[' + from + ']', '', mids, '', '[' + sink + ']')
		next_targets := grouped[sink] or { []string{} }
		if next_targets.len == 1 {
			sink_inline := '[' + sink + ']'
			next_inline := '[' + next_targets[0] + ']'
			rendered = rendered.replace('┴ ─▶ ' + sink_inline, '┴ ─▶ ' + sink_inline +
				' ─▶ ' + next_inline)
			consumed_sources[sink] = true
		}
		lines << rendered
		lines << ''
		consumed_sources[from] = true
		for target in targets {
			consumed_sources[target] = true
		}
	}
	for _, target in edges.map(it.to) {
		if target !in target_sources {
			continue
		}
		sources_raw := target_sources[target]
		sources := sources_raw.map('[' + it + ']')
		if sources.len < 2 {
			continue
		}
		mut eligible := true
		for source_name in sources_raw {
			if source_name in consumed_sources || source_counts[source_name] != 1 {
				eligible = false
				break
			}
		}
		if !eligible {
			continue
		}
		lines << ascii_lr_merge(sources, '', '[' + target + ']')
		lines << ''
		for source_name in sources_raw {
			consumed_sources[source_name] = true
		}
		target_sources.delete(target)
	}
	for i, from in order {
		if from in consumed_sources {
			continue
		}
		targets := grouped[from].map('[' + it + ']')
		for line in ascii_lr_branch('[' + from + ']', '', targets).split_into_lines() {
			lines << line
		}
		if i < order.len - 1 {
			lines << ''
		}
	}
	return lines.map(truncate_block_lines(it, width)).join('\n')
}

fn render_ascii_flow_graph_lr(graph DiagramGraph, labels map[string]string, shapes map[string]DiagramNodeShape, width int) string {
	if chain := flow_linear_chain(graph) {
		mut segments := []string{}
		for i, node_id in chain.nodes {
			segments << flow_node_inline(node_id, labels, shapes)
			if i < chain.edges.len {
				segments << flow_edge_inline(chain.edges[i])
			}
		}
		return ascii_wrap_segments(segments, max_int(width, 24)).join('\n')
	}
	mut grouped := map[string][]DiagramEdge{}
	mut order := []string{}
	mut target_sources := map[string][]DiagramEdge{}
	for edge in graph.edges {
		if edge.from !in grouped {
			grouped[edge.from] = []DiagramEdge{}
			order << edge.from
		}
		grouped[edge.from] << edge
		if edge.to !in target_sources {
			target_sources[edge.to] = []DiagramEdge{}
		}
		target_sources[edge.to] << edge
	}
	mut lines := []string{}
	mut consumed_sources := map[string]bool{}
	for from in order {
		if from in consumed_sources {
			continue
		}
		edges := grouped[from] or { continue }
		if edges.len < 2 {
			continue
		}
		mut sink := ''
		mut mids := []string{}
		mut eligible := true
		branch_label := edges[0].label
		branch_kind := edges[0].kind
		for edge in edges {
			if edge.label != branch_label || edge.kind != branch_kind {
				eligible = false
				break
			}
			outgoing := grouped[edge.to] or {
				eligible = false
				break
			}
			if outgoing.len != 1 {
				eligible = false
				break
			}
			next := outgoing[0]
			if sink.len == 0 {
				sink = next.to
			} else if next.to != sink {
				eligible = false
				break
			}
			mids << flow_node_inline(edge.to, labels, shapes)
		}
		if !eligible || sink.len == 0 {
			continue
		}
		merge_edges := target_sources[sink] or { []DiagramEdge{} }
		if merge_edges.len != edges.len {
			continue
		}
		merge_label := merge_edges[0].label
		merge_kind := merge_edges[0].kind
		for edge in merge_edges {
			if edge.label != merge_label || edge.kind != merge_kind
				|| edge.from !in edges.map(it.to) {
				eligible = false
				break
			}
		}
		if !eligible {
			continue
		}
		lines << ascii_lr_branch_merge(flow_node_inline(from, labels, shapes), branch_label, mids,
			merge_label, flow_node_inline(sink, labels, shapes))
		lines << ''
		consumed_sources[from] = true
		for edge in edges {
			consumed_sources[edge.to] = true
		}
	}
	for target, sources_to_target in target_sources {
		if sources_to_target.len < 2 {
			continue
		}
		mut eligible := true
		merge_label := sources_to_target[0].label
		merge_kind := sources_to_target[0].kind
		mut sources := []string{}
		for edge in sources_to_target {
			if edge.label != merge_label || edge.kind != merge_kind || edge.from in consumed_sources {
				eligible = false
				break
			}
			sources << flow_node_inline(edge.from, labels, shapes)
		}
		if !eligible {
			continue
		}
		lines << ascii_lr_merge(sources, merge_label, flow_node_inline(target, labels, shapes))
		lines << ''
		for edge in sources_to_target {
			consumed_sources[edge.from] = true
		}
	}
	for i, from in order {
		if from in consumed_sources {
			continue
		}
		edges := grouped[from] or { continue }
		source := flow_node_inline(from, labels, shapes)
		if edges.len == 1 {
			edge := edges[0]
			target := flow_node_inline(edge.to, labels, shapes)
			mut segments := [source, flow_edge_inline(edge), target]
			lines << ascii_wrap_segments(segments, max_int(width, 24)).join('\n')
		} else {
			targets := edges.map(flow_branch_target(it, labels, shapes))
			label := if edges[0].label.len > 0 { edges[0].label } else { '' }
			lines << ascii_lr_branch(source, label, targets)
		}
		if i < order.len - 1 {
			lines << ''
		}
	}
	return lines.map(truncate_block_lines(it, width)).join('\n')
}

struct FlowLinearChain {
	nodes []string
	edges []DiagramEdge
}

fn flow_linear_chain(graph DiagramGraph) ?FlowLinearChain {
	if graph.edges.len == 0 {
		return none
	}
	mut out_degree := map[string]int{}
	mut in_degree := map[string]int{}
	mut outgoing := map[string]DiagramEdge{}
	mut nodes := map[string]bool{}
	for edge in graph.edges {
		if edge.from.len == 0 || edge.to.len == 0 {
			return none
		}
		out_degree[edge.from] = out_degree[edge.from] + 1
		in_degree[edge.to] = in_degree[edge.to] + 1
		if out_degree[edge.from] > 1 || in_degree[edge.to] > 1 {
			return none
		}
		outgoing[edge.from] = edge
		nodes[edge.from] = true
		nodes[edge.to] = true
	}
	mut start := ''
	for node_id in nodes.keys() {
		if (in_degree[node_id] or { 0 }) == 0 {
			if start.len > 0 {
				return none
			}
			start = node_id
		}
	}
	if start.len == 0 {
		return none
	}
	mut ordered_nodes := [start]
	mut ordered_edges := []DiagramEdge{}
	mut current := start
	mut seen := map[string]bool{}
	seen[current] = true
	for {
		if current !in outgoing {
			break
		}
		edge := outgoing[current]
		if edge.to in seen {
			return none
		}
		ordered_edges << edge
		ordered_nodes << edge.to
		current = edge.to
		seen[current] = true
	}
	if ordered_edges.len != graph.edges.len || ordered_nodes.len != nodes.len {
		return none
	}
	return FlowLinearChain{
		nodes: ordered_nodes
		edges: ordered_edges
	}
}

fn render_ascii_flow_graph_td(graph DiagramGraph, labels map[string]string, shapes map[string]DiagramNodeShape, width int) string {
	if chain := flow_linear_chain(graph) {
		mut parts := []string{}
		column_width := max_int(width / 3, 16)
		for i, node_id in chain.nodes {
			block := flow_node_block(node_id, labels, shapes, column_width)
			parts << block
			if i < chain.edges.len {
				for line in ascii_vertical_edge(ascii_block_width(block),
					chain.edges[i].kind == .arrow, chain.edges[i].label) {
					parts << line
				}
			}
		}
		return parts.map(truncate_block_lines(it, width)).join('\n')
	}
	mut grouped := map[string][]DiagramEdge{}
	mut order := []string{}
	mut target_sources := map[string][]DiagramEdge{}
	for edge in graph.edges {
		if edge.from !in grouped {
			grouped[edge.from] = []DiagramEdge{}
			order << edge.from
		}
		grouped[edge.from] << edge
		if edge.to !in target_sources {
			target_sources[edge.to] = []DiagramEdge{}
		}
		target_sources[edge.to] << edge
	}
	mut lines := []string{}
	mut consumed_sources := map[string]bool{}
	for from in order {
		if from in consumed_sources {
			continue
		}
		edges := grouped[from] or { continue }
		if edges.len < 2 {
			continue
		}
		mut sink := ''
		mut mids := []string{}
		mut eligible := true
		branch_label := edges[0].label
		branch_kind := edges[0].kind
		mid_ids := edges.map(it.to)
		for edge in edges {
			if edge.label != branch_label || edge.kind != branch_kind {
				eligible = false
				break
			}
			outgoing := grouped[edge.to] or {
				eligible = false
				break
			}
			if outgoing.len != 1 {
				eligible = false
				break
			}
			next := outgoing[0]
			if sink.len == 0 {
				sink = next.to
			} else if next.to != sink {
				eligible = false
				break
			}
			mids << flow_node_inline(edge.to, labels, shapes)
		}
		if !eligible || sink.len == 0 {
			continue
		}
		merge_edges := target_sources[sink] or { []DiagramEdge{} }
		if merge_edges.len != edges.len {
			continue
		}
		merge_label := merge_edges[0].label
		merge_kind := merge_edges[0].kind
		for edge in merge_edges {
			if edge.label != merge_label || edge.kind != merge_kind || edge.from !in mid_ids {
				eligible = false
				break
			}
		}
		if !eligible {
			continue
		}
		lines << ascii_td_branch_merge(flow_node_block(from, labels, shapes, max_int(width / 3, 16)),
			branch_label, mids, merge_label, flow_node_inline(sink, labels, shapes),
			merge_kind == .arrow)
		lines << ''
		consumed_sources[from] = true
		for edge in edges {
			consumed_sources[edge.to] = true
		}
	}
	for target, sources_to_target in target_sources {
		if sources_to_target.len < 2 {
			continue
		}
		mut eligible := true
		merge_label := sources_to_target[0].label
		merge_kind := sources_to_target[0].kind
		mut sources := []string{}
		for edge in sources_to_target {
			if edge.label != merge_label || edge.kind != merge_kind || edge.from in consumed_sources {
				eligible = false
				break
			}
			sources << flow_node_inline(edge.from, labels, shapes)
		}
		if !eligible {
			continue
		}
		lines << ascii_td_merge(sources, merge_label, flow_node_inline(target, labels, shapes),
			merge_kind == .arrow)
		lines << ''
		for edge in sources_to_target {
			consumed_sources[edge.from] = true
		}
	}
	for i, from in order {
		if from in consumed_sources {
			continue
		}
		edges := grouped[from] or { continue }
		source := flow_node_block(from, labels, shapes, max_int(width / 3, 16))
		if edges.len == 1 {
			edge := edges[0]
			target := flow_node_inline(edge.to, labels, shapes)
			mut parts := source.split_into_lines()
			for line in ascii_vertical_edge(ascii_block_width(source), edge.kind == .arrow,
				edge.label) {
				parts << line
			}
			parts << target
			lines << parts.join('\n')
		} else {
			targets := edges.map(flow_branch_target(it, labels, shapes))
			label := if edges[0].label.len > 0 { edges[0].label } else { '' }
			lines << ascii_td_branch(source, label, targets, edges[0].kind == .arrow)
		}
		if i < order.len - 1 {
			lines << ''
		}
	}
	return lines.map(truncate_block_lines(it, width)).join('\n')
}

fn flow_node_label_map(nodes []DiagramNode) map[string]string {
	mut out := map[string]string{}
	for node in nodes {
		out[node.id] = if node.label.len > 0 { node.label } else { node.id }
	}
	return out
}

fn flow_node_shape_map(nodes []DiagramNode) map[string]DiagramNodeShape {
	mut out := map[string]DiagramNodeShape{}
	for node in nodes {
		out[node.id] = node.shape
	}
	return out
}

fn flow_node_inline(id string, labels map[string]string, shapes map[string]DiagramNodeShape) string {
	label := labels[id] or { id }
	mut shape := DiagramNodeShape.box
	if id in shapes {
		shape = shapes[id]
	}
	return match shape {
		.round { '(' + label + ')' }
		.diamond { '{' + label + '}' }
		.box { '[' + label + ']' }
	}
}

fn flow_node_block(id string, labels map[string]string, shapes map[string]DiagramNodeShape, width int) string {
	label := labels[id] or { id }
	mut shape := DiagramNodeShape.box
	if id in shapes {
		shape = shapes[id]
	}
	return match shape {
		.round { ascii_box(label, []string{}, max_int(width, display_width(label) + 6)) }
		.diamond { '{' + label + '}' }
		.box { ascii_box(label, []string{}, max_int(width, display_width(label) + 6)) }
	}
}

fn flow_edge_inline(edge DiagramEdge) string {
	mut connector := if edge.kind == .arrow { '──▶' } else { '───' }
	if edge.label.len > 0 {
		connector = '─ ' + edge.label + ' ' + connector
	}
	return connector
}

fn flow_branch_target(edge DiagramEdge, labels map[string]string, shapes map[string]DiagramNodeShape) string {
	target := flow_node_inline(edge.to, labels, shapes)
	if edge.label.len > 0 {
		return edge.label + ' ' + target
	}
	return target
}
