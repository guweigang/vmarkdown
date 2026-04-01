module vmarkdown

import strings

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

pub fn parse_with_options(markdown string, options ParseOptions) !Document {
	mut builder := new_builder(markdown)
	flags := options.to_md4c_flags()
	rc := C.vmd_parse_to_v(markdown.str, u32(markdown.len), flags, &builder)
	if rc != 0 {
		return error(builder.error_message(rc))
	}
	return builder.finish()
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
	link
	image
	code_span
	code_block
}

struct Frame {
	kind FrameKind
mut:
	blocks      []BlockNode
	inlines     []InlineNode
	items       []ListItemNode
	level       int
	ordered     bool
	start       int
	number      int
	url         string
	lang        string
	implicit    bool
	text        strings.Builder
}

struct Builder {
	markdown string
mut:
	frames    []Frame
	last_debug string
}

fn new_builder(markdown string) Builder {
	return Builder{
		markdown: markdown
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
		children: b.frames[0].blocks.clone()
	}
}

fn (b &Builder) error_message(code int) string {
	if b.last_debug.len > 0 {
		return 'md4c parse failed with code ${code}: ${b.last_debug}'
	}
	return 'md4c parse failed with code ${code}'
}

fn (mut b Builder) push_frame(kind FrameKind) {
	b.frames << Frame{
		kind: kind
		text: strings.new_builder(64)
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
	for i := b.frames.len - 1; i >= 0; i-- {
		match b.frames[i].kind {
			.document, .blockquote, .list_item {
				b.frames[i].blocks << node
				return
			}
			else {}
		}
	}
	return error('no block parent available for ${typeof(node).name}')
}

fn (mut b Builder) append_list_item(item ListItemNode) ! {
	for i := b.frames.len - 1; i >= 0; i-- {
		if b.frames[i].kind == .list {
			b.frames[i].items << item
			return
		}
	}
	return error('no list parent available')
}

fn (mut b Builder) append_inline(node InlineNode) ! {
	for i := b.frames.len - 1; i >= 0; i-- {
		match b.frames[i].kind {
			.heading, .paragraph, .emphasis, .strong, .link, .image {
				b.frames[i].inlines << node
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

fn (b &Builder) has_inline_parent() bool {
	for i := b.frames.len - 1; i >= 0; i-- {
		match b.frames[i].kind {
			.heading, .paragraph, .emphasis, .strong, .link, .image {
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
		b.push_frame(.paragraph)
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
			b.push_frame(.blockquote)
		}
		int(C.MD_BLOCK_UL) {
			b.push_frame(.list)
			mut top := b.top()!
			top.ordered = false
			top.start = 1
		}
		int(C.MD_BLOCK_OL) {
			b.push_frame(.list)
			mut top := b.top()!
			top.ordered = true
			ol := unsafe { &C.MD_BLOCK_OL_DETAIL(detail) }
			top.start = int(ol.start)
		}
		int(C.MD_BLOCK_LI) {
			b.flush_implicit_paragraph()!
			b.push_frame(.list_item)
			mut top := b.top()!
			depth := b.current_list_depth()
			top.level = depth
			top.number = b.next_list_item_number()!
		}
		int(C.MD_BLOCK_HR) {
			b.append_block(HorizontalRuleNode{})!
		}
		int(C.MD_BLOCK_H) {
			b.push_frame(.heading)
			mut top := b.top()!
			h := unsafe { &C.MD_BLOCK_H_DETAIL(detail) }
			top.level = int(h.level)
		}
		int(C.MD_BLOCK_CODE) {
			b.push_frame(.code_block)
			mut top := b.top()!
			code := unsafe { &C.MD_BLOCK_CODE_DETAIL(detail) }
			top.lang = attribute_to_string(code.lang)
		}
		int(C.MD_BLOCK_P) {
			b.push_frame(.paragraph)
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
				children: frame.blocks.clone()
			})!
		}
		int(C.MD_BLOCK_UL), int(C.MD_BLOCK_OL) {
			frame := b.pop_frame(.list)!
			b.append_block(ListNode{
				is_ordered: frame.ordered
				start: frame.start
				items: frame.items.clone()
			})!
		}
		int(C.MD_BLOCK_LI) {
			b.flush_implicit_paragraph()!
			frame := b.pop_frame(.list_item)!
			b.append_list_item(ListItemNode{
				level: frame.level
				number: frame.number
				children: frame.blocks.clone()
			})!
		}
		int(C.MD_BLOCK_HR) {}
		int(C.MD_BLOCK_H) {
			frame := b.pop_frame(.heading)!
			b.append_block(HeadingNode{
				level: frame.level
				children: frame.inlines.clone()
			})!
		}
		int(C.MD_BLOCK_CODE) {
			mut frame := b.pop_frame(.code_block)!
			b.append_block(CodeBlockNode{
				lang: frame.lang
				content: frame.text.str()
			})!
		}
		int(C.MD_BLOCK_P) {
			frame := b.pop_frame(.paragraph)!
			b.append_block(ParagraphNode{
				children: frame.inlines.clone()
			})!
		}
		else {}
	}
}

fn (mut b Builder) enter_span(typ int, detail voidptr) ! {
	b.ensure_inline_container()!
	match typ {
		int(C.MD_SPAN_EM) {
			b.push_frame(.emphasis)
		}
		int(C.MD_SPAN_STRONG) {
			b.push_frame(.strong)
		}
		int(C.MD_SPAN_A) {
			b.push_frame(.link)
			mut top := b.top()!
			link := unsafe { &C.MD_SPAN_A_DETAIL(detail) }
			top.url = attribute_to_string(link.href)
		}
		int(C.MD_SPAN_IMG) {
			b.push_frame(.image)
			mut top := b.top()!
			image := unsafe { &C.MD_SPAN_IMG_DETAIL(detail) }
			top.url = attribute_to_string(image.src)
		}
		int(C.MD_SPAN_CODE) {
			b.push_frame(.code_span)
		}
		else {}
	}
}

fn (mut b Builder) leave_span(typ int, _detail voidptr) ! {
	match typ {
		int(C.MD_SPAN_EM) {
			frame := b.pop_frame(.emphasis)!
			b.append_inline(EmphasisNode{
				children: frame.inlines.clone()
			})!
		}
		int(C.MD_SPAN_STRONG) {
			frame := b.pop_frame(.strong)!
			b.append_inline(StrongNode{
				children: frame.inlines.clone()
			})!
		}
		int(C.MD_SPAN_A) {
			frame := b.pop_frame(.link)!
			b.append_inline(LinkNode{
				text: frame.inlines.clone()
				url: frame.url
			})!
		}
		int(C.MD_SPAN_IMG) {
			frame := b.pop_frame(.image)!
			b.append_inline(ImageNode{
				alt: frame.inlines.clone()
				url: frame.url
			})!
		}
		int(C.MD_SPAN_CODE) {
			mut frame := b.pop_frame(.code_span)!
			b.append_inline(CodeSpanNode{
				text: frame.text.str()
			})!
		}
		else {}
	}
}

fn (mut b Builder) on_text(typ int, text &char, size u32) ! {
	content := unsafe { tos(&u8(text), int(size)).clone() }
	match typ {
		int(C.MD_TEXT_BR), int(C.MD_TEXT_SOFTBR) {
			if b.in_code_context() {
				mut top := b.top()!
				top.text.write_string('\n')
			} else {
				b.ensure_inline_container()!
				b.append_inline(TextNode{
					text: '\n'
				})!
			}
		}
		int(C.MD_TEXT_CODE) {
			mut top := b.top()!
			top.text.write_string(content)
		}
		int(C.MD_TEXT_HTML), int(C.MD_TEXT_NORMAL), int(C.MD_TEXT_NULLCHAR), int(C.MD_TEXT_ENTITY),
		int(C.MD_TEXT_LATEXMATH) {
			if b.in_code_context() {
				mut top := b.top()!
				top.text.write_string(content)
			} else {
				b.ensure_inline_container()!
				b.append_inline(TextNode{
					text: content
				})!
			}
		}
		else {}
	}
}

fn (b &Builder) in_code_context() bool {
	if b.frames.len == 0 {
		return false
	}
	last := b.frames[b.frames.len - 1]
	return last.kind == .code_block || last.kind == .code_span
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

@[export: 'vmarkdown_enter_block']
fn vmarkdown_enter_block(typ int, detail voidptr, userdata voidptr) int {
	mut b := unsafe { &Builder(userdata) }
	b.enter_block(typ, detail) or { return -1 }
	return 0
}

@[export: 'vmarkdown_leave_block']
fn vmarkdown_leave_block(typ int, detail voidptr, userdata voidptr) int {
	mut b := unsafe { &Builder(userdata) }
	b.leave_block(typ, detail) or { return -1 }
	return 0
}

@[export: 'vmarkdown_enter_span']
fn vmarkdown_enter_span(typ int, detail voidptr, userdata voidptr) int {
	mut b := unsafe { &Builder(userdata) }
	b.enter_span(typ, detail) or { return -1 }
	return 0
}

@[export: 'vmarkdown_leave_span']
fn vmarkdown_leave_span(typ int, detail voidptr, userdata voidptr) int {
	mut b := unsafe { &Builder(userdata) }
	b.leave_span(typ, detail) or { return -1 }
	return 0
}

@[export: 'vmarkdown_text']
fn vmarkdown_text(typ int, text &char, size u32, userdata voidptr) int {
	mut b := unsafe { &Builder(userdata) }
	b.on_text(typ, text, size) or { return -1 }
	return 0
}

@[export: 'vmarkdown_debug_log']
fn vmarkdown_debug_log(msg &char, userdata voidptr) {
	mut b := unsafe { &Builder(userdata) }
	b.last_debug = unsafe { cstring_to_vstring(msg).clone() }
}
