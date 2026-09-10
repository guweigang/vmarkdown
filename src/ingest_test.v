module vmarkdown

fn test_incremental_ingest_reuses_unchanged_chunks() {
	mut store := new_memory_store()
	before := '# Title

Paragraph one.

Paragraph two.
'
	first := store.ingest(before) or { panic(err) }
	assert first.root_id.len > 0
	assert first.added.len == first.chunks.len
	assert first.reused.len == 0
	assert first.changed.len == first.chunks.len - 1

	after := '# Title

Paragraph one.

Paragraph two updated.
'
	second := store.ingest(after) or { panic(err) }
	assert second.root_id != first.root_id
	assert second.added.len > 0
	assert second.reused.len > 0
	assert second.changed.len == 1

	heading_id := (parse('# Title') or { panic(err) }).children[0].stable_id()
	assert heading_id in second.reused
}

fn test_plan_then_commit_ingest() {
	mut store := new_memory_store()
	doc := parse('# Title

Paragraph one.
') or { panic(err) }
	plan := plan_ingest_document(doc, store)
	assert plan.root_id.len > 0
	assert plan.previous_root == ''
	assert plan.to_add.len == plan.all_chunks.len
	assert plan.to_reuse.len == 0

	result := commit_ingest_plan(mut store, plan) or { panic(err) }
	assert result.root_id == plan.root_id
	assert result.added.len == plan.to_add.len
	assert result.reused.len == 0
	assert store.last_root_id() == plan.root_id
	assert store.has_chunk(plan.root_id)
	assert plan.manifest.len == 2
	assert plan.manifest[0].path == 'blocks[0]'
}

fn test_ingest_diff_reports_added_removed_and_reused_blocks() {
	mut store := new_memory_store()
	store.ingest('# Title

Paragraph one.

Paragraph two.
') or { panic(err) }
	second := store.ingest('# Title

Paragraph one updated.

Paragraph two.
') or { panic(err) }

	added := second.added_blocks()
	removed := second.removed_blocks()
	reused := second.reused_blocks()
	assert added.len == 1
	assert removed.len == 1
	assert reused.len == 2
	assert added[0].kind == 'paragraph'
	assert added[0].path == 'blocks[1]'
	assert added[0].current_index == 1
	assert added[0].previous_index == -1
	assert removed[0].kind == 'paragraph'
	assert removed[0].path == 'blocks[1]'
	assert removed[0].current_index == -1
	assert removed[0].previous_index == 1
	assert reused[0].kind in ['heading', 'paragraph']
}

fn test_stable_id_normalizes_text_whitespace() {
	left := ParagraphNode{
		children: [InlineNode(TextNode{
			text: 'hello   world'
		})]
	}
	right := ParagraphNode{
		children: [InlineNode(TextNode{
			text: ' hello world '
		})]
	}
	assert BlockNode(left).stable_id() == BlockNode(right).stable_id()
}

fn test_nested_diff_uses_recursive_block_paths() {
	mut store := new_memory_store()
	store.ingest('- parent
  - child one
') or { panic(err) }
	result := store.ingest('- parent
  - child two
') or { panic(err) }

	added := result.added_blocks()
	removed := result.removed_blocks()
	assert added.len >= 3
	assert removed.len >= 3
	assert added.any(it.path == 'blocks[0].items[0].children[1]' && it.kind == 'list')
	assert removed.any(it.path == 'blocks[0].items[0].children[1]' && it.kind == 'list')
	assert added.any(it.path == 'blocks[0].items[0].children[1].items[0].children[0]'
		&& it.kind == 'paragraph')
	assert removed.any(it.path == 'blocks[0].items[0].children[1].items[0].children[0]'
		&& it.kind == 'paragraph')
}

fn test_diff_summary_groups_entries_and_formats_lines() {
	mut store := new_memory_store()
	store.ingest('# Title

Paragraph one.

Paragraph two.
') or { panic(err) }
	result := store.ingest('# Title

Paragraph one updated.

Paragraph two.
') or { panic(err) }

	summary := result.diff_summary()
	assert summary.added.len == 1
	assert summary.added[0].kind == 'paragraph'
	assert summary.added[0].count == 1
	assert summary.added[0].paths == ['blocks[1]']
	assert summary.removed.len == 1
	assert summary.removed[0].kind == 'paragraph'
	assert summary.removed[0].count == 1
	assert summary.reused.len == 2
	assert summary.lines.any(it == 'added paragraph at blocks[1]')
	assert summary.lines.any(it == 'removed paragraph at blocks[1]')
	assert summary.lines.any(it == 'reused heading at blocks[0]')
}

fn test_ingest_diff_aligns_unchanged_blocks_after_leading_insertion() {
	mut store := new_memory_store()
	store.ingest('# Title\n\nAlpha.\n\nBeta.\n') or { panic(err) }
	result := store.ingest('New.\n\n# Title\n\nAlpha.\n\nBeta.\n') or { panic(err) }

	assert result.added_blocks().len == 1
	assert result.removed_blocks().len == 0
	assert result.reused_blocks().len == 3
	assert result.moved_blocks().len == 0
	assert result.reused_blocks().any(it.previous_path == 'blocks[0]' && it.path == 'blocks[1]')
}

fn test_ingest_diff_pairs_duplicate_ids_deterministically() {
	mut store := new_memory_store()
	store.ingest('Same.\n\nSame.\n') or { panic(err) }
	result := store.ingest('New.\n\nSame.\n\nSame.\n') or { panic(err) }

	reused := result.reused_blocks()
	assert reused.len == 2
	assert reused[0].previous_path == 'blocks[0]'
	assert reused[0].path == 'blocks[1]'
	assert reused[1].previous_path == 'blocks[1]'
	assert reused[1].path == 'blocks[2]'
}

fn test_ingest_diff_reports_reordered_block_as_moved() {
	mut store := new_memory_store()
	store.ingest('Alpha.\n\nBeta.\n\nGamma.\n') or { panic(err) }
	result := store.ingest('Beta.\n\nAlpha.\n\nGamma.\n') or { panic(err) }

	assert result.added_blocks().len == 0
	assert result.removed_blocks().len == 0
	assert result.reused_blocks().len == 2
	assert result.moved_blocks().len == 1
	assert result.moved_blocks()[0].previous_path != result.moved_blocks()[0].path
	assert result.diff_summary().lines.any(it.starts_with('moved paragraph from '))
}
