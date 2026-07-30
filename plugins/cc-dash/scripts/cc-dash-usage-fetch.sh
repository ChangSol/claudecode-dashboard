#!/usr/bin/env bash
# cc-dash — 모델별 주간 리밋 fetcher (RATE_API 위젯 전용, opt-in)
#
# statusLine 은 네트워크를 타지 않는다 — 이 스크립트가 캐시 파일을 갱신하고
# statusline.sh 는 캐시만 읽는다. statusline.sh 가 TTL 초과 시 백그라운드로
# 1회 spawn 하며, `/cc-dash:ccd refresh` 는 동기로 1회 호출한다.
#
# 데이터 출처: GET /api/oauth/usage 의 limits[] 중 scope.model 이 있는 항목.
# Claude Code 의 statusLine 페이로드에는 모델별 윈도가 들어오지 않기 때문에
# (rate_limits 는 five_hour·seven_day 만 투영) 이 우회 경로가 필요하다.
#
# 실패(무토큰·만료·비200·curl 없음)는 조용히 종료한다 — statusLine 오염 방지.
# `-v` 를 주면 진단 메시지를 stderr 로 낸다. 액세스 토큰은 어떤 경로로도
# 출력하지 않으며 캐시 파일에도 기록되지 않는다.

if (( BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 3) )); then
  printf 'cc-dash: bash %s is too old (need 4.3+).\n' "$BASH_VERSION" >&2
  exit 1
fi

VERBOSE=0
[[ "$1" == "-v" || "$1" == "--verbose" ]] && VERBOSE=1

log() { (( VERBOSE )) && printf 'cc-dash-usage: %s\n' "$1" >&2; return 0; }

CACHE="${CC_DASH_USAGE_CACHE:-$HOME/.cache/cc-dash-usage}"
URL="${CC_DASH_USAGE_URL:-https://api.anthropic.com/api/oauth/usage}"
CRED="${CC_DASH_CREDENTIALS:-$HOME/.claude/.credentials.json}"

command -v curl >/dev/null 2>&1 || { log "curl 없음 — 조회 생략"; exit 1; }

# ---------- 1. OAuth 토큰 ----------
# 평문 자격증명 파일(Linux/Windows) → macOS 키체인 순으로 시도.
TOKEN="" EXPIRES=0
read_cred() { # $1=자격증명 JSON 문자열
  local blob="$1"
  [[ "$blob" =~ \"accessToken\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]] && TOKEN="${BASH_REMATCH[1]}"
  [[ "$blob" =~ \"expiresAt\"[[:space:]]*:[[:space:]]*([0-9]+) ]] && EXPIRES="${BASH_REMATCH[1]}"
}
if [[ -f "$CRED" ]]; then
  _blob=""
  while IFS= read -r _l || [[ -n "$_l" ]]; do _blob+="$_l"; done < "$CRED"
  read_cred "$_blob"
  _blob=""
fi
if [[ -z "$TOKEN" ]] && command -v security >/dev/null 2>&1; then
  # macOS: Claude Code 는 자격증명을 키체인에 보관한다
  _blob="$(security find-generic-password -s 'Claude Code-credentials' -w 2>/dev/null)"
  read_cred "$_blob"
  _blob=""
fi
[[ -n "$TOKEN" ]] || { log "OAuth 토큰 없음 (API 키·Bedrock·Vertex 세션이면 정상)"; exit 1; }

printf -v NOW '%(%s)T' -1
# expiresAt 은 ms epoch. 만료됐으면 갱신은 Claude Code 몫이므로 여기서는 종료한다
# (자격증명 파일에 쓰기 금지 — refresh 토큰 흐름을 흉내내지 않는다).
if [[ "$EXPIRES" =~ ^[0-9]+$ ]] && (( EXPIRES > 0 )) && (( EXPIRES / 1000 <= NOW )); then
  log "토큰 만료 — Claude Code 가 갱신한 뒤 다시 시도된다"
  exit 1
fi

# ---------- 2. 조회 ----------
RESP="$(curl -sS --max-time "${CC_DASH_USAGE_TIMEOUT:-6}" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "anthropic-beta: oauth-2025-04-20" \
  -H "Content-Type: application/json" \
  -w $'\n%{http_code}' "$URL" 2>/dev/null)"
TOKEN=""
CODE="${RESP##*$'\n'}"
BODY="${RESP%$'\n'*}"
RESP=""
if [[ "$CODE" != "200" ]]; then
  log "HTTP ${CODE:-none} — 응답 폐기"
  exit 1
fi
if [[ "$BODY" != *'"limits":['* ]]; then
  log "limits[] 없는 응답 — 스키마 변경 가능"
  exit 1
fi

# ---------- 3. limits[] 파싱 ----------
# ISO8601 → epoch. GNU date(-d) → BSD date(-j -f) 폴백, 실패 시 0(타이머 생략).
iso_epoch() { # $1=ISO8601 → stdout epoch
  local s="$1" base off out
  base="${s%%.*}"
  if [[ "$s" =~ ([+-][0-9][0-9]:?[0-9][0-9])$ ]]; then
    off="${BASH_REMATCH[1]}"; base="${base%"$off"}"
  else
    off="+00:00"; base="${base%Z}"
  fi
  out="$(date -u -d "${base}${off}" +%s 2>/dev/null)" \
    || out="$(date -u -j -f '%Y-%m-%dT%H:%M:%S%z' "${base}${off//:/}" +%s 2>/dev/null)" \
    || out=""
  [[ "$out" =~ ^[0-9]+$ ]] && printf '%s' "$out" || printf '0'
}

LIMITS="${BODY#*\"limits\":[}"
LIMITS="${LIMITS%%]*}"
LIMITS="${LIMITS//\},\{/$'\n'}"

LINES=() FOUND=""
while IFS= read -r _ent; do
  # scope.model.display_name 이 있는 항목만 — surface 스코프(oauth apps 등)는 제외.
  # [^}]* 로 model 객체 안에서만 display_name 을 찾는다.
  [[ "$_ent" =~ \"model\"[^{]*\{[^}]*\"display_name\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]] || continue
  _label="${BASH_REMATCH[1]}"
  _label="${_label//|/ }"          # 캐시 구분자 보호
  [[ "$_ent" =~ \"percent\"[[:space:]]*:[[:space:]]*([0-9]+) ]] || continue
  _pct="${BASH_REMATCH[1]}"
  if   [[ "$_ent" =~ \"resets_at\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
    _reset="$(iso_epoch "${BASH_REMATCH[1]}")"
  elif [[ "$_ent" =~ \"resets_at\"[[:space:]]*:[[:space:]]*([0-9]+) ]]; then
    _reset="${BASH_REMATCH[1]}"
  else
    _reset=0
  fi
  LINES+=("M|${_label}|${_pct}|${_reset}")
  FOUND+="${FOUND:+, }${_label} ${_pct}%"
done <<< "$LIMITS"

# ---------- 4. 캐시 원자적 기록 ----------
# 모델별 항목이 0개여도 T 라인은 쓴다 — 재조회 폭주를 막고 "없음"을 캐시한다.
mkdir -p "${CACHE%/*}" 2>/dev/null
TMP="${CACHE}.tmp.$$"
{
  printf 'T|%s\n' "$NOW"
  (( ${#LINES[@]} )) && printf '%s\n' "${LINES[@]}"
} > "$TMP" 2>/dev/null || { log "캐시 쓰기 실패: $TMP"; exit 1; }
mv "$TMP" "$CACHE" 2>/dev/null || { rm "$TMP" 2>/dev/null; log "캐시 교체 실패: $CACHE"; exit 1; }

log "모델별 버킷 ${#LINES[@]}개 캐시 → ${CACHE}${FOUND:+ (${FOUND})}"
exit 0
