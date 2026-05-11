#!/usr/bin/env python3
"""Posts a Claude-powered code review comment on a GitHub PR."""

import os
import sys
import json
import urllib.request
import urllib.error

import anthropic

GITHUB_TOKEN = os.environ["GITHUB_TOKEN"]
ANTHROPIC_API_KEY = os.environ["ANTHROPIC_API_KEY"]
REPO = os.environ["GITHUB_REPOSITORY"]
PR_NUMBER = os.environ["PR_NUMBER"]
PR_TITLE = os.environ.get("PR_TITLE", "")
PR_BODY = os.environ.get("PR_BODY", "")

SYSTEM_PROMPT = """You are a code reviewer for Sqares, a 2D side-scrolling rogue-like arena
shooter built in Godot 4 with GDScript. The project uses a first-class modding system.

Architecture to keep in mind:
- All built-in content lives in mods/base_game/ and is implemented via SqaresModBase subclasses
- Stats are registered at runtime through StatRegistry (no fixed enums)
- Cards are YAML data files loaded by CardRegistry
- Mods register custom arenas via LevelRegistry and game modes via GameModeRegistry
- UIManager handles mod-injected overlays, menu items, and HUD widgets
- PlayerActionRegistry allows mods to add new player actions
- NetworkManager wraps ENet for online play (authoritative server model)
- AutoLoad singletons: GameManager, StatRegistry, CardRegistry, LevelRegistry,
  GameModeRegistry, UIManager, PlayerActionRegistry, ModLoader, NetworkManager

Review guidelines:
1. GDScript style: snake_case for variables/functions, PascalCase for classes/enums,
   typed variables preferred, signals declared at top, @onready vars grouped together
2. Check that new singletons or registries follow the established pattern
3. Flag any hardcoded stats that should go through StatRegistry
4. Flag any content (cards, levels, game modes) that should live in mods/base_game/
5. Highlight security issues in any networking or mod-loading code
6. Note missing type hints that would help Godot's static analysis
7. Keep feedback actionable and concise — no need to praise correct code at length

Format your review as Markdown. Use sections: **Summary**, **Issues** (numbered list
of must-fix items), **Suggestions** (optional improvements), **Verdict**
(Approve / Request Changes / Comment). Be direct and specific."""


def gh_api(path: str, method: str = "GET", body: dict | None = None) -> dict:
    url = f"https://api.github.com{path}"
    data = json.dumps(body).encode() if body else None
    req = urllib.request.Request(
        url,
        data=data,
        headers={
            "Authorization": f"Bearer {GITHUB_TOKEN}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "Content-Type": "application/json",
        },
        method=method,
    )
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read())


def get_pr_diff() -> str:
    url = f"https://api.github.com/repos/{REPO}/pulls/{PR_NUMBER}"
    req = urllib.request.Request(
        url,
        headers={
            "Authorization": f"Bearer {GITHUB_TOKEN}",
            "Accept": "application/vnd.github.diff",
            "X-GitHub-Api-Version": "2022-11-28",
        },
    )
    with urllib.request.urlopen(req) as resp:
        return resp.read().decode("utf-8", errors="replace")


def post_comment(body: str) -> None:
    gh_api(f"/repos/{REPO}/issues/{PR_NUMBER}/comments", method="POST", body={"body": body})


def main() -> None:
    diff = get_pr_diff()
    if not diff.strip():
        print("Empty diff — skipping review.")
        return

    # Truncate very large diffs to stay within model context
    max_diff_chars = 80_000
    truncated = False
    if len(diff) > max_diff_chars:
        diff = diff[:max_diff_chars]
        truncated = True

    user_message = f"""Please review this pull request.

**PR #{PR_NUMBER}: {PR_TITLE}**
{PR_BODY or "_No description provided._"}

---

```diff
{diff}
```
{"_[diff truncated — showing first 80 000 characters]_" if truncated else ""}"""

    client = anthropic.Anthropic(api_key=ANTHROPIC_API_KEY)
    response = client.messages.create(
        model="claude-opus-4-7",
        max_tokens=4096,
        thinking={"type": "adaptive"},
        system=SYSTEM_PROMPT,
        messages=[{"role": "user", "content": user_message}],
    )

    review_text = next(
        (block.text for block in response.content if block.type == "text"), ""
    )

    comment = f"## Claude Code Review\n\n{review_text}\n\n---\n_Automated review by Claude Opus 4.7_"
    post_comment(comment)
    print("Review posted successfully.")


if __name__ == "__main__":
    main()
