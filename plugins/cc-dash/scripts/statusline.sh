#!/bin/bash
# Claude Code statusLine — fork-free bash (ccstatusline-inspired)
# 20개 위젯 — 사용량(L1)/리밋(L2)/메타(L3) 3행. 위젯 토글은 cc-dash-config.sh (기본값은 0절 CFG_*)
# 트릭: NBSP 공백(trim 방지), \x1b[0m 접두(Claude dim 무효화), JSON은 bash 정규식으로 파싱(jq fork 없음)

# Self-guard: needs bash 4.3+ (printf '%(...)T' is 4.2, `local -n` nameref is 4.3).
# macOS /bin/bash is frozen at 3.2; without this check the script would emit
# `invalid format character` / `local: -n: invalid option` and produce an empty
# statusLine. Render a single visible warning line instead so the cause is obvious.
if (( BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 3) )); then
  printf '\x1b[0m\xe2\x9a\xa0\xef\xb8\x8f  cc-dash: bash %s too old (need 4.3+) \xe2\x80\x94 macOS: brew install bash, then /cc-dash:ccd-setup\n' "$BASH_VERSION" >&2
  printf '\x1b[0m\xe2\x9a\xa0\xef\xb8\x8f  cc-dash: bash %s too old (need 4.3+) \xe2\x80\x94 macOS: brew install bash, then /cc-dash:ccd-setup\n' "$BASH_VERSION"
  exit 0
fi

# ---------- 0. 위젯 on/off 설정 로드 (fork-free) ----------
# cc-dash-config.sh 로 편집. 환경변수 CC_DASH_SHOW_SESSION/BUDGET 은 역호환성 유지.
CFG_CLOCK=1 CFG_MODEL=1 CFG_EFFORT=1 CFG_DURATION=1 CFG_CTX=1 CFG_TOKEN=1 CFG_COST=1
CFG_BUDGET=0 CFG_RATE_5H=1 CFG_RATE_7D=1
CFG_PERM=0 CFG_VERSION=1 CFG_GIT=1 CFG_PROJECT=0 CFG_SESSION=0
CFG_LINES=1 CFG_API_DUR=0 CFG_STYLE=0 CFG_RATE_MODEL=1 CFG_RATE_API=0
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
# `|| [[ -n ... ]]`: 개행 없이 끝나는 마지막 라인도 수거 — 없으면 페이로드가
# 단일 라인 + 무개행일 때 input이 통째로 비어 전 위젯이 기본값으로 무력화된다.
input=""
while IFS= read -r _line || [[ -n "$_line" ]]; do input+="$_line"; done

# 한 줄 JSON 대응: 구분자 치환으로 라인 단위 파싱화
input="${input//,/$'\n'}"
input="${input//\{/$'\n'}"
input="${input//\}/$'\n'}"

# ---------- 2. 필드 파싱 ----------
MODEL="—" MODEL_ID="" CTX_SIZE=0 DURATION_MS=0 CTX_PCT=0 TOKENS=0 COST=""
RATE_5H=0 RATE_5H_RESET=0 RATE_7D=0 RATE_7D_RESET=0
CWD="" SESSION_ID="" PERM_MODE="" CC_VERSION=""
LINES_ADD=0 LINES_DEL=0 API_DUR_MS=0 STYLE_NAME=""
# EFFORT_LEVEL: effort.level (low/medium/high/xhigh/max) — 없으면 EFFORT 세그먼트 자동 숨김
# SPEND_*: gateway 환경의 rate_limits.spend_limit — 표시 위젯은 범위 밖, CTX_PCT 오염 방지용 소비
EFFORT_LEVEL="" SPEND_PCT=0 SPEND_RESET=0
# 모델별/용도별 주간 윈도 (seven_day_opus·seven_day_sonnet 등 — 제네릭 수집)
RATE_MD_KEYS=() RATE_MD_PCTS=() RATE_MD_RESETS=()

in_block="" block_filled=0
while IFS= read -r line; do
  [[ "$line" =~ \"([a-zA-Z_]+)\"[[:space:]]*:[[:space:]]*(.*) ]] || continue
  key="${BASH_REMATCH[1]}"
  val="${BASH_REMATCH[2]}"
  val="${val//\"/}"

  case "$key" in
    context_window|rate_limits) in_block=""; block_filled=0;; # top-level 컨테이너 진입 시 상태 리셋 — 필드 하나뿐인 spend 블록이 열린 채 남아도 다음 used_percentage 를 오소비하지 않게
    five_hour)  in_block="5h"; block_filled=0;;
    seven_day)  in_block="7d"; block_filled=0;;
    spend_limit) in_block="spend"; block_filled=0;; # 값은 SPEND_* 에 소비만 — 아래 used_percentage 의 *) CTX_PCT 분기로 새지 않게
    seven_day_*) # 모델별 주간 윈도 객체(seven_day_opus 등). 불리언(seven_day_overage_included)은 val 이 차 있어 제외
      if [[ -z "$val" ]]; then
        in_block="md"; block_filled=0
        RATE_MD_KEYS+=("${key#seven_day_}"); RATE_MD_PCTS+=(0); RATE_MD_RESETS+=(0)
      fi;;
    output_style) # 객체형({"name":...})이면 다음 name 키 대기, 문자열형이면 즉시 값
      if [[ -n "$val" ]]; then STYLE_NAME="$val"; else in_block="style"; fi;;
    name)         [[ "$in_block" == "style" ]] && { STYLE_NAME="$val"; in_block=""; };;
    effort) # 객체형({"level":...}) — 값이 비어 있을 때만 블록 진입, 다음 level 키 대기
      [[ -z "$val" ]] && in_block="effort";;
    level)        [[ "$in_block" == "effort" ]] && { EFFORT_LEVEL="$val"; in_block=""; };;
    display_name) MODEL="$val";;
    id)           MODEL_ID="$val";;
    current_dir)  CWD="$val";;
    session_id|sessionId)   [[ -z "$SESSION_ID" ]] && SESSION_ID="$val";; # first-wins — remote.session_id 가 top-level 을 덮지 않도록
    permission_mode|permissionMode) PERM_MODE="$val";;
    version)      CC_VERSION="$val";;
    context_window_size) val="${val// /}"; CTX_SIZE="$val";;
    total_duration_ms)   val="${val// /}"; DURATION_MS="$val";;
    total_api_duration_ms) val="${val// /}"; API_DUR_MS="$val";;
    total_input_tokens)  val="${val// /}"; TOKENS="$val";;
    total_cost_usd)      val="${val// /}"; COST="$val";;
    total_lines_added)   val="${val// /}"; LINES_ADD="$val";;
    total_lines_removed) val="${val// /}"; LINES_DEL="$val";;
    reset_timestamp|resets_at)
      val="${val// /}"; val="${val%.*}"
      case "$in_block" in
        5h) RATE_5H_RESET="$val"; block_filled=$((block_filled+1));;
        7d) RATE_7D_RESET="$val"; block_filled=$((block_filled+1));;
        md) RATE_MD_RESETS[${#RATE_MD_KEYS[@]}-1]="$val"; block_filled=$((block_filled+1));;
        spend) SPEND_RESET="$val"; block_filled=$((block_filled+1));;
      esac
      [ "$block_filled" -ge 2 ] && { in_block=""; block_filled=0; };;
    used_percentage)
      val="${val// /}"; val="${val%.*}"
      case "$in_block" in
        5h) RATE_5H="$val"; block_filled=$((block_filled+1));;
        7d) RATE_7D="$val"; block_filled=$((block_filled+1));;
        md) RATE_MD_PCTS[${#RATE_MD_KEYS[@]}-1]="$val"; block_filled=$((block_filled+1));;
        spend) SPEND_PCT="$val"; block_filled=$((block_filled+1));;
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
[[ -z "$LINES_ADD" || "$LINES_ADD" == "null" ]] && LINES_ADD=0
[[ -z "$LINES_DEL" || "$LINES_DEL" == "null" ]] && LINES_DEL=0
[[ -z "$API_DUR_MS" || "$API_DUR_MS" == "null" ]] && API_DUR_MS=0
[[ "$STYLE_NAME" == "null" ]] && STYLE_NAME=""
[[ "$EFFORT_LEVEL" == "null" ]] && EFFORT_LEVEL=""

# ---------- 4. 포매터 (순수 bash) ----------
# Duration
fmt_ms() { # $1=ms → REPLY_TIME="XmYs"|"Ys"
  local _s=$(( $1 / 1000 )) _m
  _m=$((_s / 60)); _s=$((_s % 60))
  if [ "$_m" -gt 0 ]; then REPLY_TIME="${_m}m${_s}s"; else REPLY_TIME="${_s}s"; fi
}
fmt_ms "$DURATION_MS"; TIME="$REPLY_TIME"
fmt_ms "$API_DUR_MS";  API_TIME="$REPLY_TIME"

# 숫자 → K/M 축약
fmt_km() { # $1=n → REPLY_KM
  local _n="$1"
  if [ "$_n" -gt 999999 ]; then
    REPLY_KM="$((_n/1000000)).$((_n%1000000/100000))M"
  elif [ "$_n" -gt 999 ]; then
    REPLY_KM="$((_n/1000)).$((_n%1000/100))K"
  else
    REPLY_KM="$_n"
  fi
}
fmt_km "$TOKENS"; TOKEN_FMT="$REPLY_KM"

# ctx 절대량 — context_window_size 가 오면 % 뒤에 "used/total" 병기
[[ -z "$CTX_SIZE" || "$CTX_SIZE" == "null" ]] && CTX_SIZE=0
CTX_ABS=""
if [ "$CTX_SIZE" -gt 0 ] 2>/dev/null; then
  fmt_km $((CTX_SIZE * CTX_PCT / 100)); _ctx_used="$REPLY_KM"
  fmt_km "$CTX_SIZE"
  CTX_ABS=" (${_ctx_used}/${REPLY_KM})"
fi

# Cost → $X.XX
if [[ -n "$COST" && "$COST" != "null" && "$COST" != "0" ]]; then
  [[ "$COST" == *.* ]] || COST="${COST}.0"   # 정수 비용("5")이 $5.50 로 깨지던 것 방어
  COST_INT="${COST%%.*}"
  COST_DEC="${COST#*.}"
  COST_DEC="${COST_DEC:0:2}"
  [[ ${#COST_DEC} -eq 1 ]] && COST_DEC+="0"
  [[ ${#COST_DEC} -eq 0 ]] && COST_DEC="00"
  COST_DISPLAY="\$${COST_INT}.${COST_DEC}"
  # 세션 5분 이상이면 시간당 소진율 추정 병기 (정수 센트 연산 — fork 없음)
  DURATION_S=$((DURATION_MS / 1000))
  if [ "$DURATION_S" -ge 300 ]; then
    _cost_c=$((10#$COST_INT * 100 + 10#$COST_DEC))
    _ph_c=$((_cost_c * 3600 / DURATION_S))
    COST_DISPLAY+=" (~\$$((_ph_c/100)).$((_ph_c%100/10))/h)"
  fi
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

# 소진 페이스 — 윈도 경과율보다 사용률이 15%p 이상 앞서면 🔥 (리셋 전 소진 위험)
pace_flag() { # $1=used% $2=reset_epoch $3=window_sec → REPLY_PACE
  local _used="$1" _reset="$2" _win="$3" _remain _elapsed
  REPLY_PACE=""
  [ "$_reset" -gt 0 ] 2>/dev/null && [ -n "$NOW_EPOCH" ] || return
  _remain=$((_reset - NOW_EPOCH))
  [ "$_remain" -gt 0 ] && [ "$_remain" -le "$_win" ] || return
  _elapsed=$(( (_win - _remain) * 100 / _win ))
  [ "$_used" -ge $((_elapsed + 15)) ] && REPLY_PACE="🔥"
}
pace_flag "$RATE_5H" "$RATE_5H_RESET" 18000;  PACE_5H="$REPLY_PACE"
pace_flag "$RATE_7D" "$RATE_7D_RESET" 604800; PACE_7D="$REPLY_PACE"

# ---------- 5. ANSI 컬러 ----------
RST=$'\033[0m'
GRN=$'\033[32m'
RED=$'\033[31m'
color_for() {
  local pct="$1"
  if   [ "$pct" -ge 80 ]; then COLOR=$'\033[31m'
  elif [ "$pct" -ge 50 ]; then COLOR=$'\033[33m'
  else COLOR=$'\033[32m'; fi
}
color_for "$CTX_PCT";  CTX_COLOR="$COLOR"
color_for "$RATE_5H";  RATE_5H_COLOR="$COLOR"
color_for "$RATE_7D";  RATE_7D_COLOR="$COLOR"

if [ "$RATE_5H" -ge 80 ]; then RATE_5H_ICON="⌛"; else RATE_5H_ICON="⚡"; fi
if [ "$RATE_7D" -ge 80 ]; then RATE_7D_ICON="⌛"; else RATE_7D_ICON="📅"; fi

# ========================================================================
# 확장 위젯 #1 — Git 브랜치 + dirty heuristic
# ========================================================================
GIT_DISPLAY="🌿 git —"   # 기본값: 비-git 디렉터리임을 명시
# .git 이 디렉터리면 그대로, 파일이면 worktree(git worktree add / claude --worktree) — 첫 줄 "gitdir: <path>" 를
# 따라간다(상대경로면 CWD 기준, 백슬래시는 / 로 정규화). HEAD·MERGE_HEAD·ORIG_HEAD·rebase-merge 는 모두 그
# gitdir 아래에 있다. 해석 실패 시 기본값 "git —" 유지. fork 없음.
_gitdir=""
if [[ -n "$CWD" ]]; then
  if [[ -d "$CWD/.git" ]]; then
    _gitdir="$CWD/.git"
  elif [[ -f "$CWD/.git" ]]; then
    while IFS= read -r _gd_line || [[ -n "$_gd_line" ]]; do
      [[ "$_gd_line" == gitdir:* ]] && _gitdir="${_gd_line#gitdir:}"
      break
    done < "$CWD/.git"
    _gitdir="${_gitdir# }"; _gitdir="${_gitdir%$'\r'}"; _gitdir="${_gitdir//\\//}"
    [[ -n "$_gitdir" && "$_gitdir" != /* && "$_gitdir" != ?:/* ]] && _gitdir="$CWD/$_gitdir"
  fi
fi
if [[ -n "$_gitdir" && -f "$_gitdir/HEAD" ]]; then
  _branch=""
  while IFS= read -r _head_line; do _branch="$_head_line"; break; done < "$_gitdir/HEAD"
  if [[ "$_branch" == ref:* ]]; then
    _branch="${_branch##*/}"
  else
    _branch="${_branch:0:7}"  # detached HEAD → short SHA
  fi
  _dirty=""
  # fork-free heuristic: MERGE/REBASE/ORIG_HEAD 존재 시 진행 중 작업 표시
  if [[ -f "$_gitdir/MERGE_HEAD" || -f "$_gitdir/ORIG_HEAD" || -d "$_gitdir/rebase-merge" ]]; then
    _dirty="*"
  fi
  [[ -n "$_branch" ]] && GIT_DISPLAY="🌿 git: ${_branch}${_dirty}"
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
  auto|autoAccept)   PERM_DISPLAY="🤝 perm auto";;
  acceptEdits)       PERM_DISPLAY="✅ perm accept";;
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
  # 기본은 JSONL 각 라인의 model 필드로 모델군별 단가 자동 적용 (opus $5/$25,
  # fable·mythos $10/$50, sonnet $3/$15, haiku $1/$5 — cache w 1.25x, r 0.1x).
  # 오버라이드가 하나라도 있으면 구버전과 동일하게 전 모델 공통 단가로 동작.
  # 아래 기본값은 model 필드가 없는 라인의 폴백(= Opus 티어 $5/$25).
  RATE_INPUT="${CC_DASH_RATE_INPUT:-5000}"
  RATE_OUTPUT="${CC_DASH_RATE_OUTPUT:-25000}"
  RATE_CACHE_W="${CC_DASH_RATE_CACHE_W:-6250}"
  RATE_CACHE_R="${CC_DASH_RATE_CACHE_R:-500}"
  RATE_FIXED=0
  [[ -n "${CC_DASH_RATE_INPUT}${CC_DASH_RATE_OUTPUT}${CC_DASH_RATE_CACHE_W}${CC_DASH_RATE_CACHE_R}" ]] && RATE_FIXED=1
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
      | xargs -0 awk -v today="$TODAY_PREFIX" -v fixed="$RATE_FIXED" \
          -v ri="$RATE_INPUT" -v ro="$RATE_OUTPUT" -v rcw="$RATE_CACHE_W" -v rcr="$RATE_CACHE_R" '
        index($0, "\"timestamp\":\"" today) == 0 { next }
        index($0, "\"usage\"") == 0 { next }
        {
          ri_ = ri; ro_ = ro; rcw_ = rcw; rcr_ = rcr
          if (!fixed && match($0, /"model":"[^"]*"/)) {
            m = substr($0, RSTART+9, RLENGTH-10)
            if      (index(m, "opus"))                        { ri_=5000;  ro_=25000; rcw_=6250;  rcr_=500 }
            else if (index(m, "fable") || index(m, "mythos")) { ri_=10000; ro_=50000; rcw_=12500; rcr_=1000 }
            else if (index(m, "sonnet"))                      { ri_=3000;  ro_=15000; rcw_=3750;  rcr_=300 }
            else if (index(m, "haiku"))                       { ri_=1000;  ro_=5000;  rcw_=1250;  rcr_=100 }
          }
          # substr 오프셋 = 키 프리픽스 길이("key": 따옴표+콜론 포함) — 과거 +1 오프셋
          # 오프바이원으로 토큰 수 첫 자리가 잘려 일일 비용이 과소집계되던 결함 교정
          s = 0
          if (match($0, /"input_tokens":[0-9]+/))                s += substr($0, RSTART+15, RLENGTH-15) * ri_
          if (match($0, /"output_tokens":[0-9]+/))               s += substr($0, RSTART+16, RLENGTH-16) * ro_
          if (match($0, /"cache_creation_input_tokens":[0-9]+/)) s += substr($0, RSTART+30, RLENGTH-30) * rcw_
          if (match($0, /"cache_read_input_tokens":[0-9]+/))     s += substr($0, RSTART+26, RLENGTH-26) * rcr_
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
#   L1 사용량:  model · effort(auto-hide) · duration · api(opt) · ctx · token · cost · lines · budget(opt)
#   L2 리밋:    now(5h) · week(7d) · 모델별 주간(opt, 페이로드 있을 때만)
#   L3 메타:    perm(opt) · style(opt) · version · git · project · session · clock (맨 오른쪽)
# 위젯 CFG_* 가 0 이면 세그먼트가 빠지고 구분자(│)도 남지 않는다.
L1="" L2="" L3=""
append() {
  local -n _ref="$1"; local seg="$2"
  [[ -n "$seg" ]] || return
  [[ -n "$_ref" ]] && _ref+=" │ $seg" || _ref="$seg"
}
[[ "$CFG_MODEL"    == "1" ]] && append L1 "🤖 ${MODEL}"
# effort — 페이로드에 effort.level 이 없으면(모델 미지원) 세그먼트 자체를 생략. 경고 지표가 아니라 색상 없음
[[ "$CFG_EFFORT"   == "1" && -n "$EFFORT_LEVEL" ]] && append L1 "🧠 effort ${EFFORT_LEVEL}"
[[ "$CFG_DURATION" == "1" ]] && append L1 "⏱  dur ${TIME}"
[[ "$CFG_API_DUR"  == "1" ]] && append L1 "📡 api ${API_TIME}"
[[ "$CFG_CTX"      == "1" ]] && append L1 "📊 ctx ${CTX_COLOR}${CTX_PCT}%${RST}${CTX_ABS}"
[[ "$CFG_TOKEN"    == "1" ]] && append L1 "🪙 token ${TOKEN_FMT}"
[[ "$CFG_COST"     == "1" ]] && append L1 "💸 cost ${COST_DISPLAY}"
[[ "$CFG_LINES"    == "1" ]] && append L1 "✏️  ${GRN}+${LINES_ADD}${RST}/${RED}-${LINES_DEL}${RST}"
[[ -n "$BUDGET_DISPLAY"    ]] && append L1 "${BUDGET_DISPLAY}"

[[ "$CFG_RATE_5H"  == "1" ]] && append L2 "${RATE_5H_ICON} now ${RATE_5H_COLOR}${RATE_5H}%${RST}${PACE_5H}${TIMER_5H}"
[[ "$CFG_RATE_7D"  == "1" ]] && append L2 "${RATE_7D_ICON} week ${RATE_7D_COLOR}${RATE_7D}%${RST}${PACE_7D}${TIMER_7D}"
# 모델별 주간 윈도 — ① 페이로드의 seven_day_* 우선, ② 없으면 RATE_API 캐시(opt-in)
# 현행 Claude Code 는 statusLine 페이로드에 five_hour·seven_day 만 넣으므로 ①은
# 사실상 비어 있다. ②는 cc-dash-usage-fetch.sh 가 /api/oauth/usage 에서 받아둔
# 캐시를 읽는다 — OAuth 토큰을 쓰는 경로라 RATE_API 를 켠 사용자에게만 동작한다.
if [[ "$CFG_RATE_MODEL" == "1" && "$CFG_RATE_API" == "1" && ${#RATE_MD_KEYS[@]} -eq 0 ]]; then
  _uc="${CC_DASH_USAGE_CACHE:-$HOME/.cache/cc-dash-usage}"
  _uc_fetched=""
  if [[ -f "$_uc" ]]; then
    while IFS='|' read -r _f1 _f2 _f3 _f4; do
      case "$_f1" in
        T) _uc_fetched="$_f2";;
        M) [[ -n "$_f2" ]] || continue
           RATE_MD_KEYS+=("$_f2"); RATE_MD_PCTS+=("$_f3"); RATE_MD_RESETS+=("${_f4:-0}");;
      esac
    done < "$_uc"
  fi
  # 캐시가 없거나 TTL 초과면 백그라운드로 1회 갱신 — 이번 렌더는 stale 값을 그대로
  # 쓴다(플리커 방지). 렌더는 턴마다 여러 번 일어나므로 시도 시각을 마커 파일에
  # 적어 최소 간격을 강제한다 (mtime 조회는 fork 가 필요해 파일 내용으로 대체).
  if [[ ! "$_uc_fetched" =~ ^[0-9]+$ ]] || (( NOW_EPOCH - _uc_fetched > ${CC_DASH_USAGE_TTL:-300} )); then
    _uc_mark="${_uc}.attempt" _uc_last=0
    if [[ -f "$_uc_mark" ]]; then
      while IFS= read -r _l; do _uc_last="$_l"; break; done < "$_uc_mark"
      [[ "$_uc_last" =~ ^[0-9]+$ ]] || _uc_last=0
    fi
    if (( NOW_EPOCH - _uc_last > ${CC_DASH_USAGE_MIN_INTERVAL:-60} )); then
      _uc_fetcher="${BASH_SOURCE[0]%/*}/cc-dash-usage-fetch.sh"
      if [[ -f "$_uc_fetcher" ]]; then
        mkdir -p "${_uc%/*}" 2>/dev/null
        printf '%s\n' "$NOW_EPOCH" > "$_uc_mark" 2>/dev/null
        # 자식의 stdout/stderr 를 명시적으로 끊는다 — statusLine 파이프에 매달리면
        # Claude Code 가 렌더를 끝내지 못한다.
        bash "$_uc_fetcher" >/dev/null 2>&1 </dev/null &
      fi
    fi
  fi
fi
if [[ "$CFG_RATE_MODEL" == "1" ]]; then
  for _i in "${!RATE_MD_KEYS[@]}"; do
    _mp="${RATE_MD_PCTS[_i]}"; _mr="${RATE_MD_RESETS[_i]}"
    [[ "$_mp" =~ ^[0-9]+$ ]] || _mp=0
    [[ "$_mr" =~ ^[0-9]+$ ]] || _mr=0
    case "${RATE_MD_KEYS[_i]}" in
      opus)   _ml="Opus";;
      sonnet) _ml="Sonnet";;
      fable)  _ml="Fable";;
      haiku)  _ml="Haiku";;
      oauth_apps) _ml="apps";;
      *)      _ml="${RATE_MD_KEYS[_i]}";;
    esac
    color_for "$_mp"; _mc="$COLOR"
    if [ "$_mp" -ge 80 ]; then _mi="⌛"; else _mi="🎯"; fi
    fmt_remain "$_mr"; _mt="$REMAIN_FMT"; [ -n "$_mt" ] && _mt=" reset ${_mt}"
    pace_flag "$_mp" "$_mr" 604800
    append L2 "${_mi} ${_ml} ${_mc}${_mp}%${RST}${REPLY_PACE}${_mt}"
  done
fi

[[ "$CFG_PERM"    == "1" ]] && append L3 "$PERM_DISPLAY"
[[ "$CFG_STYLE"   == "1" ]] && append L3 "🎨 style ${STYLE_NAME:-—}"
[[ "$CFG_VERSION" == "1" ]] && append L3 "$VERSION_DISPLAY"
[[ "$CFG_GIT"     == "1" ]] && append L3 "$GIT_DISPLAY"
[[ "$CFG_PROJECT" == "1" ]] && append L3 "$PROJECT_DISPLAY"
[[ "$CFG_SESSION" == "1" ]] && append L3 "$SESSION_DISPLAY"
[[ "$CFG_CLOCK"   == "1" ]] && append L3 "${CLOCK_DISPLAY}"

# ---------- 6.5 L1·L2 너비 제한 — 한 행이 터미널 폭을 넘어 줄바꿈되지 않게 클립(L3 는 클립 안 함) ----------
# 로케일 무관(LANG 미설정·MSYS 16비트 wchar 대응), fork 없음.
# 함수 안에서 LC_ALL=C 로 바이트 모드를 고정하고(종료 시 자동 복원) UTF-8 선두 바이트로 시퀀스 길이와
# 표시 폭을 판정한다 — 1·2바이트 폭 1, 3·4바이트(이모지·CJK·박스문자) 폭 2, 변이 선택자 U+FE0F·ZWJ U+200D 폭 0.
# 시퀀스는 통째로 옮겨 중간에서 잘리지 않고(깨진 "�…" 방지), ANSI \033[…m 은 폭 0 으로 통과한다.
# 결과는 stdout 이 아니라 CLIP_OUT 변수 — 호출부의 $(...) 서브셸 fork 회피.
_cols="${COLUMNS:-9999}"
_clip_line() { # $1=line $2=limit(컬럼) → CLIP_OUT
  local LC_ALL=C
  local s="$1" limit="$2" vcol=0 out="" c esc seq n w
  # 바이트 수는 표시 폭의 상한(ASCII 1:1, 2바이트→1, 3·4바이트→2) — limit 이내면 루프 없이 원문 반환
  if (( ${#s} <= limit )); then CLIP_OUT="$s"; return; fi
  while [[ -n "$s" ]]; do
    c="${s:0:1}"
    if [[ "$c" == $'\033' && "${s:1:1}" == '[' ]]; then
      esc="${s%%m*}m"; out+="$esc"; s="${s:${#esc}}"; continue
    fi
    printf -v n '%d' "'$c"
    if   (( n < 128 ));             then n=1; w=1
    elif (( n >= 192 && n < 224 )); then n=2; w=1
    elif (( n >= 224 && n < 240 )); then n=3; w=2
    elif (( n >= 240 && n < 248 )); then n=4; w=2
    else                                 n=1; w=0   # 고아 연속 바이트/무효 선두 바이트 — 폭 0 으로 통과
    fi
    seq="${s:0:n}"
    [[ "$seq" == $'\xef\xb8\x8f' || "$seq" == $'\xe2\x80\x8d' ]] && w=0
    (( vcol + w > limit )) && { out+="${RST}…"; break; }
    out+="$seq"; s="${s:n}"; (( vcol += w ))
  done
  CLIP_OUT="$out"
}
# COLUMNS 가 있을 때만 — 바이트 수 기반 사전 판정은 부정확하므로 항상 호출(폭이 limit 이내면 원문 그대로)
if [[ "$_cols" != "9999" ]]; then
  _clip_line "$L1" "$(( _cols - 1 ))"; L1="$CLIP_OUT"
  # L2도 모델별 윈도(RATE_MODEL)로 비유계가 될 수 있어 동일 클립 적용
  _clip_line "$L2" "$(( _cols - 1 ))"; L2="$CLIP_OUT"
fi

emit() {
  [[ -n "$1" ]] || return
  local s="${1// /$'\xc2\xa0'}"
  printf '\x1b[0m%s\n' "$s"
}
emit "$L1"
emit "$L2"
emit "$L3"
