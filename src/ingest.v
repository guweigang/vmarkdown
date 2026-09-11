module vmarkdown

// Chunk storage and ingest planning.

pub struct Chunk {
pub:
	id   string
	kind string
	data []u8
	refs []string
}

pub enum DiffOp {
	added
	removed
	reused
	moved
}

pub struct DiffEntry {
pub:
	op             DiffOp
	id             string
	kind           string
	path           string
	previous_path  string
	current_index  int = -1
	previous_index int = -1
}

pub struct BlockManifestEntry {
pub:
	id    string
	kind  string
	path  string
	index int
}

pub struct DiffSummaryItem {
pub:
	op   DiffOp
	kind string
pub mut:
	count int
	paths []string
}

pub struct DiffSummary {
pub:
	added   []DiffSummaryItem
	removed []DiffSummaryItem
	reused  []DiffSummaryItem
	moved   []DiffSummaryItem
	lines   []string
}

pub struct IngestResult {
pub:
	root_id  string
	added    []string
	reused   []string
	changed  []string
	chunks   []Chunk
	diff     []DiffEntry
	manifest []BlockManifestEntry
}

pub struct IngestPlan {
pub:
	root_id       string
	previous_root string
	root_refs     []string
	to_add        []Chunk
	to_reuse      []Chunk
	changed       []string
	all_chunks    []Chunk
	diff          []DiffEntry
	manifest      []BlockManifestEntry
}

pub interface ChunkStore {
	has_chunk(id string) bool
	root_refs(root_id string) ?[]string
	root_manifest(root_id string) ?[]BlockManifestEntry
	last_root_id() string
mut:
	put_chunk(chunk Chunk) !
	put_root(root_id string, refs []string) !
	put_root_manifest(root_id string, manifest []BlockManifestEntry) !
	set_last_root_id(root_id string) !
}

pub struct MemoryStore {
pub mut:
	chunks       map[string]Chunk
	roots        map[string][]string
	manifests    map[string][]BlockManifestEntry
	last_root_id string
}

pub fn new_memory_store() MemoryStore {
	return MemoryStore{
		chunks: map[string]Chunk{}
		roots: map[string][]string{}
		manifests: map[string][]BlockManifestEntry{}
	}
}

pub fn (mut store MemoryStore) ingest(markdown string) !IngestResult {
	return store.ingest_with_limits(markdown, ParseOptions{}, ParseLimits{})
}

pub fn (mut store MemoryStore) ingest_with_options(markdown string, options ParseOptions) !IngestResult {
	return store.ingest_with_limits(markdown, options, ParseLimits{})
}

pub fn (mut store MemoryStore) ingest_with_limits(markdown string, options ParseOptions, limits ParseLimits) !IngestResult {
	doc := parse_with_limits(markdown, options, limits)!
	return store.ingest_document_with_limits(doc, AstValidationLimits{
		max_nodes: limits.max_nodes
		max_nesting_depth: limits.max_nesting_depth
	})
}

pub fn (mut store MemoryStore) ingest_document(doc Document) !IngestResult {
	return store.ingest_document_with_limits(doc, AstValidationLimits{})
}

pub fn (mut store MemoryStore) ingest_document_with_limits(doc Document, limits AstValidationLimits) !IngestResult {
	plan := plan_ingest_document_checked_with_limits(doc, store, limits)!
	return commit_ingest_plan(mut store, plan)
}

pub fn (store &MemoryStore) has_chunk(id string) bool {
	return id in store.chunks
}

pub fn (store &MemoryStore) chunk(id string) ?Chunk {
	if id !in store.chunks {
		return none
	}
	return store.chunks[id]
}

pub fn (mut store MemoryStore) put_chunk(chunk Chunk) ! {
	store.chunks[chunk.id] = chunk
}

pub fn (mut store MemoryStore) put_root(root_id string, refs []string) ! {
	store.roots[root_id] = refs.clone()
}

pub fn (mut store MemoryStore) put_root_manifest(root_id string, manifest []BlockManifestEntry) ! {
	store.manifests[root_id] = manifest.clone()
}

pub fn (mut store MemoryStore) set_last_root_id(root_id string) ! {
	store.last_root_id = root_id
}

pub fn (store &MemoryStore) root_refs(root_id string) ?[]string {
	if root_id !in store.roots {
		return none
	}
	return store.roots[root_id].clone()
}

pub fn (store &MemoryStore) last_root_id() string {
	return store.last_root_id
}

pub fn (store &MemoryStore) root_manifest(root_id string) ?[]BlockManifestEntry {
	if root_id !in store.manifests {
		return none
	}
	return store.manifests[root_id].clone()
}

pub fn plan_ingest(markdown string, store ChunkStore) !IngestPlan {
	return plan_ingest_with_limits(markdown, store, ParseOptions{}, ParseLimits{})
}

pub fn plan_ingest_with_options(markdown string, store ChunkStore, options ParseOptions) !IngestPlan {
	return plan_ingest_with_limits(markdown, store, options, ParseLimits{})
}

pub fn plan_ingest_with_limits(markdown string, store ChunkStore, options ParseOptions, limits ParseLimits) !IngestPlan {
	doc := parse_with_limits(markdown, options, limits)!
	return plan_ingest_document_checked_with_limits(doc, store, AstValidationLimits{
		max_nodes: limits.max_nodes
		max_nesting_depth: limits.max_nesting_depth
	})
}

pub fn plan_ingest_document(doc Document, store ChunkStore) IngestPlan {
	return make_ingest_plan(doc, store)
}

// plan_ingest_document_checked validates application-assembled ASTs before
// deriving stable IDs or binary chunks. Use plan_ingest_document only when the
// document has already been validated or came directly from parse().
pub fn plan_ingest_document_checked(doc Document, store ChunkStore) !IngestPlan {
	return plan_ingest_document_checked_with_limits(doc, store, AstValidationLimits{})
}

pub fn plan_ingest_document_checked_with_limits(doc Document, store ChunkStore, limits AstValidationLimits) !IngestPlan {
	doc.validate_with_limits(limits)!
	return make_ingest_plan(doc, store)
}

pub fn commit_ingest_plan(mut store ChunkStore, plan IngestPlan) !IngestResult {
	mut added := []string{cap: plan.to_add.len}
	mut reused := []string{cap: plan.to_reuse.len}
	for chunk in plan.to_add {
		store.put_chunk(chunk)!
		added << chunk.id
	}
	for chunk in plan.to_reuse {
		reused << chunk.id
	}
	store.put_root(plan.root_id, plan.root_refs)!
	store.put_root_manifest(plan.root_id, plan.manifest)!
	store.set_last_root_id(plan.root_id)!
	return IngestResult{
		root_id: plan.root_id
		added: added
		reused: reused
		changed: plan.changed.clone()
		chunks: plan.all_chunks.clone()
		diff: plan.diff.clone()
		manifest: plan.manifest.clone()
	}
}

pub fn (plan IngestPlan) added_blocks() []DiffEntry {
	return filter_diff(plan.diff, .added)
}

pub fn (plan IngestPlan) removed_blocks() []DiffEntry {
	return filter_diff(plan.diff, .removed)
}

pub fn (plan IngestPlan) reused_blocks() []DiffEntry {
	return filter_diff(plan.diff, .reused)
}

pub fn (plan IngestPlan) moved_blocks() []DiffEntry {
	return filter_diff(plan.diff, .moved)
}

pub fn (result IngestResult) added_blocks() []DiffEntry {
	return filter_diff(result.diff, .added)
}

pub fn (result IngestResult) removed_blocks() []DiffEntry {
	return filter_diff(result.diff, .removed)
}

pub fn (result IngestResult) reused_blocks() []DiffEntry {
	return filter_diff(result.diff, .reused)
}

pub fn (result IngestResult) moved_blocks() []DiffEntry {
	return filter_diff(result.diff, .moved)
}

pub fn (plan IngestPlan) diff_summary() DiffSummary {
	return build_diff_summary(plan.diff)
}

pub fn (result IngestResult) diff_summary() DiffSummary {
	return build_diff_summary(result.diff)
}

struct ChunkCollector {
mut:
	chunks   []Chunk
	manifest []BlockManifestEntry
}

fn make_ingest_plan(doc Document, store ChunkStore) IngestPlan {
	previous_root := store.last_root_id()
	previous_refs := store.root_refs(previous_root) or { []string{} }
	previous_manifest := store.root_manifest(previous_root) or { []BlockManifestEntry{} }
	mut collector := ChunkCollector{}
	root := collector.collect_document(doc)
	chunk_index := index_chunks(collector.chunks)
	mut to_add := []Chunk{}
	mut to_reuse := []Chunk{}
	for chunk in collector.chunks {
		if store.has_chunk(chunk.id) {
			to_reuse << chunk
		} else {
			to_add << chunk
		}
	}
	return IngestPlan{
		root_id: root.id
		previous_root: previous_root
		root_refs: root.refs.clone()
		to_add: to_add
		to_reuse: to_reuse
		changed: diff_root_refs(previous_refs, root.refs)
		all_chunks: collector.chunks.clone()
		diff: diff_entries(previous_manifest, collector.manifest, chunk_index)
		manifest: collector.manifest.clone()
	}
}

fn (mut c ChunkCollector) collect_document(doc Document) Chunk {
	mut refs := []string{cap: doc.children.len}
	for i, child in doc.children {
		c.collect_block(child, 'blocks[${i}]', i)
		refs << child.stable_id()
	}
	root := Chunk{
		id: doc.stable_id()
		kind: 'document'
		data: doc.binary_encode()
		refs: refs
	}
	c.chunks << root
	return root
}

fn (mut c ChunkCollector) collect_block(node BlockNode, path string, index int) {
	mut refs := []string{}
	c.manifest << BlockManifestEntry{
		id: node.stable_id()
		kind: node.kind_name()
		path: path
		index: index
	}
	match node {
		HeadingNode, ParagraphNode, CodeBlockNode, HorizontalRuleNode, MetaNode, RawHtmlBlockNode, TableNode {
		}
		BlockquoteNode {
			for child_index, child in node.children {
				c.collect_block(child, '${path}.children[${child_index}]', child_index)
				refs << child.stable_id()
			}
		}
		ListNode {
			for item_index, item in node.items {
				for child_index, child in item.children {
					c.collect_block(child, '${path}.items[${item_index}].children[${child_index}]', child_index)
					refs << child.stable_id()
				}
			}
		}
	}
	c.chunks << Chunk{
		id: node.stable_id()
		kind: node.kind_name()
		data: node.binary_encode()
		refs: refs
	}
}
