# VMDA binary format v1

The binary codec is a deterministic, content-oriented representation of the
vmarkdown AST. It is not a memory dump and it never includes `SourceSpan`:
source positions describe one parse location and must not change content IDs.

Every document starts with the ASCII magic `VMDA`, followed by version byte
`0x01`, the document tag `0x00`, a canonical unsigned LEB128 payload length,
and the block sequence. Integers, counts, and byte lengths are canonical
unsigned LEB128 values; negative values cannot be encoded. Strings are UTF-8.
Within each inline sequence, whitespace runs in text nodes collapse to one ASCII
space. Only whitespace at the two outer boundaries of the complete sequence is
trimmed; a space between text and another inline record remains significant.

Block tags are `01` heading, `02` paragraph, `03` list, `04` metadata, `05`
blockquote, `06` code block, `07` horizontal rule, `08` table, and `09` raw
HTML block. List items use framed tag `10`.

Inline tags are `20` text, `21` emphasis, `22` strong, `23` code span, `24`
link, `25` image, `26` strikethrough, `27` soft break, `28` hard break, `29`
raw inline HTML, `2a` wiki link, `2b` LaTeX math, and `2c` underline.
Variable-size nested records carry a byte length so a decoder can reject
truncation and framing errors.

## Record layouts

In the layouts below, `varint` is canonical unsigned LEB128, `bool` is exactly
`00` or `01`, and `bytes` is raw UTF-8 preceded by its byte length. A framed
sequence is a varint byte length followed by concatenated records whose total
size must exactly match that length.

| Tag | Record after tag |
| --- | --- |
| `00` document | `framed block sequence` (after the magic and version) |
| `01` heading | `level:u8, framed inline sequence` |
| `02` paragraph | `framed inline sequence` |
| `03` list | `ordered:bool, item_count:varint, start:varint, repeated framed list items` |
| `04` metadata | `pair_count:varint, repeated key:bytes + value:bytes in sorted-key order` |
| `05` blockquote | `framed block sequence` |
| `06` code block | `language:bytes, content:bytes` |
| `07` horizontal rule | no payload |
| `08` table | `columns:varint, head_rows:varint, body_rows:varint, repeated framed rows` |
| `09` raw HTML block | `html:bytes` |
| `10` list item | `level:varint, number:varint, task:bool, checked:bool, framed length-prefixed blocks` |
| `20` text | `text:bytes` |
| `21` emphasis | `framed inline sequence` |
| `22` strong | `framed inline sequence` |
| `23` code span | `text:bytes` |
| `24` link | `url:bytes, framed inline label` |
| `25` image | `url:bytes, framed inline alt text` |
| `26` strikethrough | `framed inline sequence` |
| `27` soft break | no payload |
| `28` hard break | no payload |
| `29` raw inline HTML | `html:bytes` |
| `2a` wiki link | `target:bytes, framed inline label` |
| `2b` LaTeX math | `display:bool, content:bytes` |
| `2c` underline | `framed inline sequence` |

A table row is `cell_count:varint` followed by cells. Each cell is
`alignment:u8` plus a framed inline sequence. Alignment values are `00`
default, `01` left, `02` center, and `03` right.

The byte-for-byte golden fixtures in `src/binary_codec_test.v` cover every v1
tag, both LaTeX math flag values, and significant whitespace between inline
records. Changing any fixture requires either
demonstrating that the implementation had violated this document or assigning
a new format version; synchronized encoder/decoder changes alone are not
sufficient.

The original v1 encoder trimmed every text record independently. That could
erase significant spaces between inline records, produce empty text records
that the v1 decoder correctly rejected, and give spaced and unspaced documents
the same ID. Treating only the complete inline sequence boundaries as trim
boundaries corrects that v1 implementation bug. Stable IDs produced by the
buggy encoder for affected documents are intentionally replaced.

The v1 decoder rejects incorrect magic or versions, non-canonical or
overflowing varints, invalid UTF-8, unknown tags, invalid flags/enums,
truncation, trailing bytes, non-normalized text, non-canonical metadata order,
and documents beyond its published size, depth, or node-count limits. After
structural and semantic validation, it re-encodes the AST and requires an exact
byte match so every accepted v1 document has one canonical representation.

The public decoder defaults to 64 MiB of input, one million decoded AST nodes,
and 256 nesting levels. `binary_decode_with_limits()` can tighten or explicitly
remove those budgets without changing the v1 bytes. The node count includes the
root document. The reconstructed document passes the format-independent AST
validator with the caller's same node and depth budgets before it is returned.

After framing is decoded, the document must also satisfy the public AST
validation contract. In particular, headings use levels 1 through 6; list
levels, numbers, starts, and task state are canonical; tables have one header
row and a consistent positive column count; normalized metadata keys are
unique; inline containers are structurally renderable; and source-span fields
are either valid half-open ranges or unavailable negative ranges. Decoded v1
documents do not carry source spans and therefore use unavailable ranges.
