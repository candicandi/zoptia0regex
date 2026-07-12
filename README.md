<div align="center">

# zoptia0regex

### Go's `regexp`, faithfully replicated in Zig — and faster.

A **regular-expression (regex) library for Zig** — a high-fidelity port of the
RE2 engine, with a linear-time guarantee and **~30,000 tests proving
byte-for-byte parity with Go**.

[![CI](https://github.com/zoptia/zoptia0regex/actions/workflows/ci.yml/badge.svg)](https://github.com/zoptia/zoptia0regex/actions)
[![Zig](https://img.shields.io/badge/Zig-0.16-f7a41d?logo=zig&logoColor=white)](https://ziglang.org/)
[![License](https://img.shields.io/badge/License-Apache--2.0-blue.svg)](LICENSE)

</div>

---

## ⚡ Faster than Go. Identical to Go. Provably.

Head-to-head against Go's standard-library `regexp` — same patterns, same
inputs, same 256 KB corpus, same calibration, Zig built `ReleaseFast` —
**zoptia0regex is ~27% faster on average** and compiles patterns **~1.6×
faster**. And it doesn't trade correctness for speed: ~30,000 differential tests
prove its output is **byte-for-byte identical to Go's**.

Not "inspired by." **Proven identical.**

- 🚀 **Faster than Go at matching.** Geometric mean across 20 workloads:
  **0.73×** Go's time. Anchored "validation" patterns hit the one-pass engine
  and fly — up to **~2× faster** — and a first-byte prefilter Go doesn't have
  runs unanchored case-insensitive scans at **3.5× Go's speed**.
- 🛡️ **Linear-time. ReDoS-proof.** Thompson NFA simulation means no catastrophic
  backtracking, ever. A pattern like `(a+)+` that hangs PCRE, JS, and Python
  runs in linear time here.
- ✅ **Proven identical to Go.** ~30,000 differential cases run the *real* Go
  `regexp` and this engine on the same inputs and require identical results.
  **Zero mismatches. Zero leaks.** The fidelity isn't a claim — it's enforced by
  the suite on every push.
- 🌍 **Unicode-correct.** `(?i)` case folding uses tables generated directly from
  Go's `unicode.SimpleFold` — correct across *all* of Unicode, not just ASCII.

## In a nutshell

```zig
var re = try regex.compile(gpa, "(\\w+)@(\\w+)\\.(\\w+)");
defer re.deinit();

const subs = (try re.findSubmatch(gpa, "ping me@example.com")).?;
// subs => "me" / "example" / "com"
```

→ Full install & API in the **[usage guide](docs/usage.md)**.

## 📊 The benchmark

Zig vs Go, same workload, same machine. Lower is faster — `< 1.0×` means Zig
wins.

| Workload | Engine | Zig / Go |
|---|---|---|
| `(?i)performance` (unanchored scan) | first-bytes + Pike VM | **0.28×** |
| alternation | first-bytes + Pike VM | **0.37×** |
| `\A[a-z]+\z` (anchored validation) | one-pass | **0.48×** |
| `\A\d+\z` (anchored validation) | one-pass | **0.50×** |
| `\A(?i)performance\z` | one-pass | **0.63×** |
| `\A(...)@(...)\z` with captures | one-pass | **0.79×** |
| date scan | Pike VM | **0.81×** |
| `\d+` | Pike VM | **0.87×** |
| **Geometric mean (20 workloads)** | — | **0.73×** |
| Pattern compilation | — | **0.63×** (~1.6× faster) |

**The honest caveat:** there is exactly **one** workload where Go wins — a
nested-quantifier match on a small input (`(a+)+$`, bitstate engine) at
**1.10×**, both sides in single-digit microseconds. Everything else is on par
or faster. Full methodology and the complete table:
**[BENCHMARKS.md](BENCHMARKS.md)**.

## Why this exists

zoptia0regex is a faithful, high-fidelity replica of Go's standard-library
`regexp` package — the RE2 design by Russ Cox. It mirrors Go's **leftmost-first**
match semantics (plus **POSIX leftmost-longest**), the same `Find` / `Replace` /
`Split` / submatch API surface, and the same four-stage pipeline:
**parse → simplify → compile → execute**. All three of Go's execution engines
are here — the **one-pass** matcher, the **bitstate backtracker**, and the
**Pike VM** — plus literal-prefix acceleration, with the engine chosen
automatically per pattern.

All three engines share literal-prefix acceleration (with a Rabin-Karp
fallback, like Go's `bytes.Index`), and the port adds a **first-byte
prefilter** Go doesn't have: when a pattern has no literal prefix but can only
start with a few ASCII bytes — a case-insensitive literal, a small leading
class — the unanchored engines skip ahead at memchr speed instead of stepping
the NFA at every position.

That's where the speed *and* the fidelity come from. For the full design
walkthrough, see **[docs/internals.md](docs/internals.md)**.

## Features

- 🧩 Full Go `regexp/syntax`: literals, alternation, character classes (`[...]`,
  `[^...]`, ranges, Perl `\d\w\s`, POSIX `[[:alpha:]]`, Unicode `\p{...}` curated
  subset), `.`, anchors `^ $ \A \z \b \B`.
- 🔁 Quantifiers `* + ? {n,m}`, greedy and non-greedy.
- 🏷️ Capturing, non-capturing, and named groups; inline flags `(?imsU)`;
  escapes; `\Q...\E`.
- ⚖️ Two match modes: leftmost-first (Go default) and POSIX leftmost-longest.
- 🛡️ Linear-time guarantee — immune to ReDoS.
- ⚡ Allocation-free hot loops: reuse a `Scratch` across matches
  (`matchScratch`) for zero-allocation steady state, like Go's machine pool.
- 🌍 Full-Unicode case folding via Go-derived tables.
- 🚫 Same intentional limits as RE2/Go: **no backreferences, no `\C`**.

## Install & use

Requires **Zig 0.16**.

```sh
zig fetch --save git+https://github.com/zoptia/zoptia0regex
```

```zig
const regex = @import("regex");

var re = try regex.compile(gpa, "(\\w+)@(\\w+)\\.(\\w+)");
defer re.deinit();
const subs = (try re.findSubmatch(gpa, "ping me@example.com")).?;
```

That's the taste — the **[full install + API guide lives in docs/usage.md](docs/usage.md)**:
wiring the dependency into `build.zig`, every `Find` / `FindAll` / `Replace` /
`Split` / submatch variant, the memory model, and POSIX mode.

## Trust & validation

Every push runs the **full ~30,000-case differential suite** in CI, across three
corpora:

| Corpus | Cases | What it checks |
|---|---|---|
| Curated | ~5.9k | Hand-picked edge cases across every feature |
| Random / fuzz | ~9k | Grammar-generated patterns & inputs |
| POSIX leftmost-longest | ~15k | POSIX match semantics |

Each case runs the *real* Go `regexp` and zoptia0regex on the same input and
requires **byte-for-byte identical** `FindSubmatchIndex` / `FindAll` /
`ReplaceAll` / `Split`. Result: **zero mismatches, zero memory leaks** (checked
under `std.testing.allocator`). CI stays green.

```sh
zig build test        # unit + behaviour tests
zig build difftest    # the full ~30k differential suite (no Go toolchain needed)
zig build bench       # benchmark vs Go (ReleaseFast)
```

## License & acknowledgement

Licensed under **Apache-2.0**.

zoptia0regex is a faithful port of Go's standard-library `regexp` package. Deep
thanks to **Russ Cox** and the **Go authors** — portions are derived from Go's
BSD-3-Clause-licensed code, attributed in [NOTICE](NOTICE). Not affiliated with
Go or Google.

---

<div align="center">

**[Usage guide](docs/usage.md)** · **[Internals](docs/internals.md)** ·
**[Benchmarks](BENCHMARKS.md)** · **[Contributing](CONTRIBUTING.md)**

</div>
