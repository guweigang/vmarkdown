module vmarkdown

// Ingest manifest diffing and summaries.

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
	mut previous_matches := []int{len: current.len, init: -1}
	mut previous_used := []bool{len: previous.len}
	mut previous_by_identity := map[string][]int{}
	for previous_index, entry in previous {
		key := manifest_identity(entry)
		mut positions := previous_by_identity[key]
		positions << previous_index
		previous_by_identity[key] = positions
	}
	mut identity_offsets := map[string]int{}
	// Align equal content in occurrence order. This is deterministic for duplicate IDs and means a
	// leading insertion does not make every following block look removed and added.
	for current_index, entry in current {
		key := manifest_identity(entry)
		positions := previous_by_identity[key]
		offset := identity_offsets[key]
		if offset < positions.len {
			previous_index := positions[offset]
			previous_matches[current_index] = previous_index
			previous_used[previous_index] = true
			identity_offsets[key] = offset + 1
		}
	}
	in_order := manifest_in_order_matches(previous_matches)
	mut diff := []DiffEntry{}
	for current_index, entry in current {
		previous_index := previous_matches[current_index]
		if previous_index >= 0 {
			previous_entry := previous[previous_index]
			diff << DiffEntry{
				op: if in_order[current_index] { .reused } else { .moved }
				id: entry.id
				kind: chunk_kind(index, entry.id)
				path: entry.path
				previous_path: previous_entry.path
				current_index: entry.index
				previous_index: previous_entry.index
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
	for previous_index, entry in previous {
		if !previous_used[previous_index] {
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

fn manifest_identity(entry BlockManifestEntry) string {
	return '${entry.kind}\x00${entry.id}'
}

// Occurrence matching turns the common subsequence problem into an LIS over previous positions.
// Items in the LIS kept their relative order even if an insertion changed their numeric paths.
fn manifest_in_order_matches(previous_matches []int) []bool {
	mut sequence := []int{}
	mut current_indices := []int{}
	for current_index, previous_index in previous_matches {
		if previous_index >= 0 {
			sequence << previous_index
			current_indices << current_index
		}
	}
	mut result := []bool{len: previous_matches.len}
	if sequence.len == 0 {
		return result
	}
	mut tails := []int{}
	mut links := []int{len: sequence.len, init: -1}
	for sequence_index, value in sequence {
		mut low := 0
		mut high := tails.len
		for low < high {
			middle := (low + high) / 2
			if sequence[tails[middle]] < value {
				low = middle + 1
			} else {
				high = middle
			}
		}
		if low > 0 {
			links[sequence_index] = tails[low - 1]
		}
		if low == tails.len {
			tails << sequence_index
		} else {
			tails[low] = sequence_index
		}
	}
	mut cursor := tails[tails.len - 1]
	for cursor >= 0 {
		result[current_indices[cursor]] = true
		cursor = links[cursor]
	}
	return result
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
		moved: summarize_entries(entries, .moved)
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
	if entry.op == .moved {
		return 'moved ${entry.kind} from ${entry.previous_path} to ${entry.path}'
	}
	verb := match entry.op {
		.added { 'added' }
		.removed { 'removed' }
		.reused { 'reused' }
		.moved { 'moved' }
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
