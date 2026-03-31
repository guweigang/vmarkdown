module vmarkdown

import crypto.sha256
import strings

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
}

pub struct DiffEntry {
pub:
	op             DiffOp
	id             string
	kind           string
	path           string
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
	op    DiffOp
	kind  string
pub mut:
	count int
	paths []string
}

pub struct DiffSummary {
pub:
	added   []DiffSummaryItem
	removed []DiffSummaryItem
	reused  []DiffSummaryItem
	lines   []string
}

pub struct IngestResult {
pub:
	root_id string
	added   []string
	reused  []string
	changed []string
	chunks  []Chunk
	diff    []DiffEntry
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
	return store.ingest_document(parse(markdown)!)
}

pub fn (mut store MemoryStore) ingest_document(doc Document) !IngestResult {
	plan := make_ingest_plan(doc, store)
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
	return make_ingest_plan(parse(markdown)!, store)
}

pub fn plan_ingest_document(doc Document, store ChunkStore) IngestPlan {
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

pub fn (result IngestResult) added_blocks() []DiffEntry {
	return filter_diff(result.diff, .added)
}

pub fn (result IngestResult) removed_blocks() []DiffEntry {
	return filter_diff(result.diff, .removed)
}

pub fn (result IngestResult) reused_blocks() []DiffEntry {
	return filter_diff(result.diff, .reused)
}

pub fn (plan IngestPlan) diff_summary() DiffSummary {
	return build_diff_summary(plan.diff)
}

pub fn (result IngestResult) diff_summary() DiffSummary {
	return build_diff_summary(result.diff)
}

pub fn (doc Document) stable_id() string {
	return 'doc:' + hash_bytes(doc.binary_encode())
}

pub fn (doc Document) root_refs() []string {
	mut refs := []string{cap: doc.children.len}
	for child in doc.children {
		refs << child.stable_id()
	}
	return refs
}

pub fn (doc Document) encode() []u8 {
	return doc.binary_encode()
}

pub fn (doc Document) semantic_stable_id() string {
	return 'doc:' + hash_bytes(doc.normalized_bytes())
}

pub fn (doc Document) semantic_encode() []u8 {
	return doc.normalized_bytes()
}

pub fn (node BlockNode) stable_id() string {
	encoded := node.binary_encode()
	match node {
		HeadingNode {
			return 'h${node.level}:' + hash_bytes(encoded)
		}
		ParagraphNode {
			return 'para:' + hash_bytes(encoded)
		}
		CodeBlockNode {
			lang := normalize_text(node.lang)
			return 'code:${lang}:' + hash_bytes(encoded)
		}
		BlockquoteNode {
			return 'quote:' + hash_bytes(encoded)
		}
		ListNode {
			return 'list:' + hash_bytes(encoded)
		}
		HorizontalRuleNode {
			return 'hr:' + hash_bytes(encoded)
		}
		MetaNode {
			return 'meta:' + hash_bytes(encoded)
		}
	}
}

pub fn (node BlockNode) encode() []u8 {
	return node.binary_encode()
}

pub fn (item ListItemNode) encode() []u8 {
	return item.binary_encode()
}

pub fn (node InlineNode) encode() []u8 {
	return node.binary_encode()
}

pub fn (node BlockNode) semantic_stable_id() string {
	normalized := node.normalized_bytes()
	match node {
		HeadingNode {
			return 'h${node.level}:' + hash_bytes(normalized)
		}
		ParagraphNode {
			return 'para:' + hash_bytes(normalized)
		}
		CodeBlockNode {
			lang := normalize_text(node.lang)
			return 'code:${lang}:' + hash_bytes(normalized)
		}
		BlockquoteNode {
			return 'quote:' + hash_bytes(normalized)
		}
		ListNode {
			return 'list:' + hash_bytes(normalized)
		}
		HorizontalRuleNode {
			return 'hr:' + hash_bytes(normalized)
		}
		MetaNode {
			return 'meta:' + hash_bytes(normalized)
		}
	}
}

pub fn (node BlockNode) semantic_encode() []u8 {
	return node.normalized_bytes()
}

pub fn (item ListItemNode) semantic_encode() []u8 {
	return item.normalized_bytes()
}

pub fn (node InlineNode) semantic_encode() []u8 {
	return node.normalized_bytes()
}

pub fn (doc Document) str() string {
	mut sb := strings.new_builder(256)
	sb.write_string('Document{\n')
	for child in doc.children {
		sb.write_string('  ${child.stable_id()}\n')
	}
	sb.write_string('}')
	return sb.str()
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
		HeadingNode, ParagraphNode, CodeBlockNode, HorizontalRuleNode, MetaNode {}
		BlockquoteNode {
			for child_index, child in node.children {
				c.collect_block(child, '${path}.children[${child_index}]', child_index)
				refs << child.stable_id()
			}
		}
		ListNode {
			for item_index, item in node.items {
				for child_index, child in item.children {
					c.collect_block(child, '${path}.items[${item_index}].children[${child_index}]',
						child_index)
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

const document_type_tag = u8(0x00)
const heading_type_tag = u8(0x01)
const paragraph_type_tag = u8(0x02)
const list_type_tag = u8(0x03)
const meta_type_tag = u8(0x04)
const blockquote_type_tag = u8(0x05)
const code_block_type_tag = u8(0x06)
const horizontal_rule_type_tag = u8(0x07)
const list_item_type_tag = u8(0x10)
const text_type_tag = u8(0x20)
const emphasis_type_tag = u8(0x21)
const strong_type_tag = u8(0x22)
const code_span_type_tag = u8(0x23)
const link_type_tag = u8(0x24)
const image_type_tag = u8(0x25)

pub fn (doc Document) binary_encode() []u8 {
	mut body := []u8{}
	for child in doc.children {
		body << child.binary_encode()
	}
	mut out := [document_type_tag]
	out << encode_varint(body.len)
	out << body
	return out
}

pub fn (node BlockNode) binary_encode() []u8 {
	match node {
		HeadingNode {
			content := encode_inline_sequence(node.children)
			mut out := [heading_type_tag, u8(node.level & 0xff)]
			out << encode_varint(content.len)
			out << content
			return out
		}
		ParagraphNode {
			content := encode_inline_sequence(node.children)
			mut out := [paragraph_type_tag]
			out << encode_varint(content.len)
			out << content
			return out
		}
		ListNode {
			mut out := [list_type_tag, bool_u8(node.is_ordered)]
			out << encode_u16(u16(node.items.len))
			out << encode_u16(u16(node.start))
			for item in node.items {
				item_bytes := item.binary_encode()
				out << encode_varint(item_bytes.len)
				out << item_bytes
			}
			return out
		}
		MetaNode {
			mut keys := node.data.keys()
			keys.sort()
			mut out := [meta_type_tag]
			out << encode_u16(u16(keys.len))
			for key in keys {
				key_bytes := normalize_text(key).bytes()
				value_bytes := normalize_text(node.data[key]).bytes()
				out << encode_varint(key_bytes.len)
				out << key_bytes
				out << encode_varint(value_bytes.len)
				out << value_bytes
			}
			return out
		}
		BlockquoteNode {
			mut body := []u8{}
			for child in node.children {
				body << child.binary_encode()
			}
			mut out := [blockquote_type_tag]
			out << encode_varint(body.len)
			out << body
			return out
		}
		CodeBlockNode {
			lang_bytes := normalize_text(node.lang).bytes()
			content_bytes := normalize_code(node.content).bytes()
			mut out := [code_block_type_tag]
			out << encode_varint(lang_bytes.len)
			out << lang_bytes
			out << encode_varint(content_bytes.len)
			out << content_bytes
			return out
		}
		HorizontalRuleNode {
			return [horizontal_rule_type_tag]
		}
	}
}

pub fn (item ListItemNode) binary_encode() []u8 {
	mut body := []u8{}
	for child in item.children {
		child_bytes := child.binary_encode()
		body << encode_varint(child_bytes.len)
		body << child_bytes
	}
	mut out := [list_item_type_tag]
	out << encode_u16(u16(item.level))
	out << encode_u16(u16(item.number))
	out << encode_varint(body.len)
	out << body
	return out
}

pub fn (node InlineNode) binary_encode() []u8 {
	match node {
		TextNode {
			data := normalize_text(node.text).bytes()
			mut out := [text_type_tag]
			out << encode_varint(data.len)
			out << data
			return out
		}
		EmphasisNode {
			content := encode_inline_sequence(node.children)
			mut out := [emphasis_type_tag]
			out << encode_varint(content.len)
			out << content
			return out
		}
		StrongNode {
			content := encode_inline_sequence(node.children)
			mut out := [strong_type_tag]
			out << encode_varint(content.len)
			out << content
			return out
		}
		CodeSpanNode {
			data := normalize_code(node.text).bytes()
			mut out := [code_span_type_tag]
			out << encode_varint(data.len)
			out << data
			return out
		}
		LinkNode {
			url_bytes := normalize_text(node.url).bytes()
			text_bytes := encode_inline_sequence(node.text)
			mut out := [link_type_tag]
			out << encode_varint(url_bytes.len)
			out << url_bytes
			out << encode_varint(text_bytes.len)
			out << text_bytes
			return out
		}
		ImageNode {
			url_bytes := normalize_text(node.url).bytes()
			alt_bytes := encode_inline_sequence(node.alt)
			mut out := [image_type_tag]
			out << encode_varint(url_bytes.len)
			out << url_bytes
			out << encode_varint(alt_bytes.len)
			out << alt_bytes
			return out
		}
	}
}

fn encode_inline_sequence(nodes []InlineNode) []u8 {
	mut out := []u8{}
	for node in nodes {
		child := node.binary_encode()
		out << child
	}
	return out
}

fn encode_u16(value u16) []u8 {
	return [u8(value & 0xff), u8((value >> 8) & 0xff)]
}

fn encode_varint(value int) []u8 {
	mut n := u64(value)
	mut out := []u8{}
	for {
		mut b := u8(n & 0x7f)
		n >>= 7
		if n != 0 {
			b |= 0x80
		}
		out << b
		if n == 0 {
			break
		}
	}
	return out
}

fn bool_u8(value bool) u8 {
	return if value { u8(1) } else { u8(0) }
}

fn (doc Document) normalized_bytes() []u8 {
	mut out := []u8{}
	for child in doc.children {
		out << child.stable_id().bytes()
		out << [u8(`\n`)]
	}
	return out
}

fn (node BlockNode) normalized_bytes() []u8 {
	match node {
		HeadingNode {
			mut out := []u8{}
			out << 'heading:'.bytes()
			out << node.level.str().bytes()
			out << [u8(`:`)]
			for child in node.children {
				out << child.normalized_bytes()
			}
			return out
		}
		ParagraphNode {
			mut out := 'paragraph:'.bytes()
			for child in node.children {
				out << child.normalized_bytes()
			}
			return out
		}
		BlockquoteNode {
			mut out := 'blockquote:'.bytes()
			for child in node.children {
				out << child.stable_id().bytes()
				out << [u8(`,`)]
			}
			return out
		}
		ListNode {
			mut out := 'list:'.bytes()
			out << bool_byte(node.is_ordered)
			out << node.start.str().bytes()
			out << [u8(`:`)]
			for item in node.items {
				out << item.normalized_bytes()
				out << [u8(`|`)]
			}
			return out
		}
		CodeBlockNode {
			mut out := 'code:'.bytes()
			out << normalize_text(node.lang).bytes()
			out << [u8(`:`)]
			out << normalize_code(node.content).bytes()
			return out
		}
		HorizontalRuleNode {
			return 'hr'.bytes()
		}
		MetaNode {
			mut keys := node.data.keys()
			keys.sort()
			mut out := 'meta:'.bytes()
			for key in keys {
				out << normalize_text(key).bytes()
				out << [u8(`=`)]
				out << normalize_text(node.data[key]).bytes()
				out << [u8(`;`)]
			}
			return out
		}
	}
}

fn (item ListItemNode) normalized_bytes() []u8 {
	mut out := 'item:'.bytes()
	out << item.level.str().bytes()
	out << [u8(`:`)]
	out << item.number.str().bytes()
	out << [u8(`:`)]
	for child in item.children {
		out << child.stable_id().bytes()
		out << [u8(`,`)]
	}
	return out
}

fn (node InlineNode) normalized_bytes() []u8 {
	match node {
		TextNode {
			mut out := 'text:'.bytes()
			out << normalize_text(node.text).bytes()
			return out
		}
		EmphasisNode {
			mut out := 'em:'.bytes()
			for child in node.children {
				out << child.normalized_bytes()
			}
			return out
		}
		StrongNode {
			mut out := 'strong:'.bytes()
			for child in node.children {
				out << child.normalized_bytes()
			}
			return out
		}
		CodeSpanNode {
			mut out := 'codespan:'.bytes()
			out << normalize_code(node.text).bytes()
			return out
		}
		LinkNode {
			mut out := 'link:'.bytes()
			out << normalize_text(node.url).bytes()
			out << [u8(`:`)]
			for child in node.text {
				out << child.normalized_bytes()
			}
			return out
		}
		ImageNode {
			mut out := 'image:'.bytes()
			out << normalize_text(node.url).bytes()
			out << [u8(`:`)]
			for child in node.alt {
				out << child.normalized_bytes()
			}
			return out
		}
	}
}

fn (node BlockNode) kind_name() string {
	match node {
		HeadingNode { return 'heading' }
		ParagraphNode { return 'paragraph' }
		BlockquoteNode { return 'blockquote' }
		ListNode { return 'list' }
		CodeBlockNode { return 'code_block' }
		HorizontalRuleNode { return 'horizontal_rule' }
		MetaNode { return 'meta' }
	}
}

fn normalize_text(input string) string {
	mut sb := strings.new_builder(input.len)
	mut last_space := false
	for r in input.runes() {
		if is_space_rune(r) {
			if !last_space {
				sb.write_rune(` `)
				last_space = true
			}
			continue
		}
		sb.write_rune(r)
		last_space = false
	}
	return sb.str().trim_space()
}

fn is_space_rune(r rune) bool {
	return r == ` ` || r == `\t` || r == `\n` || r == `\r` || r == `\v` || r == `\f`
}

fn normalize_code(input string) string {
	return input.replace('\r\n', '\n').replace('\r', '\n')
}

fn bool_byte(value bool) []u8 {
	return if value { [u8(`1`)] } else { [u8(`0`)] }
}

fn diff_root_refs(previous []string, current []string) []string {
	mut previous_set := map[string]bool{}
	for id in previous {
		previous_set[id] = true
	}
	mut changed := []string{}
	for id in current {
		if id !in previous_set {
			changed << id
		}
	}
	return changed
}

fn diff_entries(previous []BlockManifestEntry, current []BlockManifestEntry, index map[string]Chunk) []DiffEntry {
	mut previous_by_path := map[string]BlockManifestEntry{}
	mut current_by_path := map[string]BlockManifestEntry{}
	for entry in previous {
		previous_by_path[entry.path] = entry
	}
	for entry in current {
		current_by_path[entry.path] = entry
	}
	mut diff := []DiffEntry{}
	for entry in current {
		if entry.path in previous_by_path {
			previous_entry := previous_by_path[entry.path]
			if previous_entry.id == entry.id {
				diff << DiffEntry{
					op: .reused
					id: entry.id
					kind: chunk_kind(index, entry.id)
					path: entry.path
					current_index: entry.index
					previous_index: previous_entry.index
				}
			} else {
				diff << DiffEntry{
					op: .removed
					id: previous_entry.id
					kind: previous_entry.kind
					path: previous_entry.path
					previous_index: previous_entry.index
				}
				diff << DiffEntry{
					op: .added
					id: entry.id
					kind: chunk_kind(index, entry.id)
					path: entry.path
					current_index: entry.index
				}
			}
		} else {
			diff << DiffEntry{
				op: .added
				id: entry.id
				kind: chunk_kind(index, entry.id)
				path: entry.path
				current_index: entry.index
			}
		}
	}
	for entry in previous {
		if entry.path !in current_by_path {
			diff << DiffEntry{
				op: .removed
				id: entry.id
				kind: entry.kind
				path: entry.path
				previous_index: entry.index
			}
		}
	}
	return diff
}

fn filter_diff(entries []DiffEntry, op DiffOp) []DiffEntry {
	mut filtered := []DiffEntry{}
	for entry in entries {
		if entry.op == op {
			filtered << entry
		}
	}
	return filtered
}

fn build_diff_summary(entries []DiffEntry) DiffSummary {
	return DiffSummary{
		added: summarize_entries(entries, .added)
		removed: summarize_entries(entries, .removed)
		reused: summarize_entries(entries, .reused)
		lines: summary_lines(entries)
	}
}

fn summarize_entries(entries []DiffEntry, op DiffOp) []DiffSummaryItem {
	mut grouped := map[string]DiffSummaryItem{}
	mut order := []string{}
	for entry in entries {
		if entry.op != op {
			continue
		}
		key := entry.kind
		if key !in grouped {
			grouped[key] = DiffSummaryItem{
				op: op
				kind: entry.kind
				count: 0
				paths: []string{}
			}
			order << key
		}
		mut item := grouped[key]
		item.count++
		item.paths << entry.path
		grouped[key] = item
	}
	mut summary := []DiffSummaryItem{}
	for key in order {
		summary << grouped[key]
	}
	return summary
}

fn summary_lines(entries []DiffEntry) []string {
	mut lines := []string{}
	for entry in entries {
		lines << diff_line(entry)
	}
	return lines
}

fn diff_line(entry DiffEntry) string {
	verb := match entry.op {
		.added { 'added' }
		.removed { 'removed' }
		.reused { 'reused' }
	}
	return '${verb} ${entry.kind} at ${entry.path}'
}

fn index_chunks(chunks []Chunk) map[string]Chunk {
	mut index := map[string]Chunk{}
	for chunk in chunks {
		index[chunk.id] = chunk
	}
	return index
}

fn chunk_kind(index map[string]Chunk, id string) string {
	if id in index {
		return index[id].kind
	}
	return kind_from_id(id)
}

fn kind_from_id(id string) string {
	if id.starts_with('h') {
		return 'heading'
	}
	if id.starts_with('para:') {
		return 'paragraph'
	}
	if id.starts_with('code:') {
		return 'code_block'
	}
	if id.starts_with('quote:') {
		return 'blockquote'
	}
	if id.starts_with('list:') {
		return 'list'
	}
	if id.starts_with('hr:') {
		return 'horizontal_rule'
	}
	if id.starts_with('meta:') {
		return 'meta'
	}
	if id.starts_with('doc:') {
		return 'document'
	}
	return 'unknown'
}

fn hash_bytes(data []u8) string {
	digest := sha256.sum256(data)
	return digest.hex()
}
