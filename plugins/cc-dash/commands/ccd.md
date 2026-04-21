---
description: cc-dash 위젯 ON/OFF 토글
argument-hint: [list|toggle|on|off|reset|all-on|all-off] [KEY ...]
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/cc-dash-config.sh*)
---

!`bash ${CLAUDE_PLUGIN_ROOT}/scripts/cc-dash-config.sh $ARGUMENTS`

위 cc-dash 위젯 설정 명령의 출력을 보고 응답해.
- 인자 없음 또는 조회(list/ls/status): 스크립트가 출력한 표를 그대로 코드블록으로 보여줘 (각 위젯 한 줄씩 ON/off + 레이블). 요약 문장 덧붙이지 마.
- help: 사용법 출력을 코드블록으로 그대로 전달.
- 변경 명령(on/off/toggle/reset/all-on/all-off): 바뀐 위젯만 한 줄로 확인(예: "BUDGET ON 💰").
- "알 수 없는 …" / "사용법: …" 같은 에러: 메시지 그대로 전달 + 올바른 사용법 한 줄 안내.
