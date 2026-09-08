module vmarkdown

// prepare_console_for_preview configures the platform console before term.ui starts
// writing its UTF-8/ANSI frame buffer. It is intentionally a no-op when stdout is
// redirected or on platforms where no console setup is required.
fn prepare_console_for_preview() {
	$if windows {
		prepare_windows_console_for_preview()
	}
}
