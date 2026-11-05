"""Laptop side of the next-action data. Standard library only.

  python scripts/morning_data.py pull          download attempts into ../data/
  python scripts/morning_data.py push-prompt   publish ../data/next_action_prompt.txt

Both read the token from ../APP_TOKEN.txt. The repo is public, so data and the live
prompt are kept outside it. Pull merges into the local copy, so it never loses records.
"""
import argparse
import csv
import json
import sys
import urllib.error
import urllib.request
from collections import Counter
from pathlib import Path

BASE_URL = "https://morning-api-1017056000874.asia-south1.run.app"
PROJECT_DIR = Path(__file__).resolve().parent.parent.parent
DATA_DIR = PROJECT_DIR / "data"
TOKEN_FILE = PROJECT_DIR / "APP_TOKEN.txt"
CSV_FIELDS = ["createdAt", "status", "session", "area", "routine", "suggestions", "source", "action",
              "suggestedAction", "leadMinutes", "startedAt", "deadline", "finishedAt", "promptVersion", "id"]


def call(method, path, body=None):
    req = urllib.request.Request(BASE_URL + path, method=method)
    req.add_header("X-Token", TOKEN_FILE.read_text(encoding="utf-8").strip())
    data = None
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(req, data=data, timeout=60) as resp:
        return json.load(resp)


def status(a):
    if a.get("outcome"):
        return a["outcome"]
    return "running" if a.get("startedAt") else "not committed"


def write_atomic(path, write):
    tmp = path.with_name(path.name + ".tmp")
    with open(tmp, "w", encoding="utf-8-sig" if path.suffix == ".csv" else "utf-8", newline="") as f:
        write(f)
    tmp.replace(path)


def pull(out_dir):
    out_dir.mkdir(parents=True, exist_ok=True)
    path = out_dir / "attempts.json"
    merged = {a["id"]: a for a in json.loads(path.read_text(encoding="utf-8"))} if path.exists() else {}
    remote = call("GET", "/attempts")
    for a in remote:
        if a.get("updatedAt", 0) >= merged.get(a["id"], {}).get("updatedAt", 0):
            merged[a["id"]] = a
    rows = sorted(merged.values(), key=lambda a: a.get("createdAt", ""))

    write_atomic(path, lambda f: json.dump(rows, f, indent=2, ensure_ascii=False))

    def write_csv(f):
        w = csv.DictWriter(f, CSV_FIELDS, extrasaction="ignore")
        w.writeheader()
        for a in rows:
            shown = " | ".join(s.get("action", "") for s in a.get("suggestions", []))
            w.writerow({**a, "status": status(a), "suggestions": shown})

    write_atomic(out_dir / "attempts.csv", write_csv)

    print(f"{len(remote)} on the server, {len(rows)} saved in {out_dir}")
    for key, count in Counter(status(a) for a in rows).most_common():
        print(f"  {key}: {count}")


def push_prompt(path):
    text = path.read_text(encoding="utf-8").strip()
    saved = call("PUT", "/prompt", {"instructions": text})
    print(f"Published {path.name} as prompt version {saved['version']} ({len(text)} characters)")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("pull")
    p.add_argument("--out", type=Path, default=DATA_DIR)
    p = sub.add_parser("push-prompt")
    p.add_argument("--file", type=Path, default=DATA_DIR / "next_action_prompt.txt")
    args = parser.parse_args()
    try:
        if args.command == "pull":
            pull(args.out)
        else:
            push_prompt(args.file)
    except urllib.error.HTTPError as e:
        sys.exit(f"Server said {e.code}. 401 = check {TOKEN_FILE.name}; 400 = prompt must mention json.")
    except urllib.error.URLError as e:
        sys.exit(f"Couldn't reach the backend: {e.reason}")


if __name__ == "__main__":
    main()
