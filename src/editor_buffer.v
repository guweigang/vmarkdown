module vmarkdown

import encoding.utf8

const editor_undo_limit = 200

enum EditorMode {
	normal
	insert
	command
}

struct EditorSnapshot {
	text     string
	cursor_x int
	cursor_y int
}

// MarkdownEditor adapts the buffer/cursor approach from V's
// examples/term.ui/text_editor.v into a source-preserving, testable model.
struct MarkdownEditor {
mut:
	lines       []string
	saved_text  string
	cursor_x    int
	cursor_y    int
	mode        EditorMode
	command     string
	dirty       bool
	status      string
	pending_key string
	undo_stack  []EditorSnapshot
	redo_stack  []EditorSnapshot
}

fn new_markdown_editor(text string) MarkdownEditor {
	mut lines := text.split('\n')
	if lines.len == 0 {
		lines = ['']
	}
	return MarkdownEditor{
		lines:      lines
		saved_text: text
	}
}

fn (ed &MarkdownEditor) text() string {
	return ed.lines.join('\n')
}

fn (ed &MarkdownEditor) current_line() string {
	if ed.cursor_y < 0 || ed.cursor_y >= ed.lines.len {
		return ''
	}
	return ed.lines[ed.cursor_y]
}

fn (ed &MarkdownEditor) snapshot() EditorSnapshot {
	return EditorSnapshot{
		text:     ed.text()
		cursor_x: ed.cursor_x
		cursor_y: ed.cursor_y
	}
}

fn (mut ed MarkdownEditor) remember_change() {
	ed.undo_stack << ed.snapshot()
	if ed.undo_stack.len > editor_undo_limit {
		ed.undo_stack.delete(0)
	}
	ed.redo_stack.clear()
	ed.dirty = true
	ed.status = ''
}

fn (mut ed MarkdownEditor) restore(snapshot EditorSnapshot) {
	ed.lines = snapshot.text.split('\n')
	if ed.lines.len == 0 {
		ed.lines = ['']
	}
	ed.cursor_x = snapshot.cursor_x
	ed.cursor_y = snapshot.cursor_y
	ed.clamp_cursor()
}

fn (mut ed MarkdownEditor) undo() {
	if ed.undo_stack.len == 0 {
		ed.status = 'already at oldest change'
		return
	}
	ed.redo_stack << ed.snapshot()
	snapshot := ed.undo_stack.pop()
	ed.restore(snapshot)
	ed.dirty = ed.text() != ed.saved_text
	ed.status = 'undo'
}

fn (mut ed MarkdownEditor) redo() {
	if ed.redo_stack.len == 0 {
		ed.status = 'already at newest change'
		return
	}
	ed.undo_stack << ed.snapshot()
	snapshot := ed.redo_stack.pop()
	ed.restore(snapshot)
	ed.dirty = ed.text() != ed.saved_text
	ed.status = 'redo'
}

fn (mut ed MarkdownEditor) mark_saved() {
	ed.saved_text = ed.text()
	ed.dirty = false
	ed.status = 'written'
}

fn (mut ed MarkdownEditor) clamp_cursor() {
	if ed.lines.len == 0 {
		ed.lines = ['']
	}
	ed.cursor_y = min_int(max_int(ed.cursor_y, 0), ed.lines.len - 1)
	ed.cursor_x = min_int(max_int(ed.cursor_x, 0), ed.current_line().runes().len)
}

fn (mut ed MarkdownEditor) move_left() {
	if ed.cursor_x > 0 {
		ed.cursor_x--
	} else if ed.cursor_y > 0 {
		ed.cursor_y--
		ed.cursor_x = ed.current_line().runes().len
	}
}

fn (mut ed MarkdownEditor) move_right() {
	line_len := ed.current_line().runes().len
	if ed.cursor_x < line_len {
		ed.cursor_x++
	} else if ed.cursor_y + 1 < ed.lines.len {
		ed.cursor_y++
		ed.cursor_x = 0
	}
}

fn (mut ed MarkdownEditor) move_up() {
	if ed.cursor_y > 0 {
		ed.cursor_y--
		ed.cursor_x = min_int(ed.cursor_x, ed.current_line().runes().len)
	}
}

fn (mut ed MarkdownEditor) move_down() {
	if ed.cursor_y + 1 < ed.lines.len {
		ed.cursor_y++
		ed.cursor_x = min_int(ed.cursor_x, ed.current_line().runes().len)
	}
}

fn (mut ed MarkdownEditor) move_word_forward() {
	mut y := ed.cursor_y
	mut x := ed.cursor_x
	mut first_line := true
	for y < ed.lines.len {
		line := ed.lines[y].runes()
		for first_line && x < line.len && is_editor_word_rune(line[x]) {
			x++
		}
		for x < line.len && !is_editor_word_rune(line[x]) {
			x++
		}
		if x < line.len {
			ed.cursor_x = x
			ed.cursor_y = y
			return
		}
		y++
		x = 0
		first_line = false
	}
	ed.cursor_y = ed.lines.len - 1
	ed.cursor_x = ed.current_line().runes().len
}

fn (mut ed MarkdownEditor) move_word_backward() {
	mut y := ed.cursor_y
	mut x := ed.cursor_x
	if x == 0 && y > 0 {
		y--
		x = ed.lines[y].runes().len
	}
	for y >= 0 {
		line := ed.lines[y].runes()
		x = min_int(x, line.len)
		for x > 0 && !is_editor_word_rune(line[x - 1]) {
			x--
		}
		for x > 0 && is_editor_word_rune(line[x - 1]) {
			x--
		}
		if x < line.len || (x == 0 && line.len > 0) {
			ed.cursor_x = x
			ed.cursor_y = y
			return
		}
		y--
		if y >= 0 {
			x = ed.lines[y].runes().len
		}
	}
	ed.cursor_x = 0
	ed.cursor_y = 0
}

fn is_editor_word_rune(r rune) bool {
	return utf8.is_letter(r) || (r >= `0` && r <= `9`) || r == `_`
}

fn (mut ed MarkdownEditor) insert_text(text string) {
	if text.len == 0 {
		return
	}
	ed.remember_change()
	ed.insert_text_without_snapshot(text)
}

fn (mut ed MarkdownEditor) insert_text_without_snapshot(text string) {
	line := ed.current_line().runes()
	left := line[..ed.cursor_x].string()
	right := line[ed.cursor_x..].string()
	parts := text.split('\n')
	if parts.len == 1 {
		ed.lines[ed.cursor_y] = left + text + right
		ed.cursor_x += text.runes().len
		return
	}
	ed.lines[ed.cursor_y] = left + parts[0]
	mut inserted := []string{}
	if parts.len > 2 {
		inserted << parts[1..parts.len - 1]
	}
	inserted << parts[parts.len - 1] + right
	ed.lines.insert(ed.cursor_y + 1, inserted)
	ed.cursor_y += parts.len - 1
	ed.cursor_x = parts[parts.len - 1].runes().len
}

fn (mut ed MarkdownEditor) backspace() {
	if ed.cursor_x == 0 && ed.cursor_y == 0 {
		return
	}
	ed.remember_change()
	if ed.cursor_x > 0 {
		line := ed.current_line().runes()
		ed.lines[ed.cursor_y] = line[..ed.cursor_x - 1].string() + line[ed.cursor_x..].string()
		ed.cursor_x--
		return
	}
	previous_len := ed.lines[ed.cursor_y - 1].runes().len
	ed.lines[ed.cursor_y - 1] += ed.lines[ed.cursor_y]
	ed.lines.delete(ed.cursor_y)
	ed.cursor_y--
	ed.cursor_x = previous_len
}

fn (mut ed MarkdownEditor) delete_forward() {
	line := ed.current_line().runes()
	if ed.cursor_x >= line.len && ed.cursor_y + 1 >= ed.lines.len {
		return
	}
	ed.remember_change()
	if ed.cursor_x < line.len {
		ed.lines[ed.cursor_y] = line[..ed.cursor_x].string() + line[ed.cursor_x + 1..].string()
		return
	}
	ed.lines[ed.cursor_y] += ed.lines[ed.cursor_y + 1]
	ed.lines.delete(ed.cursor_y + 1)
}

fn (mut ed MarkdownEditor) delete_line() {
	ed.remember_change()
	if ed.lines.len == 1 {
		ed.lines[0] = ''
		ed.cursor_x = 0
		return
	}
	ed.lines.delete(ed.cursor_y)
	if ed.cursor_y >= ed.lines.len {
		ed.cursor_y = ed.lines.len - 1
	}
	ed.cursor_x = min_int(ed.cursor_x, ed.current_line().runes().len)
}

fn (mut ed MarkdownEditor) open_line_below() {
	ed.remember_change()
	ed.lines.insert(ed.cursor_y + 1, '')
	ed.cursor_y++
	ed.cursor_x = 0
	ed.mode = .insert
}

fn (mut ed MarkdownEditor) open_line_above() {
	ed.remember_change()
	ed.lines.insert(ed.cursor_y, '')
	ed.cursor_x = 0
	ed.mode = .insert
}
