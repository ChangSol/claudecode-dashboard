---
description: "cc-dash 위젯 ON/OFF 토글"
argument-hint: "[list|toggle|on|off|reset|all-on|all-off] [KEY ...]"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/cc-dash-config.sh:*)"]
---

cc-dash 위젯 설정을 조회/변경합니다.

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/cc-dash-config.sh" $ARGUMENTS
```

위 스크립트 출력을 보고 응답해.
- 인자 없음 또는 조회(list/ls/status): 출력 표를 그대로 코드블록으로 전달. 요약 덧붙이지 마.
- help: 사용법 출력을 그대로 전달.
- 변경(on/off/toggle/reset/all-on/all-off): 바뀐 위젯만 한 줄 확인(예: "BUDGET ON 💰").
- "알 수 없는 …" / "사용법: …" 에러: 메시지 그대로 + 올바른 사용법 한 줄.
