#!/bin/bash
# cc-dash 위젯 ON/OFF 대화식 설정 — statusline.sh는 이 파일을 source 해서 각 위젯 노출을 결정한다.
# 저장 경로: $CC_DASH_CONFIG (기본 ~/.config/cc-dash/widgets.conf)

CFG_FILE="${CC_DASH_CONFIG:-$HOME/.config/cc-dash/widgets.conf}"

WIDGETS=(
  "CLOCK:🕐 시각"
  "MODEL:🍋 모델"
  "DURATION:⏱ 경과 시간"
  "CTX:🪟 ctx %"
  "TOKEN:💬 token"
  "COST:💸 cost (세션 누적)"
  "BUDGET:💰 일일 예산 % (opt-in, JSONL 스캔)"
  "RATE_5H:⚡/🔥 5h 리밋 + 타이머"
  "RATE_7D:📅 7d 리밋 + 타이머"
  "PERM:🔒 권한 모드"
  "VERSION:🚀 Claude Code 버전"
  "GIT:🔀 git 브랜치"
  "PROJECT:📁 프로젝트"
  "SESSION:🆔 세션 ID"
)

DEFAULT_KEYS=(CLOCK MODEL DURATION CTX TOKEN COST RATE_5H RATE_7D VERSION GIT)
DEFAULT_OFF=(BUDGET PERM PROJECT SESSION)

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
    printf '  %-10s %s  %s\n' "$key" "$mark" "$label"
  done
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

KEY (대소문자 무관): CLOCK MODEL DURATION CTX TOKEN COST BUDGET
                    RATE_5H RATE_7D PERM VERSION GIT PROJECT
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
    s|S) save_file; printf '\n저장 완료: %s\n' "$CFG_FILE"; exit 0;;
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
