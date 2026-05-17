# AGENTS.md

## 프로젝트 개요

Trace는 macOS용 캡처 앱이다. MVP의 핵심은 빠른 영역 캡처, 날짜별 자동 저장, 클립보드 자동 복사, 앱으로 자동 전달 캡처, 최근 및 과거 캡처 히스토리다.

제품 문서는 `docs/`에 있고, 개발 문서는 `docs/development/`에 있다. 구현 전에는 반드시 관련 문서를 먼저 읽고, 문서와 충돌하는 결정을 임의로 넣지 않는다.

## Codex 작업 원칙

- 제품 흐름은 `docs/mvp-spec.md`를 기준으로 한다.
- 개발 구조는 `docs/development/architecture.md`를 기준으로 한다.
- 작업을 시작하기 전에 관련 파일을 읽고 기존 패턴을 따른다.
- 기능 구현은 작고 검증 가능한 단위로 나눈다.
- 사용자 요청과 무관한 리팩터링은 하지 않는다.
- 구현 중 제품 문서와 기술 문서가 어긋나면 코드만 바꾸지 말고 문서도 함께 갱신한다.
- macOS 권한, 전역 단축키, 화면 캡처, 앱 자동 전달은 사용자 경험에 직접 영향을 주므로 실패 상태를 반드시 고려한다.
- AI/OCR/스마트 분류는 MVP 범위가 아니므로 구현하지 않는다.

## 권장 기술 스택

- Language: Swift
- UI: SwiftUI + AppKit
- App shell: macOS menu bar app
- Persistence: JSON metadata first, SQLite/SwiftData later if needed
- Image format: PNG
- Tests: XCTest

## 구현 우선순위

1. 앱 셸과 메뉴바
2. 설정 저장
3. 전역 단축키
4. 영역 캡처 오버레이
5. 날짜별 저장과 클립보드 복사
6. 복사만 하기 캡처 흐름
7. 앱으로 자동 전달 캡처 흐름
8. 히스토리 UI
9. 안정화와 실패 상태 처리

## MVP에서 하지 않을 것

- AI 기반 파일명 생성
- AI 기반 폴더 분류
- OCR 검색
- 이미지 주석 도구
- 클라우드 동기화
- 팀 공유
- 앱별 커스텀 전달 규칙

## 문서 목록

- `README.md`: 프로젝트 진입점
- `docs/product-idea.md`: 제품 아이디어
- `docs/mvp-spec.md`: MVP 제품 명세
- `docs/roadmap.md`: 제품 로드맵
- `docs/development/tech-stack.md`: 기술 스택
- `docs/development/architecture.md`: 앱 아키텍처
- `docs/development/feature-specs.md`: 기능별 개발 명세
- `docs/development/data-and-storage.md`: 저장 구조와 메타데이터
- `docs/development/implementation-plan.md`: 구현 순서
- `docs/development/codex-workflow.md`: Codex 작업 방식
- `docs/development/testing.md`: 테스트 전략

