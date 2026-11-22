import json
import os
import re

DEFAULT_PROJECTS = "/root/jarvis/data/projects/u_DiS4in7esMF1.json"
DEFAULT_STAFF = "/root/jarvis/data/staff.json"
PROJECT_NAME = "OrientOS"
ACTIVE_STATES = ("running", "waiting")
SELF_MARKER = "homepage-benchmarks"


def load_roadmap(path=None):
    path = path or os.environ.get("OSUM_PROJECTS_JSON", DEFAULT_PROJECTS)
    with open(path) as handle:
        projects = json.load(handle)["projects"]
    for project in projects:
        if project["name"] == PROJECT_NAME:
            return {item["id"]: item for item in project["roadmap"]}
    raise SystemExit("project %s not found in %s" % (PROJECT_NAME, path))


def load_active_workers(path=None):
    path = path or os.environ.get("OSUM_STAFF_JSON", DEFAULT_STAFF)
    with open(path) as handle:
        nodes = json.load(handle)["nodes"].values()
    return [n for n in nodes
            if n.get("projectName") == PROJECT_NAME and n.get("status") in ACTIVE_STATES
            and SELF_MARKER not in (n.get("name") or "")]


def worker_matches(worker, refs, keywords):
    text = ("%s %s" % (worker.get("name", ""), worker.get("title", ""))).lower()
    if any(re.search(r"\b%s\b" % re.escape(ref), text) for ref in refs):
        return True
    return any(word.lower() in text for word in keywords)


def item_status(item, roadmap, workers):
    refs = [r.strip() for r in item["roadmap_ref"].split(",") if r.strip()]
    entries = [roadmap[r] for r in refs if r in roadmap]
    if not entries:
        return {"status": "unplanned", "refs": [], "workers": 0}
    open_refs = [e["id"] for e in entries if not e["done"]]
    active = [w for w in workers if worker_matches(w, open_refs, item.get("keywords", []))]
    if not open_refs:
        status = "landed"
    elif active:
        status = "working"
    else:
        status = "open"
    return {"status": status, "refs": [{"id": e["id"], "done": e["done"]} for e in entries], "workers": len(active)}


def derive(in_work, projects_path=None, staff_path=None):
    roadmap = load_roadmap(projects_path)
    workers = load_active_workers(staff_path)
    return [dict(item, **item_status(item, roadmap, workers)) for item in in_work]
