#!/usr/bin/env python3
import csv, json, re, sys, unicodedata, pathlib

# --- config your column names here ---
EXERCISE_COL = "Exercise"     # header for exercise name
YOUTUBE_COL  = "YouTube"      # header for demo url
# ------------------------------------

def slugify(s: str) -> str:
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode("ascii")
    s = s.lower()
    s = re.sub(r"[^a-z0-9]+", "-", s).strip("-")
    return s

def youtube_id(url: str) -> str | None:
    if not url: return None
    # v= param
    m = re.search(r"[?&]v=([A-Za-z0-9_-]{6,})", url)
    if m: return m.group(1)
    # youtu.be / embed / shorts
    m = re.search(r"(?:youtu\.be/|youtube\.com/(?:embed/|shorts/))([A-Za-z0-9_-]{6,})", url)
    if m: return m.group(1)
    # raw ID
    if re.fullmatch(r"[A-Za-z0-9_-]{6,}", url): return url
    return None

def main(csv_path: str, out_path: str = "exercise_media.json"):
    media_map: dict[str, dict] = {}
    with open(csv_path, newline="", encoding="utf-8") as f:
        rd = csv.DictReader(f)
        if EXERCISE_COL not in rd.fieldnames or YOUTUBE_COL not in rd.fieldnames:
            print(f"CSV must have columns '{EXERCISE_COL}' and '{YOUTUBE_COL}'. Found: {rd.fieldnames}")
            sys.exit(1)
        for row in rd:
            name = (row.get(EXERCISE_COL) or "").strip()
            url  = (row.get(YOUTUBE_COL)  or "").strip()
            if not name or not url: 
                continue
            vid = youtube_id(url)
            if not vid:
                print(f"⚠️  Could not parse YouTube ID: {url} ({name})")
                continue
            key = slugify(name)   # matches your existing id/slug, e.g. "stability-ball-russian-twist"
            media_map[key] = {"youtubeShort": vid}
    with open(out_path, "w", encoding="utf-8") as w:
        json.dump(media_map, w, ensure_ascii=False, indent=2)
    print(f"✅ Wrote {out_path} with {len(media_map)} entries")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python make_media_json.py path/to/exercises.csv [out.json]")
        sys.exit(1)
    csv_in  = sys.argv[1]
    out     = sys.argv[2] if len(sys.argv) > 2 else "exercise_media.json"
    main(csv_in, out)