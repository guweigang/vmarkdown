# vmarkdown roadmap

## Product direction

vmarkdown is a typed, source-aware Markdown engine for V. Its primary job is to
turn Markdown into a trustworthy AST that applications can inspect, transform,
lint, render, and persist.

The core product surface is:

- Markdown parsing and explicit dialects
- typed block and inline AST nodes with source spans
- validation, traversal, queries, rewrites, and linting
- text, Markdown, JSON, HTML, and terminal rendering
- stable identities and the versioned VMDA persistence format

The CLI, interactive preview/editor, file-encoding adapters, Mermaid renderer,
generic diagram schema, and ingest store are application or integration layers.
They remain supported, but they should not drive new core APIs merely to make
the public surface symmetrical.

## Scope rules

- Freeze the `0.1` public surface except for demonstrated correctness,
  portability, or usability problems.
- Require a real caller or reference integration before adding a new public API.
- Do not add `_checked`, `_with_options`, or `_with_limits` variants solely for
  naming symmetry. Prefer one cohesive operation when a new use case genuinely
  needs several controls.
- Keep the default path simple. Advanced validation and resource controls are
  boundary tools, not the primary quick-start experience.
- Put new preview, diagram, storage, or CLI behavior behind an application-layer
  boundary so the core engine can stay understandable and embeddable.

## Milestones

### 0.1 — Contract and release baseline

- Publish the accumulated parser, AST, conformance, safety, and persistence work.
- Document user-visible changes, compatibility guarantees, and the VMDA format.
- Ship reproducible macOS and Windows artifacts with project and third-party
  licenses.
- Pin the supported V compiler baseline in `.v-version` and validate it across
  the release matrix.
- Treat the public API contract and conformance suites as release gates.

### 0.2 — Package boundaries

- Inventory public declarations by core, integration, and application layer.
- Move preview/editor and diagram functionality behind explicit V submodules or
  companion packages without changing their behavior first.
- Reduce the core README to installation, parsing, transformation, rendering,
  and persistence; move application manuals into focused documents.
- Add reference integrations for a renderer, a lint/fix workflow, and an
  incremental-ingest consumer before designing more APIs.

### 0.3 — Source-aware transformations

- Improve edit generation around source spans so transformations can preserve
  untouched source text and formatting.
- Define conflict handling and composition for multiple structural edits.
- Measure reparsing and transformation performance on real Markdown corpora.

## Continuous engineering work

- Fuzz the V callback bridge and VMDA decoder, not only the vendored md4c core.
- Run sanitizer builds for the C boundary where CI environments support them.
- Track the vendored md4c revision and review upstream changes deliberately.
- Maintain cross-platform tests and benchmark trends without turning noisy CI
  timing into a strict microbenchmark.

## Non-goals for 0.1

- Source-exact Markdown round trips
- Complete Mermaid compatibility
- A general-purpose diagram interchange standard
- A full-screen editor competing with dedicated editors
- More public API variants without a concrete consumer
