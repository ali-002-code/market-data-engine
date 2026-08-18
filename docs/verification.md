# Verification

## Directed tests (per module)
- msg_decoder: 2 tests (field slicing, all message types)
- stream_framer: 3 tests (single message, back-to-back, valid gap)
- book_engine: 9 tests (add, accumulate, cancel partial/full, cancel absent
  no-op, modify replace/free, trade, saturating add, underflow clamp, book full)
- top_of_book: 5 tests (basic, empty side, empty book, single level, zero-qty ignore)
- market_data_top: 3 tests (end-to-end book, cancel moves best, out_valid pulse)

Total: 22 directed tests.

## Reference model
A dict-based Python order book (ref/book_model.py), written the obvious way so
it is correct by inspection. 14 standalone self-checks mirror the RTL edge cases.
It is structurally different from the RTL (dicts vs parallel register scan) on
purpose: a shared bug is unlikely across two different implementations.

## Differential test
Randomized per-message comparison (sim/test_diff.py): the same biased-random
stream drives both the RTL and the reference; best bid/ask/spread/mid are
compared after every message.

Stimulus is biased, not uniform: a 12-price pool for an 8-level book forces
frequent collisions, refills, and book-full; message types are weighted so
cancels and modifies land on existing levels often.

Result: 100,000 messages, multiple seeds, 0 mismatches.

### A real bug this caught
At message 6 (seed 1) the harness flagged a crossed book (best bid > best ask):
the RTL wrapped spread to 0xFFFF while the reference gave -1. This was an
unspecified edge case, not a coding slip. Resolved by defining spread as a
signed 16-bit value, preserving the crossed-book condition rather than hiding
it. Assumes prices fit in 15 bits (holds for this design).

## Reproducing
    cd sim
    NUM_MSGS=100000 SEED=1 make -f Makefile.diff
    NUM_MSGS=100000 SEED=2 make -f Makefile.diff
