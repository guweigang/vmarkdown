@[has_globals]
module vmarkdown

#include <windows.h>

const windows_utf8_code_page = u32(65001)

const windows_enable_virtual_terminal_processing = u32(0x0004)

struct WindowsPreviewConsoleState {
mut:
	configured          bool
	stdout_handle       voidptr
	output_code_page    u32
	output_console_mode u32
}

__global windows_preview_console_state = WindowsPreviewConsoleState{}

fn C.GetConsoleOutputCP() u32
fn C.SetConsoleOutputCP(code_page u32) bool

fn windows_preview_output_mode(mode u32) u32 {
	return mode | windows_enable_virtual_terminal_processing
}

fn prepare_windows_console_for_preview() {
	if windows_preview_console_state.configured {
		return
	}
	stdout_handle := C.GetStdHandle(C.STD_OUTPUT_HANDLE)
	if stdout_handle == C.INVALID_HANDLE_VALUE || isnil(stdout_handle) {
		return
	}
	mut output_mode := u32(0)
	// A failed GetConsoleMode means stdout is redirected rather than attached to
	// a console. In that case the UTF-8 byte stream must remain untouched.
	if !C.GetConsoleMode(stdout_handle, &output_mode) {
		return
	}
	output_code_page := C.GetConsoleOutputCP()
	if output_code_page == 0 {
		return
	}
	new_mode := windows_preview_output_mode(output_mode)
	if !C.SetConsoleMode(stdout_handle, new_mode) {
		return
	}
	if !C.SetConsoleOutputCP(windows_utf8_code_page) {
		C.SetConsoleMode(stdout_handle, output_mode)
		return
	}
	windows_preview_console_state = WindowsPreviewConsoleState{
		configured:          true
		stdout_handle:       stdout_handle
		output_code_page:    output_code_page
		output_console_mode: output_mode
	}
	at_exit(restore_windows_console_after_preview) or { restore_windows_console_after_preview() }
}

fn restore_windows_console_after_preview() {
	if !windows_preview_console_state.configured {
		return
	}
	C.SetConsoleMode(windows_preview_console_state.stdout_handle,
		windows_preview_console_state.output_console_mode)
	C.SetConsoleOutputCP(windows_preview_console_state.output_code_page)
	windows_preview_console_state.configured = false
}
