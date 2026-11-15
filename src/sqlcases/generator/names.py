"""Synthetic Malaysian names from common name parts (no real people).

Faker has no Malaysian locale, so these short lists stand in. The mix roughly follows
Malaysia's population: about 70% Malay/Bumiputera, 23% Chinese, 7% Indian.
"""

from __future__ import annotations

import numpy as np

MALAY_M = [
    "Ahmad",
    "Muhammad",
    "Mohd",
    "Amirul",
    "Hafiz",
    "Faiz",
    "Syafiq",
    "Aiman",
    "Haziq",
    "Irfan",
    "Firdaus",
    "Zulkifli",
    "Azman",
    "Khairul",
    "Danial",
    "Iskandar",
    "Rizal",
]
MALAY_F = [
    "Nur",
    "Siti",
    "Nurul",
    "Aisyah",
    "Farah",
    "Amira",
    "Hidayah",
    "Syahirah",
    "Liyana",
    "Aina",
    "Izzati",
    "Najwa",
    "Balqis",
    "Zulaikha",
    "Hanis",
    "Sofea",
    "Alya",
]
MALAY_FATHER = [
    "Abdullah",
    "Ismail",
    "Hassan",
    "Ibrahim",
    "Yusof",
    "Rahman",
    "Osman",
    "Hamid",
    "Aziz",
    "Razak",
    "Salleh",
    "Kamal",
    "Jamil",
    "Rashid",
    "Zainal",
    "Ali",
]
CHINESE_SURNAME = [
    "Tan",
    "Lim",
    "Lee",
    "Ng",
    "Wong",
    "Chan",
    "Ong",
    "Teh",
    "Goh",
    "Chong",
    "Yap",
    "Low",
    "Cheah",
    "Khoo",
    "Loh",
    "Chua",
]
CHINESE_GIVEN = [
    "Wei Ming",
    "Jia Hui",
    "Kok Leong",
    "Mei Ling",
    "Zhi Hao",
    "Xin Yi",
    "Chee Keong",
    "Hui Min",
    "Jun Jie",
    "Pei Shan",
    "Yong Sheng",
    "Li Ting",
    "Kar Wai",
    "Siew Lan",
]
INDIAN_M = ["Arjun", "Ravi", "Suresh", "Kumar", "Vikram", "Ganesh", "Prakash", "Dinesh", "Hari"]
INDIAN_F = ["Priya", "Kavitha", "Lakshmi", "Deepa", "Anitha", "Shalini", "Meena", "Revathi"]
INDIAN_FATHER = ["Muthu", "Rajan", "Subramaniam", "Krishnan", "Raman", "Selvam", "Govindasamy"]


def make_names(rng: np.random.Generator, n: int) -> list[str]:
    names = []
    groups = rng.choice(3, size=n, p=[0.70, 0.23, 0.07])
    female = rng.random(n) < 0.5
    for g, f in zip(groups, female, strict=True):
        if g == 0:
            given = rng.choice(MALAY_F if f else MALAY_M)
            names.append(f"{given} {'binti' if f else 'bin'} {rng.choice(MALAY_FATHER)}")
        elif g == 1:
            names.append(f"{rng.choice(CHINESE_SURNAME)} {rng.choice(CHINESE_GIVEN)}")
        else:
            given = rng.choice(INDIAN_F if f else INDIAN_M)
            names.append(f"{given} {'a/p' if f else 'a/l'} {rng.choice(INDIAN_FATHER)}")
    return names
