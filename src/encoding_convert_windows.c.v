module vmarkdown

#include <windows.h>

const windows_cp_utf8 = u32(65001)
const windows_cp_gbk = u32(936)
const windows_cp_gb18030 = u32(54936)
const windows_mb_err_invalid_chars = u32(0x00000008)
const windows_wc_err_invalid_chars = u32(0x00000080)

fn C.MultiByteToWideChar(codepage u32, flags u32, src &u8, src_len int, dst &u8, dst_len int) int

fn C.WideCharToMultiByte(codepage u32, flags u32, src &u8, src_len int, dst &u8, dst_len int, default_char &u8, used_default_char &bool) int

fn decode_text_encoding(bytes []u8, encoding MarkdownEncoding) !string {
	return match encoding {
		.gbk { windows_decode_code_page(bytes, windows_cp_gbk, encoding.label())! }
		.gb18030 { windows_decode_code_page(bytes, windows_cp_gb18030, encoding.label())! }
		.utf16_le { windows_wide_to_utf8(bytes, encoding.label())! }
		.utf16_be { windows_wide_to_utf8(swap_u16_bytes(bytes)!, encoding.label())! }
		.utf32_le { decode_utf32(bytes, true)! }
		.utf32_be { decode_utf32(bytes, false)! }
		.utf8 {
			return error('UTF-8 does not require platform conversion')
		}
	}
}

fn encode_text_encoding(text string, encoding MarkdownEncoding) ![]u8 {
	return match encoding {
		.gbk { windows_encode_code_page(text, windows_cp_gbk, encoding.label())! }
		.gb18030 { windows_encode_code_page(text, windows_cp_gb18030, encoding.label())! }
		.utf16_le { windows_utf8_to_wide(text)! }
		.utf16_be { swap_u16_bytes(windows_utf8_to_wide(text)!)! }
		.utf32_le { encode_utf32(text, true) }
		.utf32_be { encode_utf32(text, false) }
		.utf8 {
			return error('UTF-8 does not require platform conversion')
		}
	}
}

fn windows_decode_code_page(bytes []u8, code_page u32, label string) !string {
	if bytes.len == 0 {
		return ''
	}
	wide_len := C.MultiByteToWideChar(code_page, windows_mb_err_invalid_chars, bytes.data, bytes.len, 0, 0)
	if wide_len <= 0 {
		return error('file is not valid ${label}')
	}
	mut wide := []u8{len: wide_len * 2}
	if C.MultiByteToWideChar(code_page, windows_mb_err_invalid_chars, bytes.data, bytes.len, wide.data, wide_len) != wide_len {
		return error('file is not valid ${label}')
	}
	return windows_wide_to_utf8(wide, label)
}

fn windows_encode_code_page(text string, code_page u32, label string) ![]u8 {
	wide := windows_utf8_to_wide(text)!
	if wide.len == 0 {
		return []u8{}
	}
	// Win32 requires both default-character parameters to be NULL for
	// GB18030. Strictness is still enforced by the round-trip byte check in
	// decode_markdown_as/encode_markdown_text.
	if code_page == windows_cp_gb18030 {
		encoded_len := C.WideCharToMultiByte(code_page, 0, wide.data, wide.len / 2, 0, 0, 0, 0)
		if encoded_len <= 0 {
			return error('text cannot be represented as ${label}')
		}
		mut encoded := []u8{len: encoded_len}
		if C.WideCharToMultiByte(code_page, 0, wide.data, wide.len / 2, encoded.data, encoded.len, 0, 0) != encoded_len {
			return error('text cannot be represented as ${label}')
		}
		return encoded
	}
	mut used_default := false
	encoded_len := C.WideCharToMultiByte(code_page, 0, wide.data, wide.len / 2, 0, 0, 0, &used_default)
	if encoded_len <= 0 || used_default {
		return error('text cannot be represented as ${label}')
	}
	mut encoded := []u8{len: encoded_len}
	used_default = false
	if C.WideCharToMultiByte(code_page, 0, wide.data, wide.len / 2, encoded.data, encoded.len, 0, &used_default) != encoded_len
		|| used_default {
		return error('text cannot be represented as ${label}')
	}
	return encoded
}

fn windows_utf8_to_wide(text string) ![]u8 {
	if text.len == 0 {
		return []u8{}
	}
	wide_len := C.MultiByteToWideChar(windows_cp_utf8, windows_mb_err_invalid_chars, text.str, text.len, 0, 0)
	if wide_len <= 0 {
		return error('text is not valid UTF-8')
	}
	mut wide := []u8{len: wide_len * 2}
	if C.MultiByteToWideChar(windows_cp_utf8, windows_mb_err_invalid_chars, text.str, text.len, wide.data, wide_len) != wide_len {
		return error('text is not valid UTF-8')
	}
	return wide
}

fn windows_wide_to_utf8(wide []u8, label string) !string {
	if wide.len == 0 {
		return ''
	}
	if wide.len % 2 != 0 {
		return error('file is not valid ${label}')
	}
	utf8_len := C.WideCharToMultiByte(windows_cp_utf8, windows_wc_err_invalid_chars, wide.data, wide.len / 2, 0, 0, 0, 0)
	if utf8_len <= 0 {
		return error('file is not valid ${label}')
	}
	mut utf8 := []u8{len: utf8_len}
	if C.WideCharToMultiByte(windows_cp_utf8, windows_wc_err_invalid_chars, wide.data, wide.len / 2, utf8.data, utf8.len, 0, 0) != utf8_len {
		return error('file is not valid ${label}')
	}
	return utf8.bytestr()
}

fn swap_u16_bytes(bytes []u8) ![]u8 {
	if bytes.len % 2 != 0 {
		return error('UTF-16 input has an odd byte count')
	}
	mut swapped := bytes.clone()
	for i := 0; i < swapped.len; i += 2 {
		swapped[i], swapped[i + 1] = swapped[i + 1], swapped[i]
	}
	return swapped
}

fn decode_utf32(bytes []u8, little_endian bool) !string {
	if bytes.len % 4 != 0 {
		return error('UTF-32 input byte count is not divisible by four')
	}
	mut runes := []rune{cap: bytes.len / 4}
	for i := 0; i < bytes.len; i += 4 {
		value := if little_endian {
			u32(bytes[i]) | (u32(bytes[i + 1]) << 8) | (u32(bytes[i + 2]) << 16) | (u32(bytes[i + 3]) << 24)
		} else {
			(u32(bytes[i]) << 24) | (u32(bytes[i + 1]) << 16) | (u32(bytes[i + 2]) << 8) | u32(bytes[i + 3])
		}
		if value > 0x10ffff || (value >= 0xd800 && value <= 0xdfff) {
			return error('file contains an invalid UTF-32 code point')
		}
		runes << rune(value)
	}
	return runes.string()
}

fn encode_utf32(text string, little_endian bool) []u8 {
	mut bytes := []u8{cap: text.runes().len * 4}
	for character in text.runes() {
		value := u32(character)
		if little_endian {
			bytes << u8(value)
			bytes << u8(value >> 8)
			bytes << u8(value >> 16)
			bytes << u8(value >> 24)
		} else {
			bytes << u8(value >> 24)
			bytes << u8(value >> 16)
			bytes << u8(value >> 8)
			bytes << u8(value)
		}
	}
	return bytes
}
