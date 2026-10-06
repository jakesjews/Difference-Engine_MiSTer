#!/usr/bin/env python3
"""Independent big-integer oracle for the four DE2 arithmetic phases."""
import math
import random
from pathlib import Path

BASE = 10**31
rng = random.Random(1849)
vectors = []


def bcd_bus(columns):
    return "".join(f"{value % BASE:031d}" for value in reversed(columns))


def add_case(initial, cycles, polynomial=None, start=0):
    columns = initial.copy()
    warnings = 0
    carry_out = 0
    vectors.append(f"0 {bcd_bus(columns)} 0 0 0 0")
    for n in range(cycles):
        for phase in range(4):
            if phase == 0:
                carry_out = 0
            for c in range(phase // 2, 7, 2):
                if phase % 2 == 0:
                    # Giving-off is digitwise, before any tens are carried.
                    a, b = columns[c], columns[c + 1]
                    value = 0
                    for d in range(31):
                        s = (a // 10**d) % 10 + (b // 10**d) % 10
                        value += (s % 10) * 10**d
                        if s >= 10:
                            warnings |= 1 << (c * 31 + d)
                    columns[c] = value
                else:
                    # Resolve ALL warning weights with arbitrary precision.
                    value = columns[c] + sum(
                        10 ** (d + 1) for d in range(31) if warnings & (1 << (c * 31 + d))
                    )
                    if value >= BASE:
                        carry_out |= 1 << c
                    columns[c] = value % BASE
                    warnings &= ~(((1 << 31) - 1) << (c * 31))
            count = n + (phase == 3)
            vectors.append(
                f"1 {bcd_bus(columns)} {warnings:062x} {carry_out:02x} {(phase+1)%4} {count:06d}"
            )
        if polynomial is not None:
            # Entire machine state, independently derived from the polynomial.
            x = start + n + 1
            expected = staggered(polynomial, x)
            assert columns == expected, (polynomial, x, columns, expected)


def evaluate(coeff, x):
    return sum(c * x**order for order, c in enumerate(coeff))


def staggered(coeff, x):
    return [
        sum((-1) ** (order - j) * math.comb(order, j) * evaluate(coeff, x - order // 2 + j)
            for j in range(order + 1)) % BASE
        for order in range(8)
    ]


def main():
    for columns in ([0] * 8, [BASE - 1] * 8, [BASE - 1, 1, 0, 0, 0, 0, 0, 0],
                    [int("90" * 15 + "9")] * 8, [int("09" * 15 + "0")] * 8):
        add_case(columns, 8)
    for _ in range(200):
        add_case([rng.randrange(BASE) for _ in range(8)], 3)
    for coeff in ([41, 4, 7, 1, 5, 9, 2, 8], [0, 0, 1], [0, 0, 0, 1],
                  [100, -1], [0] * 7 + [1]):
        add_case(staggered(coeff, 0), 120, coeff)
    for _ in range(40):
        coeff = [rng.randrange(-10**24, 10**24) for _ in range(rng.randrange(1, 9))]
        start = rng.randrange(-100, 100)
        add_case(staggered(coeff, start), 20, coeff, start)
    Path("build").mkdir(exist_ok=True)
    Path("build/engine-vectors.txt").write_text("\n".join(vectors) + "\n")
    print(f"Generated {len(vectors)} load/phase vectors with an independent integer oracle")


if __name__ == "__main__":
    main()
