module vmarkdown

import encoding.utf8
import strings

// Direct bounded HTML rendering through md4c-html.

pub struct HtmlRenderLimits {
pub:
	max_input_bytes  int = 64 * 1024 * 1024
	max_output_bytes int = 256 * 1024 * 1024
}

pub enum HtmlRenderErrorKind {
	invalid_limits
	input_limit
	invalid_utf8
	output_limit
	renderer_failure
}

pub struct HtmlRenderError {
pub:
	kind        HtmlRenderErrorKind
	offset      int = -1
	native_code int
	message     string
}

pub fn (err HtmlRenderError) msg() string {
	return err.message
}

pub fn (err HtmlRenderError) code() int {
	return 6000 + int(err.kind)
}

pub struct HtmlRenderOptions {
pub:
	parser            ParseOptions
	xhtml             bool
	debug             bool
	verbatim_entities bool
	skip_utf8_bom     bool = true
}

struct HtmlOutputBuilder {
mut:
	sb               strings.Builder
	max_output_bytes int
	written          int
	exceeded         bool
}

pub fn render_html(markdown string) !string {
	return render_html_with_limits(markdown, HtmlRenderOptions{}, HtmlRenderLimits{})
}

pub fn render_html_with_options(markdown string, options HtmlRenderOptions) !string {
	return render_html_with_limits(markdown, options, HtmlRenderLimits{})
}

// render_html_with_limits streams HTML directly from md4c while bounding both
// input and accumulated output bytes. A zero limit is unbounded.
pub fn render_html_with_limits(markdown string, options HtmlRenderOptions, limits HtmlRenderLimits) !string {
	validate_html_render_limits(limits)!
	if u64(markdown.len) > u64(0xffff_ffff) {
		return html_render_error(.input_limit, -1, 0, 'Markdown input exceeds md4c maximum size 4294967295 bytes')
	}
	if limits.max_input_bytes > 0 && markdown.len > limits.max_input_bytes {
		return html_render_error(.input_limit, -1, 0, 'Markdown input exceeds maximum size ${limits.max_input_bytes} bytes')
	}
	if !utf8.validate_str(markdown) {
		offset := first_invalid_utf8_byte(markdown)
		return html_render_error(.invalid_utf8, offset, 0, 'Markdown input is not valid UTF-8 at byte ${offset}')
	}
	mut out := HtmlOutputBuilder{
		sb: strings.new_builder(512)
		max_output_bytes: limits.max_output_bytes
	}
	mut render_flags := u32(0)
	if options.xhtml {
		render_flags |= u32(C.MD_HTML_FLAG_XHTML)
	}
	if options.debug {
		render_flags |= u32(C.MD_HTML_FLAG_DEBUG)
	}
	if options.verbatim_entities {
		render_flags |= u32(C.MD_HTML_FLAG_VERBATIM_ENTITIES)
	}
	if options.skip_utf8_bom {
		render_flags |= u32(C.MD_HTML_FLAG_SKIP_UTF8_BOM)
	}
	rc := C.md_html(markdown.str, u32(markdown.len), html_process_output, &out, options.parser.to_md4c_flags(), render_flags)
	if rc != 0 {
		return html_render_error(.renderer_failure, -1, rc, 'md4c html render failed with code ${rc}')
	}
	if out.exceeded {
		return html_render_error(.output_limit, -1, 0, 'HTML output exceeds maximum size ${limits.max_output_bytes} bytes')
	}
	return out.sb.str()
}

fn validate_html_render_limits(limits HtmlRenderLimits) ! {
	if limits.max_input_bytes < 0 {
		return html_render_error(.invalid_limits, -1, 0, 'max_input_bytes cannot be negative')
	}
	if limits.max_output_bytes < 0 {
		return html_render_error(.invalid_limits, -1, 0, 'max_output_bytes cannot be negative')
	}
}

fn html_render_error(kind HtmlRenderErrorKind, offset int, native_code int, message string) IError {
	return HtmlRenderError{
		kind: kind
		offset: offset
		native_code: native_code
		message: message
	}
}

@[export: 'html_process_output']
fn html_process_output(text &char, size u32, userdata voidptr) {
	mut out := unsafe { &HtmlOutputBuilder(userdata) }
	if size == 0 || out.exceeded {
		return
	}
	if out.max_output_bytes > 0
		&& u64(out.written) + u64(size) > u64(out.max_output_bytes) {
		out.exceeded = true
		return
	}
	out.sb.write_string(unsafe { tos(&u8(text), int(size)).clone() })
	out.written += int(size)
}
