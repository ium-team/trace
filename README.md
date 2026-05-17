# Trace

Trace는 macOS 기본 캡처 경험을 개선하기 위한 캡처 도구다. 빠른 영역 캡처, 자동 저장, 클립보드 복사, 실행 중인 앱으로의 자동 전달, 최근 및 과거 캡처 히스토리 관리를 핵심으로 한다.

캡처 방식은 두 가지로 나뉜다. 사용자는 캡처 이미지를 클립보드에 자동 복사만 할 수도 있고, 자동 전달 캡처 상태로 캡처한 뒤 현재 실행 중인 앱 중 전달 대상을 선택해 이미지가 해당 앱에 자동으로 들어가게 할 수도 있다.

MVP에서는 AI 기능을 만들지 않는다. 우선 캡처 흐름과 저장, 전달, 히스토리 기능을 안정적으로 구현하고, 이후 AI 기반 자동 파일명 생성, 폴더 분류, OCR 검색으로 확장한다.

## 문서

- [제품 아이디어](docs/product-idea.md)
- [MVP 명세서](docs/mvp-spec.md)
- [로드맵](docs/roadmap.md)

## 개발 문서

- [기술 스택](docs/development/tech-stack.md)
- [아키텍처](docs/development/architecture.md)
- [기능별 개발 명세](docs/development/feature-specs.md)
- [데이터와 저장 구조](docs/development/data-and-storage.md)
- [구현 계획](docs/development/implementation-plan.md)
- [Codex 개발 워크플로우](docs/development/codex-workflow.md)
- [테스트 전략](docs/development/testing.md)
- [Codex 작업 지침](AGENTS.md)

## MVP 핵심 범위

- 전역 단축키로 빠른 캡처 시작
- 영역 선택 캡처
- 날짜별 폴더 자동 저장
- 캡처 이미지 클립보드 자동 복사
- 복사만 하기 모드
- 앱으로 자동 전달 모드
- 최근 캡처 보기
- 날짜별 과거 캡처 이력 보기
