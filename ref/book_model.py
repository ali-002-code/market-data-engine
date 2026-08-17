"""Reference L2 order book model.

Deliberately written the obvious way (dict per side) so it is correct by
inspection. It is the oracle for differential testing against the RTL, so it
must mirror the RTL SEMANTICS exactly while being structurally different.

Semantics (must match book_engine.sv):
  A level exists iff its qty != 0.
  ADD    : qty[price] += q, saturating at 0xFFFF. If the price is new and
           there is no free level, drop it (book full).
  CANCEL : qty[price] -= q, clamped at 0 (removes the level at 0). No-op if
           the price is absent.
  TRADE  : same as CANCEL at L2 scope. No-op if absent.
  MODIFY : qty[price] = q (q == 0 removes the level). No-op if absent.
"""

ADD, CANCEL, MODIFY, TRADE = 0, 1, 2, 3
BID, ASK = 0, 1

QTY_MAX = 0xFFFF


class BookModel:
    def __init__(self, num_levels=8):
        self.num_levels = num_levels
        # price -> qty, one dict per side; a price is present iff qty != 0
        self.levels = {BID: {}, ASK: {}}

    def apply(self, mtype, side, price, qty):
        book = self.levels[side]
        present = price in book

        if mtype == ADD:
            if present:
                book[price] = min(book[price] + qty, QTY_MAX)
            else:
                if qty != 0 and len(book) < self.num_levels:
                    book[price] = min(qty, QTY_MAX)
                # else: new price with no room, or zero qty -> drop
        elif mtype in (CANCEL, TRADE):
            if present:
                new = book[price] - qty
                if new > 0:
                    book[price] = new
                else:
                    del book[price]
            # else: no-op
        elif mtype == MODIFY:
            if present:
                if qty == 0:
                    del book[price]
                else:
                    book[price] = min(qty, QTY_MAX)
            # else: no-op

    def best_bid(self):
        b = self.levels[BID]
        return max(b) if b else None

    def best_ask(self):
        a = self.levels[ASK]
        return min(a) if a else None

    def top_of_book(self):
        """Returns a dict mirroring the RTL outputs.

        best_bid / best_ask are None when that side is empty (RTL: valid=0).
        spread and mid_sum are None unless both sides are populated.
        mid_sum is the UN-HALVED sum, matching the RTL's 17-bit mid_sum.
        """
        bb = self.best_bid()
        ba = self.best_ask()
        both = bb is not None and ba is not None
        return {
            "best_bid": bb,
            "best_ask": ba,
            "spread": (ba - bb) if both else None,
            "mid_sum": (bb + ba) if both else None,
        }
