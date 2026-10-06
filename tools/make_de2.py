#!/usr/bin/env python3
"""Prepare staggered decimal columns for Babbage's Difference Engine No. 2."""

import argparse
from pathlib import Path

DIGITS = 31
MODULUS = 10**DIGITS
PRESETS = {
    "museum": [41, 4, 7, 1, 5, 9, 2, 8],
    "squares": [0, 0, 1],
    "cubes": [0, 0, 0, 1],
    # Triangular numbers are supplied separately since their coefficients
    # are rational even though every value in the difference table is integral.
    "seventh": [0, 0, 0, 0, 0, 0, 0, 1],
    "descending": [100, -1],
}


def evaluate(coefficients: list[int], x: int) -> int:
    value = 0
    for coefficient in reversed(coefficients):
        value = value * x + coefficient
    return value


def initial_columns(coefficients: list[int], start: int = 0) -> list[int]:
    if not 1 <= len(coefficients) <= 8:
        raise ValueError("a polynomial must have between 1 and 8 coefficients")
    columns = []
    for order in range(8):
        # D_i = forward_difference^i f(start - floor(i/2)).
        values = [evaluate(coefficients, start - order // 2 + j) for j in range(order + 1)]
        for _ in range(order):
            values = [b - a for a, b in zip(values, values[1:])]
        columns.append(values[0] % MODULUS)
    return columns


def encode(columns: list[int]) -> bytes:
    if len(columns) != 8 or any(not 0 <= n < MODULUS for n in columns):
        raise ValueError("expected eight unsigned 31-digit columns")
    return "".join(f"{n:031d}\n" for n in columns).encode("ascii")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--coefficients", help="integer coefficients, constant first; e.g. 0,0,1 for x^2")
    source.add_argument("--preset", choices=[*PRESETS, "triangular", "carry", "blank"])
    parser.add_argument("--start", type=int, default=0, help="starting argument x (default: 0)")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        if args.coefficients is not None:
            columns = initial_columns([int(n) for n in args.coefficients.split(",")], args.start)
        elif args.preset == "triangular":
            n = args.start
            columns = [n * (n + 1) // 2 % MODULUS, (n + 1) % MODULUS, 1, 0, 0, 0, 0, 0]
        elif args.preset == "carry":
            columns = [(MODULUS - 1 + args.start) % MODULUS, 1, 0, 0, 0, 0, 0, 0]
        elif args.preset == "blank":
            columns = [0] * 8
        else:
            columns = initial_columns(PRESETS[args.preset], args.start)
        args.output.write_bytes(encode(columns))
    except ValueError as exc:
        parser.error(str(exc))
    print(f"Wrote {args.output} (256 bytes; T, D1 ... D7; x starts at {args.start})")


if __name__ == "__main__":
    main()
