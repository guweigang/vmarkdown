module vmarkdown

pub struct AsciiTreeNode {
pub mut:
	label    string
	children []AsciiTreeNode
}

pub struct AsciiOrgNode {
pub mut:
	name    string
	title   string
	reports []AsciiOrgNode
}

pub fn render_ascii_tree(root AsciiTreeNode, width int) string {
	if root.label.len == 0 {
		return ''
	}
	mut lines := ['◉ ' + truncate_display_width(root.label, max_int(width - 2, 1))]
	render_ascii_tree_children(root.children, '', mut lines, width)
	return lines.join('\n')
}

fn render_ascii_tree_children(children []AsciiTreeNode, prefix string, mut lines []string, width int) {
	for i, child in children {
		connector := if i == children.len - 1 { '└─ ' } else { '├─ ' }
		lines << truncate_display_width(prefix + connector + child.label, width)
		next_prefix := prefix + if i == children.len - 1 { '   ' } else { '│  ' }
		render_ascii_tree_children(child.children, next_prefix, mut lines, width)
	}
}

pub fn render_ascii_org_chart(root AsciiOrgNode, width int) string {
	if root.name.len == 0 {
		return ''
	}
	root_box := ascii_org_box(root, width)
	if root.reports.len == 0 {
		return root_box
	}
	reports_block, starts, block_widths, row_width := render_ascii_org_reports(root.reports, width)
	mut out := []string{}
	for line in root_box.split_into_lines() {
		out << ascii_center_line(line, row_width)
	}
	root_center := row_width / 2
	out << ' '.repeat(root_center) + '│'
	out << ascii_org_bus_line(block_widths, 4, row_width, root_center)
	out << reports_block
	for i, report in root.reports {
		if report.reports.len > 0 {
			indent := ' '.repeat(starts[i])
			subtree := render_ascii_org_reports_only(report.reports, block_widths[i])
			out << ''
			for line in subtree.split_into_lines() {
				out << indent + line
			}
		}
	}
	return out.join('\n')
}

fn render_ascii_org_reports(reports []AsciiOrgNode, width int) (string, []int, []int, int) {
	mut blocks := []string{}
	mut starts := []int{}
	mut cursor := 0
	for report in reports {
		block := ascii_org_box(report, max_int(width / max_int(reports.len, 1), 18))
		blocks << block
		starts << cursor
		cursor += ascii_block_width(block) + 4
	}
	block_widths := blocks.map(ascii_block_width(it))
	row := ascii_row(blocks, 4, width)
	row_width := ascii_block_width(row)
	return row, starts, block_widths, row_width
}

fn render_ascii_org_reports_only(reports []AsciiOrgNode, width int) string {
	if reports.len == 0 {
		return ''
	}
	row, starts, block_widths, row_width := render_ascii_org_reports(reports, width)
	mut out := []string{}
	parent_center := row_width / 2
	out << ' '.repeat(parent_center) + '│'
	out << ascii_org_bus_line(block_widths, 4, row_width, parent_center)
	out << row
	for i, report in reports {
		if report.reports.len > 0 {
			indent := ' '.repeat(starts[i])
			subtree := render_ascii_org_reports_only(report.reports, block_widths[i])
			out << ''
			for line in subtree.split_into_lines() {
				out << indent + line
			}
		}
	}
	return out.join('\n')
}

fn ascii_org_box(node AsciiOrgNode, width int) string {
	mut rows := []string{}
	if node.title.len > 0 {
		rows << node.title
	}
	return ascii_box(node.name, rows, max_int(width, display_width(node.name) + 6))
}

fn ascii_org_bus_line(widths []int, gap int, total_width int, root_center int) string {
	if widths.len == 0 {
		return ''
	}
	if widths.len == 1 {
		return ' '.repeat(root_center) + '│'
	}
	mut chars := []rune{len: total_width, init: ` `}
	mut centers := []int{}
	mut cursor := 0
	for width in widths {
		centers << cursor + width / 2
		cursor += width + gap
	}
	min_center := centers[0]
	max_center := centers[centers.len - 1]
	for i in min_center .. max_center + 1 {
		if i >= 0 && i < chars.len {
			chars[i] = `─`
		}
	}
	for center in centers {
		if center >= 0 && center < chars.len {
			chars[center] = `┬`
		}
	}
	if root_center >= 0 && root_center < chars.len {
		chars[root_center] = if chars[root_center] == `─` { `┴` } else { `┼` }
	}
	return chars.string().trim_right(' ')
}
