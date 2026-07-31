#!/usr/bin/env bash
# cc-dash 위젯 ON/OFF 대화식 설정 — statusline.sh는 이 파일을 source 해서 각 위젯 노출을 결정한다.
# 저장 경로: $CC_DASH_CONFIG (기본 ~/.config/cc-dash/widgets.conf)
# 셔뱅이 env bash 인 이유: macOS /bin/bash 는 3.2 — PATH 의 brew bash 를 잡기 위함.

# Self-guard: `declare -A`/`${var^^}` 는 bash 4+ 전용 — 플러그인 전체 최저선(4.3)으로 통일.
# macOS /bin/bash 3.2 로 실행되면 `declare: -A: invalid option` 류 오류가 나므로 명확히 안내.
if (( BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 3) )); then
  printf 'cc-dash: bash %s is too old (need 4.3+).\n' "$BASH_VERSION" >&2
  printf 'macOS: brew install bash, then retry. (system /bin/bash 3.2 cannot run cc-dash)\n' >&2
  exit 1
fi

CFG_FILE="${CC_DASH_CONFIG:-$HOME/.config/cc-dash/widgets.conf}"

WIDGETS=(
  "CLOCK:🕐 시각"
  "MODEL:🍋 모델"
  "DURATION:⏱ 경과 시간"
  "API_DUR:🌐 API 소요 시간 (opt-in)"
  "CTX:🪟 ctx % (+사용/전체)"
  "TOKEN:💬 token"
  "COST:💸 cost (세션 누적, 5분+ 시 ~\$/h)"
  "LINES:✏️ +추가/-삭제 라인"
  "BUDGET:💰 일일 예산 % (opt-in, JSONL 스캔)"
  "RATE_5H:⏳ now(5h) 리밋 + 타이머 (🔥 페이스 경고)"
  "RATE_7D:⏳ week(7d) 리밋 + 타이머 (🔥 페이스 경고)"
  "RATE_MODEL:⏳ 모델별 주간 리밋 (Fable·Opus 등)"
  "RATE_API:🌐 모델별 리밋 API 조회 (opt-in — OAuth 토큰 사용)"
  "PERM:🔒 권한 모드"
  "STYLE:🎨 output style (opt-in)"
  "VERSION:🚀 Claude Code 버전"
  "GIT:🔀 git 브랜치"
  "PROJECT:📁 프로젝트"
  "SESSION:🆔 세션 ID"
)

DEFAULT_KEYS=(CLOCK MODEL DURATION CTX TOKEN COST LINES RATE_5H RATE_7D RATE_MODEL VERSION GIT)
DEFAULT_OFF=(BUDGET PERM PROJECT SESSION API_DUR STYLE RATE_API)

declare -A STATE
reset_defaults() {
  for k in "${DEFAULT_KEYS[@]}"; do STATE["$k"]=1; done
  for k in "${DEFAULT_OFF[@]}";  do STATE["$k"]=0; done
}
reset_defaults

if [[ -f "$CFG_FILE" ]]; then
  while IFS='=' read -r _k _v; do
    [[ "$_k" =~ ^[A-Z_0-9]+$ ]] || continue
    [[ "$_v" == "0" || "$_v" == "1" ]] || continue
    STATE["$_k"]="$_v"
  done < "$CFG_FILE"
fi

valid_key() {
  local k="$1" e
  for e in "${WIDGETS[@]}"; do [[ "${e%%:*}" == "$k" ]] && return 0; done
  return 1
}

# RATE_API(조회)만 켜고 RATE_MODEL(표시)이 꺼진 죽은 조합 — 조회 결과가 렌더될 곳이 없다
warn_rate_combo() {
  if [[ "${STATE[RATE_API]}" == "1" && "${STATE[RATE_MODEL]}" != "1" ]]; then
    printf 'warning: RATE_API 는 ON 인데 RATE_MODEL 이 off — 조회해도 위젯이 표시되지 않는다. 켜려면: cc-dash-config.sh on RATE_MODEL\n' >&2
  fi
}

print_status() {
  printf '설정 파일: %s\n' "$CFG_FILE"
  local entry key label v mark use_color=1
  # 비-TTY이거나 NO_COLOR 환경변수가 있으면 ANSI 생략 (슬래시 커맨드/로그 가독성)
  [[ ! -t 1 || -n "$NO_COLOR" ]] && use_color=0
  for entry in "${WIDGETS[@]}"; do
    key="${entry%%:*}"
    label="${entry#*:}"
    v="${STATE[$key]}"
    if (( use_color )); then
      if [[ "$v" == "1" ]]; then mark=$'\033[32mON \033[0m'; else mark=$'\033[90moff\033[0m'; fi
    else
      if [[ "$v" == "1" ]]; then mark="ON "; else mark="off"; fi
    fi
    printf '  %-12s %s  %s\n' "$key" "$mark" "$label"
  done
  warn_rate_combo
}

save_file() {
  mkdir -p "${CFG_FILE%/*}" 2>/dev/null
  {
    printf '# cc-dash widgets config — 1=표시, 0=숨김. cc-dash-config.sh 로 편집 권장.\n'
    for entry in "${WIDGETS[@]}"; do
      key="${entry%%:*}"
      printf '%s=%s\n' "$key" "${STATE[$key]:-0}"
    done
  } > "$CFG_FILE"
}

# ---------- CLI 서브커맨드 (비대화식) ----------
if [[ $# -gt 0 ]]; then
  cmd="$1"; shift
  case "$cmd" in
    list|ls|status) print_status; exit 0;;
    on|off|toggle)
      [[ $# -lt 1 ]] && { printf '사용법: %s KEY [KEY ...]\n' "$cmd" >&2; exit 2; }
      for k in "$@"; do
        K="${k^^}"
        valid_key "$K" || { printf '알 수 없는 위젯: %s\n' "$k" >&2; exit 1; }
        case "$cmd" in
          on)  STATE["$K"]=1;;
          off) STATE["$K"]=0;;
          toggle)
            if [[ "${STATE[$K]}" == "1" ]]; then STATE["$K"]=0; else STATE["$K"]=1; fi;;
        esac
      done
      save_file; print_status; exit 0;;
    reset) reset_defaults; save_file; print_status; exit 0;;
    all-on)
      for e in "${WIDGETS[@]}"; do STATE["${e%%:*}"]=1; done
      save_file; print_status; exit 0;;
    all-off)
      for e in "${WIDGETS[@]}"; do STATE["${e%%:*}"]=0; done
      save_file; print_status; exit 0;;
    refresh)
      # ① budget 캐시 무효화 — 그 외 위젯은 매 렌더 실시간이라 캐시가 없다.
      cache_file="${CC_DASH_CACHE:-$HOME/.cache/cc-dash-budget}"
      if [[ -f "$cache_file" ]]; then
        if rm "$cache_file" 2>/dev/null; then
          printf 'budget 캐시 삭제: %s\n' "$cache_file"
        else
          printf 'warning: budget 캐시 삭제 실패: %s\n' "$cache_file" >&2
        fi
      else
        printf 'budget 캐시 없음 — 다음 렌더에서 새로 계산: %s\n' "$cache_file"
      fi
      # ①-b RATE_API 가 켜져 있으면 모델별 리밋을 지금 동기로 다시 받아둔다.
      # (꺼져 있으면 네트워크·토큰 접근 없음 — 캐시/마커만 정리한다.)
      usage_cache="${CC_DASH_USAGE_CACHE:-$HOME/.cache/cc-dash-usage}"
      [[ -f "${usage_cache}.attempt" ]] && rm "${usage_cache}.attempt" 2>/dev/null
      if [[ "${STATE[RATE_API]}" == "1" && "${STATE[RATE_MODEL]}" != "1" ]]; then
        # 죽은 조합 — README 문서화 동작(표시 없으면 조회 없음)과 정합: 조회를 생략한다
        printf 'usage 조회 생략 — RATE_MODEL 이 off 라 위젯이 표시되지 않는다. 켜려면: cc-dash-config.sh on RATE_MODEL\n'
        warn_rate_combo
      elif [[ "${STATE[RATE_API]}" == "1" ]]; then
        fetch_sh="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/cc-dash-usage-fetch.sh"
        if [[ -f "$fetch_sh" ]]; then
          if bash "$fetch_sh" -v; then
            printf 'usage 캐시 갱신: %s\n' "$usage_cache"
          else
            printf 'warning: usage 조회 실패 — 위 진단 참고 (세그먼트는 조용히 숨겨짐)\n' >&2
          fi
        else
          printf 'warning: cc-dash-usage-fetch.sh 없음 (%s) — usage 갱신 생략\n' "$fetch_sh" >&2
        fi
      else
        [[ -f "$usage_cache" ]] && rm "$usage_cache" 2>/dev/null
        printf 'usage 조회 off (RATE_API) — 켜려면: cc-dash-config.sh on RATE_API\n'
      fi
      # ② statusLine 재배선 — 플러그인 업그레이드 시 settings.json 이 구버전
      # 경로를 가리킨 채로 남는다. setup 은 멱등이라 최신이면 그대로 통과한다.
      setup_sh="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/cc-dash-setup.sh"
      if [[ -f "$setup_sh" ]]; then
        bash "$setup_sh" || printf 'warning: statusLine 재배선 실패 — /cc-dash:ccd-setup 을 직접 실행하세요.\n' >&2
      else
        printf 'warning: cc-dash-setup.sh 없음 (%s) — statusLine 재배선 생략\n' "$setup_sh" >&2
      fi
      exit 0;;
    -h|--help|help)
      cat <<EOF
cc-dash 위젯 ON/OFF

사용법:
  cc-dash-config.sh                    대화식 메뉴
  cc-dash-config.sh list               현재 상태
  cc-dash-config.sh toggle KEY [KEY …] 토글
  cc-dash-config.sh on KEY [KEY …]     켜기
  cc-dash-config.sh off KEY [KEY …]    끄기
  cc-dash-config.sh reset              기본값 복원
  cc-dash-config.sh all-on | all-off   전체 ON/OFF
  cc-dash-config.sh refresh            budget 캐시 비우기 + usage 재조회(RATE_API 시)
                                       + statusLine 경로 재배선

KEY (대소문자 무관): CLOCK MODEL DURATION API_DUR CTX TOKEN COST LINES BUDGET
                    RATE_5H RATE_7D RATE_MODEL RATE_API PERM STYLE VERSION GIT
                    PROJECT SESSION

RATE_API 는 모델별 주간 리밋(Fable 등)을 Anthropic /api/oauth/usage 에서 받아오는
opt-in 스위치다 — Claude Code 의 statusLine 페이로드에 그 값이 없어서 필요하다.
켜면 백그라운드에서 OAuth 액세스 토큰(~/.claude/.credentials.json)을 읽어 5분 TTL
캐시를 갱신한다. 끄면 네트워크·토큰 접근이 전혀 없다.
EOF
      exit 0;;
    *) printf '알 수 없는 명령: %s ("help" 참고)\n' "$cmd" >&2; exit 2;;
  esac
fi

# 인자 없이 비대화식(TTY 아님)으로 호출되면 — 슬래시 커맨드 경로 — 상태만 출력하고 종료.
# (TTY 없을 땐 read가 즉시 EOF → 루프가 무한 재진입하던 버그 방어)
if [[ ! -t 0 ]]; then print_status; exit 0; fi

render() {
  printf '\033[2J\033[H'
  printf 'cc-dash 위젯 ON/OFF 설정\n'
  printf '설정 파일: %s\n' "$CFG_FILE"
  printf '────────────────────────────────────────────\n'
  local i=0 entry key label v mark
  for entry in "${WIDGETS[@]}"; do
    key="${entry%%:*}"
    label="${entry#*:}"
    v="${STATE[$key]}"
    if [[ "$v" == "1" ]]; then mark=$'\033[32m[✓]\033[0m'; else mark=$'\033[90m[ ]\033[0m'; fi
    i=$((i+1))
    printf '  %2d) %s %s\n' "$i" "$mark" "$label"
  done
  printf '\n'
  printf '  번호: 토글 | a: 전체 ON | n: 전체 OFF | r: 기본값 복원\n'
  printf '  s: 저장 후 종료 | q: 저장 없이 종료\n\n'
  printf '선택> '
}

msg=""
while true; do
  render
  [[ -n "$msg" ]] && { printf '\n%s\n' "$msg"; msg=""; }
  IFS= read -r choice || { printf '\n(stdin 종료 — 저장 없이 나감)\n'; exit 0; }
  case "$choice" in
    s|S) save_file; printf '\n저장 완료: %s\n' "$CFG_FILE"; warn_rate_combo; exit 0;;
    q|Q) printf '취소됨 (저장 안 함)\n'; exit 0;;
    a|A) for e in "${WIDGETS[@]}"; do STATE["${e%%:*}"]=1; done;;
    n|N) for e in "${WIDGETS[@]}"; do STATE["${e%%:*}"]=0; done;;
    r|R) reset_defaults;;
    '') ;;
    *[!0-9]*) msg="잘못된 입력: '$choice'";;
    *)
      idx=$((choice - 1))
      if (( idx >= 0 && idx < ${#WIDGETS[@]} )); then
        key="${WIDGETS[$idx]%%:*}"
        if [[ "${STATE[$key]}" == "1" ]]; then STATE["$key"]=0; else STATE["$key"]=1; fi
      else
        msg="범위 밖: $choice (1~${#WIDGETS[@]})"
      fi;;
  esac
done
