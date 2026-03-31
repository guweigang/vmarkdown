module vmarkdown

pub struct Document {
pub mut:
	children []BlockNode
}

pub type BlockNode = BlockquoteNode | CodeBlockNode | HeadingNode | HorizontalRuleNode | ListNode | MetaNode | ParagraphNode

pub struct MetaNode {
pub:
	data map[string]string
}

pub struct HeadingNode {
pub:
	level    int
	children []InlineNode
}

pub struct ParagraphNode {
pub:
	children []InlineNode
}

pub struct BlockquoteNode {
pub:
	children []BlockNode
}

pub struct ListNode {
pub:
	is_ordered bool
	start      int
	items      []ListItemNode
}

pub struct ListItemNode {
pub:
	level    int
	number   int
	children []BlockNode
}

pub struct CodeBlockNode {
pub:
	lang    string
	content string
}

pub struct HorizontalRuleNode {}

pub type InlineNode = CodeSpanNode | EmphasisNode | ImageNode | LinkNode | StrongNode | TextNode

pub struct TextNode {
pub:
	text string
}

pub struct EmphasisNode {
pub:
	children []InlineNode
}

pub struct StrongNode {
pub:
	children []InlineNode
}

pub struct CodeSpanNode {
pub:
	text string
}

pub struct LinkNode {
pub:
	text []InlineNode
	url  string
}

pub struct ImageNode {
pub:
	alt []InlineNode
	url string
}
