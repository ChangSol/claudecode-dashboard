#!/bin/bash
# cc-dash one-time wire-up — sets ~/.claude/settings.json statusLine.command
# to the currently installed plugin's statusline.sh. Idempotent; re-run after
# plugin upgrades to pick up the new versioned install path.
#
# Override for testing: CC_DASH_SETTINGS=/tmp/x.json bash cc-dash-setup.sh

set -e

SETTINGS="${CC_DASH_SETTINGS:-$HOME/.claude/settings.json}"

if [[ -z "$CLAUDE_PLUGIN_ROOT" ]]; then
  echo "error: CLAUDE_PLUGIN_ROOT is not set. Run this via /ccd-setup inside Claude Code." >&2
  exit 1
fi

# Normalize to forward slashes — safer inside JSON strings and inside bash on
# Git Bash / MSYS where backslash is an escape char.
PLUGIN_ROOT_POSIX="${CLAUDE_PLUGIN_ROOT//\\//}"
STATUSLINE="${PLUGIN_ROOT_POSIX}/scripts/statusline.sh"

if [[ ! -f "$STATUSLINE" ]]; then
  echo "error: statusline.sh not found at $STATUSLINE" >&2
  exit 1
fi

if [[ ! -f "$SETTINGS" ]]; then
  mkdir -p "$(dirname "$SETTINGS")"
  printf '{}\n' > "$SETTINGS"
fi

node - "$SETTINGS" "$STATUSLINE" <<'JS'
const fs = require('fs');
const [, , path, sl] = process.argv;
let raw;
try { raw = fs.readFileSync(path, 'utf8'); }
catch (e) { console.error('error reading ' + path + ': ' + e.message); process.exit(1); }
let cfg;
try { cfg = raw.trim() ? JSON.parse(raw) : {}; }
catch (e) { console.error('error: ' + path + ' is not valid JSON — aborting to avoid data loss. (' + e.message + ')'); process.exit(1); }
const cmd = "bash '" + sl + "'";
const prev = cfg.statusLine && cfg.statusLine.command;
cfg.statusLine = { type: 'command', command: cmd };
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
JS

echo "Wired to $SETTINGS. Next Claude Code prompt will render the dashboard."
