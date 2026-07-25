# Contributing to clerk-zig

Thanks for contributing.

## Linear + Graphite workflow (required for product work)

Internal product work is tracked in **[Linear](https://linear.app)** team **AUTH**
(identifier **`AUTH`**), not free-form GitHub Issues.

| Piece | Convention |
| --- | --- |
| Linear issue | `AUTH-N` |
| Issue trunk | `trunk-AUTH-N` (from `master`) |
| Stack PRs | Graphite stack basing on the issue trunk |
| Land PR | `trunk-AUTH-N` → `master` (squash preferred) |

```text
master ──────────────────────────────────────────►
   \
    trunk-AUTH-12
       ├── stack PR 1
       ├── stack PR 2
       └── stack PR 3
              └──► land PR: trunk-AUTH-12 → master
```

**One Linear issue per issue trunk.** Do not mix issues on one `trunk-AUTH-*` branch.

### Linking (Linear GitHub integration)

1. **Branch name** — include `AUTH-N` (or copy git branch name from Linear).
2. **PR title** — include `AUTH-N`.
3. **PR body** — closing: `Fixes AUTH-N` / `Closes AUTH-N`; non-closing: `Related to AUTH-N`.
4. Magic words in **descriptions** need the keyword; title/branch ID alone still links.

### Graphite recipe

```bash
# Install: https://graphite.com/docs/install-the-cli
# Auth:    https://app.graphite.com/settings/cli

git fetch origin
git checkout master && git pull --ff-only

# Issue trunk (refuse if name already exists)
if git show-ref --verify --quiet refs/heads/trunk-AUTH-N; then
  echo "trunk exists — gt checkout or delete only after land PR merged" >&2
  exit 1
fi
git checkout -b trunk-AUTH-N origin/master
gt config   # multitrunk: add trunk-AUTH-N alongside master

gt create --all -m "AUTH-N: first slice"
gt submit --stack
# …more slices…
gt modify --all && gt submit --stack && gt sync

# Land after stack is green/reviewed
gh pr create --base master --head trunk-AUTH-N \
  --title "AUTH-N: <short title>" \
  --body "Closes AUTH-N."
```

Amend mid-stack with `gt modify`, restack with `gt sync`, push with `gt submit`
(or `--force-with-lease`) — not raw `git push --force`.

Merge stacks from Graphite (or bottom-up into the issue trunk), then land
`trunk-AUTH-N` → `master`.

See also: [Graphite cheatsheet](https://graphite.com/docs/cheatsheet),
[reviewing stacks](https://graphite.com/docs/best-practices-for-reviewing-stacks),
`.github/GITHUB_SETTINGS.md`.

## Continuous integration + Graphite

Expensive workflows may be gated by **[Graphite CI Optimizations](https://graphite.com/docs/stacking-and-ci)**
(`.github/workflows/graphite-ci-optimizer.yml` + `withgraphite/graphite-ci-action`).

- Mid/upstack PRs can skip when Graphite says so.
- Missing token / API errors **fail open** (CI still runs).
- Secret: `GRAPHITE_CI_TOKEN`.
- Configure stack layers: [Graphite CI Optimizations](https://app.graphite.com/settings/ci-optimizations).

CI triggers use `pull_request` types `opened | reopened | synchronize` only
(not `edited`, which fires when Graphite retargets bases). Temporary
`graphite-base/*` bases should not drive required checks — see
`.github/GITHUB_SETTINGS.md`.

## Agents

See [AGENTS.md](AGENTS.md) for agent-specific rules (Linear MCP, product boundaries).
