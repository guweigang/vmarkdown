# VMDA binary format v1

The binary codec is a deterministic, content-oriented representation of the
vmarkdown AST. It is not a memory dump and it never includes `SourceSpan`:
source positions describe one parse location and must not change content IDs.

Every document starts with the ASCII magic `VMDA`, followed by version byte
`0x01`, the document tag `0x00`, a canonical unsigned LEB128 payload length,
and the block sequence. Integers, counts, and byte lengths are canonical
unsigned LEB128 values; negative values cannot be encoded. Strings are UTF-8.

Block tags are `01` heading, `02` paragraph, `03` list, `04` metadata, `05`
blockquote, `06` code block, `07` horizontal rule, `08` table, and `09` raw
HTML block. List items use framed tag `10`.

Inline tags are `20` text, `21` emphasis, `22` strong, `23` code span, `24`
link, `25` image, `26` strikethrough, `27` soft break, `28` hard break, and
`29` raw inline HTML. Variable-size nested records carry a byte length so a
decoder can reject truncation and framing errors.

The v1 decoder rejects incorrect magic or versions, non-canonical or
overflowing varints, invalid UTF-8, unknown tags, invalid flags/enums,
truncation, trailing bytes, and documents beyond its published size, depth,
or node-count limits.
