# Benchmarks: zoptia0regex (Zig) vs Go `regexp`

A like-for-like performance comparison between this Zig port and the Go
standard-library `regexp` it is modelled on. The two engines produce
**identical match results** (verified by ~30k differential cases); this measures
how fast they get there.

## Methodology

- **Identical inputs.** Both harnesses run the *same* patterns over the *same*
  bytes: a 256 KB deterministic mixed-text corpus (words, numbers, dates,
  emails, some Unicode) generated once by `tools/genbench.go` into
  `src/bench_corpus.txt`. Cases live in `src/bench.jsonl`.
- **Same calibration.** Each operation is run in a loop whose iteration count
  doubles until a batch exceeds 250 ms; `ns/op = batch_ns / iters`. Compile time
  is measured the same way (100 ms target). Identical logic in
  `tools/benchgo.go` and `src/bench.zig`.
- **Optimized builds.** Zig is built `-OReleaseFast`; Go is the standard
  `go run` build. A result checksum is accumulated and `doNotOptimizeAway`'d to
  prevent dead-code elimination.
- **Allocation.** The Zig harness resets an arena (`retain_capacity`) per
  iteration so scratch allocation is a cheap bump — the fair analogue of Go's
  per-call machine `sync.Pool`. This isolates *engine* throughput from malloc.

> Checksums differ between the two harnesses only because the calibration runs a
> different number of iterations on each; the per-call results are identical (a
> fact established separately by the differential test suite).

## Environment

| | |
|---|---|
| CPU | Apple M4 (4 vCPU) |
| OS | macOS 26.3.1, arm64 |
| Go | go1.26.4 (`regexp`) |
| Zig | 0.16.0, `-OReleaseFast` |

## Results

`ns/op` is per match operation; **Zig/Go < 1.0 means Zig is faster**. Compile
columns are per `Compile()` call.

| case | op | Go ns/op | Zig ns/op | Zig/Go | verdict | Go comp | Zig comp |
|------|----|---------:|----------:|-------:|---------|--------:|---------:|
| literal_hit | find | 199 | 210 | 1.06× | ~equal | 769 | 553 |
| literal_miss | find | 6,030 | 5,620 | **0.93×** | ~equal | 748 | 537 |
| alternation | findall | 9,052,894 | 7,478,255 | **0.83×** | Zig faster | 2,372 | 1,672 |
| charclass_word | findall | 6,526,409 | 6,474,486 | 0.99× | ~equal | 303 | 187 |
| perl_word `\w+` | findall | 7,139,048 | 7,051,021 | 0.99× | ~equal | 314 | 200 |
| digits `\d+` | findall | 3,411,767 | 2,846,551 | **0.83×** | Zig faster | 290 | 179 |
| date `\d{4}-\d{2}-\d{2}` | findall | 3,285,840 | 2,636,208 | **0.80×** | Zig faster | 1,170 | 543 |
| email | findall | 5,028,022 | 4,707,393 | **0.94×** | Zig faster | 1,129 | 565 |
| email_submatch | submatch | 2,010 | 1,915 | 0.95× | ~equal | 1,280 | 720 |
| anchored_multiline `(?m)^\w+` | findall | 2,095,558 | 1,801,492 | **0.86×** | Zig faster | 522 | 268 |
| unicode_letters `\p{L}+` | findall | 8,049,191 | 7,495,326 | **0.93×** | Zig faster | 4,118 | 2,843 |
| dotstar_greedy `p.*e` | find | 3,647 | 2,928 | **0.80×** | Zig faster | 540 | 279 |
| redos_linear `(a+)+$` | match | 8,306 | 32,272 | 3.89× | **Zig slower** | 596 | 315 |
| nested_groups | findall | 8,990,146 | 8,597,853 | 0.96× | ~equal | 1,678 | 691 |
| caseins_literal `(?i)…` | find | 3,517,905 | 4,699,455 | 1.34× | **Zig slower** | 775 | 618 |

## Analysis

**The general NFA engine is competitive-to-faster.** On the 13 cases that run
through the Pike VM in both implementations (Go uses its Pike VM whenever a
pattern isn't simple enough for its one-pass engine), Zig ranges from on-par to
~20% faster (`date` 0.80×, `dotstar` 0.80×, `alternation`/`digits` 0.83×,
`anchored` 0.86×). A faithful port, built `-OReleaseFast` with no GC and cheap
arena scratch, holds its own against Go's mature, hand-tuned engine.

**Compilation is consistently faster** (~1.3–2×, e.g. `unicode_letters`
4,118 → 2,843 ns, `date` 1,170 → 543 ns) — Go does more up-front work
(one-pass analysis, prefix machinery, GC).

**Literal search was the one big gap — and it's now closed.** A bare Pike VM
runs the NFA at every input position, so `literal_miss` (a literal that never
matches, forcing a full scan) started at **310× slower** than Go. Porting Go's
**literal-prefix acceleration** — fast-forward to the next occurrence of the
required prefix instead of stepping the NFA — and implementing the search with a
**vectorized first-byte scan + verify** (the shape of Go's SIMD `bytes.Index`)
brought it to **0.93× — now matching Go**:

| `literal_miss` | ns/op | vs Go |
|---|---:|---:|
| bare Pike VM (no prefix accel) | 1,872,147 | 310× |
| prefix accel via `std.mem.indexOf` | 75,510 | 12.5× |
| prefix accel + SIMD first-byte scan | **5,620** | **0.93×** |

**Where Go still wins** is exactly its two specialized engines, which this port
deliberately omits (see README "Scope"):

- `redos_linear` (3.89×): `(a+)+$` over 2 KB of `a`. Both are **linear-time** —
  the whole point versus a backtracking engine — but Go dispatches small inputs
  to its *bitstate backtracker*, which beats the Pike VM here. (Throughput is
  tiny either way: 2 KB.)
- `caseins_literal` (1.34×): `(?i)performance`. Go compiles a case-insensitive
  literal into its *one-pass* engine; the Pike VM does per-rune fold matching.

Neither affects correctness, and both are documented as deferred optimizations.

## Reproduce

```sh
tools/regen.sh                       # (re)generate the corpus + cases
zig build bench                      # Zig results (ReleaseFast) -> stderr TSV
( cd tools && go run benchgo.go )    # Go results -> stdout TSV
```
