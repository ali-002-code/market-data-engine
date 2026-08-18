# Optimization Story: Pipelining the Book Engine

All Fmax numbers are post-route, measured on the Artix-7 XC7A35T
(xc7a35tcpg236-1, speed grade -1) in Vivado 2025.2, at a 6.667 ns (150 MHz)
constraint. Fmax = 1000 / (6.667 - WNS). No numbers are estimated or assumed.

## The three versions

| Version | Book design                              | WNS (ns) | Fmax (MHz) | Book latency |
|---------|------------------------------------------|----------|------------|--------------|
| v1      | Single-cycle combinational update        | -4.914   | 86.3       | 1 cycle      |
| v2      | 2-stage pipeline, full-overlay forwarding| -5.480   | 82.3       | 2 cycles     |
| v3      | 2-stage pipeline, narrow-bypass forwarding| -4.768  | 87.5       | 2 cycles     |

## What happened, in order

Baseline (v1). The book update (parallel price match, free-slot search,
saturating/clamped arithmetic, write-back) was one combinational cloud between
registers. Post-route showed this register-to-register path inside the book
engine as the critical path: 86.3 MHz, 768 failing endpoints at 150 MHz.

First attempt (v2). Split the update into two stages with a register in the
middle, and added a forwarding path so back-to-back messages to the same level
keep full throughput (read-after-write and allocate-in-flight hazards). This
cut failing endpoints from 768 to 20 and total negative slack from ~1981 ns to
~89 ns: the pipelining fixed the bulk of the timing pressure. But Fmax dropped
to 82.3 MHz. The post-route path showed why: the forwarding rebuilt the whole
effective book (an overlay mux) IN FRONT of the match search, so the long
comparison chain now ran downstream of that mux. The bypass I added to keep
throughput became the new critical path.

Fix (v3). Restructured the forwarding to a narrow bypass: run the match and
free-slot search on the committed book directly (no overlay in front), and
apply the pending-write correction AFTER the search as a small mux, plus a
free-slot exclusion so an in-flight allocation cannot be double-targeted. This
moved the bypass off the front of the search. Result: 87.5 MHz, beating both
the baseline and v2.

## The real ceiling

Every version is routing-dominated: v1 74% route, v2 72%, v3 68%. Only about a
third of the critical-path delay is logic; the rest is interconnect. On a
design this small, cells scatter across the fabric and signals travel far
regardless of logic depth, which is why all three cluster in the low-to-mid
80s MHz. Reducing logic levels (the pipelining) helped at the margin, but the
dominant cost is wire delay, not gate delay. Beating this meaningfully would
need architectural change (wider datapath to cut the byte-serial front end, or
floorplanning to localize the book), not more pipelining.

## Verification note

All three versions pass the same verification: the randomized differential
test (RTL vs reference model, per-message compare) at 100k messages across
multiple seeds, 0 mismatches. The pipelined versions were proven equivalent to
the pre-optimization behavior, so the optimization preserved correctness, not
just changed timing. The v2 -> v3 forwarding rework was re-verified the same
way before re-synthesis.
