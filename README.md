# cc-dash

**한국어** | [English](README.en.md)

**fork 없는 무의존성 Claude Code statusLine.**
19개 위젯 — 모델, 경과 시간, API 시간, 컨텍스트, 토큰, 비용, 변경 라인, 예산, 리밋(모델별 주간 포함), 권한, output style, 버전, git, 프로젝트, 세션, 시각 — 을 3행으로 렌더링합니다. `/cc-dash:ccd`로 위젯별 ON/OFF.

```
🧠 Opus 4.7 (1M context) │ ⏱  dur 22m0s │ 🪟 ctx 25% │ 💬 token 50.0K │ 💸 cost $0.50 │ ✏️  +120/-34
⏳ now 0% reset 3h0m │ ⏳ week 2% reset 6d22h
🚀 cc v2.1.116 │ 🔀 git: main │ 🕐 2026.04.21 13:03
```

---

## 왜 cc-dash인가

대부분의 statusLine 스크립트는 매초 `jq`, `awk`, `date`, `git`을 fork해 셸을 무겁게 만듭니다. cc-dash는 **fast path가 순수 bash 내장 명령**(bash ≥ 4.3)입니다 — fork 없음, `cat` 없음, `sed` 없음. 예외는 opt-in 위젯 둘뿐입니다: budget은 60초 캐시와 함께 `awk`를 1회 호출하고, `RATE_API`는 5분 캐시가 식을 때만 백그라운드 조회를 1회 띄웁니다.

1행은 터미널 폭(`$COLUMNS`)에 맞춰 자동으로 잘리므로 2·3행은 항상 보입니다.

---

## 주요 기능

- **19개 위젯 전부 토글 가능** — `/cc-dash:ccd toggle BUDGET`, `/cc-dash:ccd off RATE_7D`, `/cc-dash:ccd reset`.
- **3행 레이아웃** — 1행 사용량, 2행 리밋, 3행 메타 + 시계.
- **셀프 라벨링** — 모든 아이콘에 짧은 영문 태그가 붙어 있어 의미가 헷갈리지 않습니다.
- **컨텍스트 %, now(5h)/week(7d) 리밋, 토큰 수, 세션 비용** — 전부 Claude Code가 제공하는 statusLine JSON 페이로드에서 파싱합니다.
- **임계 색상** — ≥50% 주황, ≥80% 빨강. 쿼터가 뜨거우면 `⏳`가 `⌛`로 바뀌고, 사용률이 리셋 페이스보다 앞서면 🔥가 붙습니다.
- **Git 브랜치** + 진행 중 표시(merge/rebase 시 `*`).
- **선택형 budget 위젯** — 오늘의 JSONL 로그를 스캔해 `$CC_DASH_BUDGET` 대비 일일 지출을 추적합니다.
- **PROJECT / SESSION** 별도 토글 위젯.

---

## 설치

### 1. 플러그인으로

Claude Code는 마켓플레이스를 통해 플러그인을 설치하므로 2단계입니다 — 먼저 저장소를 마켓플레이스로 등록한 뒤, 거기서 `cc-dash` 플러그인을 설치합니다:

```
/plugin marketplace add ChangSol/claudecode-dashboard
/plugin install cc-dash@claudecode-dashboard
```

`/cc-dash:ccd` 슬래시 커맨드와 `cc-dash-config.sh` / `statusline.sh` 스크립트는 플러그인에 포함되어 있습니다.

### 2. statusLine 배선

```
/cc-dash:ccd-setup
```

Claude Code 플러그인 매니페스트에는 `statusLine` 필드가 없어서, 최초 1회 배선은 `~/.claude/settings.json`에 올바른 `statusLine` 항목을 대신 써 주는 원샷 헬퍼 커맨드로 처리합니다. 플러그인 업그레이드 후에는 다시 실행하세요 — 설치 경로에 버전이 포함되어(`.../cc-dash/1.0.0/...`) 업데이트마다 바뀝니다. `/cc-dash:ccd refresh`도 같은 재배선을 수행하므로 둘 중 아무거나 쓰면 됩니다.

> **macOS 참고:** 시스템 `/bin/bash`는 3.2에 고정되어 있어 cc-dash를 실행할 수 없습니다(`printf '%(…)T'`·`local -n` 사용, bash ≥ 4.3 필요). `/cc-dash:ccd-setup` 실행 *전에* `brew install bash`로 최신 bash를 설치하세요 — macOS에서는 셋업 스크립트가 항상 **절대경로** bash를 `settings.json`에 배선합니다(PATH의 bash가 4.3 이상이면 그 경로, 아니면 Apple Silicon은 `/opt/homebrew/bin/bash`, Intel은 `/usr/local/bin/bash`). 덕분에 GUI에서 최소 PATH로 실행된 Claude Code에서도 statusLine이 계속 동작합니다. 호환 bash를 찾지 못하면 statusLine이 빈 줄 대신 한 줄 경고를 렌더링합니다. `/cc-dash:ccd` 위젯 토글에도 brew bash가 필요합니다 — bash 3.2에서는 암호 같은 오류 대신 명확한 메시지와 함께 거부합니다.

직접 편집을 선호하면 현재 설치 경로로 아래 블록을 `~/.claude/settings.json`에 추가하세요(정확한 위치는 `/plugin` 참조):

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash <absolute-path-to>/cc-dash/scripts/statusline.sh"
  }
}
```

Windows에서는 슬래시를 사용하세요(예: `C:/Users/.../plugins/cache/claudecode-dashboard/cc-dash/1.0.0/scripts/statusline.sh`). macOS에서는 맨 앞의 `bash`를 brew bash 절대경로로 바꾸세요(예: `'/opt/homebrew/bin/bash' '<path>/statusline.sh'`) — GUI에서 실행된 Claude Code에서는 순수 `bash`가 3.2 시스템 bash로 해석됩니다.

### 3. 플러그인 없이 (체크아웃 방식)

```bash
git clone https://github.com/ChangSol/claudecode-dashboard ~/cc-dash
```

그 다음 `statusLine.command`를 `~/cc-dash/scripts/statusline.sh`로 지정하고, 토글 커맨드가 필요하면 `commands/ccd.md`를 `~/.claude/commands/`에 복사한 뒤 스크립트 경로를 체크아웃 위치로 수정하세요.

---

## `/cc-dash:ccd` 커맨드

Claude Code 플러그인 슬래시 커맨드는 `<plugin-name>:` 네임스페이스 접두사가 필수라 모든 호출은 `/cc-dash:ccd …` 형태입니다(짧은 `/ccd`는 라우팅되지 않음). 짧은 형태를 원하면 `~/.claude/commands/ccd.md`에 사용자 레벨 별칭을 만드세요 — 아래 [별칭 안내](#짧은-커맨드-별칭-선택)를 참조하세요.

| 사용법 | 동작 |
|---|---|
| `/cc-dash:ccd list` *(또는 `ls`, `status`)* | 전체 위젯 ON/off 표시 |
| `/cc-dash:ccd toggle CLOCK GIT` | 위젯 1개 이상 토글 |
| `/cc-dash:ccd on BUDGET` | 강제 ON |
| `/cc-dash:ccd off RATE_5H RATE_7D` | 강제 OFF |
| `/cc-dash:ccd reset` | 기본값 복원 |
| `/cc-dash:ccd all-on` / `/cc-dash:ccd all-off` | 일괄 ON/OFF |
| `/cc-dash:ccd refresh` | budget 캐시 비우기 + statusLine 경로 재배선 |
| `/cc-dash:ccd help` | 사용법 |

위젯 키(대소문자 무관):

```
CLOCK  MODEL  DURATION  API_DUR  CTX  TOKEN  COST  LINES  BUDGET
RATE_5H  RATE_7D  RATE_MODEL  RATE_API  PERM  STYLE  VERSION  GIT  PROJECT  SESSION
```

상태는 `~/.config/cc-dash/widgets.conf`에 저장됩니다(`CC_DASH_CONFIG`로 재정의 가능). 파일은 순수 `KEY=0/1` 형식이라 직접 편집해도 됩니다.

### 짧은 커맨드 별칭 (선택)

매번 `/cc-dash:ccd`를 입력하기 번거로우면 `~/.claude/commands/`에 사용자 레벨 별칭을 만드세요:

`~/.claude/commands/ccd.md`:

```markdown
---
description: alias for /cc-dash:ccd
argument-hint: "[list|toggle|on|off|reset|all-on|all-off|refresh] [KEY ...]"
---

/cc-dash:ccd $ARGUMENTS
```

`~/.claude/commands/ccd-setup.md`:

```markdown
---
description: alias for /cc-dash:ccd-setup
---

/cc-dash:ccd-setup
```

저장 후에는 `/ccd list`와 `/ccd-setup`이 플러그인 커맨드로 연결됩니다. 사용자 레벨 커맨드는 개인 설정이며 플러그인에 포함되지 않으므로, 짧은 형태를 원하는 사람이 각자 1회 설정합니다.

---

## 위젯 레퍼런스

| 키 | 기본 | 설명 | 예시 | 행 |
|---|---|---|---|---|
| `MODEL`    | on  | 현재 모델 표시명 | `🧠 Opus 4.7 (1M context)`      | 1 |
| `DURATION` | on  | 세션 시작 이후 경과 시간 | `⏱  dur 22m23s`                 | 1 |
| `API_DUR`  | **off** | API 호출에 쓴 누적 시간 (경과 시간 중 실제 대기분) | `🌐 api 4m32s`              | 1 |
| `CTX`      | on  | 컨텍스트 사용률 — 페이로드가 주면 사용/전체 토큰 병기 | `🪟 ctx 25% (50.0K/200.0K)`     | 1 |
| `TOKEN`    | on  | 세션 누적 입력 토큰 | `💬 token 58.3K`                | 1 |
| `COST`     | on  | 세션 누적 비용 — 5분 이상이면 시간당 소진율 병기 | `💸 cost $1.66 (~$4.5/h)`       | 1 |
| `LINES`    | on  | 세션 중 추가/삭제한 코드 라인 수 | `✏️  +120/-34`                  | 1 |
| `BUDGET`   | **off** | 오늘 지출 대비 일일 예산 — JSONL 스캔, 종량제 플랜용 | `💰 budget $4.21/$15 (28%)`| 1 |
| `RATE_5H`  | on  | 5시간 리밋 사용률 + 리셋 타이머 (🔥 페이스 경고) | `⏳ now 19% reset 3h8m`         | 2 |
| `RATE_7D`  | on  | 주간(7일) 리밋 사용률 + 리셋 타이머 (🔥 페이스 경고) | `⏳ week 2% reset 6d22h`        | 2 |
| `RATE_MODEL` | on | 모델별 주간 리밋 — 데이터가 없으면 자동 숨김 | `⏳ Fable 26% reset 4d2h`      | 2 |
| `RATE_API` | **off** | `RATE_MODEL`의 데이터 출처를 API 조회로 확보 (opt-in, OAuth 토큰 사용) | — | 2 |
| `PERM`     | **off** | 현재 권한 모드 (ask·plan·accept·auto·bypass) | `🔒 perm ask`               | 3 |
| `STYLE`    | **off** | 활성 output style 이름 | `🎨 style Explanatory`      | 3 |
| `VERSION`  | on  | 실행 중인 Claude Code 버전 | `🚀 cc v2.1.116`                | 3 |
| `GIT`      | on  | 현재 브랜치 — `*`는 merge/rebase 진행 중 | `🔀 git: main` / `🔀 git: main*`| 3 |
| `PROJECT`  | **off** | 작업 디렉터리 이름 | `📁 proj: cc-dash`          | 3 |
| `SESSION`  | **off** | 세션 ID 앞 8자 | `🆔 ab12cd34`               | 3 |
| `CLOCK`    | on  | 현재 날짜·시각 | `🕐 2026.04.21 13:03`           | 3 (맨 오른쪽) |

컨텍스트 %, `now`(5h), `week`(7d), budget %는 동일한 임계 색상을 공유합니다: 녹색 → 주황(≥50%) → 빨강(≥80%).

사용량 부가 표시(별도 토글 없음 — 부모 위젯을 따라갑니다):
- `CTX`는 페이로드에 `context_window_size`가 오면 `(사용/전체)`를 병기합니다.
- `COST`는 세션이 5분을 넘으면 시간당 소진율 추정치(`~$X.X/h`)를 병기합니다.
- `RATE_5H` / `RATE_7D`는 사용률이 윈도 경과율보다 15%p 이상 앞서면 🔥를 붙입니다 — 리셋 전에 리밋을 소진할 페이스라는 뜻입니다.
- `RATE_MODEL`은 모델별 주간 윈도마다 세그먼트 하나를 렌더링합니다 — 색상/타이머/🔥 처리는 `RATE_7D`와 동일하고 모델명으로 라벨링됩니다(`Fable 26%`). 데이터가 없으면 자동 숨김입니다. **현재 Claude Code(2.1.220 확인)의 statusLine 페이로드 `rate_limits`에는 `five_hour`·`seven_day` 둘만 들어오므로**, 모델별 값을 보려면 아래 `RATE_API`를 켜야 합니다. 향후 페이로드에 `seven_day_opus` 류 필드가 추가되면 그 값을 우선 사용합니다(네트워크 조회 없음).

---

## 커스터마이징

### Budget 위젯 (opt-in)

`/cc-dash:ccd on BUDGET`으로 일일 지출 트래커를 켭니다. 오늘의 `~/.claude/projects/**/*.jsonl`을 순회하며 토큰 사용량 × 모델 단가를 합산합니다. 결과는 `~/.cache/cc-dash-budget`에 60초간 캐시됩니다. 캐시가 만료되기 전에 갱신하려면 `/cc-dash:ccd refresh`를 실행하세요.

> **참고:** budget 위젯은 토큰 종량제 플랜용으로 설계되었습니다. Claude 구독 플랜을 쓴다면 실제 비용을 반영하지 않습니다.

단가는 **모델별**로 적용됩니다: JSONL 각 라인의 `model` 필드가 가격 티어를 결정합니다 — Opus $5/$25, Fable/Mythos $10/$50, Sonnet $3/$15, Haiku $1/$5 per Mtok(캐시 쓰기 1.25×, 캐시 읽기는 input의 0.1×). `model` 필드가 없는 라인은 Opus 티어로 폴백합니다.

| 변수 | 기본값 | 의미 |
|---|---|---|
| `CC_DASH_BUDGET`       | `15`    | 일일 예산(USD) |
| `CC_DASH_RATE_INPUT`   | `5000`  | $/Mtok × 1000, input |
| `CC_DASH_RATE_OUTPUT`  | `25000` | output |
| `CC_DASH_RATE_CACHE_W` | `6250`  | cache_creation |
| `CC_DASH_RATE_CACHE_R` | `500`   | cache_read |
| `CC_DASH_CACHE`        | `~/.cache/cc-dash-budget` | 캐시 파일 경로 |
| `CC_DASH_CONFIG`       | `~/.config/cc-dash/widgets.conf` | 위젯 토글 파일 |

`CC_DASH_RATE_*` 변수를 **하나라도** 설정하면 레거시 단일 단가 모드로 전환됩니다: 모델과 무관하게 모든 라인에 해당 단가가 적용됩니다(할인/인트로 가격에 유용). 설정하지 않은 변수는 위 표의 기본값으로 폴백하므로, 완전한 커스텀 가격을 원하면 4개를 모두 설정하세요.

### 모델별 주간 리밋 (RATE_API, opt-in)

`/cc-dash:ccd on RATE_API`로 켭니다. Claude Code가 statusLine 페이로드에 모델별 윈도를 넣어주지 않기 때문에, 이 스위치는 Anthropic의 `GET /api/oauth/usage` 응답에서 `limits[]` 중 모델 스코프 항목(`Fable` 등)을 직접 받아옵니다. 서버가 주는 `display_name`을 그대로 라벨로 씁니다.

> **⚠️ 켜기 전에 알아둘 것**
> - **OAuth 액세스 토큰을 읽습니다** — `~/.claude/.credentials.json`(없으면 macOS 키체인 `Claude Code-credentials`). 토큰은 어디에도 출력·기록되지 않고 요청 헤더로만 쓰입니다. 토큰이 만료돼 있으면 조회를 건너뜁니다(자격증명 파일에 쓰지 않음 — 갱신은 Claude Code 몫).
> - **비공개 엔드포인트입니다** — 문서화된 API가 아니라 Claude Code가 내부적으로 쓰는 경로입니다. 스키마가 바뀌면 세그먼트가 조용히 사라질 뿐 statusLine은 깨지지 않습니다.
> - 기본값은 OFF입니다. 끈 상태에서는 네트워크 요청도, 자격증명 읽기도 전혀 없습니다.

statusLine 자체는 여전히 네트워크를 타지 않습니다. `cc-dash-usage-fetch.sh`가 백그라운드에서 캐시(`~/.cache/cc-dash-usage`)를 갱신하고, 렌더는 그 캐시만 읽습니다. 캐시가 TTL을 넘으면 **직전 값을 그대로 보여주면서** 백그라운드 갱신을 1회 띄웁니다(깜빡임 방지). 즉시 갱신은 `/cc-dash:ccd refresh`.

| 변수 | 기본값 | 의미 |
|---|---|---|
| `CC_DASH_USAGE_CACHE` | `~/.cache/cc-dash-usage` | 캐시 파일 경로 |
| `CC_DASH_USAGE_TTL`   | `300`  | 캐시 유효 시간(초) |
| `CC_DASH_USAGE_MIN_INTERVAL` | `60` | 백그라운드 갱신 최소 간격(초) |
| `CC_DASH_USAGE_TIMEOUT` | `6`  | curl 타임아웃(초) |
| `CC_DASH_USAGE_URL`   | `https://api.anthropic.com/api/oauth/usage` | 조회 엔드포인트 |
| `CC_DASH_CREDENTIALS` | `~/.claude/.credentials.json` | 자격증명 파일 경로 |

`RATE_MODEL`을 끄면 `RATE_API`가 켜져 있어도 조회하지 않습니다(표시할 곳이 없으므로). 이 조합은 `/cc-dash:ccd list` 등 설정을 조회·변경할 때 `warning:`으로 알려줍니다. 진단이 필요하면 `bash scripts/cc-dash-usage-fetch.sh -v`를 직접 실행하세요 — 실패 원인을 stderr로 한 줄 출력합니다.

### 터미널 폭 클리핑

`$COLUMNS`가 설정되어 있으면 1행이 잘려서 좁은 터미널에서도 2·3행이 항상 보입니다. 자동 감지를 켜려면 `~/.bashrc`에 추가하세요:

```bash
export COLUMNS
```

### 레거시 환경변수 토글

구버전 opt-in 환경변수도 여전히 동작하며 설정 파일 상태를 재정의합니다:
- `CC_DASH_SHOW_SESSION=1` → `PROJECT` + `SESSION` ON
- `CC_DASH_SHOW_BUDGET=1`  → `BUDGET` ON

---

## 성능 노트

- **Fast path: fork 0회.** 일반 렌더에서 `jq`, `awk`, `sed`, `cat`, `date` 없음 — bash 내장만 사용합니다(`printf -v '%(…)T'`, `[[`, `read`).
- **Budget 위젯**: 캐시가 식었을 때만 `find -newermt` 1회 + `awk` 1회(~1초). 캐시 히트는 캐시 파일 `read` 1회(~5ms)입니다.
- **RATE_API 위젯**: 렌더는 항상 캐시 `read` 1회입니다. 캐시가 식으면 fetcher를 백그라운드로 detach해 띄우고(stdout/stderr 차단) 렌더는 기다리지 않습니다 — 최소 간격 60초로 spawn을 억제합니다.
- **후행 공백 트릭**: 출력 전에 모든 공백을 NBSP(` `)로 치환해 터미널이 공백을 잘라내지 않고, Claude Code의 dim 속성이 줄에 번지지 않게 합니다(`\x1b[0m` 접두).

---

## 호환성

- **셸**: bash ≥ 4.3 (4.2의 `printf -v '%(…)T'`와 4.3의 `local -n` nameref 필요). macOS `/bin/bash`는 3.2라 **미지원** — `brew install bash` 후 `/cc-dash:ccd-setup`이 절대경로를 배선하게 하세요. Windows Git Bash에서 동작합니다.
- **Claude Code**: `statusLine` 훅 JSON 페이로드(모델, 비용, 리밋, 세션 필드)를 사용합니다. 해당 필드를 내보내는 모든 Claude Code 빌드를 지원합니다.
- **플랫폼**: Linux, macOS(brew bash), Windows(Git Bash / WSL).

---

## 한계

- **Git dirty는 휴리스틱입니다.** `MERGE_HEAD` / `ORIG_HEAD` / `rebase-merge` 존재 여부로 `*`를 결정합니다. 실제 `git status`는 fork가 필요합니다.
- **Budget 단가는 수동 관리입니다.** JSONL 로그에는 `cost_usd` 필드가 직접 저장되지 않아 cc-dash가 토큰 수 × 모델별 단가로 계산합니다. 환경변수를 Anthropic 가격과 동기화하세요.
- **statusLine은 플러그인이 선언할 수 없습니다.** Claude Code 플러그인 스키마에 현재 `statusLine` 필드가 없어, 설치 후 사용자가 직접 `settings.json`에 두 줄을 추가해야 합니다.
- **JSONL 스키마 드리프트.** Claude Code가 트랜스크립트의 usage 필드명을 바꾸면 budget 위젯의 `awk` 정규식을 갱신해야 합니다.
- **모델별 리밋은 statusLine 페이로드에 없습니다.** `rate_limits`는 `five_hour`·`seven_day`만 담고 있어 `RATE_MODEL`은 opt-in `RATE_API`(비공개 `/api/oauth/usage` 조회, `curl` 필요) 없이는 비어 있습니다. Anthropic이 스키마를 바꾸면 세그먼트가 조용히 사라집니다.

---

## 프로젝트 구조

```
claudecode-dashboard/         # 저장소 루트 (= 마켓플레이스)
├── .claude-plugin/
│   └── marketplace.json      # 마켓플레이스 매니페스트 (플러그인 목록)
├── plugins/
│   └── cc-dash/              # cc-dash 플러그인
│       ├── .claude-plugin/
│       │   └── plugin.json   # 플러그인 매니페스트
│       ├── commands/
│       │   ├── ccd.md            # /cc-dash:ccd 슬래시 커맨드 — 위젯 토글
│       │   └── ccd-setup.md      # /cc-dash:ccd-setup — settings.json 원샷 배선
│       └── scripts/
│           ├── statusline.sh     # statusLine 렌더러
│           ├── cc-dash-config.sh # 위젯 토글 CLI + 대화식 메뉴
│           ├── cc-dash-setup.sh  # settings.json 패처 (/cc-dash:ccd-setup 이 호출)
│           └── cc-dash-usage-fetch.sh # 모델별 리밋 조회 → 캐시 (RATE_API 전용)
├── LICENSE
├── README.md                 # 한국어 (기본)
└── README.en.md              # English
```

---

## 수동 테스트

```bash
# 합성 페이로드로 렌더
echo '{"model":{"display_name":"Opus 4.7 (1M context)","id":"claude-opus-4-7"},"output_style":{"name":"default"},"context_window_size":200000,"used_percentage":25,"total_input_tokens":50000,"total_duration_ms":120000,"total_api_duration_ms":95000,"total_cost_usd":0.5,"total_lines_added":120,"total_lines_removed":34,"session_id":"abc12345","current_dir":".","permission_mode":"default","version":"2.1.116","rate_limits":{"five_hour":{"used_percentage":7,"resets_at":1745289600},"seven_day":{"used_percentage":26,"resets_at":1745808000}}}' \
  | bash scripts/statusline.sh

# 실행 시간 측정
time (echo '{…}' | bash scripts/statusline.sh)

# 전체 위젯 ON
CC_DASH_SHOW_SESSION=1 CC_DASH_SHOW_BUDGET=1 bash scripts/statusline.sh <<< '{…}'

# refresh — 실제 settings.json / 캐시를 건드리지 않고 확인
CC_DASH_SETTINGS=/tmp/x.json CC_DASH_CACHE=/tmp/x-cache bash scripts/cc-dash-config.sh refresh

# RATE_API — 모델별 리밋 조회 단독 실행 (진단 출력은 stderr, 토큰은 노출 없음)
CC_DASH_USAGE_CACHE=/tmp/x-usage bash scripts/cc-dash-usage-fetch.sh -v && cat /tmp/x-usage
```

기본 렌더의 기대 출력(`widgets.conf`가 아직 없는 상태 — clock·git 위젯은 사용자 환경을 반영하며, 위 `resets_at`은 과거 시각이라 `reset` 타이머가 표시되지 않습니다):

```
🧠 Opus 4.7 (1M context) │ ⏱  dur 2m0s │ 🪟 ctx 25% (50.0K/200.0K) │ 💬 token 50.0K │ 💸 cost $0.50 │ ✏️  +120/-34
⏳ now 7% │ ⏳ week 26%
🚀 cc v2.1.116 │ 🔀 git — │ 🕐 2026.04.21 14:53
```

`API_DUR`(`🌐 api 1m35s`)와 `STYLE`(`🎨 style default`)은 기본 OFF입니다 — `/cc-dash:ccd on API_DUR STYLE`로 확인하세요.

Windows Git Bash 기준 일반적인 실측 시간은 **100–140ms**입니다(bash 기동과 JSON 파싱이 지배적이며, budget 위젯은 기본 OFF라 JSONL 스캔이 없습니다). Linux/macOS 네이티브 bash 5.2는 대체로 더 빠릅니다.

---

## 라이선스

MIT.
