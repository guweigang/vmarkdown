module vmarkdown

fn test_markdown_editor_preserves_source_and_trailing_newline() {
	ed := new_markdown_editor('# Title\n\nBody\n')
	assert ed.text() == '# Title\n\nBody\n'
}

fn test_markdown_editor_inserts_unicode_and_splits_lines() {
	mut ed := new_markdown_editor('ab')
	ed.cursor_x = 1
	ed.insert_text('中文\nxy')
	assert ed.text() == 'a中文\nxyb'
	assert ed.cursor_y == 1
	assert ed.cursor_x == 2
}

fn test_markdown_editor_backspace_and_delete_join_lines() {
	mut ed := new_markdown_editor('one\ntwo')
	ed.cursor_y = 1
	ed.backspace()
	assert ed.text() == 'onetwo'
	assert ed.cursor_x == 3
	ed.cursor_x = 3
	ed.delete_forward()
	assert ed.text() == 'onewo'
}

fn test_markdown_editor_delete_line_undo_and_redo() {
	mut ed := new_markdown_editor('one\ntwo\nthree')
	ed.cursor_y = 1
	ed.delete_line()
	assert ed.text() == 'one\nthree'
	ed.undo()
	assert ed.text() == 'one\ntwo\nthree'
	ed.redo()
	assert ed.text() == 'one\nthree'
}

fn test_markdown_editor_word_movements() {
	mut ed := new_markdown_editor('one  two\nthree')
	ed.move_word_forward()
	assert ed.cursor_x == 5
	ed.move_word_forward()
	assert ed.cursor_y == 1
	assert ed.cursor_x == 0
	ed.move_word_backward()
	assert ed.cursor_y == 0
	assert ed.cursor_x == 5
}
