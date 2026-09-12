#!/usr/bin/env python3
"""Pull one step's `run:` script out of action.yml, by step name.

The point is that the tests exercise the SHIPPED script rather than a copy of
it — a copy drifts, and a drifted copy of a security-relevant script is worse
than no test at all.
"""
import sys, yaml

name = sys.argv[1]
doc = yaml.safe_load(open("action.yml"))
for step in doc["runs"]["steps"]:
    if step.get("name") == name:
        sys.stdout.write(step["run"])
        sys.exit(0)
sys.exit(f"no step named {name!r}")
