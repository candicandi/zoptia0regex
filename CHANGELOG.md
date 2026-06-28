# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/), and this project adheres to
[Semantic Versioning](https://semver.org/).

## [0.2.0] — 2026-06-28

### Added

- **Allocation-free matching via a reusable `Scratch`.** `Regexp.matchScratch`
  and `Regexp.findSubmatchIndexScratch` take a caller-owned `Scratch`
  (`Scratch.init` / `deinit`) and reuse the Pike-VM and bitstate engine buffers
  (sparse-set queues, thread pool, visited bitmap) across calls — the port's
  equivalent of Go's per-`Regexp` `*machine` `sync.Pool`. After warm-up a hot
  match loop does zero heap allocation. The existing `match` / `find` / `replace`
  / `split` API is unchanged; it now wraps the same path with a temporary
  scratch, so the differential suite validates the shared code.

### Performance

- Reusing one `Scratch` across a short-input hot loop is ~1.2–2.8× faster than
  the allocating `match`, closing the per-call allocation gap with Go's pooled
  machine. See BENCHMARKS.md ("Allocation-free matching").
- Pike-VM sparse sets are no longer zeroed on each run — the dense cross-check
  makes a stale sparse index safe — removing two `memset`s from the hot path.

### Validation

- ~30,000 differential cases still byte-for-byte identical to Go, zero leaks
  (the new reuse path is what the suite now exercises).

## [0.1.0] — 2026-06-25

Initial release: a faithful Zig port of Go's `regexp` package.

### Engines

- **Pike VM** (NFA simulation) with submatch capture and leftmost-first
  (and POSIX leftmost-longest) semantics.
- **Bitstate backtracker** for small programs/inputs.
- **One-pass** engine for qualifying anchored regexps.
- **Literal-prefix acceleration** (vectorized first-byte scan + verify).

### Features

- Full `regexp/syntax` parser: literals, alternation, character classes
  (Perl `\d\w\s`, POSIX `[[:…:]]`, Unicode `\p{…}` subset), `.`, anchors
  `^ $ \A \z \b \B`, quantifiers `* + ? {n,m}` (greedy/non-greedy), capturing /
  non-capturing / named groups, inline flags `(?imsU)`, escapes and `\Q…\E`.
- Public API mirroring Go: `compile`, `compilePOSIX`, `mustCompile`, `match`,
  `find` / `findIndex`, `findSubmatch` / `findSubmatchIndex`,
  `findAll` / `findAllIndex` / `findAllSubmatchIndex`, `replaceAllString` /
  `replaceAllLiteralString` / `replaceAllStringFunc`, `expand`, `split`,
  `quoteMeta`, plus introspection (`numSubexp`, `subexpIndex`, `literalPrefix`).
- Unicode case folding via tables generated from Go's `unicode.SimpleFold`
  (correct across all of Unicode).
- Parser resource limits matching Go (`maxHeight`, `maxRunes`, repeat-size).

### Validation

- ~30,000 differential cases vs Go's `regexp` (curated + randomized +
  leftmost-longest), byte-for-byte identical, zero leaks.

### Performance

- ~11% faster than Go on average (geomean 0.887× over 20 workloads), ~1.7×
  faster to compile; faster than Go on anchored validation patterns.
