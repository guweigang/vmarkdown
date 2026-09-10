module vmarkdown

fn test_markdown_encoding_auto_detects_utf8_and_gbk() {
	utf8_file := decode_markdown_bytes('# 中文\n'.bytes(), 'auto') or { panic(err) }
	assert utf8_file.encoding == .utf8
	assert utf8_file.text == '# 中文\n'

	gbk_file := decode_markdown_bytes([u8(0x23), 0x20, 0xd6, 0xd0, 0xce, 0xc4, 0x0a], 'auto') or {
		panic(err)
	}
	assert gbk_file.encoding == .gbk
	assert gbk_file.text == '# 中文\n'
}

fn test_markdown_encoding_detects_and_preserves_bom() {
	file := decode_markdown_bytes([u8(0xff), 0xfe, 0x23, 0x00, 0x20, 0x00, 0x41, 0x00], 'auto') or {
		panic(err)
	}
	assert file.encoding == .utf16_le
	assert file.bom
	assert file.text == '# A'
	assert encode_markdown_text(file.text, file.encoding, file.bom) or { panic(err) } == [
		u8(0xff),
		0xfe,
		0x23,
		0x00,
		0x20,
		0x00,
		0x41,
		0x00,
	]
}

fn test_markdown_encoding_auto_detects_gb18030_four_byte_character() {
	text := 'x' + rune(0x80).str() + 'y'
	encoded := encode_markdown_text(text, .gb18030, false) or { panic(err) }
	file := decode_markdown_bytes(encoded, 'auto') or { panic(err) }
	assert file.encoding == .gb18030
	assert file.text == text
}

fn test_markdown_encoding_detects_and_preserves_utf32_bom() {
	for encoding in [MarkdownEncoding.utf32_le, .utf32_be] {
		encoded := encode_markdown_text('# 中文', encoding, true) or { panic(err) }
		file := decode_markdown_bytes(encoded, 'auto') or { panic(err) }
		assert file.encoding == encoding
		assert file.bom
		assert file.text == '# 中文'
		assert encode_markdown_text(file.text, file.encoding, file.bom) or { panic(err) } == encoded
	}
}

fn test_markdown_encoding_override_and_unrepresentable_save() {
	file := decode_markdown_bytes([u8(0xd6), 0xd0, 0xce, 0xc4], 'cp936') or { panic(err) }
	assert file.encoding == .gbk
	assert file.text == '中文'
	if encoded := encode_markdown_text('中文😀', .gbk, false) {
		assert false, 'GBK unexpectedly encoded ${encoded}'
	} else {
		assert err.msg().contains('cannot be represented')
	}
}

fn test_markdown_encoding_rejects_unknown_override() {
	if decoded := decode_markdown_bytes('text'.bytes(), 'shift-jis') {
		assert false, 'unexpected decode: ${decoded}'
	} else {
		assert err.msg().contains('unsupported')
	}
}
