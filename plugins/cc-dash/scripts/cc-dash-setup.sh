#!/bin/bash
# cc-dash one-time wire-up for ~/.claude/settings.json:
#   - statusLine.command → this install's statusline.sh
#   - permissions.allow  → Bash allowlist for /ccd and /ccd-setup invocations
# Idempotent; safe to re-run after each plugin upgrade to refresh the path.
#
# Override for testing: CC_DASH_SETTINGS=/tmp/x.json bash cc-dash-setup.sh

set -e

SETTINGS="${CC_DASH_SETTINGS:-$HOME/.claude/settings.json}"

# Claude Code substitutes ${CLAUDE_PLUGIN_ROOT} in command.md files but does
# NOT export it to the invoked bash process, so derive the plugin root from
# the script's own location. (Prefer an explicit env var if caller set one.)
if [[ -n "$CLAUDE_PLUGIN_ROOT" ]]; then
  PLUGIN_ROOT="$CLAUDE_PLUGIN_ROOT"
else
  PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

# Normalize to forward slashes — safer inside JSON strings and inside bash on
# Git Bash / MSYS where backslash is an escape char.
PLUGIN_ROOT="${PLUGIN_ROOT//\\//}"
STATUSLINE="${PLUGIN_ROOT}/scripts/statusline.sh"

if [[ ! -f "$STATUSLINE" ]]; then
  echo "error: statusline.sh not found at $STATUSLINE" >&2
  exit 1
fi

if [[ ! -f "$SETTINGS" ]]; then
  mkdir -p "$(dirname "$SETTINGS")"
  printf '{}\n' > "$SETTINGS"
fi

# statusline.sh needs bash 4.3+ (printf '%(...)T' is 4.2, `local -n` nameref is
# 4.3). macOS ships /bin/bash 3.2 frozen at GPLv2; if that's all PATH gives us,
# fall back to a Homebrew-installed bash so Claude Code spawns the right one.
pick_bash() {
  local cand ver maj min
  for cand in "$@"; do
    [[ -n "$cand" && -x "$cand" ]] || continue
    ver=$("$cand" -c 'printf %s "$BASH_VERSION"' 2>/dev/null) || continue
    maj="${ver%%.*}"
    min="${ver#*.}"; min="${min%%.*}"
    [[ "$maj" =~ ^[0-9]+$ && "$min" =~ ^[0-9]+$ ]] || continue
    if (( maj > 4 || (maj == 4 && min >= 3) )); then
      printf '%s' "$cand"
      return 0
    fi
  done
  return 1
}

PATH_BASH="$(command -v bash 2>/dev/null || true)"
BASH_BIN_FOR_CMD=""
if pick_bash "$PATH_BASH" >/dev/null; then
  : # PATH bash is new enough — leave the wired command as plain `bash`
else
  BREW_BASH="$(pick_bash /opt/homebrew/bin/bash /usr/local/bin/bash || true)"
  if [[ -n "$BREW_BASH" ]]; then
    BASH_BIN_FOR_CMD="$BREW_BASH"
    echo "info: PATH bash (${PATH_BASH:-not found}) is too old; using $BREW_BASH for statusLine."
  else
    echo "warning: no bash 4.3+ found on PATH or in /opt/homebrew/bin /usr/local/bin." >&2
    echo "         macOS users: brew install bash, then re-run /cc-dash:ccd-setup." >&2
    echo "         The statusLine will render a one-line bash-too-old warning until you do." >&2
  fi
fi

node - "$SETTINGS" "$STATUSLINE" "$BASH_BIN_FOR_CMD" <<'JS'
const fs = require('fs');
const [, , path, sl, bashOverride] = process.argv;
let raw;
try { raw = fs.readFileSync(path, 'utf8'); }
catch (e) { console.error('error reading ' + path + ': ' + e.message); process.exit(1); }
let cfg;
try { cfg = raw.trim() ? JSON.parse(raw) : {}; }
catch (e) { console.error('error: ' + path + ' is not valid JSON — aborting to avoid data loss. (' + e.message + ')'); process.exit(1); }

// 1. statusLine
const bashRef = bashOverride ? "'" + bashOverride + "'" : "bash";
const cmd = bashRef + " '" + sl + "'";
const prev = cfg.statusLine && cfg.statusLine.command;
cfg.statusLine = { type: 'command', command: cmd };

// 2. permissions.allow — Bash rules so /ccd and /ccd-setup skip approval prompts
cfg.permissions = cfg.permissions || {};
cfg.permissions.allow = cfg.permissions.allow || [];
const rules = [
  'Bash(*cc-dash-config.sh*)',
  'Bash(*cc-dash-setup.sh*)',
  'Bash(*statusline.sh*)'
];
const addedRules = rules.filter(r => !cfg.permissions.allow.includes(r));
cfg.permissions.allow.push(...addedRules);

fs.writeFileSync(path, JSON.stringify(cfg, null, 2) + '\n');

if (prev === cmd) {
  console.log('statusLine already up to date: ' + cmd);
} else if (prev) {
  console.log('statusLine updated.');
  console.log('  from: ' + prev);
  console.log('  to:   ' + cmd);
} else {
  console.log('statusLine added: ' + cmd);
}
if (addedRules.length) {
  console.log('permissions.allow added: ' + addedRules.join(', '));
} else {
  console.log('permissions.allow already has cc-dash rules.');
}
JS

echo "Wired to $SETTINGS. Next Claude Code prompt will render the dashboard."
