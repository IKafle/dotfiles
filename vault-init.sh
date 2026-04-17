#!/bin/bash
#
# vault-init.sh
# ─────────────────────────────────────────────────────────────────────────────
# Creates ~/vault with a fixed, human-readable folder structure and routes
# files from common source locations into the right folders automatically.
#
# Safe to run multiple times — skips any work that is already done.
#
# Usage:
#   bash vault-init.sh                        # scans default source dirs
#   bash vault-init.sh ~/Restore ~/USB/files  # also scan extra dirs
#   bash vault-init.sh --include-downloads    # also scan ~/Downloads
#
# Vault structure created:
#   ~/vault/
#   ├── work/
#   │   ├── resumes/      ← CVs, bios, cover letters
#   │   ├── docs/         ← Word docs, reports, contracts
#   │   ├── sheets/       ← Excel files, spreadsheets
#   │   ├── slides/       ← PowerPoint presentations
#   │   ├── architecture/ ← Technical diagrams, system design docs
#   │   └── vpn/          ← VPN configs and scripts
#   ├── school/           ← Thesis, assignments, research papers
#   ├── learning/         ← Books, course PDFs, study notes
#   ├── code/             ← Coding projects and practice
#   ├── gallery/          ← Photos, personal videos, ID scans
#   ├── entertainment/    ← Movies and shows
#   ├── apps/             ← Installed software
#   ├── archives/         ← Compressed backups (.zip, .tar.xz, etc.)
#   └── inbox/            ← Unsorted — review and move out regularly
#
# Rules:
#   - Never deletes anything, only moves
#   - Logs every action to ~/vault/migration.log
#   - Renames files on conflict instead of overwriting
#   - Skips hidden files and system folders (snap, .cache, .config, etc.)
#   - Skips ~/Downloads unless --include-downloads flag is passed
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

H="$HOME"
V="$H/vault"
LOG="$V/migration.log"
INCLUDE_DOWNLOADS=false
MOVED_COUNT=0   # tracks actual moves this run; zero means nothing new to do

# ── Parse flags ──────────────────────────────────────────────
EXTRA_SOURCES=()
for arg in "$@"; do
    case "$arg" in
        --include-downloads) INCLUDE_DOWNLOADS=true ;;
        *) EXTRA_SOURCES+=("$arg") ;;
    esac
done

# ── Helpers ──────────────────────────────────────────────────
ts()   { date '+%Y-%m-%d %H:%M:%S'; }
log()  { echo "[$(ts)] $1" >> "$LOG"; }
info() { echo "  $1"; }
ok()   { echo "  OK: $1"; }
skip() { echo "  --: $1"; }

safe_move() {
    local src="$1" dst_dir="$2" dst_name="${3:-}"

    # Source is gone — already moved in a previous run, silently skip
    [ -e "$src" ] || return 0

    local final_name="${dst_name:-$(basename "$src")}"
    local dest="$dst_dir/$final_name"

    # Destination already has a file with this name — rename to avoid overwrite
    if [ -e "$dest" ]; then
        local base ext stamp
        stamp=$(date '+%s')
        if [[ "$final_name" == *.* ]]; then
            base="${final_name%.*}"
            ext=".${final_name##*.}"
        else
            base="$final_name"
            ext=""
        fi
        dest="$dst_dir/${base} (conflict-${stamp})${ext}"
    fi

    mv "$src" "$dest"
    log "MOVED: $src  →  $dest"
    (( MOVED_COUNT++ )) || true
}

# ── Step 1: vault structure ──────────────────────────────────
create_vault() {
    mkdir -p "$V"/{work/{resumes,docs,sheets,slides,architecture,vpn},school,learning,code,gallery,entertainment,apps,archives,inbox}
}

# ── Step 2: bashrc ───────────────────────────────────────────
setup_bashrc() {
    local dotfiles_bashrc="$H/.bin/dotFiles/bashrc"
    local bashrc="$H/.bashrc"
    local bashrc_bak="$H/.bashrc.bak"
    local expected='. ~/.bin/dotFiles/bashrc'

    echo ""
    echo "── Step 1: .bashrc ─────────────────────────────────────"

    if [ ! -f "$dotfiles_bashrc" ]; then
        skip "~/.bin/dotFiles/bashrc not found — restore your .bin repo first, then re-run"
        echo ""
        return
    fi

    # Check if .bashrc is already the clean one-liner — nothing to do
    local current
    current=$(grep -v '^[[:space:]]*$' "$bashrc" 2>/dev/null || true)
    if [ "$current" = "$expected" ]; then
        skip "~/.bashrc already configured correctly"
        echo ""
        return
    fi

    # First time: back up whatever is there
    if [ ! -f "$bashrc_bak" ]; then
        cp "$bashrc" "$bashrc_bak"
        ok "Backed up ~/.bashrc → ~/.bashrc.bak"
    fi

    printf '%s\n' "$expected" > "$bashrc"
    ok "Wrote ~/.bashrc (sources ~/.bin/dotFiles/bashrc)"

    if bash --norc -c "source $bashrc" 2>/dev/null; then
        ok ".bashrc sources cleanly"
    else
        echo "  WARNING: .bashrc sourced with errors — check ~/.bin/dotFiles/bashrc"
        echo "           Your backup is safe at ~/.bashrc.bak"
    fi
    echo ""
}

# ── Step 3: disable terminal bell ────────────────────────────
disable_bell() {
    local inputrc="$H/.inputrc"

    echo "── Step 2: Terminal bell ────────────────────────────────"

    if grep -q "bell-style none" "$inputrc" 2>/dev/null; then
        skip "Bell already disabled in ~/.inputrc"
    else
        printf 'set bell-style none\n' >> "$inputrc"
        ok "Wrote ~/.inputrc — bell disabled"
    fi
    echo ""
}

# ── Routing logic ────────────────────────────────────────────
route_file() {
    local f="$1"
    [ -f "$f" ] || return

    local name ext lower_name
    name="$(basename "$f")"
    ext="${name##*.}"
    [ "$ext" = "$name" ] && ext=""
    ext="${ext,,}"
    lower_name="${name,,}"

    # VPN / network configs
    if [[ "$lower_name" == *vpn* || "$ext" == "ovpn" ]]; then
        safe_move "$f" "$V/work/vpn/"; return
    fi

    # Resumes, CVs, bios, cover letters
    if [[ "$lower_name" == *resume*            || "$lower_name" == *" cv"*          ||
          "$lower_name" == "cv"*               || "$lower_name" == *"curriculum"*   ||
          "$lower_name" == *"cover letter"*    || "$lower_name" == *"cover_letter"* ||
          "$lower_name" == *"_bio"*            || "$lower_name" == *" bio"*         ||
          "$lower_name" == "bio_"*             || "$lower_name" == "bio "*          ||
          "$lower_name" == *"ikcv"* ]]; then
        safe_move "$f" "$V/work/resumes/"; return
    fi

    # Thesis / academic research
    if [[ "$lower_name" == *"thesis"*       || "$lower_name" == *"dissertation"* ||
          "$lower_name" == *"templete"*     || "$lower_name" == *"template pu"*  ||
          "$lower_name" == *"prediction"*   || "$lower_name" == *"assignment"*   ||
          "$lower_name" == *"research"* ]]; then
        safe_move "$f" "$V/school/"; return
    fi

    # Technical architecture docs
    if [[ ("$ext" == "pdf" || "$ext" == "docx" || "$ext" == "doc") &&
          ("$lower_name" == *"architecture"* || "$lower_name" == *"diagram"*      ||
           "$lower_name" == *"design doc"*   || "$lower_name" == *"system design"* ||
           "$lower_name" == *"erd"*          || "$lower_name" == *"flowchart"*) ]]; then
        safe_move "$f" "$V/work/architecture/"; return
    fi

    case "$ext" in
        jpg|jpeg|png|gif|webp|bmp|tiff|heic|heif|raw|svg)
            safe_move "$f" "$V/gallery/" ;;

        mp4|mkv|mov|m4v|flv|wmv)
            local size_mb
            size_mb=$(( $(stat -c%s "$f") / 1048576 ))
            if (( size_mb > 300 )); then safe_move "$f" "$V/entertainment/"
            else                         safe_move "$f" "$V/gallery/"
            fi ;;

        mp3|flac|wav|aac|ogg|m4a|wma)
            safe_move "$f" "$V/entertainment/" ;;

        pdf)
            if [[ "$lower_name" == *"book"*          || "$lower_name" == *"guide"*    ||
                  "$lower_name" == *"handbook"*       || "$lower_name" == *"learning"* ||
                  "$lower_name" == *"course"*         || "$lower_name" == *"slides"*   ||
                  "$lower_name" == *"interview"*      || "$lower_name" == *"deep dive"* ||
                  "$lower_name" == *"head first"*     || "$lower_name" == *"principles"* ||
                  "$lower_name" == *"certified"*      || "$lower_name" == *"agentic"*  ||
                  "$lower_name" == *"design pattern"* || "$lower_name" == *"the art"* ]]; then
                safe_move "$f" "$V/learning/"
            else
                safe_move "$f" "$V/work/docs/"
            fi ;;

        docx|doc|odt|rtf)  safe_move "$f" "$V/work/docs/"   ;;
        xlsx|xls|ods|csv|tsv) safe_move "$f" "$V/work/sheets/" ;;
        pptx|ppt|odp|key)  safe_move "$f" "$V/work/slides/" ;;
        zip|gz|xz|bz2|7z|rar|tar) safe_move "$f" "$V/archives/" ;;

        txt|md|rst)
            if [[ "$lower_name" == *"question"* || "$lower_name" == *"interview"* ||
                  "$lower_name" == *"cheat"*     || "$lower_name" == *"note"* ]]; then
                safe_move "$f" "$V/learning/"
            else
                safe_move "$f" "$V/inbox/"
            fi ;;

        sh|bash|zsh|fish) safe_move "$f" "$V/inbox/" ;;
        *)                safe_move "$f" "$V/inbox/" ;;
    esac
}

# Detect if a directory looks like a code project
is_code_project() {
    local dir="$1"
    local markers=(
        ".git" "package.json" "requirements.txt" "Pipfile" "pyproject.toml"
        "Makefile" "Dockerfile" "docker-compose.yml" "go.mod" "Cargo.toml"
        "pom.xml" "build.gradle" "CMakeLists.txt" "*.py" "*.js" "*.ts"
        "*.go" "*.rs" ".gitignore"
    )
    for marker in "${markers[@]}"; do
        # shellcheck disable=SC2086
        if ls "$dir"/$marker &>/dev/null 2>&1 || [ -e "$dir/$marker" ]; then
            return 0
        fi
    done
    return 1
}

# Scan a directory: route files, move code project dirs as a whole
scan_dir() {
    local src="$1"
    [ -d "$src" ] || return

    for item in "$src"/*; do
        [ -e "$item" ] || continue
        local item_name
        item_name="$(basename "$item")"
        [[ "$item_name" == .* ]] && continue   # skip hidden

        if [ -f "$item" ]; then
            route_file "$item"
        elif [ -d "$item" ]; then
            if is_code_project "$item"; then
                safe_move "$item" "$V/code/"
            else
                # Not a code project — go one level deeper
                for subitem in "$item"/*; do
                    [ -e "$subitem" ] || continue
                    [[ "$(basename "$subitem")" == .* ]] && continue
                    if [ -f "$subitem" ]; then
                        route_file "$subitem"
                    elif [ -d "$subitem" ] && is_code_project "$subitem"; then
                        safe_move "$subitem" "$V/code/"
                    fi
                done
            fi
        fi
    done
}

# ── Main ─────────────────────────────────────────────────────
main() {
    # Always create vault dirs first (mkdir -p is a no-op if they exist)
    create_vault

    # System setup steps — each checks its own state before acting
    setup_bashrc
    disable_bell

    # Open a new log section for this run
    log "══════════════════════════════════════════"
    log "vault-init.sh run at $(ts)"
    log "══════════════════════════════════════════"

    echo "── Step 3: Organizing files ─────────────────────────────"

    # Default source directories
    local sources=(
        "$H/Documents"
        "$H/personal"
        "$H/Desktop"
    )
    $INCLUDE_DOWNLOADS && sources+=("$H/Downloads")
    for extra in "${EXTRA_SOURCES[@]+"${EXTRA_SOURCES[@]}"}"; do
        sources+=("$extra")
    done

    # Loose files directly in ~/
    for f in "$H"/*; do
        [ -f "$f" ]          || continue
        [[ "$f" == "$V"* ]]  && continue   # never touch files inside vault
        route_file "$f"
    done

    # Configured source directories
    for src in "${sources[@]}"; do
        scan_dir "$src"
    done

    log "══════════════════════════════════════════"
    log "Run complete. Files moved this run: $MOVED_COUNT"
    log "══════════════════════════════════════════"

    echo ""
    if (( MOVED_COUNT == 0 )); then
        echo "  Nothing new to organize — vault is already up to date."
    else
        echo "  Moved $MOVED_COUNT item(s) into ~/vault"
        echo "  Full log: ~/vault/migration.log"
    fi

    echo ""
    echo "── Vault summary ───────────────────────────────────────"
    for d in "$V"/*/; do
        count=$(find "$d" -type f 2>/dev/null | wc -l)
        printf "  %-20s %s files\n" "$(basename "$d")/" "$count"
    done
    echo ""
}

main
