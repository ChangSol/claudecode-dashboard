# cc-dash

**A fork-free, zero-dependency statusLine for Claude Code.**
13 widgets — model, duration, context, tokens, cost, rate limits, version, git, project, session, clock — rendered in three rows. Toggle any widget with `/ccd`.

```
🧠 Opus 4.7 (1M context) │ ⏱  dur 22m0s │ 🪟 ctx 25% │ 💬 token 50.0K │ 💸 cost $0.50
⏳ 5h 0% reset 3h0m │ ⏳ 7d 2% reset 6d22h
🚀 cc v2.1.116 │ 🔀 git: main │ 🕐 2026.04.21 13:03
```

---

## Why

Most statusLine scripts fork `jq`, `awk`, `date`, `git` every second and leave your shell wheezing. cc-dash is **pure bash 5.2 built-ins on the fast path** — no forks, no `cat`, no `sed`. The one exception is the opt-in budget widget, which uses a single `awk` call with a 60-second cache.

L1 is automatically clipped to terminal width (respects `$COLUMNS`) so L2 and L3 are always visible.

---

## Features

- **13 widgets, all toggle-able** — `/ccd toggle BUDGET`, `/ccd off RATE_7D`, `/ccd reset`.
- **3-row layout** — usage on row 1, rate limits on row 2, meta + clock on row 3.
- **Self-labeling** — every icon has a short English tag so nothing is cryptic.
- **Context %, 5h / 7d rate limits, token count, session cost** — all parsed from the statusLine JSON payload Claude Code provides.
- **Threshold colors** — ≥50% amber, ≥80% red. `⏳` flips to `⌛` when quota is hot.
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

The `/ccd` slash command and the `cc-dash-config.sh` / `statusline.sh` scripts ship inside the plugin.

### 2. Wire up the statusLine (manual step)

Claude Code plugins cannot register a `statusLine` entry automatically. After installing the plugin, add this to your `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash <absolute-path-to>/cc-dash/scripts/statusline.sh"
  }
}
```

Replace `<absolute-path-to>` with the plugin's checkout path (on Windows use forward slashes, e.g. `C:/Users/.../plugins/cc-dash/scripts/statusline.sh`).

### 3. Without the plugin (vendored checkout)

```bash
git clone https://github.com/ChangSol/claudecode-dashboard ~/cc-dash
```

Then point `statusLine.command` at `~/cc-dash/scripts/statusline.sh` and — if you want the toggle command — copy `commands/ccd.md` to `~/.claude/commands/` and rewrite the script paths to your checkout.

---

## `/ccd` command

| Usage | What it does |
|---|---|
| `/ccd list` *(or `ls`, `status`)* | Show every widget with ON/off |
| `/ccd toggle CLOCK GIT` | Toggle one or more widgets |
| `/ccd on BUDGET` | Force on |
| `/ccd off RATE_5H RATE_7D` | Force off |
| `/ccd reset` | Back to defaults |
| `/ccd all-on` / `/ccd all-off` | Bulk |
| `/ccd help` | Usage |

Widget keys (case-insensitive):

```
CLOCK  MODEL  DURATION  CTX  TOKEN  COST  BUDGET
RATE_5H  RATE_7D  PERM  VERSION  GIT  PROJECT  SESSION
```

State is persisted at `~/.config/cc-dash/widgets.conf` (override with `CC_DASH_CONFIG`). The file is plain `KEY=0/1` — editable by hand.

---

## Widget reference

| Key | Default | Example | Row |
|---|---|---|---|
| `MODEL`    | on  | `🧠 Opus 4.7 (1M context)`      | 1 |
| `DURATION` | on  | `⏱  dur 22m23s`                 | 1 |
| `CTX`      | on  | `🪟 ctx 25%`                    | 1 |
| `TOKEN`    | on  | `💬 token 58.3K`                | 1 |
| `COST`     | on  | `💸 cost $1.66`                 | 1 |
| `BUDGET`   | **off** | `💰 budget $4.21/$15 (28%)`| 1 |
| `RATE_5H`  | on  | `⏳ 5h 19% reset 3h8m`          | 2 |
| `RATE_7D`  | on  | `⏳ 7d 2% reset 6d22h`          | 2 |
| `PERM`     | **off** | `🔒 perm ask`               | 3 |
| `VERSION`  | on  | `🚀 cc v2.1.116`                | 3 |
| `GIT`      | on  | `🔀 git: main` / `🔀 git: main*`| 3 |
| `PROJECT`  | **off** | `📁 proj: cc-dash`          | 3 |
| `SESSION`  | **off** | `🆔 ab12cd34`               | 3 |
| `CLOCK`    | on  | `🕐 2026.04.21 13:03`           | 3 (rightmost) |

Context %, `5h`, `7d`, and budget % share the same threshold colors: green → amber (≥50%) → red (≥80%).

---

## Customization

### Budget widget (opt-in)

`/ccd on BUDGET` enables a daily-spend tracker. It walks today's `~/.claude/projects/**/*.jsonl` and sums token usage × model rates. The result is cached for 60 seconds at `~/.cache/cc-dash-budget`.

> **Note:** The budget widget is designed for pay-per-token plans. If you use a Claude subscription plan, this widget will not reflect actual costs.

| Variable | Default | Meaning |
|---|---|---|
| `CC_DASH_BUDGET`       | `15`    | Daily budget in USD |
| `CC_DASH_RATE_INPUT`   | `15000` | $/Mtok × 1000, input |
| `CC_DASH_RATE_OUTPUT`  | `75000` | output |
| `CC_DASH_RATE_CACHE_W` | `18750` | cache_creation |
| `CC_DASH_RATE_CACHE_R` | `1500`  | cache_read |
| `CC_DASH_CACHE`        | `~/.cache/cc-dash-budget` | cache file path |
| `CC_DASH_CONFIG`       | `~/.config/cc-dash/widgets.conf` | widget toggle file |

Defaults are tuned for Opus 4.x. For Sonnet, set:
```
CC_DASH_RATE_INPUT=3000 CC_DASH_RATE_OUTPUT=15000 \
CC_DASH_RATE_CACHE_W=3750 CC_DASH_RATE_CACHE_R=300
```

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
- **Trailing-whitespace trick**: every space is replaced with NBSP (` `) before output, so terminals don't trim and the Claude Code dim attribute doesn't bleed into the line (`\x1b[0m` prefix).

---

## Compatibility

- **Shell**: bash ≥ 5.2 (needs `printf -v '%(%s)T'` and `${var//…/…}` semantics). Works under Git Bash on Windows.
- **Claude Code**: uses the `statusLine` hook JSON payload (model, cost, rate limits, session fields). Any Claude Code build that emits those fields is supported.
- **Platforms**: Linux, macOS, Windows (Git Bash / WSL).

---

## Limitations

- **Git dirty is a heuristic.** The script checks for `MERGE_HEAD` / `ORIG_HEAD` / `rebase-merge` to decide whether to append `*`. A real `git status` would require a fork.
- **Budget rates are manual.** JSONL logs don't store a `cost_usd` field directly; cc-dash multiplies token counts by per-model rates. Keep the env vars in sync with Anthropic's pricing.
- **statusLine is not plugin-declared.** Claude Code's plugin schema currently exposes no `statusLine` field, so users have to add a two-line entry to their own `settings.json` after installing the plugin.
- **JSONL schema drift.** If Claude Code renames usage fields in the transcript, the `awk` regexes in the budget widget need to be updated.

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
│       │   └── ccd.md        # /ccd slash command (uses ${CLAUDE_PLUGIN_ROOT})
│       └── scripts/
│           ├── statusline.sh     # the statusLine renderer
│           └── cc-dash-config.sh # widget toggle CLI + interactive menu
├── LICENSE
└── README.md
```

---

## Manual testing

```bash
# Render with a synthetic payload
echo '{"model":{"display_name":"Opus 4.7 (1M context)","id":"claude-opus-4-7"},"context_window_size":200000,"used_percentage":25,"total_input_tokens":50000,"total_duration_ms":120000,"total_cost_usd":0.5,"session_id":"abc12345","current_dir":".","permission_mode":"default","version":"2.1.116","rate_limits":{"five_hour":{"used_percentage":7,"resets_at":1745289600},"seven_day":{"used_percentage":26,"resets_at":1745808000}}}' \
  | bash scripts/statusline.sh

# Time it
time (echo '{…}' | bash scripts/statusline.sh)

# Everything on
CC_DASH_SHOW_SESSION=1 CC_DASH_SHOW_BUDGET=1 bash scripts/statusline.sh <<< '{…}'
```

Expected output for the default render (no `widgets.conf` yet — clock and git widgets reflect your environment):

```
🧠 Opus 4.7 (1M context) │ ⏱  dur 2m0s │ 🪟 ctx 25% │ 💬 token 50.0K │ 💸 cost $0.50
⏳ 5h 7% │ ⏳ 7d 26%
🚀 cc v2.1.116 │ 🔀 git — │ 🕐 2026.04.21 14:53
```

Typical wall-clock on Git Bash for Windows is **100–140 ms** (dominated by bash startup and JSON parse; the budget widget is off by default so no JSONL scan). Native bash 5.2 on Linux/macOS is typically faster.

---

## License

MIT.
