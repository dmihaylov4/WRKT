#!/usr/bin/env python3
# tools/svg_indexer_run.py
#
# Run directly (no CLI args needed):
#   python tools/svg_indexer_run.py
#
# It will read the two SVGs below and write the JSON index to OUTPUT_JSON.

import os
import sys
import json
import xml.etree.ElementTree as ET
from collections import defaultdict
from typing import Tuple

# ---- YOUR PATHS (edit here if you move files) -------------------------------
FRONT_SVG     = "/Users/dimitarmihaylov/dev/WRKT/torso.svg"
BACK_SVG      = "/Users/dimitarmihaylov/dev/WRKT/torso_back.svg"
OUTPUT_JSON   = "/Users/dimitarmihaylov/dev/WRKT/muscles_index.json"
# -----------------------------------------------------------------------------

NSBRACE_START = "{"

def strip_ns(tag: str) -> str:
    """Turn '{http://www.w3.org/2000/svg}g' -> 'g'."""
    if tag.startswith(NSBRACE_START):
        return tag.split("}", 1)[1]
    return tag

def parse_svg(path: str, side_hint: str | None = None) -> Tuple[ET.Element, str]:
    """Parse an SVG file and return (root_element, side_label)."""
    if not os.path.exists(path):
        print(f"ERROR: file not found → {path}", file=sys.stderr)
        sys.exit(2)
    try:
        tree = ET.parse(path)
        root = tree.getroot()
    except Exception as e:
        print(f"ERROR: failed to parse {path}: {e}", file=sys.stderr)
        sys.exit(2)

    # Infer side if not provided
    name = os.path.basename(path).lower()
    if side_hint:
        side = side_hint
    elif "back" in name or "posterior" in name:
        side = "back"
    else:
        side = "front"
    return root, side

def walk_svg_groups(root: ET.Element, side_label: str) -> dict:
    """
    Traverse the SVG and record EVERY <g> element (group), regardless of id/class).
    Returns:
      {
        "elements":  [ {id, classes, tag, parentId, side}, ... ],
        "byId":      { id: info, ... },
        "classToIds":{ class: [ids], ... },
        "counts":    { total, groups, with_id, with_class }
      }
    """
    elements = []
    byId = {}
    class_to_ids = defaultdict(set)  # dedupe
    counts = {"total": 0, "groups": 0, "with_id": 0, "with_class": 0}

    def rec(el: ET.Element, parent_id):
        tag = strip_ns(el.tag)
        el_id = el.attrib.get("id")
        cls_raw = el.attrib.get("class", "") or ""
        classes = [c for c in cls_raw.replace("\n", " ").split(" ") if c]

        if tag == "g":  # record ONLY groups
            info = {
                "id": el_id,
                "classes": classes,
                "tag": tag,
                "parentId": parent_id,
                "side": side_label,
            }
            elements.append(info)
            counts["total"] += 1
            counts["groups"] += 1
            if el_id:
                counts["with_id"] += 1
                byId[el_id] = info
            if classes:
                counts["with_class"] += 1
                if el_id:
                    for c in classes:
                        class_to_ids[c].add(el_id)

        # Recurse regardless, so nested groups are visited
        for child in list(el):
            rec(child, el_id or parent_id)

    rec(root, parent_id=None)

    # Convert sets to sorted lists for JSON
    class_to_ids_json = {k: sorted(v) for k, v in sorted(class_to_ids.items(), key=lambda kv: kv[0])}

    return {
        "elements": elements,
        "byId": byId,
        "classToIds": class_to_ids_json,
        "counts": counts,
    }

def main():
    root_f, side_f = parse_svg(FRONT_SVG, None)
    root_b, side_b = parse_svg(BACK_SVG, None)

    idx_front = walk_svg_groups(root_f, side_f)
    idx_back  = walk_svg_groups(root_b, side_b)

    out = {
        "front": idx_front,
        "back":  idx_back,
    }

    os.makedirs(os.path.dirname(OUTPUT_JSON) or ".", exist_ok=True)
    with open(OUTPUT_JSON, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=2)

    print(f"Wrote {OUTPUT_JSON}")
    print(f"  front counts: {idx_front['counts']}")
    print(f"  back  counts: {idx_back['counts']}")
    # Quick hints for inspection:
    print(list(idx_front["byId"].keys())[:10])
    print(list(idx_front["classToIds"].keys())[:20])

if __name__ == "__main__":
    main()