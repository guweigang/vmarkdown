module vmarkdown

import strings

pub enum MarkdownDialect {
	commonmark
	gfm
}

pub struct ParseLimits {
pub:
	max_input_bytes   int = 64 * 1024 * 1024
	max_nodes         int = 1_000_000
	max_nesting_depth int = 256
}

pub struct ParseOptions {
pub:
	tables                    bool = true
	tasklists                 bool = true
	strikethrough             bool = true
	permissive_url_autolinks  bool = true
	permissive_www_autolinks  bool = true
	permissive_email_autolink bool = true
	wiki_links                bool
	latex_math                bool
	underline                 bool
	no_html_blocks            bool
	no_html_spans             bool
	no_indented_code_blocks   bool
}

pub fn parse(markdown string) !Document {
	return parse_with_options(markdown, ParseOptions{})
}

pub fn parse_with_dialect(markdown string, dialect MarkdownDialect) !Document {
	return parse_with_options(markdown, parse_options_for_dialect(dialect))
}

pub fn parse_options_for_dialect(dialect MarkdownDialect) ParseOptions {
	return match dialect {
		.commonmark {
			ParseOptions{
				tables: false
				tasklists: false
				strikethrough: false
				permissive_url_autolinks: false
				permissive_www_autolinks: false
				permissive_email_autolink: false
			}
		}
		.gfm { ParseOptions{} }
	}
}

pub fn parse_with_options(markdown string, options ParseOptions) !Document {
	return parse_with_limits(markdown, options, ParseLimits{})
}

pub fn parse_with_limits(markdown string, options ParseOptions, limits ParseLimits) !Document {
	validate_parse_limits(limits)!
	if u64(markdown.len) > u64(0xffff_ffff) {
		return error('Markdown input exceeds md4c maximum size 4294967295 bytes')
	}
	if limits.max_input_bytes > 0 && markdown.len > limits.max_input_bytes {
		return error('Markdown input exceeds maximum size ${limits.max_input_bytes} bytes')
	}
	mut builder := new_builder(markdown, limits)
	flags := options.to_md4c_flags()
	rc := C.vmd_parse_to_v(markdown.str, u32(markdown.len), flags, &builder)
	if rc != 0 {
		return error(builder.error_message(rc))
	}
	doc := builder.finish()!
	doc.validate_with_limits(AstValidationLimits{
		max_nodes: limits.max_nodes
		max_nesting_depth: limits.max_nesting_depth
	})!
	return doc
}

fn validate_parse_limits(limits ParseLimits) ! {
	if limits.max_input_bytes < 0 {
		return error('max_input_bytes cannot be negative')
	}
	if limits.max_nodes < 0 {
		return error('max_nodes cannot be negative')
	}
	if limits.max_nesting_depth < 0 {
		return error('max_nesting_depth cannot be negative')
	}
}

fn (options ParseOptions) to_md4c_flags() u32 {
	mut flags := u32(0)
	if options.tables {
		flags |= u32(C.MD_FLAG_TABLES)
	}
	if options.tasklists {
		flags |= u32(C.MD_FLAG_TASKLISTS)
	}
	if options.strikethrough {
		flags |= u32(C.MD_FLAG_STRIKETHROUGH)
	}
	if options.permissive_url_autolinks {
		flags |= u32(C.MD_FLAG_PERMISSIVEURLAUTOLINKS)
	}
	if options.permissive_www_autolinks {
		flags |= u32(C.MD_FLAG_PERMISSIVEWWWAUTOLINKS)
	}
	if options.permissive_email_autolink {
		flags |= u32(C.MD_FLAG_PERMISSIVEEMAILAUTOLINKS)
	}
	if options.wiki_links {
		flags |= u32(C.MD_FLAG_WIKILINKS)
	}
	if options.latex_math {
		flags |= u32(C.MD_FLAG_LATEXMATHSPANS)
	}
	if options.underline {
		flags |= u32(C.MD_FLAG_UNDERLINE)
	}
	if options.no_html_blocks {
		flags |= u32(C.MD_FLAG_NOHTMLBLOCKS)
	}
	if options.no_html_spans {
		flags |= u32(C.MD_FLAG_NOHTMLSPANS)
	}
	if options.no_indented_code_blocks {
		flags |= u32(C.MD_FLAG_NOINDENTEDCODEBLOCKS)
	}
	return flags
}

enum FrameKind {
	document
	blockquote
	list
	list_item
	heading
	paragraph
	emphasis
	strong
	strikethrough
	underline
	link
	wiki_link
	image
	code_span
	latex_math
	code_block
	html_block
	table
	table_head
	table_body
	table_row
	table_cell
}

struct Frame {
	kind FrameKind
mut:
	blocks    []BlockNode
	inlines   []InlineNode
	items     []ListItemNode
	level     int
	ordered   bool
	start     int
	number    int
	url       string
	lang      string
	implicit  bool
	columns   int
	rows      []TableRowNode
	head_rows []TableRowNode
	body_rows []TableRowNode
	cells     []TableCellNode
	alignment TableAlignment
	span      SourceSpan = SourceSpan{ start: -1, end: -1 }
	is_task   bool
	checked   bool
	display   bool
	text      strings.Builder
}

struct Builder {
	markdown string
	limits   ParseLimits
mut:
	frames         []Frame
	callback_error string
	last_debug     string
	source_cursor  int
	nodes          int
}

fn new_builder(markdown string, limits ParseLimits) Builder {
	return Builder{
		markdown: markdown
		limits: limits
		nodes: 1
		frames: [Frame{
			kind: .document
			text: strings.new_builder(0)
		}]
	}
}

fn (mut b Builder) finish() !Document {
	if b.frames.len != 1 || b.frames[0].kind != .document {
		return error('markdown parse ended with an unbalanced frame stack')
	}
	return Document{
		span: SourceSpan{ start: 0, end: b.markdown.len }
		children: b.frames[0].blocks.clone()
	}
}

fn (b &Builder) error_message(code int) string {
	if b.last_debug.len > 0 {
		if b.callback_error.len > 0 {
			return 'md4c parse failed with code ${code}: ${b.callback_error} (${b.last_debug})'
		}
		return 'md4c parse failed with code ${code}: ${b.last_debug}'
	}
	if b.callback_error.len > 0 {
		return 'md4c parse failed with code ${code}: ${b.callback_error}'
	}
	return 'md4c parse failed with code ${code}'
}

fn (mut b Builder) push_frame(kind FrameKind) ! {
	if b.limits.max_nesting_depth > 0 && b.frames.len >= b.limits.max_nesting_depth {
		return error('Markdown AST exceeds maximum nesting depth ${b.limits.max_nesting_depth}')
	}
	b.frames << Frame{
		kind: kind
		text: strings.new_builder(64)
	}
}

fn (mut b Builder) reserve_node() ! {
	b.nodes++
	if b.limits.max_nodes > 0 && b.nodes > b.limits.max_nodes {
		return error('Markdown AST exceeds maximum node count ${b.limits.max_nodes}')
	}
}

fn (mut b Builder) top() !&Frame {
	if b.frames.len == 0 {
		return error('frame stack is empty')
	}
	return &b.frames[b.frames.len - 1]
}

fn (mut b Builder) pop_frame(expected FrameKind) !Frame {
	if b.frames.len == 0 {
		return error('frame stack is empty')
	}
	last := b.frames[b.frames.len - 1]
	if last.kind != expected {
		return error('expected ${expected}, got ${last.kind}')
	}
	b.frames.delete(b.frames.len - 1)
	return last
}

fn (mut b Builder) append_block(node BlockNode) ! {
	b.reserve_node()!
	span := node.source_span()
	for i := b.frames.len - 1; i >= 0; i-- {
		match b.frames[i].kind {
			.document, .blockquote, .list_item {
				b.frames[i].blocks << node
				b.frames[i].absorb_span(span)
				return
			}
			else {}
		}
	}
	return error('no block parent available for ${typeof(node).name}')
}

fn (mut b Builder) append_list_item(item ListItemNode) ! {
	b.reserve_node()!
	for i := b.frames.len - 1; i >= 0; i-- {
		if b.frames[i].kind == .list {
			b.frames[i].items << item
			b.frames[i].absorb_span(item.span)
			return
		}
	}
	return error('no list parent available')
}

fn (mut b Builder) append_inline(node InlineNode) ! {
	span := node.source_span()
	for i := b.frames.len - 1; i >= 0; i-- {
		match b.frames[i].kind {
			.heading, .paragraph, .emphasis, .strong, .strikethrough, .underline, .link, .wiki_link, .image, .table_cell {
				if node is TextNode && b.frames[i].inlines.len > 0 {
					last_index := b.frames[i].inlines.len - 1
					last := b.frames[i].inlines[last_index]
					if last is TextNode {
						b.frames[i].inlines[last_index] = TextNode{
							span: merge_source_spans(last.span, node.span)
							text: last.text + node.text
						}
						b.frames[i].absorb_span(span)
						return
					}
				}
				b.reserve_node()!
				b.frames[i].inlines << node
				b.frames[i].absorb_span(span)
				return
			}
			.code_span {
				return error('cannot append inline node into code span')
			}
			else {}
		}
	}
	return error('no inline parent available for ${typeof(node).name}')
}

fn merge_source_spans(left SourceSpan, right SourceSpan) SourceSpan {
	if !left.is_valid() {
		return right
	}
	if !right.is_valid() {
		return left
	}
	return SourceSpan{
		start: min_int(left.start, right.start)
		end: max_int(left.end, right.end)
	}
}

fn (b &Builder) has_inline_parent() bool {
	for i := b.frames.len - 1; i >= 0; i-- {
		match b.frames[i].kind {
			.heading, .paragraph, .emphasis, .strong, .strikethrough, .underline, .link, .wiki_link, .image, .table_cell {
				return true
			}
			else {}
		}
	}
	return false
}

fn (mut b Builder) ensure_inline_container() ! {
	if b.has_inline_parent() {
		return
	}
	if b.frames.len == 0 {
		return error('frame stack is empty')
	}
	last := b.frames[b.frames.len - 1]
	if last.kind == .list_item {
		b.push_frame(.paragraph)!
		mut top := b.top()!
		top.implicit = true
		return
	}
	return error('no inline container available')
}

fn (mut b Builder) flush_implicit_paragraph() ! {
	if b.frames.len == 0 {
		return
	}
	last := b.frames[b.frames.len - 1]
	if last.kind != .paragraph || !last.implicit {
		return
	}
	frame := b.pop_frame(.paragraph)!
	b.append_block(ParagraphNode{
		span: frame.span
		children: frame.inlines.clone()
	})!
}

fn (b &Builder) current_list_depth() int {
	mut depth := 0
	for f in b.frames {
		if f.kind == .list {
			depth++
		}
	}
	return depth
}

fn (mut b Builder) enter_block(typ int, detail voidptr) ! {
	if typ != int(C.MD_BLOCK_P) {
		b.flush_implicit_paragraph()!
	}
	match typ {
		int(C.MD_BLOCK_DOC) {}
		int(C.MD_BLOCK_QUOTE) {
			b.push_frame(.blockquote)!
		}
		int(C.MD_BLOCK_UL) {
			b.push_frame(.list)!
			mut top := b.top()!
			top.ordered = false
			top.start = 1
		}
		int(C.MD_BLOCK_OL) {
			b.push_frame(.list)!
			mut top := b.top()!
			top.ordered = true
			ol := unsafe { &C.MD_BLOCK_OL_DETAIL(detail) }
			top.start = int(ol.start)
		}
		int(C.MD_BLOCK_LI) {
			b.flush_implicit_paragraph()!
			b.push_frame(.list_item)!
			mut top := b.top()!
			depth := b.current_list_depth()
			top.level = depth
			top.number = b.next_list_item_number()!
			li := unsafe { &C.MD_BLOCK_LI_DETAIL(detail) }
			top.is_task = li.is_task != 0
			top.checked = top.is_task && li.task_mark != ` `
			if top.is_task {
				top.absorb_span(SourceSpan{ start: int(li.task_mark_offset), end: int(li.task_mark_offset) + 1 })
			}
		}
		int(C.MD_BLOCK_HR) {
			b.append_block(HorizontalRuleNode{})!
		}
		int(C.MD_BLOCK_H) {
			b.push_frame(.heading)!
			mut top := b.top()!
			h := unsafe { &C.MD_BLOCK_H_DETAIL(detail) }
			top.level = int(h.level)
		}
		int(C.MD_BLOCK_CODE) {
			b.push_frame(.code_block)!
			mut top := b.top()!
			code := unsafe { &C.MD_BLOCK_CODE_DETAIL(detail) }
			info := attribute_to_string(code.info).trim_space()
			top.lang = if info.len > 0 { info } else { attribute_to_string(code.lang) }
		}
		int(C.MD_BLOCK_HTML) {
			b.push_frame(.html_block)!
		}
		int(C.MD_BLOCK_P) {
			b.push_frame(.paragraph)!
		}
		int(C.MD_BLOCK_TABLE) {
			b.push_frame(.table)!
			mut top := b.top()!
			table := unsafe { &C.MD_BLOCK_TABLE_DETAIL(detail) }
			top.columns = int(table.col_count)
		}
		int(C.MD_BLOCK_THEAD) {
			b.push_frame(.table_head)!
		}
		int(C.MD_BLOCK_TBODY) {
			b.push_frame(.table_body)!
		}
		int(C.MD_BLOCK_TR) {
			b.push_frame(.table_row)!
		}
		int(C.MD_BLOCK_TH), int(C.MD_BLOCK_TD) {
			b.push_frame(.table_cell)!
			mut top := b.top()!
			cell := unsafe { &C.MD_BLOCK_TD_DETAIL(detail) }
			top.alignment = table_alignment_from_md4c(cell.align)
		}
		else {}
	}
}

fn (mut b Builder) leave_block(typ int, _detail voidptr) ! {
	match typ {
		int(C.MD_BLOCK_DOC) {}
		int(C.MD_BLOCK_QUOTE) {
			frame := b.pop_frame(.blockquote)!
			b.append_block(BlockquoteNode{
				span: frame.span
				children: frame.blocks.clone()
			})!
		}
		int(C.MD_BLOCK_UL), int(C.MD_BLOCK_OL) {
			frame := b.pop_frame(.list)!
			b.append_block(ListNode{
				span: frame.span
				is_ordered: frame.ordered
				start: frame.start
				items: frame.items.clone()
			})!
		}
		int(C.MD_BLOCK_LI) {
			b.flush_implicit_paragraph()!
			frame := b.pop_frame(.list_item)!
			b.append_list_item(ListItemNode{
				span: frame.span
				level: frame.level
				number: frame.number
				is_task: frame.is_task
				checked: frame.checked
				children: frame.blocks.clone()
			})!
		}
		int(C.MD_BLOCK_HR) {}
		int(C.MD_BLOCK_H) {
			frame := b.pop_frame(.heading)!
			b.append_block(HeadingNode{
				span: frame.span
				level: frame.level
				children: frame.inlines.clone()
			})!
		}
		int(C.MD_BLOCK_CODE) {
			mut frame := b.pop_frame(.code_block)!
			b.append_block(CodeBlockNode{
				span: frame.span
				lang: frame.lang
				content: frame.text.str()
			})!
		}
		int(C.MD_BLOCK_HTML) {
			mut frame := b.pop_frame(.html_block)!
			b.append_block(RawHtmlBlockNode{
				span: frame.span
				html: frame.text.str()
			})!
		}
		int(C.MD_BLOCK_P) {
			frame := b.pop_frame(.paragraph)!
			b.append_block(ParagraphNode{
				span: frame.span
				children: frame.inlines.clone()
			})!
		}
		int(C.MD_BLOCK_TABLE) {
			frame := b.pop_frame(.table)!
			b.append_block(TableNode{
				span: frame.span
				columns: frame.columns
				head: frame.head_rows.clone()
				body: frame.body_rows.clone()
			})!
		}
		int(C.MD_BLOCK_THEAD) {
			frame := b.pop_frame(.table_head)!
			mut top := b.top()!
			top.head_rows << frame.rows
			top.absorb_span(frame.span)
		}
		int(C.MD_BLOCK_TBODY) {
			frame := b.pop_frame(.table_body)!
			mut top := b.top()!
			top.body_rows << frame.rows
			top.absorb_span(frame.span)
		}
		int(C.MD_BLOCK_TR) {
			frame := b.pop_frame(.table_row)!
			b.reserve_node()!
			mut top := b.top()!
			top.rows << TableRowNode{
				span: frame.span
				cells: frame.cells.clone()
			}
			top.absorb_span(frame.span)
		}
		int(C.MD_BLOCK_TH), int(C.MD_BLOCK_TD) {
			frame := b.pop_frame(.table_cell)!
			b.reserve_node()!
			mut top := b.top()!
			top.cells << TableCellNode{
				span: frame.span
				alignment: frame.alignment
				children: frame.inlines.clone()
			}
			top.absorb_span(frame.span)
		}
		else {}
	}
}

fn (mut b Builder) enter_span(typ int, detail voidptr) ! {
	b.ensure_inline_container()!
	match typ {
		int(C.MD_SPAN_EM) {
			b.push_frame(.emphasis)!
		}
		int(C.MD_SPAN_STRONG) {
			b.push_frame(.strong)!
		}
		int(C.MD_SPAN_DEL) {
			b.push_frame(.strikethrough)!
		}
		int(C.MD_SPAN_U) {
			b.push_frame(.underline)!
		}
		int(C.MD_SPAN_A) {
			b.push_frame(.link)!
			mut top := b.top()!
			link_detail := unsafe { &C.MD_SPAN_A_DETAIL(detail) }
			top.url = attribute_to_string(link_detail.href)
		}
		int(C.MD_SPAN_WIKILINK) {
			b.push_frame(.wiki_link)!
			mut top := b.top()!
			wiki := unsafe { &C.MD_SPAN_WIKILINK_DETAIL(detail) }
			top.url = attribute_to_string(wiki.target)
		}
		int(C.MD_SPAN_IMG) {
			b.push_frame(.image)!
			mut top := b.top()!
			image := unsafe { &C.MD_SPAN_IMG_DETAIL(detail) }
			top.url = attribute_to_string(image.src)
		}
		int(C.MD_SPAN_CODE) {
			b.push_frame(.code_span)!
		}
		int(C.MD_SPAN_LATEXMATH), int(C.MD_SPAN_LATEXMATH_DISPLAY) {
			b.push_frame(.latex_math)!
			mut top := b.top()!
			top.display = typ == int(C.MD_SPAN_LATEXMATH_DISPLAY)
		}
		else {}
	}
}

fn (mut b Builder) leave_span(typ int, _detail voidptr) ! {
	match typ {
		int(C.MD_SPAN_EM) {
			frame := b.pop_frame(.emphasis)!
			b.append_inline(EmphasisNode{
				span: frame.span
				children: frame.inlines.clone()
			})!
		}
		int(C.MD_SPAN_STRONG) {
			frame := b.pop_frame(.strong)!
			b.append_inline(StrongNode{
				span: frame.span
				children: frame.inlines.clone()
			})!
		}
		int(C.MD_SPAN_DEL) {
			frame := b.pop_frame(.strikethrough)!
			b.append_inline(StrikethroughNode{
				span: frame.span
				children: frame.inlines.clone()
			})!
		}
		int(C.MD_SPAN_U) {
			frame := b.pop_frame(.underline)!
			b.append_inline(UnderlineNode{
				span: frame.span
				children: frame.inlines.clone()
			})!
		}
		int(C.MD_SPAN_A) {
			frame := b.pop_frame(.link)!
			b.append_inline(LinkNode{
				span: frame.span
				text: frame.inlines.clone()
				url: frame.url
			})!
		}
		int(C.MD_SPAN_WIKILINK) {
			frame := b.pop_frame(.wiki_link)!
			b.append_inline(WikiLinkNode{
				span: frame.span
				target: frame.url
				text: frame.inlines.clone()
			})!
		}
		int(C.MD_SPAN_IMG) {
			frame := b.pop_frame(.image)!
			b.append_inline(ImageNode{
				span: frame.span
				alt: frame.inlines.clone()
				url: frame.url
			})!
		}
		int(C.MD_SPAN_CODE) {
			mut frame := b.pop_frame(.code_span)!
			b.append_inline(CodeSpanNode{
				span: frame.span
				text: frame.text.str()
			})!
		}
		int(C.MD_SPAN_LATEXMATH), int(C.MD_SPAN_LATEXMATH_DISPLAY) {
			mut frame := b.pop_frame(.latex_math)!
			b.append_inline(LatexMathNode{
				span: frame.span
				content: frame.text.str()
				display: frame.display
			})!
		}
		else {}
	}
}

fn (mut b Builder) on_text(typ int, text &char, size u32) ! {
	content := unsafe { tos(&u8(text), int(size)).clone() }
	span := b.source_span_for(typ, text, int(size))
	b.absorb_open_frames(span)
	match typ {
		int(C.MD_TEXT_BR) {
			if b.in_code_context() {
				mut top := b.top()!
				top.text.write_string('\n')
			} else {
				b.ensure_inline_container()!
				b.append_inline(HardBreakNode{ span: span })!
			}
		}
		int(C.MD_TEXT_SOFTBR) {
			if b.in_code_context() {
				mut top := b.top()!
				top.text.write_string('\n')
			} else {
				b.ensure_inline_container()!
				b.append_inline(SoftBreakNode{ span: span })!
			}
		}
		int(C.MD_TEXT_CODE) {
			mut top := b.top()!
			top.text.write_string(content)
		}
		int(C.MD_TEXT_LATEXMATH) {
			mut top := b.top()!
			if top.kind != .latex_math {
				return error('LaTeX math text emitted outside a math span')
			}
			top.text.write_string(content)
		}
		int(C.MD_TEXT_HTML) {
			if b.in_code_context() {
				mut top := b.top()!
				top.text.write_string(content)
			} else {
				b.ensure_inline_container()!
				b.append_inline(RawHtmlInlineNode{ span: span, html: content })!
			}
		}
		int(C.MD_TEXT_NORMAL), int(C.MD_TEXT_NULLCHAR), int(C.MD_TEXT_ENTITY) {
			if b.in_code_context() {
				mut top := b.top()!
				top.text.write_string(content)
			} else {
				b.ensure_inline_container()!
				b.append_inline(TextNode{
					span: span
					text: content
				})!
			}
		}
		else {}
	}
}

fn (mut frame Frame) absorb_span(span SourceSpan) {
	if !span.is_valid() {
		return
	}
	if !frame.span.is_valid() {
		frame.span = span
		return
	}
	frame.span = SourceSpan{
		start: min_int(frame.span.start, span.start)
		end: max_int(frame.span.end, span.end)
	}
}

fn (mut b Builder) source_span_for(typ int, text &char, size int) SourceSpan {
	base := usize(b.markdown.str)
	address := usize(text)
	if size >= 0 && address >= base && address + usize(size) <= base + usize(b.markdown.len) {
		start := int(address - base)
		b.source_cursor = max_int(b.source_cursor, start + size)
		return SourceSpan{ start: start, end: start + size }
	}
	if typ == int(C.MD_TEXT_BR) || typ == int(C.MD_TEXT_SOFTBR)
		|| (typ == int(C.MD_TEXT_HTML) && size == 1) {
		start := b.markdown.index_after('\n', b.source_cursor) or { return SourceSpan{} }
		b.source_cursor = start + 1
		return SourceSpan{ start: start, end: start + 1 }
	}
	return SourceSpan{}
}

fn (mut b Builder) absorb_open_frames(span SourceSpan) {
	for i in 0 .. b.frames.len {
		b.frames[i].absorb_span(span)
	}
}

fn (b &Builder) in_code_context() bool {
	if b.frames.len == 0 {
		return false
	}
	last := b.frames[b.frames.len - 1]
	return last.kind == .code_block || last.kind == .code_span || last.kind == .html_block
}

fn (mut b Builder) next_list_item_number() !int {
	for i := b.frames.len - 1; i >= 0; i-- {
		if b.frames[i].kind == .list {
			number := if b.frames[i].ordered {
				b.frames[i].start + b.frames[i].items.len
			} else {
				0
			}
			return number
		}
	}
	return error('no list frame available')
}

fn attribute_to_string(attr C.MD_ATTRIBUTE) string {
	if isnil(attr.text) || attr.size == 0 {
		return ''
	}
	return unsafe { tos(&u8(attr.text), int(attr.size)).clone() }
}

fn table_alignment_from_md4c(alignment int) TableAlignment {
	return match alignment {
		int(C.MD_ALIGN_LEFT) { .left }
		int(C.MD_ALIGN_CENTER) { .center }
		int(C.MD_ALIGN_RIGHT) { .right }
		else { .default_ }
	}
}

@[export: 'vmarkdown_enter_block']
pub fn vmarkdown_enter_block(typ int, detail voidptr, userdata voidptr) int {
	mut b := unsafe { &Builder(userdata) }
	b.enter_block(typ, detail) or {
		b.callback_error = err.msg()
		return -1
	}
	return 0
}

@[export: 'vmarkdown_leave_block']
pub fn vmarkdown_leave_block(typ int, detail voidptr, userdata voidptr) int {
	mut b := unsafe { &Builder(userdata) }
	b.leave_block(typ, detail) or {
		b.callback_error = err.msg()
		return -1
	}
	return 0
}

@[export: 'vmarkdown_enter_span']
pub fn vmarkdown_enter_span(typ int, detail voidptr, userdata voidptr) int {
	mut b := unsafe { &Builder(userdata) }
	b.enter_span(typ, detail) or {
		b.callback_error = err.msg()
		return -1
	}
	return 0
}

@[export: 'vmarkdown_leave_span']
pub fn vmarkdown_leave_span(typ int, detail voidptr, userdata voidptr) int {
	mut b := unsafe { &Builder(userdata) }
	b.leave_span(typ, detail) or {
		b.callback_error = err.msg()
		return -1
	}
	return 0
}

@[export: 'vmarkdown_text']
pub fn vmarkdown_text(typ int, text &char, size u32, userdata voidptr) int {
	mut b := unsafe { &Builder(userdata) }
	b.on_text(typ, text, size) or {
		b.callback_error = err.msg()
		return -1
	}
	return 0
}

@[export: 'vmarkdown_debug_log']
pub fn vmarkdown_debug_log(msg &char, userdata voidptr) {
	mut b := unsafe { &Builder(userdata) }
	b.last_debug = unsafe { cstring_to_vstring(msg).clone() }
}
