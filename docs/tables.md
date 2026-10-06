# Making a difference table

The engine evaluates integer polynomials up to degree seven. The eight files in [`programs/`](../programs/) also make good starting points. Put `.de2` files in `games/DifferenceEngine/`, then choose **Load difference table** from the MiSTer menu.

To generate `3x³ − 2x + 7`, starting at `x = 10`, run:

```sh
python3 tools/make_de2.py --coefficients=7,-2,0,3 --start 10 --output example.de2
```

Coefficients go in ascending order: constant, x, x², …, x⁷. Include zeros for missing terms. The generator calculates the initial differences and encodes negative values as 31-digit ten's complements. The engine performs only decimal addition.

The initial result appears as step zero. Steps count cycles since loading, so for the example above the current argument is `10 + step`. F5 reloads the original table.

## File format

A `.de2` file is exactly eight lines of 31 ASCII digits, each followed by LF: 256 bytes total. The lines hold T, D1, …, D7, with the most significant digit first. There are no headers, signs, spaces, or CRLF line endings.

If preparing a table by hand, column `i` must contain:

```text
C[i] = forward_difference^i f(start - floor(i/2)) modulo 10^31
```

These are staggered differences. Loading all the forward differences at the same argument gives the wrong sequence. For example, cubes starting at zero use `[0, 1, 0, 6, 0, 0, 0, 0]`.

A valid load stops the engine, clears the paper and cycle counter, and prints the initial result. An invalid file displays an error and leaves the current table intact. Load a valid file or reset to clear the notice.

Arithmetic wraps at 31 digits. The lamps below the columns show carry beyond that width; this also occurs during normal negative-number arithmetic. The paper shows the lower thirty digits, as the original printer did.
