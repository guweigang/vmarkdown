module vmarkdown

fn test_walk_visits_every_ast_layer_in_preorder() {
	doc := parse('# Title\n\n- [x] **one**\n  - [two](https://example.com)\n\n| A | B |\n| --- | --- |\n| x | y |\n') or {
		panic(err)
	}
	mut visits := []AstVisit{}
	mut visits_ref := &visits
	completed := doc.walk(fn [mut visits_ref] (visit AstVisit) bool {
		visits_ref << visit
		return true
	})
	assert completed
	assert visits[0].kind == .document
	assert visits[0].path == 'document'
	assert visits[1].kind == .heading
	assert visits[1].path == 'document.children[0]'
	assert visits[2].kind == .text
	assert visits[2].depth == 2
	assert visits.any(it.kind == .list_item && it.path == 'document.children[1].items[0]')
	assert visits.any(it.kind == .strong
		&& it.path == 'document.children[1].items[0].children[0].children[0]')
	assert visits.any(it.kind == .link && it.path.contains('.items[0].children[0].children[0]'))
	assert visits.any(it.kind == .table_row && it.path == 'document.children[2].head[0]')
	assert visits.any(it.kind == .table_cell
		&& it.path == 'document.children[2].body[0].cells[1]')
}

fn test_walk_can_stop_without_visiting_later_nodes() {
	doc := parse('# one\n\n## two\n') or { panic(err) }
	mut paths := []string{}
	mut paths_ref := &paths
	completed := doc.walk(fn [mut paths_ref] (visit AstVisit) bool {
		paths_ref << visit.path
		return visit.kind != .text
	})
	assert !completed
	assert paths == ['document', 'document.children[0]', 'document.children[0].children[0]']
}

fn test_find_all_returns_typed_matching_visits() {
	doc := parse('[one](first) and [two](second)') or { panic(err) }
	links := doc.find_all(.link)
	assert links.len == 2
	assert links[0].node is LinkNode
	assert (links[0].node as LinkNode).url == 'first'
	assert links[1].path.ends_with('.children[2]')
}

fn test_walk_and_rewrite_descend_into_wiki_link_labels() {
	doc := parse_with_options('[[docs|old]]', ParseOptions{
		wiki_links: true
	}) or { panic(err) }
	wikis := doc.find_all(.wiki_link)
	assert wikis.len == 1
	assert wikis[0].node is WikiLinkNode
	assert (wikis[0].node as WikiLinkNode).target == 'docs'
	assert doc.find_all(.text)[0].path.ends_with('.text[0]')

	rewritten := doc.rewrite_inlines(fn (visit AstInlineRewrite) ![]InlineNode {
		if visit.node is TextNode && visit.node.text == 'old' {
			return [InlineNode(TextNode{ text: 'new' })]
		}
		return [visit.node]
	}) or { panic(err) }
	assert rewritten.to_markdown() == '[[docs|new]]'
}
