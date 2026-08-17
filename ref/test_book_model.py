"""Standalone checks for the reference model. Run: python ref/test_book_model.py"""
from book_model import BookModel, ADD, CANCEL, MODIFY, TRADE, BID, ASK


def check(name, cond):
    print(f"{'PASS' if cond else 'FAIL'}  {name}")
    assert cond, name


m = BookModel()
m.apply(ADD, BID, 100, 10)
m.apply(ADD, BID, 101, 5)
m.apply(ADD, ASK, 105, 8)
m.apply(ADD, ASK, 104, 3)
tob = m.top_of_book()
check("best_bid highest", tob["best_bid"] == 101)
check("best_ask lowest", tob["best_ask"] == 104)
check("spread", tob["spread"] == 3)
check("mid_sum unhalved", tob["mid_sum"] == 205)

m = BookModel()
m.apply(ADD, BID, 100, 10)
m.apply(ADD, BID, 100, 5)
check("accumulate same price", m.levels[BID][100] == 15)

m = BookModel()
m.apply(ADD, BID, 100, 0xFFF0)
m.apply(ADD, BID, 100, 0x20)
check("saturating add", m.levels[BID][100] == 0xFFFF)

m = BookModel()
m.apply(ADD, BID, 100, 5)
m.apply(CANCEL, BID, 100, 100)
check("cancel clamps and removes", 100 not in m.levels[BID])

m = BookModel()
m.apply(CANCEL, BID, 500, 5)
check("cancel absent no-op", len(m.levels[BID]) == 0)

m = BookModel()
m.apply(ADD, ASK, 200, 10)
m.apply(MODIFY, ASK, 200, 3)
check("modify replaces", m.levels[ASK][200] == 3)
m.apply(MODIFY, ASK, 200, 0)
check("modify to zero removes", 200 not in m.levels[ASK])

m = BookModel()
for k in range(8):
    m.apply(ADD, BID, 300 + k, 5)
m.apply(ADD, BID, 999, 5)
check("book full drops new price", 999 not in m.levels[BID])
check("book full keeps count", len(m.levels[BID]) == 8)

m = BookModel()
check("empty best_bid None", m.best_bid() is None)
check("empty tob spread None", m.top_of_book()["spread"] is None)

print("\nAll reference-model checks passed.")
