import importlib.util
import math
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location("make_de2", Path(__file__).parents[1] / "tools/make_de2.py")
tables = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tables)


class TableTests(unittest.TestCase):
    def test_museum_original_table(self):
        self.assertEqual(tables.initial_columns(tables.PRESETS["museum"]),
                         [41, 36, 28, 1464, 360, 15240, 1440, 40320])

    def test_staggered_columns_against_binomial_definition(self):
        for coeff in tables.PRESETS.values():
            for start in (-100, -1, 0, 1, 1024):
                expected = [sum((-1)**(i-j) * math.comb(i, j) *
                                sum(c * (start-i//2+j)**p for p, c in enumerate(coeff))
                                for j in range(i+1)) % tables.MODULUS for i in range(8)]
                self.assertEqual(tables.initial_columns(coeff, start), expected)

    def test_format_and_complements(self):
        columns = tables.initial_columns([100, -1])
        encoded = tables.encode(columns)
        self.assertEqual(len(encoded), 256)
        self.assertEqual(encoded[32:64], b"9" * 31 + b"\n")
        self.assertEqual([int(s) for s in encoded.splitlines()], columns)

    def test_invalid_capacity(self):
        for coefficients in ([], [0] * 9):
            with self.assertRaises(ValueError):
                tables.initial_columns(coefficients)
        for columns in ([0] * 7, [-1] * 8, [tables.MODULUS] * 8):
            with self.assertRaises(ValueError):
                tables.encode(columns)


if __name__ == "__main__":
    unittest.main()
