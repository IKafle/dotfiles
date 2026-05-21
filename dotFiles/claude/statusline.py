#!/usr/bin/env python3
import json
import os
import sys

try:
    data = json.load(sys.stdin)
except (json.JSONDecodeError, ValueError):
    print("[?] no data")
    sys.exit(0)

model_name = data.get('model', {}).get('display_name', 'Unknown')
total_input_tokens = data.get('context_window', {}).get('total_input_tokens', 0) or 0
used_percentage = data.get('context_window', {}).get('used_percentage', 0) or 0
cwd = (
    data.get('workspace', {}).get('current_dir')
    or data.get('cwd')
    or ''
)


def format_tokens(n):
    if n >= 1_000_000:
        v = n / 1_000_000
        return f"{int(v)}M" if v == int(v) else f"{v:.1f}M"
    if n >= 1_000:
        v = n / 1_000
        return f"{int(v)}k" if v == int(v) else f"{v:.1f}k"
    return str(int(n))


def derive_limit(tokens, pct):
    if pct < 1 or tokens < 1000:
        return None
    raw = tokens / (pct / 100)
    # Snap to common Anthropic context sizes (handles integer-% rounding error)
    if raw <= 300_000:
        return 200_000
    if raw <= 700_000:
        return 500_000
    if raw <= 1_500_000:
        return 1_000_000
    return int(round(raw / 100_000) * 100_000)


tokens_display = format_tokens(total_input_tokens)
limit = derive_limit(total_input_tokens, used_percentage)
limit_display = f" / {format_tokens(limit)}" if limit else ""

if used_percentage >= 90:
    color = '\033[31m'
elif used_percentage >= 70:
    color = '\033[33m'
else:
    color = '\033[32m'
reset = '\033[0m'

cwd_name = os.path.basename(cwd.rstrip('/')) if cwd else ''

def find_git_head(start_dir):
    d = os.path.abspath(start_dir)
    while True:
        head = os.path.join(d, '.git', 'HEAD')
        if os.path.isfile(head):
            return head
        # Worktrees: .git is a file pointing at the gitdir
        dotgit = os.path.join(d, '.git')
        if os.path.isfile(dotgit):
            try:
                with open(dotgit) as f:
                    line = f.readline().strip()
                if line.startswith('gitdir: '):
                    gitdir = line[len('gitdir: '):]
                    if not os.path.isabs(gitdir):
                        gitdir = os.path.join(d, gitdir)
                    cand = os.path.join(gitdir, 'HEAD')
                    if os.path.isfile(cand):
                        return cand
            except OSError:
                pass
        parent = os.path.dirname(d)
        if parent == d:
            return None
        d = parent


branch = ''
if cwd and os.path.isdir(cwd):
    head_path = find_git_head(cwd)
    if head_path:
        try:
            with open(head_path) as f:
                ref = f.readline().strip()
            if ref.startswith('ref: refs/heads/'):
                branch = ref[len('ref: refs/heads/'):]
            elif ref:
                branch = ref[:7]  # detached HEAD — short sha
        except OSError:
            pass

pct_int = int(used_percentage)

prefix_parts = [f"[{model_name}]"]
if cwd_name:
    prefix_parts.append(cwd_name)
if branch:
    prefix_parts.append(f"({branch})")
prefix = ' '.join(prefix_parts)

token_portion = f"{color}{tokens_display}{limit_display} ({pct_int}%){reset}"

print(f"{prefix} | {token_portion}")
