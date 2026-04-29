#!/usr/bin/env python3
"""Resolve PR markdown image URLs to rendered/private image URLs.

This is designed for agents reading PR descriptions/comments:
1. If URL already returns HTTP 200 on HEAD, do not remap.
2. Parse PR target from URL or repo + PR number.
3. Query GitHub GraphQL for markdown + HTML bodies.
4. Extract markdown image URLs and HTML src URLs in order.
5. Build mapping markdown_url -> html_src_url.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from typing import Dict, Iterable, List, Optional, Tuple

PR_URL_RE = re.compile(r"^https?://github\.com/([^/]+)/([^/]+)/pull/([0-9]+)(?:/.*)?$")
MD_IMAGE_RE = re.compile(r"!\[[^\]]*\]\(([^)\s]+(?:\s+\"[^\"]*\")?)\)")
HTML_SRC_RE = re.compile(r'\ssrc="([^"]+)"')
EPHEMERAL_WARNING = (
    "Resolved private image URLs are signed and ephemeral; they may expire within minutes. "
    "Use immediately and re-resolve when needed."
)

GRAPHQL_QUERY = """
query GetBody($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) {
      bodyHTML
      body
      comments(first: 100) {
        nodes { bodyHTML body }
      }
      reviews(first: 100) {
        nodes {
          comments(first: 100) {
            nodes { bodyHTML body }
          }
        }
      }
    }
  }
}
""".strip()


@dataclass
class BodyEntry:
    md: str
    html: str


class PRImageResolver:
    def __init__(self, gh_user: Optional[str] = None):
        self.gh_user = gh_user
        self._cache: Dict[str, str] = {}
        self._switched_user = False

    def resolve(self, owner: str, repo: str, pr_number: int, src: str) -> Optional[str]:
        if src in self._cache:
            return self._cache[src]
        if not src.startswith("https://github.com"):
            return None
        if self._url_is_directly_accessible(src):
            return None

        bodies = self._fetch_bodies(owner, repo, pr_number)
        if not bodies:
            return None

        self._populate_cache(bodies)
        return self._cache.get(src)

    def build_map(self, owner: str, repo: str, pr_number: int) -> Dict[str, str]:
        bodies = self._fetch_bodies(owner, repo, pr_number)
        if not bodies:
            return {}
        self._populate_cache(bodies)
        return dict(self._cache)

    def _url_is_directly_accessible(self, src: str) -> bool:
        proc = subprocess.run(
            ["curl", "-s", "-X", "HEAD", "-I", src],
            capture_output=True,
            text=True,
            check=False,
        )
        if proc.returncode != 0:
            return False
        first_line = proc.stdout.splitlines()[0] if proc.stdout else ""
        return "200" in first_line

    def _fetch_bodies(self, owner: str, repo: str, number: int) -> List[BodyEntry]:
        output = self._gh(
            [
                "api",
                "graphql",
                "-F",
                f"owner={owner}",
                "-F",
                f"repo={repo}",
                "-F",
                f"number={number}",
                "-f",
                f"query={GRAPHQL_QUERY}",
            ]
        )
        if not output:
            return []
        try:
            response = json.loads(output)
        except json.JSONDecodeError:
            return []

        data = response.get("data", {}).get("repository", {}).get("pullRequest")
        if not data:
            return []

        bodies: List[BodyEntry] = [
            BodyEntry(md=data.get("body") or "", html=data.get("bodyHTML") or "")
        ]

        comments = data.get("comments", {}).get("nodes", []) or []
        for comment in comments:
            bodies.append(
                BodyEntry(
                    md=comment.get("body") or "", html=comment.get("bodyHTML") or ""
                )
            )

        reviews = data.get("reviews", {}).get("nodes", []) or []
        for review in reviews:
            review_comments = review.get("comments", {}).get("nodes", []) or []
            for comment in review_comments:
                bodies.append(
                    BodyEntry(
                        md=comment.get("body") or "", html=comment.get("bodyHTML") or ""
                    )
                )

        return bodies

    def _populate_cache(self, bodies: Iterable[BodyEntry]) -> None:
        for body in bodies:
            md_urls = self._extract_markdown_urls(body.md)
            html_urls = self._extract_html_urls(body.html)
            for idx, md_url in enumerate(md_urls):
                if idx < len(html_urls):
                    self._cache[md_url] = html_urls[idx]

    def _extract_markdown_urls(self, markdown: str) -> List[str]:
        matches: List[Tuple[int, str]] = []
        for match in MD_IMAGE_RE.finditer(markdown):
            raw = match.group(1).strip()
            if " " in raw and raw.endswith('"'):
                raw = raw.split(" ", 1)[0]
            matches.append((match.start(1), raw))
        for match in HTML_SRC_RE.finditer(markdown):
            matches.append((match.start(1), match.group(1)))
        matches.sort(key=lambda item: item[0])
        return [url for _, url in matches]

    def _extract_html_urls(self, html: str) -> List[str]:
        return [m.group(1) for m in HTML_SRC_RE.finditer(html)]

    def _gh(self, args: List[str]) -> Optional[str]:
        env = os.environ.copy()
        if self.gh_user:
            env.pop("GH_TOKEN", None)
            env.pop("GITHUB_TOKEN", None)
            if not self._switched_user:
                switch = subprocess.run(
                    ["gh", "auth", "switch", "--user", self.gh_user],
                    capture_output=True,
                    text=True,
                    check=False,
                    env=env,
                )
                if switch.returncode != 0:
                    sys.stderr.write(switch.stderr or switch.stdout)
                    return None
                self._switched_user = True

        proc = subprocess.run(
            ["gh", *args],
            capture_output=True,
            text=True,
            check=False,
            env=env,
        )
        if proc.returncode != 0:
            sys.stderr.write(proc.stderr or proc.stdout)
            return None
        return proc.stdout


def parse_pr_target(
    pr_url: Optional[str], repo: Optional[str], pr_number: Optional[int]
) -> Optional[Tuple[str, str, int]]:
    if pr_url:
        match = PR_URL_RE.match(pr_url)
        if not match:
            return None
        owner, repo_name, raw_number = match.groups()
        return owner, repo_name, int(raw_number)

    if repo and pr_number is not None:
        if "/" not in repo:
            return None
        owner, repo_name = repo.split("/", 1)
        if not owner or not repo_name:
            return None
        return owner, repo_name, pr_number
    return None


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Resolve GitHub image URLs from PR descriptions/comments."
    )
    parser.add_argument("--gh-user", help="Optional gh user to switch to before API calls.")
    parser.add_argument("--json", action="store_true", help="Emit JSON output.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    resolve_parser = subparsers.add_parser("resolve", help="Resolve one markdown image URL.")
    resolve_parser.add_argument("--pr-url", help="PR URL: https://github.com/owner/repo/pull/123")
    resolve_parser.add_argument("--repo", help="Repository in owner/repo format.")
    resolve_parser.add_argument("--pr-number", type=int, help="Pull request number.")
    resolve_parser.add_argument("--src", required=True, help="Markdown image URL to resolve.")

    map_parser = subparsers.add_parser("map", help="Build URL map for a pull request.")
    map_parser.add_argument("--pr-url", help="PR URL: https://github.com/owner/repo/pull/123")
    map_parser.add_argument("--repo", help="Repository in owner/repo format.")
    map_parser.add_argument("--pr-number", type=int, help="Pull request number.")

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    resolver = PRImageResolver(gh_user=args.gh_user)

    if args.command == "resolve":
        target = parse_pr_target(args.pr_url, args.repo, args.pr_number)
        if not target:
            parser.error("Provide --pr-url OR both --repo and --pr-number.")
        owner, repo, pr_number = target
        resolved = resolver.resolve(owner, repo, pr_number, args.src)
        if args.json:
            print(
                json.dumps(
                    {
                        "repo": f"{owner}/{repo}",
                        "pr_number": pr_number,
                        "src": args.src,
                        "resolved": resolved,
                        "ephemeral_warning": EPHEMERAL_WARNING,
                    },
                    indent=2,
                )
            )
        elif resolved:
            print(resolved)
        return 0

    if args.command == "map":
        target = parse_pr_target(args.pr_url, args.repo, args.pr_number)
        if not target:
            parser.error("Provide --pr-url OR both --repo and --pr-number.")
        owner, repo, pr_number = target
        mapping = resolver.build_map(owner, repo, pr_number)
        if args.json:
            print(
                json.dumps(
                    {
                        "repo": f"{owner}/{repo}",
                        "pr_number": pr_number,
                        "count": len(mapping),
                        "mapping": mapping,
                        "ephemeral_warning": EPHEMERAL_WARNING,
                    },
                    indent=2,
                )
            )
        else:
            for source, resolved in mapping.items():
                print(f"{source} -> {resolved}")
        return 0

    parser.print_help()
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
