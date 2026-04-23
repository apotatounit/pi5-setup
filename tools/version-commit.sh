#!/usr/bin/env bash
# Bump patch in VERSION, stage all tracked changes, commit with 10 keyword lines.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

[[ -d .git ]] || die "not a git repo — run: git init"

[[ -n "${KEYWORDS:-}" ]] || die "set KEYWORDS='w1 w2 w3 w4 w5 w6 w7 w8 w9 w10' (space-separated)"

read -r -a KW <<< "$KEYWORDS"
((${#KW[@]} == 10)) || die "need exactly 10 keywords, got ${#KW[@]} — KEYWORDS='$KEYWORDS'"

[[ -f VERSION ]] || die "missing VERSION file"

raw="$(tr -d '[:space:]' < VERSION)"
raw="${raw#v}"
[[ "$raw" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "VERSION must be semver M.m.p (got: $(cat VERSION))"

IFS=. read -r maj min pat <<< "$raw"
pat=$((pat + 1))
new="${maj}.${min}.${pat}"
printf '%s\n' "$new" > VERSION

git add -A
git diff --cached --quiet && die "nothing to commit (working tree clean after VERSION bump?)"

msg="$(mktemp)"
{
  printf 'chore(release): v%s\n\n' "$new"
  printf '# %s\n' "${KW[@]}"
} >"$msg"
git commit -F "$msg"
rm -f "$msg"

printf 'committed v%s with 10 keyword lines\n' "$new"
