#!/usr/bin/env python3
"""Extracts one version's section from CHANGELOG.md and converts it to a
small HTML fragment for Sparkle's appcast <description> — shown right in
the native update dialog the user already sees when Sparkle finds a new
version, so "what changed" doesn't need a separate interruption.

Deliberately a tiny hand-rolled converter, not a markdown library
dependency: the only syntax CHANGELOG.md ever actually uses is
"### heading" and "- bullet" lines, both trivial to match line by line.
"""
import html
import re
import sys


def extract_section(changelog_text: str, version: str) -> str:
    pattern = re.compile(
        rf"^## \[{re.escape(version)}\].*?$\n(.*?)(?=^## \[|\Z)",
        re.MULTILINE | re.DOTALL,
    )
    match = pattern.search(changelog_text)
    if not match:
        raise SystemExit(f"No CHANGELOG.md section found for version {version}")
    return match.group(1).strip("\n")


def inline_format(escaped_text: str) -> str:
    """Applied after html.escape(), so **/` below are always literal
    characters, never something an attacker-controlled string could smuggle
    HTML through — CHANGELOG.md is a file we author ourselves, but this
    keeps the conversion correct regardless."""
    text = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", escaped_text)
    text = re.sub(r"`(.+?)`", r"<code>\1</code>", text)
    return text


def to_html(section: str) -> str:
    lines = section.splitlines()
    html_lines: list[str] = []
    in_list = False
    # Indices into html_lines of the currently-open <li>/<p>, so a wrapped
    # continuation line (markdown's own convention: an indented line right
    # after a "- " bullet, no "- " of its own) can be appended to it
    # instead of becoming its own stray paragraph.
    open_item_index: int | None = None

    for line in lines:
        stripped = line.strip()
        if not stripped:
            open_item_index = None
            continue
        if stripped.startswith("### "):
            if in_list:
                html_lines.append("</ul>")
                in_list = False
            html_lines.append(f"<h4>{inline_format(html.escape(stripped[4:]))}</h4>")
            open_item_index = None
        elif stripped.startswith("- "):
            if not in_list:
                html_lines.append("<ul>")
                in_list = True
            html_lines.append(f"<li>{inline_format(html.escape(stripped[2:]))}</li>")
            open_item_index = len(html_lines) - 1
        elif open_item_index is not None:
            tag = "li" if in_list else "p"
            html_lines[open_item_index] = html_lines[open_item_index][: -len(f"</{tag}>")] + " " + inline_format(html.escape(stripped)) + f"</{tag}>"
        else:
            if in_list:
                html_lines.append("</ul>")
                in_list = False
            html_lines.append(f"<p>{inline_format(html.escape(stripped))}</p>")
            open_item_index = len(html_lines) - 1
    if in_list:
        html_lines.append("</ul>")
    return "\n".join(html_lines)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} <CHANGELOG.md path> <version>", file=sys.stderr)
        sys.exit(1)
    changelog_path, version = sys.argv[1], sys.argv[2]
    with open(changelog_path, encoding="utf-8") as f:
        text = f.read()
    print(to_html(extract_section(text, version)))
