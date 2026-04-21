---
description: cc-dash statusLine을 settings.json에 자동 배선 (설치·업그레이드 직후 1회)
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/cc-dash-setup.sh:*)
---

!`bash ${CLAUDE_PLUGIN_ROOT}/scripts/cc-dash-setup.sh`

위 설치 헬퍼 스크립트 출력을 그대로 짧게 확인해.
- 성공 메시지(`statusLine added/updated/already up to date`): 한 줄로 "완료 — 다음 턴부터 대시보드 표시" 정도.
- `error:` 로 시작하면 메시지를 그대로 전달하고 권한/경로 문제 여부만 짚어줘.
