#!/usr/bin/env python3
"""Catch expressions GitHub will compile but we only meant to write about.

Every STRING VALUE in action.yml is a template — including the body of a `run:`
block, shell comments and all. YAML comments are not, because the YAML parser
drops them before the templating engine ever sees the file. That distinction is
invisible while reading and cost two CI failures, so it gets a check.

Both real bugs this caught:
  * an input `description` containing an example `${{ github.ref == ... }}` —
    compiled, and `github` is not in scope for a description
  * a shell comment inside `run:` explaining that `${{ }}` is GitHub's syntax —
    compiled as an empty expression
"""
import re, sys, yaml

EXPR = re.compile(r"\$\{\{(.*?)\}\}", re.S)
# What a composite action may actually reference. `secrets` is absent on purpose:
# an action cannot read them, the caller passes them in as inputs.
ALLOWED = ("inputs.", "steps.", "github.", "runner.", "env.", "job.")

def walk(node, path=""):
    if isinstance(node, dict):
        for k, v in node.items():
            yield from walk(v, f"{path}.{k}" if path else str(k))
    elif isinstance(node, list):
        for i, v in enumerate(node):
            yield from walk(v, f"{path}[{i}]")
    elif isinstance(node, str):
        yield path, node

doc = yaml.safe_load(open("action.yml"))
bad = []
for path, text in walk(doc):
    for m in EXPR.finditer(text):
        inner = m.group(1).strip()
        if not inner:
            bad.append((path, "empty expression ${{ }} — GitHub compiles this and fails"))
        elif not inner.startswith(ALLOWED):
            bad.append((path, f"expression {inner!r} references something out of scope"))
    # A description is prose shown to a human; an expression in one is always a
    # mistake, even a well-formed one, because it renders rather than displays.
    if re.match(r"^inputs\.[^.]+\.description$", path) and "${{" in text:
        bad.append((path, "an input description is templated — it cannot contain an example expression"))

for path, why in bad:
    print(f"  FAIL {path}: {why}", file=sys.stderr)
print(f"  ok   no stray expressions in action.yml ({'clean' if not bad else str(len(bad)) + ' problems'})")
sys.exit(1 if bad else 0)
