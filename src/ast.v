module vmarkdown

pub struct Document {
pub:
	span SourceSpan = SourceSpan{ start: -1, end: -1 }
pub mut:
	children []BlockNode
}

// SourceSpan is a half-open UTF-8 byte range in the original Markdown input.
// A negative start denotes a node for which md4c did not expose source bytes.
pub struct SourceSpan {
pub:
	start int = -1
	end   int = -1
}

pub fn (span SourceSpan) is_valid() bool {
	return span.start >= 0 && span.end >= span.start
}

pub fn (span SourceSpan) len() int {
	return if span.is_valid() { span.end - span.start } else { 0 }
}

pub type BlockNode = BlockquoteNode
	| CodeBlockNode
	| HeadingNode
	| HorizontalRuleNode
	| ListNode
	| MetaNode
	| ParagraphNode
	| RawHtmlBlockNode
	| TableNode

pub struct MetaNode {
pub:
	span SourceSpan = SourceSpan{ start: -1, end: -1 }
	data map[string]string
}

pub struct HeadingNode {
pub:
	span     SourceSpan = SourceSpan{ start: -1, end: -1 }
	level    int
	children []InlineNode
}

pub struct ParagraphNode {
pub:
	span     SourceSpan = SourceSpan{ start: -1, end: -1 }
	children []InlineNode
}

pub struct BlockquoteNode {
pub:
	span     SourceSpan = SourceSpan{ start: -1, end: -1 }
	children []BlockNode
}

pub struct ListNode {
pub:
	span       SourceSpan = SourceSpan{ start: -1, end: -1 }
	is_ordered bool
	start      int
	items      []ListItemNode
}

pub struct ListItemNode {
pub:
	span     SourceSpan = SourceSpan{ start: -1, end: -1 }
	level    int
	number   int
	is_task  bool
	checked  bool
	children []BlockNode
}

pub struct CodeBlockNode {
pub:
	span    SourceSpan = SourceSpan{ start: -1, end: -1 }
	lang    string
	content string
}

pub struct HorizontalRuleNode {
pub:
	span SourceSpan = SourceSpan{ start: -1, end: -1 }
}

// Raw HTML is preserved verbatim and deliberately not interpreted or sanitized.
pub struct RawHtmlBlockNode {
pub:
	span SourceSpan = SourceSpan{ start: -1, end: -1 }
	html string
}

pub enum TableAlignment {
	default_
	left
	center
	right
}

pub struct TableNode {
pub:
	span    SourceSpan = SourceSpan{ start: -1, end: -1 }
	columns int
	head    []TableRowNode
	body    []TableRowNode
}

pub struct TableRowNode {
pub:
	span  SourceSpan = SourceSpan{ start: -1, end: -1 }
	cells []TableCellNode
}

pub struct TableCellNode {
pub:
	span      SourceSpan = SourceSpan{ start: -1, end: -1 }
	alignment TableAlignment
	children  []InlineNode
}

pub type InlineNode = CodeSpanNode
	| EmphasisNode
	| HardBreakNode
	| ImageNode
	| LatexMathNode
	| LinkNode
	| RawHtmlInlineNode
	| SoftBreakNode
	| StrikethroughNode
	| StrongNode
	| TextNode
	| UnderlineNode
	| WikiLinkNode

pub struct TextNode {
pub:
	span SourceSpan = SourceSpan{ start: -1, end: -1 }
	text string
}

pub struct EmphasisNode {
pub:
	span     SourceSpan = SourceSpan{ start: -1, end: -1 }
	children []InlineNode
}

pub struct StrongNode {
pub:
	span     SourceSpan = SourceSpan{ start: -1, end: -1 }
	children []InlineNode
}

pub struct StrikethroughNode {
pub:
	span     SourceSpan = SourceSpan{ start: -1, end: -1 }
	children []InlineNode
}

pub struct UnderlineNode {
pub:
	span     SourceSpan = SourceSpan{ start: -1, end: -1 }
	children []InlineNode
}

pub struct CodeSpanNode {
pub:
	span SourceSpan = SourceSpan{ start: -1, end: -1 }
	text string
}

pub struct LatexMathNode {
pub:
	span    SourceSpan = SourceSpan{ start: -1, end: -1 }
	content string
	display bool
}

pub struct LinkNode {
pub:
	span SourceSpan = SourceSpan{ start: -1, end: -1 }
	text []InlineNode
	url  string
}

pub struct WikiLinkNode {
pub:
	span   SourceSpan = SourceSpan{ start: -1, end: -1 }
	target string
	text   []InlineNode
}

pub struct ImageNode {
pub:
	span SourceSpan = SourceSpan{ start: -1, end: -1 }
	alt  []InlineNode
	url  string
}

pub struct SoftBreakNode {
pub:
	span SourceSpan = SourceSpan{ start: -1, end: -1 }
}

pub struct HardBreakNode {
pub:
	span SourceSpan = SourceSpan{ start: -1, end: -1 }
}

pub struct RawHtmlInlineNode {
pub:
	span SourceSpan = SourceSpan{ start: -1, end: -1 }
	html string
}

pub fn (node BlockNode) source_span() SourceSpan {
	return match node {
		BlockquoteNode { node.span }
		CodeBlockNode { node.span }
		HeadingNode { node.span }
		HorizontalRuleNode { node.span }
		ListNode { node.span }
		MetaNode { node.span }
		ParagraphNode { node.span }
		RawHtmlBlockNode { node.span }
		TableNode { node.span }
	}
}

pub fn (node InlineNode) source_span() SourceSpan {
	return match node {
		CodeSpanNode { node.span }
		EmphasisNode { node.span }
		HardBreakNode { node.span }
		ImageNode { node.span }
		LatexMathNode { node.span }
		LinkNode { node.span }
		RawHtmlInlineNode { node.span }
		SoftBreakNode { node.span }
		StrikethroughNode { node.span }
		StrongNode { node.span }
		TextNode { node.span }
		UnderlineNode { node.span }
		WikiLinkNode { node.span }
	}
}
