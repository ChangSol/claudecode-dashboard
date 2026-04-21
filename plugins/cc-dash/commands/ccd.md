---
description: "cc-dash 위젯 ON/OFF 토글"
argument-hint: "[list|toggle|on|off|reset|all-on|all-off] [KEY ...]"
allowed-tools: ["Bash(*cc-dash-config.sh*)"]
---

cc-dash 위젯 설정 조회/변경.

!`${CLAUDE_PLUGIN_ROOT}/scripts/cc-dash-config.sh $ARGUMENTS`

위 스크립트 출력을 보고 응답해.
- 조회(list/ls/status 또는 인자 없음): 표를 그대로 코드블록으로. 요약 덧붙이지 마.
- help: 사용법 그대로.
- 변경(on/off/toggle/reset/all-on/all-off): 바뀐 위젯만 한 줄 확인(예: "BUDGET ON 💰").
- 에러(알 수 없는/사용법): 메시지 그대로 + 사용법 한 줄.
