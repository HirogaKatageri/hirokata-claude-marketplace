#!/usr/bin/env python3
"""Assemble the dashboard's data island from Kumiai rows.

The kumiai twin of dashboard.sql. Reads one JSON file per dashboard key from a directory --
each file is the raw `rows` array a read_view / list call returned, saved as-is -- and prints
ONE escaped JSON document with exactly the keys and field names dashboard.sql produces, so the
page renders identically on either backend.

    python3 dashboard-kumiai.py /tmp/guild-dash > /tmp/guild-data.json

A missing file is an empty list, never null (expectations §6.c). `<`, `>` and `&` are escaped
as \\u003c, \\u003e, \\u0026 here, before the value can reach the page -- the same escape the
SQL does inside the engine.
"""
import json
import os
import sys


def s(v):
    return "" if v is None else v


# key -> (source file, {output field: source column or callable})
SHAPES = {
    "brief": {"fact": "fact", "value": "value"},
    "goals": {"id": "id", "status": "status", "priority": "priority",
              "projects": "projects_total", "projects_done": "projects_done",
              "runnable": "projects_runnable", "runnable_ids": "runnable_project_ids",
              "done": "requirements_done", "total": "requirements_total", "title": "title"},
    "projects": {"id": "id", "goal": "goal_id", "ordinal": "ordinal", "status": "status",
                 "priority": "priority", "concurrent": "concurrent", "isolation": "isolation",
                 "worktree": "worktree_path", "runnable": "runnable",
                 "reqs": "requirements_total", "reqs_done": "requirements_done",
                 "open": "tasks_open", "blocked": "tasks_blocked", "title": "title"},
    "requirements": {"id": "id", "project": lambda r: s(r.get("project_id")),
                     "status": "status", "priority": "priority", "total": "tasks_total",
                     "done": "tasks_done", "open": "tasks_open", "blocked": "tasks_blocked",
                     "failed": "tasks_failed", "title": "title"},
    "tasks": {"section": "section", "n": "section_no", "id": "id", "status": "status",
              "who": "who", "req": "requirement_id", "priority": "priority", "title": "title"},
    "blocked": {"id": "id", "reason": "reason"},
    "approvals": {"id": "id", "req": "requirement_id", "status": "status",
                  "gate": "gate_node_id", "title": "title"},
    "nodes": {"id": "id", "req": "requirement_id", "key": "node_key", "kind": "kind",
              "status": "status", "task": lambda r: s(r.get("task_id")),
              "group": lambda r: s(r.get("parallel_group"))},
    "edges": {"from": "from_node", "to": "to_node"},
    "gates": {"node": "node_id", "kind": "kind", "status": "status", "prompt": "prompt",
              "decision": lambda r: s(r.get("decision")),
              "decided": lambda r: s(r.get("decided_at"))},
    "bugs": {"id": "id", "severity": "severity", "status": "status", "by": "found_by",
             "req": lambda r: s(r.get("requirement_id")),
             "fix": lambda r: s(r.get("fix_task_id")), "created": "created_at", "title": "title"},
    "findings": {"id": "id", "task": "task_id", "reviewer": "reviewer", "severity": "severity",
                 "disposition": "disposition", "file": lambda r: s(r.get("file")),
                 "line": lambda r: r.get("line") or 0,
                 "fix": lambda r: s(r.get("fix_task_id")), "created": "created_at",
                 "summary": "summary", "detail": lambda r: s(r.get("detail"))},
    "coverage": {"id": "id", "area": "area", "risk": "risk",
                 "spec": lambda r: s(r.get("spec_path")),
                 "last": lambda r: s(r.get("last_inspected_at")),
                 "notes": lambda r: s(r.get("notes"))},
    "docs": {"slug": "slug", "title": "title", "kind": "kind", "status": "status",
             "area": "area", "source": "source", "created": "created_at",
             "updated": "updated_at", "revisions": "revisions", "edges": "edges"},
    "decisions": {"slug": "slug", "title": "title", "status": "status", "area": "area",
                  "created": "created_at", "supersedes": "supersedes",
                  "superseded_by": "superseded_by", "governs": "governs",
                  "revisions": "revisions"},
    "links": {"rel": "rel", "from_type": "from_type", "from": "from_id", "to_type": "to_type",
              "to": "to_id", "note": "note", "by": "created_by"},
    "docs_stale": {"slug": "slug", "title": "title", "kind": "kind", "rel": "rel",
                   "subject_type": "subject_type", "subject": "subject_id",
                   "doc_updated": "doc_updated_at", "subject_moved": "subject_moved_at"},
    "undocumented": {"id": "id", "title": "title", "project": lambda r: s(r.get("project_id")),
                     "finished": "finished_at", "tasks": "tasks_done"},
    "activity": {"ts": "ts", "actor": "actor", "verb": "verb", "type": "subject_type",
                 "subject": "subject_id", "title": "subject_title", "phrase": "phrase"},
}


def rows_of(path):
    """The rows in one saved file. A malformed file is a FAILED build, never an empty view:
    an empty island would pass the `<` check and render a board that silently lost a key."""
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            sys.exit(f"dashboard-kumiai: {path} is not valid JSON ({e})")
    if isinstance(data, dict):            # tolerate a saved {"rows": [...]} result
        data = data.get("rows", [])
    data = data or []
    if not isinstance(data, list) or not all(isinstance(r, dict) for r in data):
        sys.exit(f"dashboard-kumiai: {path} must hold a list of row objects")
    return data


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: dashboard-kumiai.py <dir-of-row-files>")
    d = sys.argv[1]
    out = {}
    for key, shape in SHAPES.items():
        out[key] = [
            {k: (src(r) if callable(src) else r.get(src)) for k, src in shape.items()}
            for r in rows_of(os.path.join(d, key + ".json"))
        ]
    text = json.dumps(out, ensure_ascii=False, separators=(",", ":"))
    text = text.replace("&", "\\u0026").replace("<", "\\u003c").replace(">", "\\u003e")
    sys.stdout.write(text + "\n")


if __name__ == "__main__":
    main()
