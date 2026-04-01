module main

import os
import vmarkdown

fn main() {
	args := os.args
	if args.len < 2 {
		println(usage())
		return
	}
	match args[1] {
		'preview' {
			if args.len < 3 {
				eprintln('preview requires a markdown file path')
				exit(1)
			}
			vmarkdown.preview_file(args[2]) or {
				eprintln(err)
				exit(1)
			}
		}
		'terminal' {
			if args.len < 3 {
				eprintln('terminal requires a markdown file path')
				exit(1)
			}
			markdown := os.read_file(args[2]) or {
				eprintln(err)
				exit(1)
			}
			output := vmarkdown.render_terminal(markdown) or {
				eprintln(err)
				exit(1)
			}
			println(output)
		}
		'markdown' {
			if args.len < 3 {
				eprintln('markdown requires a markdown file path')
				exit(1)
			}
			markdown := os.read_file(args[2]) or {
				eprintln(err)
				exit(1)
			}
			output := vmarkdown.render_markdown(markdown) or {
				eprintln(err)
				exit(1)
			}
			println(output)
		}
		'html' {
			if args.len < 3 {
				eprintln('html requires a markdown file path')
				exit(1)
			}
			markdown := os.read_file(args[2]) or {
				eprintln(err)
				exit(1)
			}
			output := vmarkdown.render_html(markdown) or {
				eprintln(err)
				exit(1)
			}
			println(output)
		}
		'ast' {
			if args.len < 3 {
				eprintln('ast requires a markdown file path')
				exit(1)
			}
			markdown := os.read_file(args[2]) or {
				eprintln(err)
				exit(1)
			}
			doc := vmarkdown.parse(markdown) or {
				eprintln(err)
				exit(1)
			}
			println(doc.pretty())
		}
		else {
			println(usage())
		}
	}
}

fn usage() string {
	return 'vmarkdown commands:
  v run cmd/vmarkdown preview <file.md>
  v run cmd/vmarkdown terminal <file.md>
  v run cmd/vmarkdown markdown <file.md>
  v run cmd/vmarkdown html <file.md>
  v run cmd/vmarkdown ast <file.md>'
}
