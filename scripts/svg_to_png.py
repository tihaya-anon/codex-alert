from __future__ import annotations

import argparse
import re
from pathlib import Path

import cairosvg


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_INPUT = REPO_ROOT / "hooks" / "codex.svg"
DEFAULT_OUTPUT = REPO_ROOT / "hooks" / "codex-approval-toast-icon.png"
HEX_COLOR = re.compile(r"^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$")


def color_arg(value: str) -> str | None:
    if value.lower() == "none":
        return None
    if not HEX_COLOR.match(value):
        raise argparse.ArgumentTypeError("expected #RRGGBB, #RRGGBBAA, or none")
    return value


def view_box(svg: str) -> tuple[float, float, float, float]:
    match = re.search(r'\bviewBox\s*=\s*"([^"]+)"', svg)
    if not match:
        raise ValueError("SVG must have a viewBox")

    values = [float(part) for part in re.split(r"[,\s]+", match.group(1).strip()) if part]
    if len(values) != 4:
        raise ValueError("SVG viewBox must contain four numbers")
    return values[0], values[1], values[2], values[3]


def build_svg(svg: str, foreground: str, background: str | None, padding: float) -> str:
    svg = svg.replace("currentColor", foreground)
    if background is None and padding <= 0:
        return svg

    match = re.search(r"<svg\b(?P<attrs>[^>]*)>(?P<body>.*)</svg>\s*$", svg, re.DOTALL | re.IGNORECASE)
    if not match:
        raise ValueError("input does not look like a complete SVG document")

    min_x, min_y, width, height = view_box(svg)
    body = match.group("body")

    if padding > 0:
        usable_width = width - (padding * 2)
        usable_height = height - (padding * 2)
        if usable_width <= 0 or usable_height <= 0:
            raise ValueError("padding leaves no drawable area")
        scale = min(usable_width / width, usable_height / height)
        body = (
            f'<g fill="{foreground}" color="{foreground}" '
            f'transform="translate({min_x + padding:g} {min_y + padding:g}) '
            f"scale({scale:g}) translate({-min_x:g} {-min_y:g})\">{body}</g>"
        )
    else:
        body = f'<g fill="{foreground}" color="{foreground}">{body}</g>'

    background_rect = ""
    if background is not None:
        background_rect = (
            f'<rect x="{min_x:g}" y="{min_y:g}" width="{width:g}" '
            f'height="{height:g}" fill="{background}"/>'
        )

    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{min_x:g} {min_y:g} {width:g} {height:g}" '
        f'width="{width:g}" height="{height:g}">{background_rect}{body}</svg>'
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Render an SVG icon to a PNG suitable for the overlay window.")
    parser.add_argument("--input", type=Path, default=DEFAULT_INPUT)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--size", type=int, default=256)
    parser.add_argument("--foreground", type=color_arg, default="#FFFFFF")
    parser.add_argument("--background", type=color_arg, default="#111827")
    parser.add_argument("--padding", type=float, default=2.0, help="Padding in SVG viewBox units.")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    source = args.input.read_text(encoding="utf-8")
    rendered_svg = build_svg(
        svg=source,
        foreground=args.foreground,
        background=args.background,
        padding=args.padding,
    )

    args.output.parent.mkdir(parents=True, exist_ok=True)
    cairosvg.svg2png(
        bytestring=rendered_svg.encode("utf-8"),
        write_to=str(args.output),
        output_width=args.size,
        output_height=args.size,
    )
    print(args.output)


if __name__ == "__main__":
    main()
