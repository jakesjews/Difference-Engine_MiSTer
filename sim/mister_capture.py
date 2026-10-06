#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow>=12"]
# ///
"""Capture actual MiSTer output using Zaparoo, optionally check displayed values.

Run with: uv run sim/mister_capture.py build/hardware/ready.png
Pass --keys '{f3}' to operate the core before capturing (requires it to be loaded).
At the default slow speed, allow --settle 7 for a complete F2 crank.
Direct video must be disabled to capture the complete native 640x480 raster.
"""
import argparse
import base64
import io
import json
from pathlib import Path
import re
import shlex
import subprocess
import time
from urllib.request import Request, urlopen

from PIL import Image


def rpc(host, method, params=None, transport="ssh"):
    if transport == "ssh":
        argument = method if params is None else method + ":" + json.dumps(params)
        command = shlex.join(["/media/fat/Scripts/zaparoo.sh", "-api", argument])
        response = subprocess.run(
            ["ssh", "-o", "BatchMode=yes", "-o", "LogLevel=ERROR", "-o", "ConnectTimeout=10",
             f"root@{host}", command], check=True, capture_output=True, text=True, timeout=40)
        result = json.loads(response.stdout)
        if result is None:
            return None
        if "error" in result:
            raise RuntimeError(result["error"])
        return result.get("result", result)
    request = {"jsonrpc": "2.0", "id": 1, "method": method}
    if params is not None:
        request["params"] = params
    with urlopen(Request(f"http://{host}:7497/api/v0.1", json.dumps(request).encode(),
                         {"Content-Type": "application/json"}), timeout=30) as response:
        result = json.load(response)
    if "error" in result:
        raise RuntimeError(result["error"])
    return result["result"]


def read_panel(image):
    width, height = image.size
    if width < 640 or height < 480 or width * 3 != height * 4:
        raise ValueError(f"Expected a complete 640x480 or larger 4:3 raster, received {image.size}")
    # Zaparoo versions may request Main's nearest-neighbor scaled capture.
    if image.size != (640, 480):
        image = image.resize((640, 480), Image.Resampling.NEAREST)
    font = (Path(__file__).resolve().parents[1] / "rtl/de2_font.sv").read_text()
    digits = {}
    for digit, body in re.findall(r'"([0-9])": glyph = \{([^}]+)\}', font):
        digits[tuple(int(bit) for row in re.findall(r"5'b([01]{5})", body) for bit in row)] = digit
    image = image.convert("RGB")

    def number_at(x, y, light=False):
        pixels = tuple(int((sum(image.getpixel((x + dx, y + dy))) > 500) if light else
                           (sum(image.getpixel((x + dx, y + dy))) < 380))
                       for dy in range(7) for dx in range(5))
        if pixels not in digits:
            raise ValueError(f"Unrecognized digit at ({x}, {y}); is the panel obscured?")
        return digits[pixels]

    columns = [int("".join(number_at(46 + col * 44, 87 + row * 10)
                           for row in range(31))) for col in range(8)]
    count = int("".join(number_at(120 + digit * 6, 416, light=True) for digit in range(6)))
    return {"columns": columns, "count": count}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--host", default="mister")
    parser.add_argument("--transport", choices=("ssh", "http"), default="ssh",
                        help="Use the authenticated local CLI over SSH, or the HTTP API")
    controls = parser.add_mutually_exclusive_group()
    controls.add_argument("--keys", help="Zaparoo keyboard macro; sends input to the loaded core")
    controls.add_argument("--buttons", help="Zaparoo gamepad macro; requires a MiSTer controller mapping")
    parser.add_argument("--settle", type=float, default=0.4, help="Seconds to wait after input (default: 0.4)")
    parser.add_argument("--read-panel", action="store_true")
    parser.add_argument("--expect-columns", help="Eight comma-separated decimal integers")
    parser.add_argument("--expect-count", type=int)
    args = parser.parse_args()
    if args.settle < 0:
        parser.error("--settle must be nonnegative")
    if args.keys:
        rpc(args.host, "input.keyboard", {"keys": args.keys}, args.transport)
    if args.buttons:
        rpc(args.host, "input.gamepad", {"buttons": args.buttons}, args.transport)
    if args.keys or args.buttons:
        time.sleep(args.settle)
    shot = rpc(args.host, "screenshot", transport=args.transport)
    data = base64.b64decode(shot["data"])
    image = Image.open(io.BytesIO(data))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(data)
    result = {"image": str(args.output), "size": image.size}
    if args.read_panel or args.expect_columns is not None or args.expect_count is not None:
        result.update(read_panel(image))
    print(json.dumps(result))
    if args.expect_columns is not None:
        expected = [int(value) % (10 ** 31) for value in args.expect_columns.split(",")]
        if len(expected) != 8 or result["columns"] != expected:
            raise AssertionError(f"Columns differ: expected {expected}, got {result['columns']}")
    if args.expect_count is not None and result["count"] != args.expect_count:
        raise AssertionError(f"Count differs: expected {args.expect_count}, got {result['count']}")


if __name__ == "__main__":
    main()
