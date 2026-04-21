#!/bin/bash
# Claude Code statusLine — fork-free bash (ccstatusline-inspired)
# 원본 7개 위젯(model/duration/ctx/token/cost/5h/7d) + 확장 4개(git/project/ctx-bar/budget)
# 트릭: NBSP 공백(trim 방지), \x1b[0m 접두(Claude dim 무효화), JSON은 bash 정규식으로 파싱(jq fork 없음)

# ---------- 0. 위젯 on/off 설정 로드 (fork-free) ----------
# cc-dash-config.sh 로 편집. 환경변수 CC_DASH_SHOW_SESSION/BUDGET 은 역호환성 유지.
CFG_CLOCK=1 CFG_MODEL=1 CFG_DURATION=1 CFG_CTX=1 CFG_TOKEN=1 CFG_COST=1
CFG_BUDGET=1 CFG_RATE_5H=1 CFG_RATE_7D=1
CFG_PERM=1 CFG_VERSION=1 CFG_GIT=1 CFG_PROJECT=0 CFG_SESSION=1
_CC_DASH_CFG="${CC_DASH_CONFIG:-$HOME/.config/cc-dash/widgets.conf}"
if [[ -f "$_CC_DASH_CFG" ]]; then
  while IFS='=' read -r _k _v; do
    [[ "$_k" =~ ^[A-Z_0-9]+$ ]] || continue
    [[ "$_v" == "0" || "$_v" == "1" ]] || continue
    printf -v "CFG_$_k" '%s' "$_v"
  done < "$_CC_DASH_CFG"
fi
[[ "$CC_DASH_SHOW_SESSION" == "1" ]] && CFG_PROJECT=1 && CFG_SESSION=1
[[ "$CC_DASH_SHOW_BUDGET"  == "1" ]] && CFG_BUDGET=1

# ---------- 1. stdin → 변수 ----------
input=""
while IFS= read -r _line; do input+="$_line"; done

# 한 줄 JSON 대응: 구분자 치환으로 라인 단위 파싱화
input="${input//,/$'\n'}"
input="${input//\{/$'\n'}"
input="${input//\}/$'\n'}"

# ---------- 2. 필드 파싱 ----------
MODEL="—" MODEL_ID="" CTX_SIZE=0 DURATION_MS=0 CTX_PCT=0 TOKENS=0 COST=""
RATE_5H=0 RATE_5H_RESET=0 RATE_7D=0 RATE_7D_RESET=0
CWD="" SESSION_ID="" PERM_MODE="" CC_VERSION=""

in_block="" block_filled=0
while IFS= read -r line; do
  [[ "$line" =~ \"([a-zA-Z_]+)\"[[:space:]]*:[[:space:]]*(.*) ]] || continue
  key="${BASH_REMATCH[1]}"
  val="${BASH_REMATCH[2]}"
  val="${val//\"/}"

  case "$key" in
    five_hour)  in_block="5h"; block_filled=0;;
    seven_day)  in_block="7d"; block_filled=0;;
    display_name) MODEL="$val";;
    id)           MODEL_ID="$val";;
    current_dir)  CWD="$val";;
    session_id|sessionId)   SESSION_ID="$val";;
    permission_mode|permissionMode) PERM_MODE="$val";;
    version)      CC_VERSION="$val";;
    context_window_size) val="${val// /}"; CTX_SIZE="$val";;
    total_duration_ms)   val="${val// /}"; DURATION_MS="$val";;
    total_input_tokens)  val="${val// /}"; TOKENS="$val";;
    total_cost_usd)      val="${val// /}"; COST="$val";;
    reset_timestamp|resets_at)
      val="${val// /}"; val="${val%.*}"
      case "$in_block" in
        5h) RATE_5H_RESET="$val"; block_filled=$((block_filled+1));;
        7d) RATE_7D_RESET="$val"; block_filled=$((block_filled+1));;
      esac
      [ "$block_filled" -ge 2 ] && { in_block=""; block_filled=0; };;
    used_percentage)
      val="${val// /}"; val="${val%.*}"
      case "$in_block" in
        5h) RATE_5H="$val"; block_filled=$((block_filled+1));;
        7d) RATE_7D="$val"; block_filled=$((block_filled+1));;
        *)  CTX_PCT="$val";;
      esac
      [ "$block_filled" -ge 2 ] && { in_block=""; block_filled=0; };;
  esac
done <<< "$input"

# ---------- 3. 기본값 보정 ----------
[[ -z "$MODEL" || "$MODEL" == "null" ]] && MODEL="—"
[[ -z "$DURATION_MS" || "$DURATION_MS" == "null" ]] && DURATION_MS=0
[[ -z "$CTX_PCT" || "$CTX_PCT" == "null" ]] && CTX_PCT=0
[[ -z "$TOKENS" || "$TOKENS" == "null" ]] && TOKENS=0
[[ -z "$RATE_5H" || "$RATE_5H" == "null" ]] && RATE_5H=0
[[ -z "$RATE_7D" || "$RATE_7D" == "null" ]] && RATE_7D=0

# ---------- 4. 포매터 (순수 bash) ----------
# Duration
DURATION_S=$((DURATION_MS / 1000))
MINS=$((DURATION_S / 60)); SECS=$((DURATION_S % 60))
if [ "$MINS" -gt 0 ]; then TIME="${MINS}m${SECS}s"; else TIME="${SECS}s"; fi

# Tokens → K/M
if [ "$TOKENS" -gt 999999 ]; then
  TOKEN_FMT="$((TOKENS/1000000)).$((TOKENS%1000000/100000))M"
elif [ "$TOKENS" -gt 999 ]; then
  TOKEN_FMT="$((TOKENS/1000)).$((TOKENS%1000/100))K"
else
  TOKEN_FMT="${TOKENS}"
fi

# Cost → $X.XX
if [[ -n "$COST" && "$COST" != "null" && "$COST" != "0" ]]; then
  COST_INT="${COST%%.*}"
  COST_DEC="${COST#*.}"
  COST_DEC="${COST_DEC:0:2}"
  [[ ${#COST_DEC} -eq 1 ]] && COST_DEC+="0"
  [[ ${#COST_DEC} -eq 0 ]] && COST_DEC="00"
  COST_DISPLAY="\$${COST_INT}.${COST_DEC}"
else
  COST_DISPLAY="\$0"
fi

# 현재 epoch (date fork 없이 bash 내장)
printf -v NOW_EPOCH '%(%s)T' -1 2>/dev/null

# 리셋 타이머
fmt_remain() {
  local reset="$1" remain=0
  [ "$reset" -gt 0 ] 2>/dev/null && [ -n "$NOW_EPOCH" ] || { REMAIN_FMT=""; return; }
  remain=$((reset - NOW_EPOCH))
  if [ "$remain" -le 0 ]; then REMAIN_FMT=""; return; fi
  if [ "$remain" -ge 86400 ]; then
    REMAIN_FMT="$((remain/86400))d$(( (remain%86400)/3600 ))h"
  else
    REMAIN_FMT="$((remain/3600))h$(( (remain%3600)/60 ))m"
  fi
}
fmt_remain "$RATE_5H_RESET"; TIMER_5H="$REMAIN_FMT"
fmt_remain "$RATE_7D_RESET"; TIMER_7D="$REMAIN_FMT"
[ -n "$TIMER_5H" ] && TIMER_5H=" reset ${TIMER_5H}"
[ -n "$TIMER_7D" ] && TIMER_7D=" reset ${TIMER_7D}"

# ---------- 5. ANSI 컬러 ----------
RST=$'\033[0m'
color_for() {
  local pct="$1"
  if   [ "$pct" -ge 80 ]; then COLOR=$'\033[31m'
  elif [ "$pct" -ge 50 ]; then COLOR=$'\033[33m'
  else COLOR=$'\033[32m'; fi
}
color_for "$CTX_PCT";  CTX_COLOR="$COLOR"
color_for "$RATE_5H";  RATE_5H_COLOR="$COLOR"
color_for "$RATE_7D";  RATE_7D_COLOR="$COLOR"

if [ "$RATE_5H" -ge 80 ]; then RATE_5H_ICON="⌛"; else RATE_5H_ICON="⏳"; fi
if [ "$RATE_7D" -ge 80 ]; then RATE_7D_ICON="⌛"; else RATE_7D_ICON="⏳"; fi

# ========================================================================
# 확장 위젯 #1 — Git 브랜치 + dirty heuristic
# ========================================================================
GIT_DISPLAY="🔀 git —"   # 기본값: 비-git 디렉터리임을 명시
if [[ -n "$CWD" && -f "$CWD/.git/HEAD" ]]; then
  _branch=""
  while IFS= read -r _head_line; do _branch="$_head_line"; break; done < "$CWD/.git/HEAD"
  if [[ "$_branch" == ref:* ]]; then
    _branch="${_branch##*/}"
  else
    _branch="${_branch:0:7}"  # detached HEAD → short SHA
  fi
  _dirty=""
  # fork-free heuristic: MERGE/REBASE/ORIG_HEAD 존재 시 진행 중 작업 표시
  if [[ -f "$CWD/.git/MERGE_HEAD" || -f "$CWD/.git/ORIG_HEAD" || -d "$CWD/.git/rebase-merge" ]]; then
    _dirty="*"
  fi
  [[ -n "$_branch" ]] && GIT_DISPLAY="🔀 git: ${_branch}${_dirty}"
fi

# ========================================================================
# 확장 위젯 #2 — 프로젝트 (CFG_PROJECT=1 일 때만)
# ========================================================================
PROJECT_DISPLAY=""
if [[ "$CFG_PROJECT" == "1" ]]; then
  _proj=""
  if [[ -n "$CWD" ]]; then
    _proj="${CWD//\\//}"
    _proj="${_proj%/}"
    _proj="${_proj##*/}"
  fi
  [[ -n "$_proj" ]] && PROJECT_DISPLAY="📁 proj: ${_proj}" || PROJECT_DISPLAY="📁 proj —"
fi

# ========================================================================
# 확장 위젯 #2b — 세션 (CFG_SESSION=1 일 때만)
# ========================================================================
SESSION_DISPLAY=""
if [[ "$CFG_SESSION" == "1" ]]; then
  _sess="${SESSION_ID:0:8}"
  [[ -n "$_sess" ]] && SESSION_DISPLAY="🆔 ${_sess}" || SESSION_DISPLAY="🆔 —"
fi

# ========================================================================
# 확장 위젯 #5 — 현재 시각 (0 fork, bash 내장)
# ========================================================================
printf -v CLOCK_DISPLAY '🕐 %(%Y.%m.%d %H:%M)T' -1

# ========================================================================
# 확장 위젯 #6 — 권한 모드 (stdin permission_mode)
# ========================================================================
case "$PERM_MODE" in
  plan)              PERM_DISPLAY="📋 perm plan";;
  auto|autoAccept)   PERM_DISPLAY="🔓 perm auto";;
  acceptEdits)       PERM_DISPLAY="⚡ perm accept";;
  bypassPermissions) PERM_DISPLAY="🏃 perm bypass";;
  default|ask)       PERM_DISPLAY="🔒 perm ask";;
  "")                PERM_DISPLAY="🔒 perm —";;
  *)                 PERM_DISPLAY="🔒 perm ${PERM_MODE}";;
esac

# ========================================================================
# 확장 위젯 #7 — Claude Code 버전
# ========================================================================
if [[ -n "$CC_VERSION" ]]; then VERSION_DISPLAY="🚀 cc v${CC_VERSION}"; else VERSION_DISPLAY="🚀 cc —"; fi

# ========================================================================
# 확장 위젯 #4 — 일일 누적 비용 (CFG_BUDGET=1 일 때만 활성)
# JSONL 파일이 매우 큰 경우가 있어 기본 OFF. 활성 시 60초 TTL 캐시 사용.
# 캐시 미스 시에만 grep(단일 fork)로 오늘 라인만 추려서 bash 루프 진입.
# ========================================================================
BUDGET_DISPLAY=""
if [[ "$CFG_BUDGET" == "1" ]]; then
  # 단가 (환경변수 오버라이드 가능). 단위: 나노달러/토큰 (× 10^-9 USD)
  # Opus 4.x 기본값 — $15 / $75 / $18.75 / $1.50 per Mtok
  RATE_INPUT="${CC_DASH_RATE_INPUT:-15000}"
  RATE_OUTPUT="${CC_DASH_RATE_OUTPUT:-75000}"
  RATE_CACHE_W="${CC_DASH_RATE_CACHE_W:-18750}"
  RATE_CACHE_R="${CC_DASH_RATE_CACHE_R:-1500}"
  BUDGET_LIMIT="${CC_DASH_BUDGET:-15}"
  CACHE_FILE="${CC_DASH_CACHE:-$HOME/.cache/cc-dash-budget}"
  CACHE_TTL=60
  TODAY_COST=""

  if [[ -f "$CACHE_FILE" ]]; then
    while IFS='|' read -r _epoch _cost; do
      if [[ -n "$NOW_EPOCH" && -n "$_epoch" ]] && (( NOW_EPOCH - _epoch < CACHE_TTL )); then
        TODAY_COST="$_cost"
      fi
      break
    done < "$CACHE_FILE"
  fi

  if [[ -z "$TODAY_COST" ]]; then
    printf -v TODAY_PREFIX '%(%Y-%m-%d)T' -1
    # 오늘 수정된 JSONL만 find 로 선별 → awk 단일 호출로 필터·추출·합산
    # bash 정규식 루프는 거대 JSONL 라인(메가바이트급)에서 매우 느리므로 회피
    _cents=$(find "$HOME/.claude/projects" -name '*.jsonl' -newermt "$TODAY_PREFIX" -print0 2>/dev/null \
      | xargs -0 awk -v today="$TODAY_PREFIX" \
          -v ri="$RATE_INPUT" -v ro="$RATE_OUTPUT" -v rcw="$RATE_CACHE_W" -v rcr="$RATE_CACHE_R" '
        index($0, "\"timestamp\":\"" today) == 0 { next }
        index($0, "\"usage\"") == 0 { next }
        {
          s = 0
          if (match($0, /"input_tokens":[0-9]+/))                s += substr($0, RSTART+16, RLENGTH-16) * ri
          if (match($0, /"output_tokens":[0-9]+/))               s += substr($0, RSTART+17, RLENGTH-17) * ro
          if (match($0, /"cache_creation_input_tokens":[0-9]+/)) s += substr($0, RSTART+31, RLENGTH-31) * rcw
          if (match($0, /"cache_read_input_tokens":[0-9]+/))     s += substr($0, RSTART+27, RLENGTH-27) * rcr
          total += s
        }
        END { printf("%.0f", total / 10000000) }
      ' 2>/dev/null)
    [[ -z "$_cents" ]] && _cents=0
    _dollars=$((_cents / 100))
    _frac=$((_cents % 100))
    printf -v TODAY_COST '%d.%02d' "$_dollars" "$_frac"
    mkdir -p "${CACHE_FILE%/*}" 2>/dev/null
    printf '%s|%s\n' "$NOW_EPOCH" "$TODAY_COST" > "$CACHE_FILE" 2>/dev/null
  fi

  if [[ -n "$TODAY_COST" && "$BUDGET_LIMIT" -gt 0 ]]; then
    _tint="${TODAY_COST%%.*}"
    _pct=$((_tint * 100 / BUDGET_LIMIT))
    color_for "$_pct"; _bcol="$COLOR"
    BUDGET_DISPLAY="💰 budget \$${TODAY_COST}/\$${BUDGET_LIMIT} ${_bcol}(${_pct}%)${RST}"
  fi
fi

# ---------- 6. 출력 조립 ----------
# 3행으로 분배.
#   L1 사용량:  model · duration · ctx · token · cost · budget
#   L2 메타:    perm(opt) · version · git · project · clock (맨 오른쪽)
#   L3 리밋:    5h · 7d
# 위젯 CFG_* 가 0 이면 세그먼트가 빠지고 구분자(│)도 남지 않는다.
L1="" L2="" L3=""
append() {
  local -n _ref="$1"; local seg="$2"
  [[ -n "$seg" ]] || return
  [[ -n "$_ref" ]] && _ref+=" │ $seg" || _ref="$seg"
}
[[ "$CFG_MODEL"    == "1" ]] && append L1 "🧠 ${MODEL}"
[[ "$CFG_DURATION" == "1" ]] && append L1 "⏱  dur ${TIME}"
[[ "$CFG_CTX"      == "1" ]] && append L1 "🪟 ctx ${CTX_COLOR}${CTX_PCT}%${RST}"
[[ "$CFG_TOKEN"    == "1" ]] && append L1 "💬 token ${TOKEN_FMT}"
[[ "$CFG_COST"     == "1" ]] && append L1 "💸 cost ${COST_DISPLAY}"
[[ -n "$BUDGET_DISPLAY"    ]] && append L1 "${BUDGET_DISPLAY}"

[[ "$CFG_RATE_5H"  == "1" ]] && append L2 "${RATE_5H_ICON} 5h ${RATE_5H_COLOR}${RATE_5H}%${RST}${TIMER_5H}"
[[ "$CFG_RATE_7D"  == "1" ]] && append L2 "${RATE_7D_ICON} 7d ${RATE_7D_COLOR}${RATE_7D}%${RST}${TIMER_7D}"

[[ "$CFG_PERM"    == "1" ]] && append L3 "$PERM_DISPLAY"
[[ "$CFG_VERSION" == "1" ]] && append L3 "$VERSION_DISPLAY"
[[ "$CFG_GIT"     == "1" ]] && append L3 "$GIT_DISPLAY"
[[ "$CFG_PROJECT" == "1" ]] && append L3 "$PROJECT_DISPLAY"
[[ "$CFG_SESSION" == "1" ]] && append L3 "$SESSION_DISPLAY"
[[ "$CFG_CLOCK"   == "1" ]] && append L3 "${CLOCK_DISPLAY}"

# ---------- 6.5 L1 너비 제한 — L2 항상 표시 ----------
# ANSI 이스케이프(비시각) 건너뛰고, 비-ASCII(이모지 등)는 2컬럼으로 계산.
_cols="${COLUMNS:-9999}"
_clip_line() {
  local s="$1" limit="$2" vcol=0 out="" c esc
  while [[ -n "$s" ]]; do
    c="${s:0:1}"
    if [[ "$c" == $'\033' && "${s:1:1}" == '[' ]]; then
      esc="${s%%m*}m"; out+="$esc"; s="${s:${#esc}}"; continue
    fi
    if [[ "$c" > $'\x7f' ]]; then
      (( vcol + 2 > limit )) && { out+="${RST}…"; break; }
      out+="$c"; s="${s:1}"; (( vcol += 2 ))
    else
      (( vcol + 1 > limit )) && { out+="${RST}…"; break; }
      out+="$c"; s="${s:1}"; (( vcol++ ))
    fi
  done
  printf '%s' "$out"
}
(( ${#L1} + 5 > _cols )) && L1=$(_clip_line "$L1" "$(( _cols - 1 ))")

emit() {
  [[ -n "$1" ]] || return
  local s="${1// /$'\xc2\xa0'}"
  printf '\x1b[0m%s\n' "$s"
}
emit "$L1"
emit "$L2"
emit "$L3"
