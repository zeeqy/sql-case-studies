"""The e-wallet generator must be reproducible and internally consistent (no DB needed)."""

from collections import defaultdict
from decimal import Decimal

import pytest

from sqlcases.generator import config as C
from sqlcases.generator.simulate import WALLET_OFFSET, generate


@pytest.fixture(scope="module")
def world():
    return generate(n_users=900, seed=7)


def test_same_seed_same_data(world):
    again = generate(n_users=900, seed=7)
    assert again.transactions == world.transactions
    assert again.users == world.users


def test_different_seed_different_data(world):
    assert generate(n_users=900, seed=8).transactions != world.transactions


def test_ids_and_references(world):
    wallet_ids = {w[0] for w in world.wallets}
    merchant_ids = {m[0] for m in world.merchants}
    assert all(w[0] == w[1] + WALLET_OFFSET for w in world.wallets)
    txn_ids = [t[0] for t in world.transactions]
    assert txn_ids == list(range(1, len(txn_ids) + 1))
    for t in world.transactions:
        assert t[1] in wallet_ids
        assert t[7] is None or t[7] in merchant_ids
        assert t[8] is None or t[8] in wallet_ids


def test_types_match_their_columns(world):
    for _id, _w, _ts, kind, amount, _st, _ch, merchant, cp, bill, _p, _cb in world.transactions:
        assert amount > 0
        assert (merchant is not None) == (kind == "merchant")
        assert (cp is not None) == (kind == "p2p")
        assert (bill is not None) == (kind == "bill")


def test_no_wallet_ever_goes_negative(world):
    bal = defaultdict(Decimal)
    for _id, w, _ts, kind, amount, status, _ch, _m, cp, _b, _p, cashback in world.transactions:
        if status != "success":
            continue
        amt = Decimal(str(amount))
        if kind == "topup":
            bal[w] += amt
        else:
            bal[w] -= amt
            if cp is not None:
                bal[cp] += amt
        bal[w] += Decimal(str(cashback))
        assert bal[w] >= 0, (w, _id)


def test_cashback_follows_promo_rules(world):
    promos = {p.promo_id: p for p in C.PROMOS}
    mcc = {m[0]: m[2] for m in world.merchants}
    for t in world.transactions:
        _id, _w, ts, kind, amount, status, _ch, merchant, _cp, _b, promo_id, cashback = t
        if promo_id is None:
            assert cashback == 0
            continue
        p = promos[promo_id]
        assert kind == "merchant" and status == "success"
        assert p.start <= ts.date() <= p.end
        assert p.mccs is None or mcc[merchant] in p.mccs
        assert cashback <= p.cap + 1e-9


def test_planted_mules_and_decoys_exist(world):
    assert len({b[0] for b in world.mule_bursts}) >= 3
    # decoys: some non-mule wallet receives 5+ P2P transfers within 30 minutes
    mules = {b[0] + WALLET_OFFSET for b in world.mule_bursts}
    inbound = defaultdict(list)
    for t in world.transactions:
        if t[3] == "p2p" and t[8] not in mules:
            inbound[t[8]].append(t[2])

    def has_burst(times):
        times.sort()
        return any((times[i + 4] - times[i]).total_seconds() <= 1800 for i in range(len(times) - 4))

    assert any(has_burst(v) for v in inbound.values())
