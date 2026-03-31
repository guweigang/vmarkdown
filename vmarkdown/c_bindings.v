module vmarkdown

#flag -I @VMODROOT/vmarkdown/c
#flag -I @VMODROOT/thirdparty/md4c/src
#flag @VMODROOT/vmarkdown/c/md4c_bridge.c
#flag @VMODROOT/thirdparty/md4c/src/md4c.c
#flag @VMODROOT/thirdparty/md4c/src/md4c-html.c
#flag @VMODROOT/thirdparty/md4c/src/entity.c

#include "md4c.h"
#include "md4c-html.h"
#include "md4c_bridge.h"

@[typedef]
struct C.MD_ATTRIBUTE {
	text           &char
	size           u32
	substr_types   &int
	substr_offsets &u32
}

@[typedef]
struct C.MD_BLOCK_OL_DETAIL {
	start          u32
	is_tight       int
	mark_delimiter char
}

@[typedef]
struct C.MD_BLOCK_H_DETAIL {
	level u32
}

@[typedef]
struct C.MD_BLOCK_CODE_DETAIL {
	info       C.MD_ATTRIBUTE
	lang       C.MD_ATTRIBUTE
	fence_char char
}

@[typedef]
struct C.MD_SPAN_A_DETAIL {
	href        C.MD_ATTRIBUTE
	title       C.MD_ATTRIBUTE
	is_autolink int
}

@[typedef]
struct C.MD_SPAN_IMG_DETAIL {
	src   C.MD_ATTRIBUTE
	title C.MD_ATTRIBUTE
}

fn C.vmd_parse_to_v(text &char, size u32, flags u32, userdata voidptr) int
fn C.md_html(input &char, input_size u32, process_output fn (&char, u32, voidptr), userdata voidptr, parser_flags u32, renderer_flags u32) int
