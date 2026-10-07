#!/usr/bin/env python3
"""List the plugins in awesome-jellyfin's README sorted by GitHub stars.

Usage:  GH_TOKEN=ghp_xxx python3 scripts/awesome-jellyfin-stars.py [--section "UI & Customization"] [--csv out.csv]
        (token optional: unauthenticated GitHub API allows only 60 requests/hour; the list has ~110 repos)
Uses a single GraphQL request per 50 repos when a token is set, REST otherwise.
"""
import argparse, csv, json, os, re, sys, urllib.request

README = "https://raw.githubusercontent.com/awesome-jellyfin/awesome-jellyfin/main/README.md"
TOKEN = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")

def get(url, data=None):
    req = urllib.request.Request(url, data=data)
    req.add_header("User-Agent", "awesome-jellyfin-stars")
    if TOKEN:
        req.add_header("Authorization", f"Bearer {TOKEN}")
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)

def parse(text):
    """Return [(section, name, owner, repo)] for entries under '## Plugins' only."""
    out, section, in_plugins = [], "", False
    for line in text.splitlines():
        if line.startswith("## "):
            in_plugins = "Plugins" in line
        elif line.startswith("### "):
            section = re.sub(r"^###\s*\S+\s*", "", line).strip()
        m = re.match(r"- \[([^\]]+)\]\(https://github\.com/([^/)\s]+)/([^/)\s#]+)", line)
        if in_plugins and m:
            out.append((section, m.group(1), m.group(2), m.group(3)))
    return out

def stars_graphql(repos):
    result = {}
    for i in range(0, len(repos), 50):
        chunk = repos[i:i + 50]
        fields = "\n".join(
            f'r{j}: repository(owner:"{o}", name:"{n}") {{ stargazerCount }}'
            for j, (_, _, o, n) in enumerate(chunk))
        res = get("https://api.github.com/graphql",
                  json.dumps({"query": "query {" + fields + "}"}).encode())
        for j, (_, _, o, n) in enumerate(chunk):
            node = (res.get("data") or {}).get(f"r{j}")
            result[(o, n)] = node["stargazerCount"] if node else None
    return result

def stars_rest(repos):
    result = {}
    for _, _, o, n in repos:
        try:
            result[(o, n)] = get(f"https://api.github.com/repos/{o}/{n}")["stargazers_count"]
        except Exception as e:
            print(f"warn: {o}/{n}: {e}", file=sys.stderr)
            result[(o, n)] = None
    return result

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--section", help="only this plugin section, e.g. 'Playback'")
    ap.add_argument("--csv", help="also write results to this CSV file")
    ap.add_argument("--readme", help="read a local README.md instead of downloading")
    a = ap.parse_args()
    text = open(a.readme).read() if a.readme else urllib.request.urlopen(README).read().decode()
    entries = parse(text)
    if a.section:
        entries = [e for e in entries if a.section.lower() in e[0].lower()]
    stars = (stars_graphql if TOKEN else stars_rest)(entries)
    rows = sorted(((stars[(o, n)] or 0, sec, name, f"https://github.com/{o}/{n}")
                   for sec, name, o, n in entries), reverse=True)
    for s, sec, name, url in rows:
        print(f"{s:>6}  {name:<45} {sec:<24} {url}")
    if a.csv:
        with open(a.csv, "w", newline="") as f:
            w = csv.writer(f); w.writerow(["stars", "name", "section", "url"])
            w.writerows((s, name, sec, url) for s, sec, name, url in rows)

if __name__ == "__main__":
    main()
