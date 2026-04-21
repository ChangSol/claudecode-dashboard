---
description: "cc-dash statusLine을 settings.json에 자동 배선 (설치·업그레이드 직후 1회)"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/cc-dash-setup.sh:*)"]
---

cc-dash statusLine을 `~/.claude/settings.json`에 배선합니다.

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/cc-dash-setup.sh"
```

위 출력을 그대로 짧게 확인해.
- `statusLine added/updated/already up to date`: "완료 — 다음 턴부터 대시보드 표시".
- `error:` 로 시작하면 메시지 그대로 전달.
