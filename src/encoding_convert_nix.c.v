module vmarkdown

import encoding.iconv

fn decode_text_encoding(bytes []u8, encoding MarkdownEncoding) !string {
	return iconv.encoding_to_vstring(bytes, encoding.label())
}

fn encode_text_encoding(text string, encoding MarkdownEncoding) ![]u8 {
	return iconv.vstring_to_encoding(text, encoding.label())
}
