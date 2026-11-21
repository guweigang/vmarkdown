module vmarkdown

const max_footnote_label_bytes = 76

// md4c distinguishes raw labels when resolving references, but exposes
// unescaped labels in callbacks. Keep distinct definitions distinct when the
// unescaped labels coincide.
fn disambiguate_footnote_labels(doc Document) !Document {
	mut used := map[string]bool{}
	mut renamed := map[int]string{}
	for block in doc.children {
		if block is FootnoteDefinitionNode {
			key := block.label.to_lower()
			if key in used {
				renamed[block.number] = ''
			}
			used[key] = true
		}
	}
	if renamed.len == 0 {
		return doc
	}
	mut children := doc.children.clone()
	for index, block in doc.children {
		if block is FootnoteDefinitionNode && block.number in renamed {
			definition := block as FootnoteDefinitionNode
			base := 'footnote-${definition.number}'
			mut label := base
			mut suffix := 2
			for (label in used) {
				label = '${base}-${suffix}'
				suffix++
			}
			used[label] = true
			renamed[definition.number] = label
			children[index] = FootnoteDefinitionNode{
				...definition
				label: label
			}
		}
	}
	for index, block in children {
		children[index] = rewrite_block_inlines(block, 'document.children[${index}]', 1,
			fn [renamed] (visit AstInlineRewrite) ![]InlineNode {
				if visit.node is FootnoteReferenceNode {
					ref := visit.node as FootnoteReferenceNode
					if label := renamed[ref.number] {
						return [InlineNode(FootnoteReferenceNode{ ...ref, label: label })]
					}
				}
				return [visit.node]
			})!
	}
	return Document{ ...doc, children: children }
}
