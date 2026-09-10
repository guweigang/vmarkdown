module vmarkdown

import encoding.utf8.validate
import os

pub enum MarkdownEncoding {
	utf8
	utf16_le
	utf16_be
	utf32_le
	utf32_be
	gbk
	gb18030
}

pub fn (encoding MarkdownEncoding) label() string {
	return match encoding {
		.utf8 { 'UTF-8' }
		.utf16_le { 'UTF-16LE' }
		.utf16_be { 'UTF-16BE' }
		.utf32_le { 'UTF-32LE' }
		.utf32_be { 'UTF-32BE' }
		.gbk { 'GBK' }
		.gb18030 { 'GB18030' }
	}
}

pub struct MarkdownFile {
pub:
	text     string
	encoding MarkdownEncoding
	bom      bool
mut:
	raw []u8
}

pub fn read_markdown_file(path string) !MarkdownFile {
	return read_markdown_file_with_encoding(path, 'auto')
}

pub fn read_markdown_file_with_encoding(path string, requested_encoding string) !MarkdownFile {
	bytes := os.read_bytes(path)!
	return decode_markdown_bytes(bytes, requested_encoding)
}

pub fn decode_markdown_bytes(bytes []u8, requested_encoding string) !MarkdownFile {
	requested := requested_encoding.trim_space().to_lower().replace('_', '-').replace(' ', '')
	if requested.len > 0 && requested != 'auto' {
		encoding := markdown_encoding_from_name(requested)!
		payload, bom := strip_matching_bom(bytes, encoding)
		return decode_markdown_as(payload, encoding, bom, bytes)
	}
	if encoding := markdown_bom_encoding(bytes) {
		payload, _ := strip_matching_bom(bytes, encoding)
		return decode_markdown_as(payload, encoding, true, bytes)
	}
	raw := bytes.bytestr()
	if validate.utf8_string(raw) {
		return MarkdownFile{
			text:     raw
			encoding: .utf8
			raw:      bytes.clone()
		}
	}
	if decoded := decode_markdown_as(bytes, .gbk, false, bytes) {
		return decoded
	}
	if decoded := decode_markdown_as(bytes, .gb18030, false, bytes) {
		return decoded
	}
	return error('file is not valid UTF-8, GBK, or GB18030; use --encoding to specify its encoding')
}

pub fn encode_markdown_text(text string, encoding MarkdownEncoding, bom bool) ![]u8 {
	mut encoded := if encoding == .utf8 {
		if !validate.utf8_string(text) {
			return error('text is not valid UTF-8')
		}
		text.bytes()
	} else {
		encode_text_encoding(text, encoding) or {
			return error('text contains characters that cannot be represented as ${encoding.label()}; convert the file to UTF-8 before saving')
		}
	}
	decoded := if encoding == .utf8 {
		encoded.bytestr()
	} else {
		decode_text_encoding(encoded, encoding)!
	}
	if decoded != text {
		return error('text contains characters that cannot be represented as ${encoding.label()}; convert the file to UTF-8 before saving')
	}
	if bom {
		mut with_bom := markdown_bom(encoding)
		with_bom << encoded
		encoded = with_bom.clone()
	}
	return encoded
}

fn decode_markdown_as(payload []u8, encoding MarkdownEncoding, bom bool, original []u8) !MarkdownFile {
	text := if encoding == .utf8 {
		value := payload.bytestr()
		if !validate.utf8_string(value) {
			return error('file is not valid UTF-8')
		}
		value
	} else {
		decode_text_encoding(payload, encoding)!
	}
	// Win32 conversion can substitute invalid input instead of reporting an
	// error. Re-encoding makes detection and saving strict on every platform.
	round_trip := encode_markdown_text(text, encoding, false)!
	if round_trip != payload {
		return error('file is not valid ${encoding.label()}')
	}
	return MarkdownFile{
		text:     text
		encoding: encoding
		bom:      bom
		raw:      original.clone()
	}
}

fn markdown_encoding_from_name(name string) !MarkdownEncoding {
	return match name {
		'utf8', 'utf-8' { .utf8 }
		'utf16le', 'utf-16le' { .utf16_le }
		'utf16be', 'utf-16be' { .utf16_be }
		'utf32le', 'utf-32le' { .utf32_le }
		'utf32be', 'utf-32be' { .utf32_be }
		'gbk', 'cp936', 'windows-936', 'gb2312' { .gbk }
		'gb18030', 'cp54936' { .gb18030 }
		else { return error('unsupported Markdown encoding `${name}`') }
	}
}

fn markdown_bom_encoding(bytes []u8) ?MarkdownEncoding {
	if bytes_start_with(bytes, [u8(0xff), 0xfe, 0x00, 0x00]) {
		return .utf32_le
	}
	if bytes_start_with(bytes, [u8(0x00), 0x00, 0xfe, 0xff]) {
		return .utf32_be
	}
	if bytes_start_with(bytes, [u8(0xef), 0xbb, 0xbf]) {
		return .utf8
	}
	if bytes_start_with(bytes, [u8(0xff), 0xfe]) {
		return .utf16_le
	}
	if bytes_start_with(bytes, [u8(0xfe), 0xff]) {
		return .utf16_be
	}
	return none
}

fn strip_matching_bom(bytes []u8, encoding MarkdownEncoding) ([]u8, bool) {
	bom := markdown_bom(encoding)
	if bom.len > 0 && bytes_start_with(bytes, bom) {
		return bytes[bom.len..].clone(), true
	}
	return bytes.clone(), false
}

fn bytes_start_with(bytes []u8, prefix []u8) bool {
	if prefix.len > bytes.len {
		return false
	}
	return bytes[..prefix.len] == prefix
}

fn markdown_bom(encoding MarkdownEncoding) []u8 {
	return match encoding {
		.utf8 { [u8(0xef), 0xbb, 0xbf] }
		.utf16_le { [u8(0xff), 0xfe] }
		.utf16_be { [u8(0xfe), 0xff] }
		.utf32_le { [u8(0xff), 0xfe, 0x00, 0x00] }
		.utf32_be { [u8(0x00), 0x00, 0xfe, 0xff] }
		.gbk, .gb18030 { []u8{} }
	}
}
