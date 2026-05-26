# 데이터와 저장 구조

## 저장 원칙

MVP에서는 캡처 파일을 사용자가 볼 수 있는 폴더 구조로 저장한다. 앱 내부 데이터베이스에만 묶어두지 않는다.

## 기본 폴더 구조

```text
Trace/
  captures/
    2026-05-17/
      2026-05-17_14-32-08.png
      2026-05-17_14-35-21.png
  thumbnails/
    2026-05-17/
      2026-05-17_14-32-08.jpg
      2026-05-17_14-35-21.jpg
  metadata.json
  settings.json
```

## 캡처 파일명

기본 형식:

```text
YYYY-MM-DD_HH-mm-ss.png
```

충돌 시:

```text
YYYY-MM-DD_HH-mm-ss-2.png
YYYY-MM-DD_HH-mm-ss-3.png
```

## 메타데이터

`metadata.json`은 히스토리 표시를 위한 최소 정보를 저장한다.

예시:

```json
{
  "captures": [
    {
      "id": "2026-05-17_14-32-08",
      "title": "2026-05-17_14-32-08",
      "filePath": "captures/2026-05-17/2026-05-17_14-32-08.png",
      "thumbnailPath": "thumbnails/2026-05-17/2026-05-17_14-32-08.jpg",
      "createdAt": "2026-05-17T14:32:08+09:00",
      "width": 1280,
      "height": 720,
      "captureMode": "deliverToApp",
      "deliveredAppName": "Slack",
      "deliveryState": "delivered",
      "isPinned": false,
      "isBookmarked": false
    }
  ]
}
```

쓰기 정책:

- 메타데이터는 임시 파일에 먼저 쓴 뒤 교체하는 방식으로 원자적으로 갱신한다.
- 메타데이터 쓰기에 실패해도 원본 PNG 저장이 성공했다면 캡처 파일을 삭제하지 않는다.
- 앱 시작 시 `metadata.json`이 손상되어 읽을 수 없으면 백업 파일을 만들고 빈 메타데이터로 복구한다.
- 같은 id가 이미 있으면 파일명 충돌 처리 규칙과 동일하게 suffix를 붙여 새 id를 만든다.
- 이름 편집은 원본 PNG 파일명과 썸네일 파일명을 함께 변경하고 `filePath`, `thumbnailPath`, `title`을 갱신한다.
- 삭제는 원본 PNG, 썸네일, 메타데이터 항목을 함께 제거한다.
- 고정과 북마크는 파일 이동 없이 메타데이터 플래그만 갱신한다.

## 설정

`settings.json`은 사용자의 기본 설정을 저장한다.
현재 선택된 저장 위치는 앱 설정에도 기록해 재실행 시 마지막으로 선택한 위치의 `settings.json`을 다시 불러온다.

예시:

```json
{
  "saveDirectory": "~/Pictures/Trace",
  "globalShortcut": "command+shift+2",
  "copyToClipboardByDefault": true,
  "basicCaptureShortcut": "command+shift+2",
  "deliveryCaptureShortcut": "command+shift+3",
  "defaultCaptureMode": "copyOnly",
  "basicCaptureAction": "copyAndSave",
  "deliveryCaptureAction": "copySaveAndDeliver",
  "deliveryTargetMode": "chooseEachTime",
  "fixedDeliveryAppBundleIdentifier": "com.apple.TextEdit",
  "fixedDeliveryAppName": "TextEdit",
  "fixedDeliveryAppWindowMode": "mostRecentWindow"
}
```

## 히스토리 표시 기준

MVP에서는 현재 선택된 저장 위치 아래의 `metadata.json`을 기준으로 히스토리를 표시한다.

정책:

- 메타데이터에 있는 항목을 최신순으로 보여준다.
- 파일이 삭제된 항목은 누락 상태로 표시한다.
- 앱 밖에서 새 파일을 폴더에 넣어도 자동으로 히스토리에 추가하지 않는다.
- 저장 위치를 바꾸면 새 위치의 `metadata.json`을 읽어 해당 위치의 히스토리만 표시한다.
- 저장 위치를 바꿀 때 기존 위치의 캡처 파일이나 메타데이터를 새 위치로 이동하거나 병합하지 않는다.
- 이전 저장 위치를 다시 선택하면 해당 위치에 남아 있는 `metadata.json` 기준의 히스토리를 다시 표시한다.
- 현재 저장 위치의 메타데이터 항목에 해당하는 파일이 접근 불가능하면 누락 상태로 표시하고, 사용자가 Finder에서 열 때 실패 메시지를 보여준다.

## 썸네일

히스토리 UI 성능을 위해 원본 이미지를 그대로 목록에 사용하지 않는다.

정책:

- 캡처 저장 시 썸네일을 함께 생성한다.
- 썸네일은 원본과 별도 폴더에 저장한다.
- 썸네일 생성에 실패해도 원본 저장은 성공으로 처리한다.
