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

node - "$SETTINGS" "$STATUSLINE" <<'JS'
const fs = require('fs');
const [, , path, sl] = process.argv;
let raw;
try { raw = fs.readFileSync(path, 'utf8'); }
catch (e) { console.error('error reading ' + path + ': ' + e.message); process.exit(1); }
let cfg;
try { cfg = raw.trim() ? JSON.parse(raw) : {}; }
catch (e) { console.error('error: ' + path + ' is not valid JSON — aborting to avoid data loss. (' + e.message + ')'); process.exit(1); }

// 1. statusLine
const cmd = "bash '" + sl + "'";
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
