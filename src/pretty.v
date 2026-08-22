module vmarkdown

import strings

pub fn (doc Document) pretty() string {
	mut sb := strings.new_builder(512)
	sb.write_string('Document\n')
	for i, child in doc.children {
		write_block_pretty(mut sb, child, '', i == doc.children.len - 1)
	}
	return sb.str()
}

fn write_block_pretty(mut sb strings.Builder, node BlockNode, prefix string, is_last bool) {
	branch := if is_last { '└─ ' } else { '├─ ' }
	next_prefix := if is_last { prefix + '   ' } else { prefix + '│  ' }
	match node {
		HeadingNode {
			sb.write_string(prefix + branch + 'Heading(level=${node.level}) "' +
				inline_preview(node.children) + '"\n')
		}
		ParagraphNode {
			sb.write_string(prefix + branch + 'Paragraph "' + inline_preview(node.children) + '"\n')
		}
		CodeBlockNode {
			sb.write_string(prefix + branch + 'CodeBlock(lang="' + node.lang + '") "' +
				single_line(node.content) + '"\n')
		}
		HorizontalRuleNode {
			sb.write_string(prefix + branch + 'HorizontalRule\n')
		}
		MetaNode {
			sb.write_string(prefix + branch + 'Meta\n')
			mut keys := node.data.keys()
			keys.sort()
			for i, key in keys {
				item_branch := if i == keys.len - 1 { '└─ ' } else { '├─ ' }
				sb.write_string(next_prefix + item_branch + key + ': ' + node.data[key] + '\n')
			}
		}
		BlockquoteNode {
			sb.write_string(prefix + branch + 'Blockquote\n')
			for i, child in node.children {
				write_block_pretty(mut sb, child, next_prefix, i == node.children.len - 1)
			}
		}
		ListNode {
			label := if node.is_ordered { 'OrderedList' } else { 'UnorderedList' }
			sb.write_string(prefix + branch + '${label}(start=${node.start})\n')
			for i, item in node.items {
				write_list_item_pretty(mut sb, item, next_prefix, i == node.items.len - 1)
			}
		}
		TableNode {
			sb.write_string(prefix + branch + 'Table(columns=${node.columns})\n')
			mut rows := node.head.clone()
			rows << node.body
			for row_index, row in rows {
				row_branch := if row_index == rows.len - 1 { '└─ ' } else { '├─ ' }
				row_prefix := if row_index == rows.len - 1 {
					next_prefix + '   '
				} else {
					next_prefix + '│  '
				}
				kind := if row_index < node.head.len { 'HeaderRow' } else { 'Row' }
				sb.write_string(next_prefix + row_branch + kind + '\n')
				for cell_index, cell in row.cells {
					cell_branch := if cell_index == row.cells.len - 1 {
						'└─ '
					} else {
						'├─ '
					}
					sb.write_string(row_prefix + cell_branch + 'Cell(align=${cell.alignment}) "' +
						inline_preview(cell.children) + '"\n')
				}
			}
		}
	}
}

fn write_list_item_pretty(mut sb strings.Builder, item ListItemNode, prefix string, is_last bool) {
	branch := if is_last { '└─ ' } else { '├─ ' }
	next_prefix := if is_last { prefix + '   ' } else { prefix + '│  ' }
	sb.write_string(prefix + branch + 'ListItem(level=${item.level}, number=${item.number})\n')
	for i, child in item.children {
		write_block_pretty(mut sb, child, next_prefix, i == item.children.len - 1)
	}
}

fn inline_preview(nodes []InlineNode) string {
	mut sb := strings.new_builder(64)
	for node in nodes {
		match node {
			TextNode {
				sb.write_string(node.text)
			}
			EmphasisNode {
				sb.write_string('*' + inline_preview(node.children) + '*')
			}
			StrongNode {
				sb.write_string('**' + inline_preview(node.children) + '**')
			}
			CodeSpanNode {
				sb.write_string('`' + node.text + '`')
			}
			LinkNode {
				sb.write_string('[' + inline_preview(node.text) + '](' + node.url + ')')
			}
			ImageNode {
				sb.write_string('![' + inline_preview(node.alt) + '](' + node.url + ')')
			}
		}
	}
	return single_line(sb.str())
}

fn single_line(input string) string {
	return input.replace('\n', '\\n').trim_space()
}
