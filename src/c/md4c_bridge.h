#ifndef VMARKDOWN_MD4C_BRIDGE_H
#define VMARKDOWN_MD4C_BRIDGE_H

#include "md4c.h"

int vmarkdown_enter_block(int type, void* detail, void* userdata);
int vmarkdown_leave_block(int type, void* detail, void* userdata);
int vmarkdown_enter_span(int type, void* detail, void* userdata);
int vmarkdown_leave_span(int type, void* detail, void* userdata);
int vmarkdown_text(int type, MD_CHAR* text, MD_SIZE size, void* userdata);
void vmarkdown_debug_log(char* msg, void* userdata);

int vmd_parse_to_v(const MD_CHAR* text, MD_SIZE size, unsigned flags, void* userdata);

#endif
