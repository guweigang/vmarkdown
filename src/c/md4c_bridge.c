#include "md4c_bridge.h"

static int vmd_enter_block(MD_BLOCKTYPE type, void* detail, void* userdata) {
	return vmarkdown_enter_block((int) type, detail, userdata);
}

static int vmd_leave_block(MD_BLOCKTYPE type, void* detail, void* userdata) {
	return vmarkdown_leave_block((int) type, detail, userdata);
}

static int vmd_enter_span(MD_SPANTYPE type, void* detail, void* userdata) {
	return vmarkdown_enter_span((int) type, detail, userdata);
}

static int vmd_leave_span(MD_SPANTYPE type, void* detail, void* userdata) {
	return vmarkdown_leave_span((int) type, detail, userdata);
}

static int vmd_text(MD_TEXTTYPE type, const MD_CHAR* text, MD_SIZE size, void* userdata) {
	return vmarkdown_text((int) type, (MD_CHAR*) text, size, userdata);
}

static void vmd_debug_log(const char* msg, void* userdata) {
	vmarkdown_debug_log((char*) msg, userdata);
}

int vmd_parse_to_v(const MD_CHAR* text, MD_SIZE size, unsigned flags, void* userdata) {
	MD_PARSER parser = {
		0,
		flags,
		vmd_enter_block,
		vmd_leave_block,
		vmd_enter_span,
		vmd_leave_span,
		vmd_text,
		vmd_debug_log,
		0
	};
	return md_parse(text, size, &parser, userdata);
}
