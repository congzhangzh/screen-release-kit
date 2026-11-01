#!/usr/bin/env python3
"""Publish a kit release on GitHub, using only the standard library.

Usage: publish-release.py <tag> <kit sha> <title> <notes.md> <asset>...
Environment: GH_TOKEN, GITHUB_REPOSITORY, GITHUB_API_URL (the workflow provides them), and
CHECK_REPOS: more repositories (owner/name, space-separated) whose releases count as taken.

Order, so that a failure leaves nothing half-public:
  0. refuse when a release with this title already exists here or in CHECK_REPOS: a
     package version is released once (bump the revision in sources.lock instead);
  1. a draft release (a draft creates no tag) with every asset uploaded;
  2. publish the draft, which creates the tag <tag> at <kit sha>.
A failure before 2 leaves only a draft, which nobody else sees.
"""
import json, mimetypes, os, sys, urllib.error, urllib.parse, urllib.request

tag, sha, title, notes_file, *assets = sys.argv[1:]
token = os.environ["GH_TOKEN"]
repo = os.environ["GITHUB_REPOSITORY"]
api = os.environ.get("GITHUB_API_URL", "https://api.github.com")
check = [repo] + os.environ.get("CHECK_REPOS", "").split()


def call(method, url, body=None, data=None, ctype="application/json"):
    if body is not None:
        data = json.dumps(body).encode()
    req = urllib.request.Request(url, data=data, method=method, headers={
        "Authorization": f"Bearer {token}",
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "Content-Type": ctype,
    })
    try:
        with urllib.request.urlopen(req) as r:
            return json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        sys.exit(f"::error::{method} {url}: HTTP {e.code}: {e.read().decode(errors='replace')[:500]}")


for r in check:
    for page in range(1, 11):
        rels = call("GET", f"{api}/repos/{r}/releases?per_page=100&page={page}")
        for rel in rels:
            if rel["name"] == title and not rel["draft"]:
                sys.exit(f"::error::{title} is already released ({rel['html_url']}); "
                         "bump the revision in sources.lock")
            if rel["tag_name"] == tag and r == repo:
                sys.exit(f"::error::tag {tag} is taken ({rel['html_url']})")
        if len(rels) < 100:
            break

with open(notes_file, encoding="utf-8") as f:
    notes = f.read()

rel = call("POST", f"{api}/repos/{repo}/releases", {
    "tag_name": tag, "target_commitish": sha, "name": title, "body": notes,
    "draft": True, "make_latest": "true",
})
print(f"draft release {rel['id']} for {tag}")

upload = rel["upload_url"].split("{", 1)[0]
for path in assets:
    name = os.path.basename(path)
    ctype = mimetypes.guess_type(name)[0] or "application/octet-stream"
    with open(path, "rb") as f:
        a = call("POST", f"{upload}?name={urllib.parse.quote(name)}", data=f.read(), ctype=ctype)
    print(f"  uploaded {name} ({a.get('size')} bytes)")

rel = call("PATCH", f"{api}/repos/{repo}/releases/{rel['id']}", {"draft": False})
print(f"published {rel['html_url']}")
