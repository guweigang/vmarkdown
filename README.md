# vmarkdown

`vmarkdown` is a V wrapper around [md4c](https://github.com/mity/md4c) that builds a typed Markdown AST instead of only streaming HTML.

## Why this shape

The public AST follows the DSL direction from your sketch:

- `Document` owns `[]BlockNode`
- `BlockNode` is a V `sum type`
- `InlineNode` is a V `sum type`

One deliberate adjustment was made for production parsing: `ListItemNode.children` uses `[]BlockNode` instead of `[]InlineNode`. `md4c` can emit multi-block list items, nested lists, and paragraphs inside a single list item, so this keeps the AST lossless.

## Layout

- `vmarkdown/ast.v`: AST types
- `vmarkdown/parser.v`: md4c-backed parser and event builder
- `vmarkdown/serialize.v`: normalized stable IDs, chunk collection, and in-memory incremental ingest
- `vmarkdown/render.v`: HTML, plain-text, and JSON renderers
- `vmarkdown/c/md4c_bridge.c`: thin callback adapter
- `thirdparty/md4c`: vendored upstream parser

## Quick Start

```v
import vmarkdown

doc := vmarkdown.parse('# hello\n\nworld')!
println(doc.stable_id())
```

Run the bundled example with:

```sh
v run examples/basic.v
```

Rendering helpers:

```v
html := vmarkdown.render_html(markdown)!
text := vmarkdown.render_text(markdown)!
json := vmarkdown.render_json(markdown)!
```

AST pretty printing:

```v
doc := vmarkdown.parse(markdown)!
println(doc.pretty())
```

Example output:

```text
Document
├─ Heading(level=1) "PollyDB"
├─ Paragraph "A **structured** memory with a [link](https://example.com)."
├─ UnorderedList(start=1)
│  ├─ ListItem(level=1, number=0)
│  │  └─ Paragraph "first item"
│  └─ ListItem(level=1, number=0)
│     └─ Paragraph "second item"
└─ CodeBlock(lang="v") "println("hi")\n"
```

## Stable ID

There are now two encoding paths:

- `stable_id()` / `encode()`
  Uses the binary protocol intended for PollyDB-facing storage keys.
- `semantic_stable_id()` / `semantic_encode()`
  Uses the older normalized semantic byte stream and is kept for comparison/debugging.

The binary protocol follows the type-tagged layout direction from your DSL notes. Current block tags are:

- `HeadingNode`: `0x01` + `level (u8)` + `content_len (varint)` + encoded inline data
- `ParagraphNode`: `0x02` + `content_len (varint)` + encoded inline data
- `ListNode`: `0x03` + `is_ordered (u8)` + `item_count (u16)` + `start (u16)` + encoded items
- `MetaNode`: `0x04` + `kv_pairs_count (u16)` + encoded key/value pairs
- `BlockquoteNode`: `0x05` + `content_len (varint)` + encoded child blocks
- `CodeBlockNode`: `0x06` + `lang_len (varint)` + `lang` + `content_len (varint)` + `content`
- `HorizontalRuleNode`: `0x07`

Notes on stability:

- Plain text is normalized by collapsing repeated whitespace and trimming edges.
- Code text keeps internal spacing but normalizes newlines to `\n`.
- Structural changes change IDs.
- If the binary protocol changes in the future, previously computed `stable_id()` values will also change.

Incremental ingest is available through the in-memory store:

```v
mut store := vmarkdown.new_memory_store()
result := store.ingest(markdown)!
println(result.root_id)
println(result.added.len)
println(result.reused.len)
```

If you want PollyDB to own the final write path, you can split ingest into planning and commit:

```v
mut store := vmarkdown.new_memory_store()
plan := vmarkdown.plan_ingest(markdown, store)!
result := vmarkdown.commit_ingest_plan(mut store, plan)!
println(plan.to_add.len)
println(result.root_id)
```

The ingest plan also exposes a pure semantic diff for top-level blocks:

```v
plan := vmarkdown.plan_ingest(markdown, store)!
for entry in plan.diff {
	println('${entry.op} ${entry.path} ${entry.kind} ${entry.id}')
}

summary := plan.diff_summary()
for line in summary.lines {
	println(line)
}
```

Paths are recursive block paths, for example:

```text
blocks[0]
blocks[1].items[0].children[1]
```

When a nested structure changes, both the changed descendant and any affected ancestor containers can appear in the diff.

## Notes

- The parser currently targets the core node types from your DSL sketch.
- `MetaNode` is kept in the AST for your PollyDB layer, but it is not emitted by `md4c` directly.
- Raw HTML, tables, and some extended spans are not yet projected into dedicated V nodes.
