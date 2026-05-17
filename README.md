# Trace

Trace는 macOS 기본 캡처 경험을 개선하기 위한 캡처 도구다. MVP에서는 Trace 자체 영역 캡처 오버레이와 전체 화면 캡처를 사용하고, 자동 저장, 클립보드 복사, 실행 중인 앱으로의 자동 전달, 최근 및 과거 캡처 히스토리 관리를 핵심으로 한다.

캡처 방식은 두 가지로 나뉜다. 사용자는 캡처 이미지를 클립보드에 자동 복사만 할 수도 있고, 자동 전달 캡처 상태로 캡처한 뒤 현재 실행 중인 앱 중 전달 대상을 선택해 이미지가 해당 앱에 자동으로 들어가게 할 수도 있다.

MVP에서는 AI 기능을 만들지 않는다. 우선 자체 영역/전체 화면 캡처 흐름과 저장, 전달, 히스토리 기능을 안정적으로 구현하고, 이후 AI 기반 자동 파일명 생성, 폴더 분류, OCR 검색으로 확장한다.

## 문서

- [제품 아이디어](docs/product-idea.md)
- [MVP 명세서](docs/mvp-spec.md)
- [로드맵](docs/roadmap.md)

## 개발 문서

- [기술 스택](docs/development/tech-stack.md)
- [아키텍처](docs/development/architecture.md)
- [기능별 개발 명세](docs/development/feature-specs.md)
- [데이터와 저장 구조](docs/development/data-and-storage.md)
- [macOS 권한 정책](docs/development/permissions.md)
- [앱 자동 전달 정책](docs/development/delivery.md)
- [구현 계획](docs/development/implementation-plan.md)
- [Codex 개발 워크플로우](docs/development/codex-workflow.md)
- [테스트 전략](docs/development/testing.md)
- [Codex 작업 지침](AGENTS.md)

## MVP 핵심 범위

- 전역 단축키로 빠른 캡처 시작
- 캡처 방식 선택 화면
- Trace 자체 오버레이 기반 영역 선택 캡처
- 주 디스플레이 전체 화면 캡처
- 날짜별 폴더 자동 저장
- 캡처 이미지 클립보드 자동 복사
- 복사만 하기 모드
- 앱으로 자동 전달 모드
- 최근 캡처 보기
- 날짜별 과거 캡처 이력 보기

## 실행

개발 실행:

```bash
swift run Trace
```

앱 번들 생성:

```bash
chmod +x scripts/build-app.sh
scripts/build-app.sh
open build/Trace.app
```

기본 단축키:

- 캡처 방식 선택 열기: `command+shift+2`
- 캡처 방식 선택 열기: `command+shift+3`

화면 캡처 권한은 실제 실행 주체에 부여해야 한다. `swift run Trace`로 실행하면 터미널 앱에 Screen Recording 권한이 필요하고, `build/Trace.app`으로 실행하면 Trace 앱에 권한이 필요하다. 앱으로 자동 전달을 사용하려면 Accessibility 권한도 허용해야 한다.

권한을 허용했는데도 계속 다시 묻는 경우:

```bash
scripts/build-app.sh
open build/Trace.app
```

`swift run Trace`와 `open build/Trace.app`을 번갈아 쓰면 macOS가 서로 다른 앱으로 권한을 관리한다. 권한 테스트는 `build/Trace.app` 하나로만 진행하는 것이 좋다. 이미 꼬였다면 시스템 설정의 Screen Recording, Accessibility 목록에서 기존 Trace 항목을 제거한 뒤 `build/Trace.app`을 다시 열어 권한을 새로 허용한다.
