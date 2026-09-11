# Changelog

All notable changes to vmarkdown are documented here. The project follows
[Semantic Versioning](https://semver.org/); before `1.0.0`, minor releases may
still refine public APIs with migration notes in this file.

## [Unreleased]

No user-facing changes yet.

## [0.1.0] - 2026-09-12

This release establishes the first documented library contract for the typed,
source-aware Markdown engine. It contains all changes made after `v0.0.6`.

### Added

- Explicit CommonMark and GFM dialects plus opt-in wiki-link, LaTeX-math, and
  underline AST nodes.
- Public source spans, UTF-8 source coordinates, AST traversal, queries,
  validated rewrites, composable lint rules, and atomic lint fixes.
- Versioned VMDA v1 binary decoding, stable structural identities, semantic
  identities, chunk planning, and incremental in-memory ingest.
- Structured public errors and configurable resource budgets for parsing,
  validation, decoding, rendering, transformations, linting, and ingest.
- External-module API contract tests and a 723-example structural conformance
  gate covering CommonMark, GFM features, and supported md4c extensions.
- Mouse-wheel navigation and clickable view tabs in the interactive terminal
  preview, with real-PTY regression coverage.
- A static project website describing the library and terminal editor.

### Changed

- Markdown parsing now rejects invalid UTF-8 instead of allowing native parser
  behavior to leak through the public contract.
- Application-assembled ASTs can use checked rendering, encoding, identity,
  traversal, transformation, and ingest boundaries before consuming data.
- Markdown rendering has broader semantic round-trip coverage for nested block
  structures, tables, links, images, code spans, and fenced code blocks.

### Hardened

- Text parsing, binary decoding, AST validation, and direct HTML rendering have
  bounded defaults and reject negative limits.
- VMDA decoding rejects malformed envelopes, non-canonical varints, invalid
  enums, trailing bytes, invalid UTF-8, and resource-budget violations.
- Terminal output sanitizes untrusted control sequences by default.

### Compatibility

- The persisted binary format remains VMDA version 1.
- `parse()` retains the established GFM-oriented defaults; use
  `parse_with_dialect()` when an explicit dialect contract is required.
- Non-fallible AST methods remain fast paths for parser-produced or already
  validated documents. Checked variants are intended for application-built
  ASTs.

[Unreleased]: https://github.com/guweigang/vmarkdown/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/guweigang/vmarkdown/compare/v0.0.6...v0.1.0
