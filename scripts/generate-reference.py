#!/usr/bin/env python3
"""Generate docs/reference.md from the comments in variables.tf and outputs.tf.

Every input, every nested setting and every output, with its default and the
comment written above it. Run from the repository root after changing an input:

    python3 scripts/generate-reference.py
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OPEN = re.compile(r"^\s*([a-z0-9_]+)\s*=\s*(optional\()?(list\(|map\()?object\(\{\s*$")
LEAF = re.compile(r"^\s*([a-z0-9_]+)\s*=\s*(.+?)\s*$")
CLOSE = re.compile(r"^\s*\}\)")


def join(path, attribute):
    """The dotted path of an attribute, with list and map markers attached to their parent."""
    return ".".join(path + [attribute]).replace(".[*]", "[*]")


def cell(text):
    return text.replace("|", "\\|").strip()


def default_of(type_text):
    """The default of optional(type, default), or required/none."""
    match = re.match(r"optional\((.*)\)$", type_text)
    if not match:
        return "required"
    inner, depth = match.group(1), 0
    for index, char in enumerate(inner):
        if char in "([{":
            depth += 1
        elif char in ")]}":
            depth -= 1
        elif char == "," and depth == 0:
            return "`" + inner[index + 1 :].strip() + "`"
    return "`null`"


def parse_variables(text):
    variables = []
    for block in re.finditer(r'^variable "([^"]+)" \{\n(.*?)^\}', text, re.M | re.S):
        name, body = block.group(1), block.group(2)
        description = re.search(r'^\s+description\s*=\s*"(.*)"', body, re.M)
        default = re.search(r"^  default\s*=\s*(.+)$", body, re.M)
        rows, path, comment = [], [], []
        type_block = re.search(r"^  type\s*=\s*(.*?)(?=^  (?:default|sensitive|nullable|validation)\b|\Z)", body, re.M | re.S)
        first = type_block.group(1).splitlines()[0] if type_block else ""
        prefix = "<key>" if first.startswith("map(object") else "[*]" if first.startswith("list(object") else None
        if prefix:
            path.append(prefix)
        for line in (type_block.group(1) if type_block else "").splitlines()[1:]:
            stripped = line.strip()
            if stripped.startswith("#"):
                comment.append(stripped.lstrip("#").strip())
                continue
            opened = OPEN.match(line)
            if opened:
                attribute = opened.group(1)
                kind = "list of objects" if opened.group(3) == "list(" else "map of objects" if opened.group(3) == "map(" else "object"
                rows.append((join(path, attribute), kind, "optional" if opened.group(2) else "required", " ".join(comment)))
                path.append(attribute + ("[*]" if opened.group(3) == "list(" else ".<key>" if opened.group(3) == "map(" else ""))
                comment = []
                continue
            if CLOSE.match(line):
                if len(path) > (1 if prefix else 0):
                    path.pop()
                comment = []
                continue
            leaf = LEAF.match(line)
            if leaf:
                type_text = leaf.group(2).rstrip(",")
                rows.append((join(path, leaf.group(1)), "`" + re.sub(r"^optional\((.*?)(,.*)?\)$", r"\1", type_text) + "`", default_of(type_text), " ".join(comment)))
                comment = []
        variables.append((name, description.group(1) if description else "", default.group(1).strip() if default else None, rows))
    return variables


def parse_outputs(text):
    return re.findall(r'^output "([^"]+)" \{\n\s+description\s*=\s*"(.*)"', text, re.M)


def main():
    variables = parse_variables((ROOT / "variables.tf").read_text())
    outputs = parse_outputs((ROOT / "outputs.tf").read_text())
    lines = [
        "# Reference",
        "",
        "Every input, nested setting and output of the module. Generated from the comments in `variables.tf` and `outputs.tf` by `scripts/generate-reference.py`; do not edit by hand. For how to use them, start with [getting started](getting-started.md).",
        "",
        "## Inputs",
        "",
    ]
    for name, description, default, rows in variables:
        lines += [f"### `{name}`", "", cell(description) + ".", ""]
        lines += [f"Default: `{default}`" if default is not None else "Required.", ""]
        if rows:
            lines += ["| Setting | Type | Default | Description |", "| --- | --- | --- | --- |"]
            lines += [f"| `{name}.{path}` | {cell(kind)} | {cell(dflt)} | {cell(text)} |" for path, kind, dflt, text in rows]
            lines.append("")
    lines += ["## Outputs", "", "| Output | Description |", "| --- | --- |"]
    lines += [f"| `{name}` | {cell(description)} |" for name, description in outputs]
    (ROOT / "docs" / "reference.md").write_text("\n".join(lines) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
