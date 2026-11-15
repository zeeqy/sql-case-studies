"""Knobs for the synthetic e-wallet. Every number here is an assumption, written down on purpose."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date

START = date(2024, 1, 1)
END = date(2025, 12, 31)  # inclusive
N_USERS = 8000
SEED = 42

# State weights: approximate population (millions, DOSM 2024 estimates, rounded) x an
# urban e-wallet adoption factor (my assumption: KL 1.5, Selangor 1.3, Penang 1.2).
STATES = {
    "Selangor": 7.3 * 1.3,
    "Johor": 4.1,
    "Sabah": 3.5,
    "Perak": 2.5,
    "Sarawak": 2.5,
    "Kedah": 2.2,
    "W.P. Kuala Lumpur": 2.0 * 1.5,
    "Kelantan": 1.9,
    "Pulau Pinang": 1.8 * 1.2,
    "Pahang": 1.6,
    "Terengganu": 1.2,
    "Negeri Sembilan": 1.2,
    "Melaka": 1.0,
    "Perlis": 0.3,
    "W.P. Putrajaya": 0.12,
    "W.P. Labuan": 0.1,
}


@dataclass(frozen=True)
class Category:
    mcc: int
    name: str
    avg_myr: float  # typical ticket size
    weight: float  # share of merchant payments in Jan 2024
    growth: float  # monthly change in share (planted trend)
    n_merchants: int
    prefixes: tuple[str, ...]  # used to build merchant names
    online_share: float = 0.1


CATEGORIES = [
    Category(5411, "Grocery", 48, 0.17, 0.000, 90, ("Pasar Mini", "Mart", "Supermarket")),
    Category(5812, "Restaurants", 30, 0.14, 0.004, 110, ("Restoran", "Kopitiam", "Nasi Kandar")),
    Category(5814, "Fast food & kiosks", 17, 0.16, 0.006, 70, ("Gerai", "Kiosk", "Burger")),
    Category(5499, "Convenience stores", 12, 0.14, 0.000, 80, ("Kedai Runcit", "24 Mart")),
    Category(5541, "Petrol", 62, 0.10, -0.008, 45, ("Stesen Minyak",)),  # planted: declining
    Category(4121, "Ride-hailing", 16, 0.07, 0.012, 8, ("Ride", "Teksi"), 1.0),
    Category(4111, "Public transport", 5, 0.05, 0.025, 6, ("Transit",)),  # planted: fastest
    Category(5912, "Pharmacy", 36, 0.04, 0.002, 35, ("Farmasi",)),
    Category(5311, "Department stores", 95, 0.03, 0.000, 20, ("Gedung",), 0.3),
    Category(5651, "Clothing", 85, 0.03, 0.000, 40, ("Butik", "Pakaian"), 0.5),
    Category(5732, "Electronics", 320, 0.02, 0.003, 25, ("Elektronik", "Gadget"), 0.6),
    Category(7832, "Cinema", 32, 0.02, 0.000, 10, ("Pawagam",)),
    Category(5977, "Beauty", 55, 0.03, 0.002, 30, ("Salun", "Kosmetik")),
]

BILLS = {"electricity": 115, "water": 28, "mobile postpaid": 58, "broadband": 129, "insurance": 160}


@dataclass(frozen=True)
class Promo:
    promo_id: int
    name: str
    start: date
    end: date
    mccs: tuple[int, ...] | None  # None = all categories
    pct: float
    cap: float
    budget: float
    true_uplift: float  # planted effect on eligible spend rate (1.0 = no effect)
    signup_boost: float = 1.0  # extra new-user signups during the promo


PROMOS = [
    Promo(
        1, "Raya Cashback 2024", date(2024, 3, 25), date(2024, 4, 14), None, 10, 5, 60000, 1.35, 1.6
    ),
    Promo(2, "Grocery Saver July", date(2024, 7, 1), date(2024, 7, 31), (5411,), 5, 3, 15000, 1.25),
    Promo(
        3,
        "11.11 Mega Sale",
        date(2024, 11, 9),
        date(2024, 11, 13),
        (5311, 5651, 5732),
        15,
        20,
        30000,
        2.2,
    ),
    Promo(
        4, "Transit Rewards", date(2025, 2, 1), date(2025, 4, 30), (4111, 4121), 20, 2, 25000, 1.6
    ),
    Promo(
        5, "Raya Cashback 2025", date(2025, 3, 20), date(2025, 4, 9), None, 10, 5, 80000, 1.3, 1.5
    ),
    # planted dud: generous on a low-margin category, barely moves behaviour
    Promo(6, "Fast Food Frenzy", date(2025, 9, 1), date(2025, 9, 30), (5814,), 8, 2, 20000, 1.03),
]

# Calendar seasonality on overall activity. Hari Raya Aidilfitri: 10 Apr 2024, 31 Mar 2025.
SEASON = {
    (2024, 4): 1.15,
    (2025, 3): 1.12,
    (2025, 4): 1.05,
    (2024, 11): 1.08,
    (2025, 11): 1.08,
    (2024, 12): 1.12,
    (2025, 12): 1.12,
    (2024, 2): 0.95,
    (2025, 2): 0.95,
}

# Hour-of-day weights for spending (index = hour), peaks at lunch and dinner.
HOURS = [1, 0.5, 0.3, 0.2, 0.2, 0.5, 2, 4, 6, 5, 5, 7, 10, 8, 6, 6, 6, 7, 9, 10, 9, 7, 5, 3]

# Behaviour
TRYER_SHARE = {"basic": 0.48, "full": 0.30}  # users who try it once and leave
MONTHLY_CHURN = {"basic": 0.07, "full": 0.045}  # after the first month
TRYER_DAYS = 6  # mean days a tryer stays
PAYS_BILLS = {"basic": 0.35, "full": 0.6}
P2P_ROUND_SHARE = 0.55  # normal users also send round amounts: fraud signals must combine
FAIL_RATE = 0.015
MULES_PER_USERS = 1 / 600
# Decoys for the fraud-lite query: legit group collections (shared meal, kutu savings
# circle) look like mule bursts, many round P2P amounts in quickly, but the money stays.
GROUP_COLLECTORS_PER_USERS = 1 / 150
