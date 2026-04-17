# ── PATH helper: only add a dir if it actually exists ────────
_pathdd() { [[ -d "$1" ]] && export PATH="$1:$PATH"; }

# ── Core user paths ──────────────────────────────────────────
_pathdd "$HOME/bin"
_pathdd "$HOME/.local/bin"
_pathdd "$HOME/.npm-global/bin"

# ── Maven ────────────────────────────────────────────────────
export MAVEN_HOME=/opt/apache-maven
_pathdd "$MAVEN_HOME/bin"

# ── Java ─────────────────────────────────────────────────────
export JAVA_HOME=/opt/jdk-1.8
_pathdd "$JAVA_HOME/bin"

# ── PyCharm ──────────────────────────────────────────────────
export IDEA_HOME="$HOME/vault/apps/pycharm-2024"
_pathdd "$IDEA_HOME/bin"

# ── VS Code ──────────────────────────────────────────────────
export VS_CODE=/opt/vscode
_pathdd "$VS_CODE/bin"

# ── Screenshot tool ──────────────────────────────────────────
export IMGUR_SCREENSHOT=/opt/screenshot
_pathdd "$IMGUR_SCREENSHOT"

# ── Colour for directory listings ────────────────────────────
export LS_COLORS='ow=07;33:'

# ── Node.js heap size ────────────────────────────────────────
export NODE_OPTIONS="--max-old-space-size=5120"

# ── Python project path ──────────────────────────────────────
# NOTE: PYTHONPATH is for Python module resolution only — never add it to PATH
# Uncomment and update when working on this project:
# export PYTHONPATH="$HOME/vault/code/python/lis/srp/solid"

# ── Default editor (picks first available) ───────────────────
if   command -v code &>/dev/null; then export EDITOR="code --wait"; export VISUAL="code --wait"
elif command -v vim  &>/dev/null; then export EDITOR=vim;            export VISUAL=vim
elif command -v nano &>/dev/null; then export EDITOR=nano;           export VISUAL=nano
fi

# Cleanup helper — don't leak into shell environment
unset -f _pathdd
