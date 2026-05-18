# Trace 아키텍처

## 목표

아키텍처 목표는 캡처, 저장, 전달, 히스토리 기능을 서로 분리해 변경 비용을 낮추는 것이다. MVP에서는 Trace 자체 캡처 오버레이를 구현하되, 과한 추상화보다 명확한 모듈 경계를 우선한다.

## 상위 구조

```text
TraceApp
  AppShell
  Capture
  Delivery
  History
  Storage
  Settings
  Shared
```

## 모듈 책임

### AppShell

앱의 진입점과 macOS 앱 생명주기를 담당한다.

주요 책임:

- 메뉴바 앱 구성
- 앱 시작/종료
- 전역 단축키 등록
- 설정 창 열기
- 히스토리 창 열기
- 캡처 흐름 시작

### Capture

캡처 UI와 캡처 결과 생성을 담당한다.

주요 책임:

- 영역 선택 오버레이 표시
- 드래그 영역 계산
- 선택 영역 캡처
- 전체 화면 캡처
- 캡처 취소 처리
- 캡처 결과 객체 생성

### Storage

캡처 이미지와 메타데이터 저장을 담당한다.

주요 책임:

- 날짜별 폴더 생성
- 파일명 생성
- PNG 저장
- 썸네일 저장
- 메타데이터 읽기/쓰기
- 저장 위치 변경 처리

### Clipboard

클립보드 관련 동작을 담당한다.

주요 책임:

- 자동 복사 설정에 따른 캡처 이미지 복사
- 히스토리 이미지 다시 복사
- 복사 실패 처리

### Delivery

앱으로 자동 전달 캡처 흐름을 담당한다.

주요 책임:

- 실행 중인 앱 목록 조회
- 전달 대상 선택 창 표시
- 전달 대상 선택 처리
- 선택한 앱 활성화
- 붙여넣기 이벤트 전송
- 건너뛰기 처리

### History

최근 캡처와 과거 캡처 이력을 담당한다.

주요 책임:

- 최근 캡처 목록 표시
- 날짜별 히스토리 그룹 표시
- 이미지 미리보기
- Finder에서 보기
- 이미지 다시 복사
- 캡처 이름 편집
- 캡처 삭제
- 캡처 고정 및 북마크 토글

### Settings

사용자 설정을 담당한다.

주요 책임:

- 저장 위치 설정
- 기본 캡처 전역 단축키 설정
- 앱으로 전달 캡처 전역 단축키 설정
- 기본 캡처 방식 설정
- 기본 캡처 완료 후 동작 설정
- 앱으로 전달 캡처 완료 후 동작 설정
- macOS 알림 설정으로 이동

## 핵심 도메인 모델

### CaptureMode

```text
copyOnly
deliverToApp
```

### CaptureItem

```text
id
title
filePath
thumbnailPath
createdAt
width
height
captureMode
deliveredAppName
deliveryState
isPinned
isBookmarked
```

### DeliveryState

```text
none
skipped
delivered
failed
```

### AppDestination

```text
bundleIdentifier
name
icon
isActive
```

### AppWindowDestination

```text
title
isMain
accessibilityElement
```

### Settings

```text
saveDirectory
basicCaptureShortcut
deliveryCaptureShortcut
defaultCaptureMode
basicCaptureAction
deliveryCaptureAction
```

## 핵심 흐름

### 기본 캡처

```text
GlobalShortcut
  -> CaptureOverlay(select area/full screen and copy/deliver while active)
  -> CaptureResult
  -> Clipboard.copy
  -> Storage.save if basicCaptureAction is copyAndSave
  -> Notification.showSavedLocation if saved
  -> History.refresh if saved
```

### 앱으로 자동 전달 캡처

```text
GlobalShortcut
  -> CaptureOverlay(select area/full screen and copy/deliver while active)
  -> CaptureResult
  -> Clipboard.copy
  -> Storage.save if deliveryCaptureAction is copySaveAndDeliver
  -> DeliveryDestinationPicker
  -> DeliveryWindowPicker
  -> Delivery.deliver
  -> History.refresh if saved
```

### 히스토리에서 다시 복사

```text
HistoryWindow
  -> SelectCaptureItem
  -> Clipboard.copy
```

## 설계 원칙

- Capture는 저장 위치나 히스토리 UI를 알지 않는다.
- Storage는 UI를 알지 않는다.
- Delivery는 캡처 방식을 직접 결정하지 않고 전달 대상 선택과 전달만 담당한다.
- History는 파일 시스템 상태와 메타데이터를 읽어 표시한다.
- Settings는 전역 상태처럼 흩어지지 않고 한 모듈에서 관리한다.
