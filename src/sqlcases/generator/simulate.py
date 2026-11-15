"""Seeded simulation of a Malaysian e-wallet: users, merchants, promotions, transactions.

How it works:
1. Make users (signup date, state, KYC, how active, how long they stay) and merchants.
2. For each user and each month they are active, draw merchant payments, P2P transfers
   and bills. Promotions add extra eligible spend (the planted, "true" effect).
3. Plant mule accounts: bursts of round-amount P2P transfers in, then quickly out.
4. Replay all events in time order with a balance per wallet. When a payment would
   overdraw the wallet, add a top-up a few minutes earlier, like a user reloading
   at the counter. Balances therefore never go negative, and top-ups look realistic.

Times are integer seconds since START (MYT). Money is integer sen (1/100 MYR), so
there is no float rounding.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta

import numpy as np

from sqlcases.generator import config as C
from sqlcases.generator.names import make_names

DAY = 86_400
T0 = datetime(C.START.year, C.START.month, C.START.day)
N_DAYS = (C.END - C.START).days + 1
WALLET_OFFSET = 100_000  # wallet_id = user_id + 100000, so mixing the two up fails loudly

AGE_BANDS = ["18-24", "25-34", "35-44", "45-54", "55+"]
AGE_P = [0.22, 0.34, 0.22, 0.13, 0.09]
AGE_ACTIVITY = [1.1, 1.25, 1.0, 0.8, 0.6]
NAME_WORDS = [
    "Seri",
    "Bestari",
    "Jaya",
    "Indah",
    "Murni",
    "Maju",
    "Sentosa",
    "Harmoni",
    "Cahaya",
    "Mutiara",
    "Delima",
    "Kenanga",
    "Melati",
    "Cempaka",
    "Bintang",
    "Damai",
    "Permai",
    "Gemilang",
    "Ceria",
    "Wangi",
]
NATIONAL_MCC = {4121, 4111}
TOPUP_SOURCES = ["fpx", "card", "cash_counter"]
# More cash-counter reloads outside the big cities (my assumption, for a visible regional pattern)
RURAL_STATES = {
    "Kelantan",
    "Terengganu",
    "Kedah",
    "Perlis",
    "Sabah",
    "Sarawak",
    "Pahang",
}  # ride-hailing and transit operators are national, not per state


def _months() -> list[tuple[int, int, int, int]]:
    """(year, month, first_day_index, n_days) for every month in the range."""
    out, d = [], C.START
    while d <= C.END:
        nxt = date(d.year + d.month // 12, d.month % 12 + 1, 1)
        out.append((d.year, d.month, (d - C.START).days, (nxt - d).days))
        d = nxt
    return out


MONTHS = _months()


@dataclass
class World:
    users: list[tuple] = field(default_factory=list)
    wallets: list[tuple] = field(default_factory=list)
    merchants: list[tuple] = field(default_factory=list)
    promotions: list[tuple] = field(default_factory=list)
    transactions: list[tuple] = field(default_factory=list)
    mule_bursts: list[tuple] = field(default_factory=list)
    promo_uplift: list[tuple] = field(default_factory=list)


def _ts(t: int) -> datetime:
    return T0 + timedelta(seconds=int(t))


class Sim:
    def __init__(self, n_users: int, seed: int):
        self.rng = np.random.default_rng(seed)
        self.n = n_users
        self.hour_p = np.array(C.HOURS) / sum(C.HOURS)
        self.states = list(C.STATES)
        self.state_p = np.array(list(C.STATES.values())) / sum(C.STATES.values())
        self.cats = C.CATEGORIES
        self.topup_p = [
            [0.45, 0.25, 0.30] if st in RURAL_STATES else [0.58, 0.36, 0.06] for st in self.states
        ]
        self.events: list[list] = []  # [t, user, type, sen, merchant, cp_user, bill, channel, ok]
        self._buf, self._hbuf, self._i = np.empty(0), np.empty(0, dtype=np.int64), 0
        self._mcache: dict[tuple[int, int, int], tuple[np.ndarray, np.ndarray]] = {}

    def _refill(self) -> None:
        # Drawing randoms one by one from numpy costs ~1 us each; batches are ~50x faster.
        self._buf = self.rng.random(1 << 18)
        self._hbuf = self.rng.choice(24, size=1 << 18, p=self.hour_p)
        self._i = 0

    def _u(self) -> tuple[float, int]:
        """One uniform float and one hour-of-day draw from the buffers."""
        if self._i >= len(self._buf):
            self._refill()
        i = self._i
        self._i += 1
        return float(self._buf[i]), int(self._hbuf[i])

    # ---------------------------------------------------------------- helpers
    def _time_in(self, s: int, e: int) -> int:
        """A random second in [s, e) following the hour-of-day profile."""
        d0, d1 = s // DAY, max(s // DAY + 1, -(-e // DAY))
        u, hour = self._u()
        day = d0 + int(u * (d1 - d0))
        t = day * DAY + hour * 3600 + int((u * 1e6) % 3600)
        return min(max(t, s + 1), e - 1)

    def _sen(self, myr: float) -> int:
        return max(100, int(round(myr * 100)))

    # ---------------------------------------------------------------- users
    def make_users(self) -> None:
        r, n = self.rng, self.n
        m_w = np.array([1 + 1.6 * i / (len(MONTHS) - 1) for i in range(len(MONTHS))])  # growth
        for p in C.PROMOS:  # acquisition campaigns pull signups into their months
            for i, (y, mo, _, _) in enumerate(MONTHS):
                if (y, mo) in {(p.start.year, p.start.month), (p.end.year, p.end.month)}:
                    m_w[i] *= p.signup_boost
        month_idx = r.choice(len(MONTHS), size=n, p=m_w / m_w.sum())

        self.state = r.choice(len(self.states), size=n, p=self.state_p)
        self.age = r.choice(5, size=n, p=AGE_P)
        self.kyc = np.where(r.random(n) < 0.45, "full", "basic").tolist()
        names = make_names(r, n)

        self.signup = np.zeros(n, dtype=np.int64)
        self.end = np.zeros(n, dtype=np.int64)
        self.lam = np.zeros(n)
        self.prefs = r.dirichlet([c.weight * 25 for c in self.cats], size=n)
        horizon = N_DAYS * DAY
        for u in range(n):
            _, _, d0, nd = MONTHS[month_idx[u]]
            self.signup[u] = (
                (d0 + int(r.integers(0, nd))) * DAY
                + int(r.choice(24, p=self.hour_p)) * 3600
                + int(r.integers(0, 3600))
            )
            k = self.kyc[u]
            if r.random() < C.TRYER_SHARE[k]:
                life_days = 1 + r.exponential(C.TRYER_DAYS)
            else:
                life_days = r.geometric(C.MONTHLY_CHURN[k]) * 30.4 + r.uniform(-15, 15)
            self.end[u] = min(horizon, self.signup[u] + int(max(1, life_days) * DAY))
            self.lam[u] = (
                r.lognormal(math.log(5.0), 0.7)
                * AGE_ACTIVITY[self.age[u]]
                * (1.15 if k == "full" else 1.0)
            )

        # friends for P2P: mostly people in the same state
        by_state: dict[int, np.ndarray] = {
            s: np.flatnonzero(self.state == s) for s in range(len(self.states))
        }
        self.friends = []
        for u in range(n):
            same = by_state[self.state[u]]
            k_same = int(r.integers(2, 6))
            f = list(r.choice(same, size=min(k_same, len(same)), replace=False))
            f += list(r.integers(0, n, size=int(r.integers(1, 4))))
            self.friends.append([x for x in dict.fromkeys(f) if x != u])
        # friendship goes both ways, so P2P relationships can be reciprocal
        for u in range(n):
            for f in list(self.friends[u]):
                if u not in self.friends[f]:
                    self.friends[f].append(u)

        self.bills = []
        for u in range(n):
            if r.random() < C.PAYS_BILLS[self.kyc[u]]:
                cats = r.choice(list(C.BILLS), size=int(r.integers(1, 4)), replace=False)
                self.bills.append([(c, int(r.integers(0, 28))) for c in cats])
            else:
                self.bills.append([])

        self.world.users = [
            (
                u + 1,
                names[u],
                self.states[self.state[u]],
                AGE_BANDS[self.age[u]],
                self.kyc[u],
                _ts(self.signup[u]),
            )
            for u in range(n)
        ]
        self.world.wallets = [
            (
                u + 1 + WALLET_OFFSET,
                u + 1,
                "premium" if self.kyc[u] == "full" and r.random() < 0.6 else "lite",
                _ts(self.signup[u]),
            )
            for u in range(n)
        ]

    # ---------------------------------------------------------------- merchants
    def make_merchants(self) -> None:
        r = self.rng
        self.m_pool = []  # per category: (ids, state_idx or -1, onboard_t, popularity)
        mid = 0
        rows = []
        for c in self.cats:
            ids, st, onb, pop = [], [], [], []
            for _ in range(c.n_merchants):
                mid += 1
                national = c.mcc in NATIONAL_MCC
                s = -1 if national else int(r.choice(len(self.states), p=self.state_p))
                # 80% already on the platform at launch, the rest join over the two years
                if r.random() < 0.8:
                    on_day = -int(r.integers(30, 900))
                else:
                    on_day = int(r.integers(0, N_DAYS - 60))
                name = f"{r.choice(c.prefixes)} {r.choice(NAME_WORDS)} {r.choice(NAME_WORDS)}"
                rows.append(
                    (
                        mid,
                        name,
                        c.mcc,
                        c.name,
                        "National" if national else self.states[s],
                        C.START + timedelta(days=on_day),
                    )
                )
                ids.append(mid)
                st.append(s)
                onb.append(on_day * DAY)
                pop.append(r.pareto(1.2) + 0.2)  # a few merchants get most of the traffic
            self.m_pool.append((np.array(ids), np.array(st), np.array(onb), np.array(pop)))
        self.world.merchants = rows

    def _pick_merchant(self, ci: int, u: int, t: int) -> int:
        local = self._u()[0] < 0.8  # most spending happens in the user's home state
        month = t // (30 * DAY)
        key = (ci, int(self.state[u]) if local else -2, month)
        if key not in self._mcache:
            ids, st, onb, pop = self.m_pool[ci]
            ok = onb <= month * 30 * DAY  # merchant must be on the platform by then
            if local:
                here = ok & ((st == self.state[u]) | (st == -1))
                if here.any():
                    ok = here
            w = np.cumsum(pop * ok)
            self._mcache[key] = (ids, w / w[-1])
        ids, cdf = self._mcache[key]
        return int(ids[min(np.searchsorted(cdf, self._u()[0]), len(ids) - 1)])

    # ---------------------------------------------------------------- behaviour
    def simulate_users(self) -> None:
        r = self.rng
        growth = np.array([[(1 + c.growth) ** i for c in self.cats] for i in range(len(MONTHS))])
        promo_win = [
            ((p.start - C.START).days * DAY, ((p.end - C.START).days + 1) * DAY, p)
            for p in C.PROMOS
        ]
        cat_index = {c.mcc: i for i, c in enumerate(self.cats)}

        for u in range(self.n):
            s_u, e_u = int(self.signup[u]), int(self.end[u])
            for mi, (y, mo, d0, nd) in enumerate(MONTHS):
                ms, me = d0 * DAY, (d0 + nd) * DAY
                s, e = max(s_u, ms), min(e_u, me)
                if s >= e:
                    continue
                frac = (e - s) / (me - ms)
                rate = self.lam[u] * C.SEASON.get((y, mo), 1.0) * frac
                p = self.prefs[u] * growth[mi]
                p = p / p.sum()

                n_pay = r.poisson(rate * 0.78)
                for ci in r.choice(len(p), size=n_pay, p=p):
                    self._merchant_event(u, int(ci), self._time_in(s, e))

                for ps, pe, promo in promo_win:  # planted promotion effect
                    a, b = max(s, ps), min(e, pe)
                    if a >= b or promo.true_uplift <= 1:
                        continue
                    elig = (
                        list(range(len(p)))
                        if promo.mccs is None
                        else [cat_index[m] for m in promo.mccs]
                    )
                    pe_ = p[elig]
                    days = (b - a) / DAY
                    extra = r.poisson(
                        self.lam[u] * 0.78 * pe_.sum() * (promo.true_uplift - 1) * days / 30.4
                    )
                    for j in r.choice(len(elig), size=extra, p=pe_ / pe_.sum()):
                        self._merchant_event(u, elig[int(j)], self._time_in(a, b))

                for _ in range(r.poisson(rate * 0.22)):
                    self._p2p_event(u, self._time_in(s, e))

                for cat, dom in self.bills[u]:
                    t = (d0 + min(dom, nd - 1)) * DAY + int(r.integers(8 * 3600, 23 * 3600))
                    if s < t < e:
                        amt = C.BILLS[cat] * r.lognormal(0, 0.25)
                        self._add(t, u, "bill", self._sen(amt), bill=cat, channel="in_app")

    def _add(self, t, u, kind, sen, merchant=None, cp=None, bill=None, channel="in_app", ok=None):
        if ok is None:
            ok = self._u()[0] >= C.FAIL_RATE
        cp = None if cp is None else int(cp)
        bill = None if bill is None else str(bill)
        self.events.append([int(t), int(u), kind, int(sen), merchant, cp, bill, channel, ok])

    def _merchant_event(self, u: int, ci: int, t: int) -> None:
        c = self.cats[ci]
        months_in = t / (30.4 * DAY)
        amt = c.avg_myr * self.rng.lognormal(0, 0.5) * (1 + 0.0025 * months_in)  # mild inflation
        channel = "online" if self._u()[0] < c.online_share else "qr"
        self._add(
            t,
            u,
            "merchant",
            self._sen(amt),
            merchant=self._pick_merchant(ci, u, t),
            channel=channel,
        )

    def _p2p_event(self, u: int, t: int) -> None:
        friends = [f for f in self.friends[u] if self.signup[f] < t]
        if not friends:
            return
        cp = friends[int(self.rng.integers(len(friends)))]
        if self.rng.random() < C.P2P_ROUND_SHARE:
            amt = float(
                self.rng.choice([10, 20, 30, 50, 100, 200], p=[0.2, 0.25, 0.1, 0.25, 0.15, 0.05])
            )
        else:
            amt = self.rng.lognormal(math.log(35), 0.7)
        self._add(t, u, "p2p", self._sen(amt), cp=cp)

    # ---------------------------------------------------------------- fraud-lite
    def plant_group_collections(self) -> None:
        """Legit look-alikes: 5-10 friends each send RM10-50 within half an hour, then nothing."""
        r = self.rng
        n_coll = max(2, round(self.n * C.GROUP_COLLECTORS_PER_USERS))
        long_lived = np.flatnonzero(self.end - self.signup > 120 * DAY)
        for c in r.choice(long_lived, size=n_coll, replace=False):
            s, e = int(self.signup[c]) + 7 * DAY, int(self.end[c]) - DAY
            for _ in range(int(r.integers(2, 6))):
                t0 = int(r.integers(s, e))
                pool = [f for f in self.friends[c] if self.signup[f] < t0 < self.end[f]]
                pool += list(
                    np.flatnonzero(
                        (self.signup < t0) & (self.end > t0) & (self.state == self.state[c])
                    )[:40]
                )
                pool = list(dict.fromkeys(int(x) for x in pool if x != c))
                k = min(len(pool), int(r.integers(5, 11)))
                if k < 5:
                    continue
                amt = int(r.choice([10, 20, 30, 50]))  # everyone chips in the same share
                for snd, off in zip(
                    r.choice(pool, size=k, replace=False),
                    np.sort(r.integers(0, 25 * 60, size=k)),
                    strict=True,
                ):
                    self._add(t0 + int(off), snd, "p2p", amt * 100, cp=int(c), ok=True)

    def plant_mules(self) -> None:
        r = self.rng
        n_mules = max(3, round(self.n * C.MULES_PER_USERS))
        long_lived = np.flatnonzero(self.end - self.signup > 120 * DAY)
        mules = r.choice(long_lived, size=n_mules, replace=False)
        self.mules = set(int(m) for m in mules)
        for m in mules:
            s, e = int(self.signup[m]) + 7 * DAY, int(self.end[m]) - DAY
            for _ in range(int(r.integers(3, 7))):
                t0 = int(r.integers(s, e))
                pool = np.flatnonzero((self.signup < t0) & (self.end > t0))
                pool = [x for x in pool if x not in self.mules]
                k = min(len(pool), int(r.integers(6, 16)))
                if k < 3:
                    continue
                senders = r.choice(pool, size=k, replace=False)
                offsets = np.sort(r.integers(0, 25 * 60, size=k))
                total = 0
                for snd, off in zip(senders, offsets, strict=True):
                    amt = int(r.choice([100, 200, 300, 500], p=[0.3, 0.3, 0.2, 0.2]))
                    total += amt
                    self._add(t0 + int(off), snd, "p2p", amt * 100, cp=int(m), ok=True)
                t_out = t0 + int(offsets[-1]) + int(r.integers(120, 900))
                others = [x for x in self.mules if x != m]
                collector = int(r.choice(others)) if others else int(r.choice(pool))
                remaining = total // 100 * 100  # cash out in round hundreds
                for j in range(int(r.integers(1, 4))):
                    chunk = remaining if j == 2 else max(100, remaining // 2 // 100 * 100)
                    if remaining <= 0:
                        break
                    chunk = min(chunk, remaining)
                    self._add(
                        t_out + j * int(r.integers(30, 240)),
                        m,
                        "p2p",
                        chunk * 100,
                        cp=collector,
                        ok=True,
                    )
                    remaining -= chunk
                self.world.mule_bursts.append((int(m) + 1, _ts(t0), _ts(t_out + 3 * 240)))

    # ---------------------------------------------------------------- settle
    def settle(self) -> None:
        """Replay events in time order, add top-ups so no balance goes negative, apply cashback."""
        r = self.rng
        promos = [
            ((p.start - C.START).days * DAY, ((p.end - C.START).days + 1) * DAY, p)
            for p in C.PROMOS
        ]
        mcc_of = {row[0]: row[2] for row in self.world.merchants}
        bal = np.zeros(self.n, dtype=np.int64)
        out = []  # [t, seq, user, type, sen, status, channel, merchant, cp, bill, promo, cashback]
        self.events.sort(key=lambda ev: ev[0])
        seq = 0
        for t, u, kind, sen, merchant, cp, bill, channel, ok in self.events:
            seq += 1
            status = "success" if ok else "failed"
            if ok and bal[u] < sen:
                need = int(sen - bal[u])
                planned = r.random() < 0.45
                if planned:  # topped up ahead of time, a bigger round amount
                    top = -(-need // 10000) * 10000 + int(r.choice([5000, 10000, 20000, 30000]))
                    t_top = max(int(self.signup[u]), t - int(r.integers(3600, 72 * 3600)))
                else:  # just in time, at the counter or in the app
                    top = -(-need // 5000) * 5000 + int(r.choice([0, 5000, 10000, 20000]))
                    t_top = max(int(self.signup[u]), t - int(r.integers(60, 1200)))
                src = str(r.choice(TOPUP_SOURCES, p=self.topup_p[self.state[u]]))
                if r.random() < 0.02:  # a failed attempt (e.g. bank timeout), retried
                    out.append(
                        [
                            max(int(self.signup[u]), t_top - int(r.integers(30, 180))),
                            seq - 0.7,
                            u,
                            "topup",
                            top,
                            "failed",
                            src,
                            None,
                            None,
                            None,
                            None,
                            0,
                        ]
                    )
                out.append(
                    [t_top, seq - 0.5, u, "topup", top, "success", src, None, None, None, None, 0]
                )
                bal[u] += top
            promo_id, cashback = None, 0
            if ok:
                bal[u] -= sen
                if kind == "p2p":
                    bal[cp] += sen
                if kind == "merchant":
                    for ps, pe, p in promos:
                        if ps <= t < pe and (p.mccs is None or mcc_of[merchant] in p.mccs):
                            promo_id = p.promo_id
                            cashback = min(int(round(sen * p.pct / 100)), int(p.cap * 100))
                            bal[u] += cashback
                            break
            out.append(
                [
                    t,
                    seq,
                    u,
                    kind,
                    sen,
                    status,
                    channel,
                    merchant,
                    None if cp is None else int(cp) + 1 + WALLET_OFFSET,
                    bill,
                    promo_id,
                    int(cashback),
                ]
            )

        out.sort(key=lambda row: (row[0], row[1]))
        self.world.transactions = [
            (
                i + 1,
                int(row[2]) + 1 + WALLET_OFFSET,
                _ts(row[0]),
                row[3],
                int(row[4]) / 100,
                row[5],
                row[6],
                row[7],
                row[8],
                row[9],
                row[10],
                row[11] / 100,
            )
            for i, row in enumerate(out)
        ]
        self.world.promotions = [
            (
                p.promo_id,
                p.name,
                p.start,
                p.end,
                list(p.mccs) if p.mccs else None,
                p.pct,
                p.cap,
                p.budget,
            )
            for p in C.PROMOS
        ]
        self.world.promo_uplift = [(p.promo_id, p.true_uplift) for p in C.PROMOS]

    def run(self) -> World:
        self.world = World()
        self.make_users()
        self.make_merchants()
        self.simulate_users()
        self.plant_group_collections()
        self.plant_mules()
        self.settle()
        return self.world


def generate(n_users: int = C.N_USERS, seed: int = C.SEED) -> World:
    return Sim(n_users, seed).run()
