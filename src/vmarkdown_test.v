module vmarkdown

import os
import v.vmod

fn test_version_matches_vmod() {
	vm := vmod.decode(@VMOD_FILE) or { panic(err) }
	assert version == vm.version
}

fn test_parse_heading_list_and_code_block() {
	input := '# Title

- alpha
- beta

```v
println("ok")
```
'
	doc := parse(input) or { panic(err) }
	assert doc.children.len == 3

	assert doc.children[0] is HeadingNode
	heading := doc.children[0] as HeadingNode
	assert heading.level == 1
	assert heading.children.len == 1
	assert heading.children[0] is TextNode
	assert (heading.children[0] as TextNode).text == 'Title'

	assert doc.children[1] is ListNode
	list := doc.children[1] as ListNode
	assert !list.is_ordered
	assert list.items.len == 2
	assert list.items[0].children.len == 1
	assert list.items[0].children[0] is ParagraphNode

	assert doc.children[2] is CodeBlockNode
	code := doc.children[2] as CodeBlockNode
	assert code.lang == 'v'
	assert code.content.contains('println("ok")')
}

fn test_parse_code_block_preserves_full_info_string() {
	input := '```json diagram\n{"version":1,"kind":"timeline","entries":[]}\n```\n'
	doc := parse(input) or { panic(err) }
	assert doc.children.len == 1
	assert doc.children[0] is CodeBlockNode
	code := doc.children[0] as CodeBlockNode
	assert code.lang == 'json diagram'
}

fn test_parse_table_ast_with_alignment_and_inline_children() {
	input := '| Name | Score | Note |\n| :--- | ---: | :---: |\n| **Ada** | 10 | [ok](https://example.com) |\n'
	doc := parse(input) or { panic(err) }
	assert doc.children.len == 1
	assert doc.children[0] is TableNode
	table := doc.children[0] as TableNode
	assert table.columns == 3
	assert table.head.len == 1
	assert table.body.len == 1
	assert table.head[0].cells.map(it.alignment) == [.left, .right, .center]
	assert table.head[0].cells[0].children[0] is TextNode
	assert table.body[0].cells[0].children[0] is StrongNode
	assert table.body[0].cells[2].children[0] is LinkNode
	assert BlockNode(table).binary_encode()[0] == u8(0x08)
	assert BlockNode(table).stable_id().starts_with('table:')
}

fn test_parse_with_tables_disabled_keeps_pipe_text_as_paragraph() {
	doc := parse_with_options('| A | B |\n| --- | --- |\n| x | y |\n', ParseOptions{
		tables: false
	}) or { panic(err) }
	assert doc.children.len == 1
	assert doc.children[0] is ParagraphNode
}

fn test_binary_encoding_uses_protocol_type_tags() {
	heading := HeadingNode{
		level:    2
		children: [InlineNode(TextNode{
			text: 'Hello'
		})]
	}
	encoded := BlockNode(heading).binary_encode()
	assert encoded[0] == u8(0x01)
	assert encoded[1] == u8(2)

	paragraph := ParagraphNode{
		children: [InlineNode(TextNode{
			text: 'Hello'
		})]
	}
	assert BlockNode(paragraph).binary_encode()[0] == u8(0x02)
	assert BlockNode(paragraph).stable_id() != BlockNode(paragraph).semantic_stable_id()
}

fn test_parse_list_item_starting_with_code_span() {
	input := '- `Document` owns `[]BlockNode`\n'
	doc := parse(input) or { panic(err) }
	assert doc.children.len == 1
	assert doc.children[0] is ListNode
	list := doc.children[0] as ListNode
	assert list.items.len == 1
	assert list.items[0].children.len == 1
	assert list.items[0].children[0] is ParagraphNode
	paragraph := list.items[0].children[0] as ParagraphNode
	assert paragraph.children.len == 3
	assert paragraph.children[0] is CodeSpanNode
	assert paragraph.children[1] is TextNode
	assert paragraph.children[2] is CodeSpanNode
}

fn test_parse_readme_smoke() {
	readme := os.read_file(os.join_path(@VMODROOT, 'README.md')) or { panic(err) }
	doc := parse(readme) or { panic(err) }
	assert doc.children.len > 0
}
