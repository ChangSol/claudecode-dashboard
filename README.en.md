# cc-dash

[한국어](README.md) | **English**

**A fork-free, zero-dependency statusLine for Claude Code.**
19 widgets — model, duration, API duration, context, tokens, cost, lines changed, budget, rate limits (incl. per-model weekly), permission, output style, version, git, project, session, clock — rendered in three rows. Toggle any widget with `/cc-dash:ccd`.

```
🧠 Opus 4.7 (1M context) │ ⏱  dur 22m0s │ 🪟 ctx 25% │ 💬 token 50.0K │ 💸 cost $0.50 │ ✏️  +120/-34
⏳ now 0% reset 3h0m │ ⏳ week 2% reset 6d22h
🚀 cc v2.1.116 │ 🔀 git: main │ 🕐 2026.04.21 13:03
```

---

## Why

Most statusLine scripts fork `jq`, `awk`, `date`, `git` every second and leave your shell wheezing. cc-dash is **pure bash built-ins on the fast path** (bash ≥ 4.3) — no forks, no `cat`, no `sed`. The only exceptions are two opt-in widgets: budget makes a single `awk` call behind a 60-second cache, and `RATE_API` detaches one background fetch when its 5-minute cache goes cold.

L1 is automatically clipped to terminal width (respects `$COLUMNS`) so L2 and L3 are always visible.

---

## Features

- **19 widgets, all toggle-able** — `/cc-dash:ccd toggle BUDGET`, `/cc-dash:ccd off RATE_7D`, `/cc-dash:ccd reset`.
- **3-row layout** — usage on row 1, rate limits on row 2, meta + clock on row 3.
- **Self-labeling** — every icon has a short English tag so nothing is cryptic.
- **Context %, now (5h) / week (7d) rate limits, token count, session cost** — all parsed from the statusLine JSON payload Claude Code provides.
- **Threshold colors** — ≥50% amber, ≥80% red. `⏳` flips to `⌛` when quota is hot; 🔥 appears when usage runs ahead of the window's reset pace.
- **Git branch** + in-progress indicator (`*` for merge/rebase).
- **Optional budget widget** — scans today's JSONL logs to track daily spend against `$CC_DASH_BUDGET`.
- **PROJECT and SESSION** as separate toggle-able widgets.

---

## Install

### 1. As a plugin

Claude Code installs plugins via marketplaces, so it's a two-step flow — add the repo as a marketplace first, then install the `cc-dash` plugin from it:

```
/plugin marketplace add ChangSol/claudecode-dashboard
/plugin install cc-dash@claudecode-dashboard
```

The `/cc-dash:ccd` slash command and the `cc-dash-config.sh` / `statusline.sh` scripts ship inside the plugin.

### 2. Wire up the statusLine

```
/cc-dash:ccd-setup
```

Claude Code's plugin manifest has no `statusLine` field, so the first-time wiring is a one-shot helper command that writes the correct `statusLine` entry into `~/.claude/settings.json` for you. Re-run it after every plugin upgrade — the installed path carries the version (`.../cc-dash/1.0.0/...`) and changes on each update. `/cc-dash:ccd refresh` performs the same re-wiring, so either command works.

> **macOS note:** the system `/bin/bash` is frozen at 3.2 and cannot run cc-dash (which uses `printf '%(…)T'` and `local -n`, requiring bash ≥ 4.3). Install a current bash with `brew install bash` *before* running `/cc-dash:ccd-setup` — on macOS the setup script always wires an **absolute** bash path into `settings.json` (PATH bash if it is ≥ 4.3, otherwise `/opt/homebrew/bin/bash` on Apple Silicon or `/usr/local/bin/bash` on Intel), so the statusLine keeps working even when Claude Code is launched from the GUI with a minimal PATH. If no compatible bash is found, the statusLine renders a one-line warning instead of staying blank. The `/cc-dash:ccd` widget toggle needs the brew bash too — on bash 3.2 it refuses with a clear message instead of failing cryptically.

If you'd rather edit by hand, add this block to `~/.claude/settings.json` with the current installed path (see `/plugin` for the exact location):

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash <absolute-path-to>/cc-dash/scripts/statusline.sh"
  }
}
```

On Windows use forward slashes (e.g. `C:/Users/.../plugins/cache/claudecode-dashboard/cc-dash/1.0.0/scripts/statusline.sh`). On macOS replace the leading `bash` with the absolute brew bash path (e.g. `'/opt/homebrew/bin/bash' '<path>/statusline.sh'`) — a plain `bash` resolves to the 3.2 system bash when Claude Code is launched from the GUI.

### 3. Without the plugin (vendored checkout)

```bash
git clone https://github.com/ChangSol/claudecode-dashboard ~/cc-dash
```

Then point `statusLine.command` at `~/cc-dash/scripts/statusline.sh` and — if you want the toggle command — copy `commands/ccd.md` to `~/.claude/commands/` and rewrite the script paths to your checkout.

---

## `/cc-dash:ccd` command

Claude Code plugin slash commands require the `<plugin-name>:` namespace prefix, so every invocation is `/cc-dash:ccd …` (the short `/ccd` form isn't routed). If you want the shorter form, create a user-level alias at `~/.claude/commands/ccd.md` — see [the alias note](#shorter-command-aliases-optional) below.

| Usage | What it does |
|---|---|
| `/cc-dash:ccd list` *(or `ls`, `status`)* | Show every widget with ON/off |
| `/cc-dash:ccd toggle CLOCK GIT` | Toggle one or more widgets |
| `/cc-dash:ccd on BUDGET` | Force on |
| `/cc-dash:ccd off RATE_5H RATE_7D` | Force off |
| `/cc-dash:ccd reset` | Back to defaults |
| `/cc-dash:ccd all-on` / `/cc-dash:ccd all-off` | Bulk |
| `/cc-dash:ccd refresh` | Drop the budget cache + re-wire the statusLine path |
| `/cc-dash:ccd help` | Usage |

Widget keys (case-insensitive):

```
CLOCK  MODEL  DURATION  API_DUR  CTX  TOKEN  COST  LINES  BUDGET
RATE_5H  RATE_7D  RATE_MODEL  RATE_API  PERM  STYLE  VERSION  GIT  PROJECT  SESSION
```

State is persisted at `~/.config/cc-dash/widgets.conf` (override with `CC_DASH_CONFIG`). The file is plain `KEY=0/1` — editable by hand.

### Shorter command aliases (optional)

If typing `/cc-dash:ccd` every time is tedious, create user-level aliases in `~/.claude/commands/`:

`~/.claude/commands/ccd.md`:

```markdown
---
description: alias for /cc-dash:ccd
argument-hint: "[list|toggle|on|off|reset|all-on|all-off|refresh] [KEY ...]"
---

/cc-dash:ccd $ARGUMENTS
```

`~/.claude/commands/ccd-setup.md`:

```markdown
---
description: alias for /cc-dash:ccd-setup
---

/cc-dash:ccd-setup
```

After saving, `/ccd list` and `/ccd-setup` resolve to the plugin commands. User-level commands are personal, not shipped by the plugin, so anyone who wants the short form opts in once.

---

## Widget reference

| Key | Default | What it shows | Example | Row |
|---|---|---|---|---|
| `MODEL`    | on  | Display name of the active model | `🧠 Opus 4.7 (1M context)`      | 1 |
| `DURATION` | on  | Wall-clock time since the session started | `⏱  dur 22m23s`                 | 1 |
| `API_DUR`  | **off** | Cumulative time spent waiting on API calls | `🌐 api 4m32s`              | 1 |
| `CTX`      | on  | Context usage — appends used/total when the payload carries it | `🪟 ctx 25% (50.0K/200.0K)`     | 1 |
| `TOKEN`    | on  | Cumulative input tokens for the session | `💬 token 58.3K`                | 1 |
| `COST`     | on  | Session cost — appends burn rate past 5 minutes | `💸 cost $1.66 (~$4.5/h)`       | 1 |
| `LINES`    | on  | Code lines added/removed during the session | `✏️  +120/-34`                  | 1 |
| `BUDGET`   | **off** | Today's spend against a daily budget — JSONL scan, pay-as-you-go plans | `💰 budget $4.21/$15 (28%)`| 1 |
| `RATE_5H`  | on  | 5-hour limit usage + reset timer (🔥 pace warning) | `⏳ now 19% reset 3h8m`         | 2 |
| `RATE_7D`  | on  | Weekly (7-day) limit usage + reset timer (🔥 pace warning) | `⏳ week 2% reset 6d22h`        | 2 |
| `RATE_MODEL` | on | Per-model weekly limits — hidden when no data is available | `⏳ Fable 26% reset 4d2h`      | 2 |
| `RATE_API` | **off** | Sources `RATE_MODEL` from an API lookup (opt-in, uses your OAuth token) | — | 2 |
| `PERM`     | **off** | Current permission mode (ask·plan·accept·auto·bypass) | `🔒 perm ask`               | 3 |
| `STYLE`    | **off** | Name of the active output style | `🎨 style Explanatory`      | 3 |
| `VERSION`  | on  | Running Claude Code version | `🚀 cc v2.1.116`                | 3 |
| `GIT`      | on  | Current branch — `*` means a merge/rebase is in progress | `🔀 git: main` / `🔀 git: main*`| 3 |
| `PROJECT`  | **off** | Working directory name | `📁 proj: cc-dash`          | 3 |
| `SESSION`  | **off** | First 8 characters of the session ID | `🆔 ab12cd34`               | 3 |
| `CLOCK`    | on  | Current date and time | `🕐 2026.04.21 13:03`           | 3 (rightmost) |

Context %, `now` (5h), `week` (7d), and budget % share the same threshold colors: green → amber (≥50%) → red (≥80%).

Usage extras (no separate toggles — they ride their parent widget):
- `CTX` appends `(used/total)` when the payload carries `context_window_size`.
- `COST` appends an hourly burn-rate estimate (`~$X.X/h`) once the session is 5+ minutes old.
- `RATE_5H` / `RATE_7D` append 🔥 when your usage % is ≥15 points ahead of the window's elapsed time — you are on pace to exhaust the limit before it resets.
- `RATE_MODEL` renders one segment per model-scoped weekly window with the same colors/timer/🔥 treatment as `RATE_7D`, labeled by model (`Fable 26%`). It hides itself when no data is available. **As of Claude Code 2.1.220 the statusLine payload's `rate_limits` carries only `five_hour` and `seven_day`**, so per-model values require the `RATE_API` switch below. If a future payload adds `seven_day_opus`-style fields, those win and no network lookup happens.

---

## Customization

### Budget widget (opt-in)

`/cc-dash:ccd on BUDGET` enables a daily-spend tracker. It walks today's `~/.claude/projects/**/*.jsonl` and sums token usage × model rates. The result is cached for 60 seconds at `~/.cache/cc-dash-budget`. Run `/cc-dash:ccd refresh` to recompute before the cache expires.

> **Note:** The budget widget is designed for pay-per-token plans. If you use a Claude subscription plan, this widget will not reflect actual costs.

Rates are applied **per model**: each JSONL line's `model` field selects the price tier — Opus $5/$25, Fable/Mythos $10/$50, Sonnet $3/$15, Haiku $1/$5 per Mtok (cache write 1.25×, cache read 0.1× of input). Lines without a `model` field fall back to the Opus tier.

| Variable | Default | Meaning |
|---|---|---|
| `CC_DASH_BUDGET`       | `15`    | Daily budget in USD |
| `CC_DASH_RATE_INPUT`   | `5000`  | $/Mtok × 1000, input |
| `CC_DASH_RATE_OUTPUT`  | `25000` | output |
| `CC_DASH_RATE_CACHE_W` | `6250`  | cache_creation |
| `CC_DASH_RATE_CACHE_R` | `500`   | cache_read |
| `CC_DASH_CACHE`        | `~/.cache/cc-dash-budget` | cache file path |
| `CC_DASH_CONFIG`       | `~/.config/cc-dash/widgets.conf` | widget toggle file |

Setting **any** `CC_DASH_RATE_*` variable switches back to legacy single-rate mode: your rates apply to every line regardless of model (useful for discounted/introductory pricing). Unset variables fall back to the defaults in the table above — set all four for fully custom pricing.

### Per-model weekly limits (RATE_API, opt-in)

Turn it on with `/cc-dash:ccd on RATE_API`. Because Claude Code does not put per-model windows in the statusLine payload, this switch reads them straight from Anthropic's `GET /api/oauth/usage` response — the model-scoped entries in `limits[]` (`Fable`, …). The server-supplied `display_name` becomes the label.

> **⚠️ Before you enable it**
> - **It reads your OAuth access token** — from `~/.claude/.credentials.json`, falling back to the macOS keychain entry `Claude Code-credentials`. The token is never printed or written anywhere; it is only used as a request header. If it has expired the lookup is skipped (cc-dash never writes to the credentials file — refreshing is Claude Code's job).
> - **The endpoint is private** — it is not a documented API, just the path Claude Code uses internally. If the schema changes the segment disappears silently; the statusLine keeps working.
> - Default is OFF. While it is off there is no network request and no credential read at all.

The statusLine itself still never touches the network: `cc-dash-usage-fetch.sh` refreshes a cache (`~/.cache/cc-dash-usage`) in the background and the render only reads that file. When the cache goes stale the render **keeps showing the previous values** and detaches one background refresh (no flicker). For an immediate refresh, run `/cc-dash:ccd refresh`.

| Variable | Default | Meaning |
|---|---|---|
| `CC_DASH_USAGE_CACHE` | `~/.cache/cc-dash-usage` | cache file path |
| `CC_DASH_USAGE_TTL`   | `300`  | cache lifetime (seconds) |
| `CC_DASH_USAGE_MIN_INTERVAL` | `60` | minimum gap between background refreshes (seconds) |
| `CC_DASH_USAGE_TIMEOUT` | `6`  | curl timeout (seconds) |
| `CC_DASH_USAGE_URL`   | `https://api.anthropic.com/api/oauth/usage` | lookup endpoint |
| `CC_DASH_CREDENTIALS` | `~/.claude/.credentials.json` | credentials file path |

Turning `RATE_MODEL` off disables the lookup even when `RATE_API` is on (nowhere to render it). This combination is flagged with a `warning:` line whenever you view or change the config, e.g. via `/cc-dash:ccd list`. To diagnose, run `bash scripts/cc-dash-usage-fetch.sh -v` — it prints a one-line reason to stderr.

### Terminal width clipping

L1 is clipped to `$COLUMNS` when set, so L2 and L3 are always visible on narrow terminals. To enable auto-detection, add to `~/.bashrc`:

```bash
export COLUMNS
```

### Legacy env-var toggles

The old opt-in env vars still work and override config-file state:
- `CC_DASH_SHOW_SESSION=1` → `PROJECT` + `SESSION` on
- `CC_DASH_SHOW_BUDGET=1`  → `BUDGET` on

---

## Performance notes

- **Fast path: zero forks.** No `jq`, `awk`, `sed`, `cat`, or `date` on normal renders — only bash built-ins (`printf -v '%(…)T'`, `[[`, `read`).
- **Budget widget**: one `find -newermt` + one `awk` only when cache is cold (~1 s). Cache hits are a single `read` from the cache file (~5 ms).
- **RATE_API widget**: the render is always one cache `read`. When the cache is cold it detaches the fetcher in the background (stdout/stderr closed) and never waits on it — spawns are throttled to one per 60 seconds.
- **Trailing-whitespace trick**: every space is replaced with NBSP (` `) before output, so terminals don't trim and the Claude Code dim attribute doesn't bleed into the line (`\x1b[0m` prefix).

---

## Compatibility

- **Shell**: bash ≥ 4.3 (needs `printf -v '%(…)T'` from 4.2 and `local -n` namerefs from 4.3). macOS `/bin/bash` is 3.2 and is **not** supported — `brew install bash` and let `/cc-dash:ccd-setup` wire the absolute path. Works under Git Bash on Windows.
- **Claude Code**: uses the `statusLine` hook JSON payload (model, cost, rate limits, session fields). Any Claude Code build that emits those fields is supported.
- **Platforms**: Linux, macOS (with brew bash), Windows (Git Bash / WSL).

---

## Limitations

- **Git dirty is a heuristic.** The script checks for `MERGE_HEAD` / `ORIG_HEAD` / `rebase-merge` to decide whether to append `*`. A real `git status` would require a fork.
- **Budget rates are manual.** JSONL logs don't store a `cost_usd` field directly; cc-dash multiplies token counts by per-model rates. Keep the env vars in sync with Anthropic's pricing.
- **statusLine is not plugin-declared.** Claude Code's plugin schema currently exposes no `statusLine` field, so users have to add a two-line entry to their own `settings.json` after installing the plugin.
- **JSONL schema drift.** If Claude Code renames usage fields in the transcript, the `awk` regexes in the budget widget need to be updated.
- **Per-model limits are absent from the statusLine payload.** `rate_limits` carries only `five_hour` and `seven_day`, so `RATE_MODEL` stays empty without the opt-in `RATE_API` lookup (private `/api/oauth/usage`, needs `curl`). If Anthropic changes that schema, the segment disappears silently.

---

## Project layout

```
claudecode-dashboard/         # repo root (= marketplace)
├── .claude-plugin/
│   └── marketplace.json      # marketplace manifest (lists plugins)
├── plugins/
│   └── cc-dash/              # the cc-dash plugin
│       ├── .claude-plugin/
│       │   └── plugin.json   # plugin manifest
│       ├── commands/
│       │   ├── ccd.md            # /cc-dash:ccd slash command — widget toggle
│       │   └── ccd-setup.md      # /cc-dash:ccd-setup — one-shot settings.json wire-up
│       └── scripts/
│           ├── statusline.sh     # the statusLine renderer
│           ├── cc-dash-config.sh # widget toggle CLI + interactive menu
│           ├── cc-dash-setup.sh  # settings.json patcher (called by /cc-dash:ccd-setup)
│           └── cc-dash-usage-fetch.sh # per-model limit lookup → cache (RATE_API only)
├── LICENSE
├── README.md                 # Korean (default)
└── README.en.md              # this file
```

---

## Manual testing

```bash
# Render with a synthetic payload
echo '{"model":{"display_name":"Opus 4.7 (1M context)","id":"claude-opus-4-7"},"output_style":{"name":"default"},"context_window_size":200000,"used_percentage":25,"total_input_tokens":50000,"total_duration_ms":120000,"total_api_duration_ms":95000,"total_cost_usd":0.5,"total_lines_added":120,"total_lines_removed":34,"session_id":"abc12345","current_dir":".","permission_mode":"default","version":"2.1.116","rate_limits":{"five_hour":{"used_percentage":7,"resets_at":1745289600},"seven_day":{"used_percentage":26,"resets_at":1745808000}}}' \
  | bash scripts/statusline.sh

# Time it
time (echo '{…}' | bash scripts/statusline.sh)

# Everything on
CC_DASH_SHOW_SESSION=1 CC_DASH_SHOW_BUDGET=1 bash scripts/statusline.sh <<< '{…}'

# refresh — exercise it without touching your real settings.json / cache
CC_DASH_SETTINGS=/tmp/x.json CC_DASH_CACHE=/tmp/x-cache bash scripts/cc-dash-config.sh refresh

# RATE_API — run the per-model lookup on its own (diagnostics on stderr, token never printed)
CC_DASH_USAGE_CACHE=/tmp/x-usage bash scripts/cc-dash-usage-fetch.sh -v && cat /tmp/x-usage
```

Expected output for the default render (no `widgets.conf` yet — clock and git widgets reflect your environment; the `resets_at` timestamps above are in the past, so no `reset` timers appear):

```
🧠 Opus 4.7 (1M context) │ ⏱  dur 2m0s │ 🪟 ctx 25% (50.0K/200.0K) │ 💬 token 50.0K │ 💸 cost $0.50 │ ✏️  +120/-34
⏳ now 7% │ ⏳ week 26%
🚀 cc v2.1.116 │ 🔀 git — │ 🕐 2026.04.21 14:53
```

`API_DUR` (`🌐 api 1m35s`) and `STYLE` (`🎨 style default`) are off by default — `/cc-dash:ccd on API_DUR STYLE` to see them.

Typical wall-clock on Git Bash for Windows is **100–140 ms** (dominated by bash startup and JSON parse; the budget widget is off by default so no JSONL scan). Native bash 5.2 on Linux/macOS is typically faster.

---

## License

MIT.
