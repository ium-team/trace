import AppKit
import Combine
import SwiftUI
import UserNotifications

struct SettingsView: View {
    private static let permissionRefreshTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    @Bindable var settingsStore: SettingsStore
    @State private var draft: TraceSettings
    @State private var hasScreenRecordingPermission = PermissionService.hasScreenRecordingPermission
    @State private var hasAccessibilityPermission = PermissionService.hasAccessibilityPermission
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        self._draft = State(initialValue: settingsStore.settings)
    }

    var body: some View {
        Form {
            Section("저장") {
                HStack {
                    TextField("저장 위치", text: $draft.saveDirectory)
                    Button {
                        chooseDirectory()
                    } label: {
                        Label("선택", systemImage: "folder")
                    }
                }
                Picker("저장 이름", selection: $draft.fileNameRule) {
                    ForEach(TraceSettings.FileNameRule.allCases) { rule in
                        Text(rule.title).tag(rule)
                    }
                }
                if draft.fileNameRule == .dateTime {
                    Picker("날짜 형식", selection: $draft.dateFileNameFormat) {
                        ForEach(TraceSettings.DateFileNameFormat.allCases) { format in
                            Text(format.title).tag(format)
                        }
                    }
                } else {
                    Picker("순서 형식", selection: $draft.sequenceStyle) {
                        ForEach(TraceSettings.SequenceStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                }
            }

            Section("캡처") {
                Picker("기본 캡처 방식", selection: $draft.defaultCaptureMode) {
                    ForEach(CaptureMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                Text("두 단축키는 같은 캡처 오버레이를 열고, 처음 선택된 캡처 방식만 다릅니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("기본 캡처") {
                Picker("완료 후 동작", selection: $draft.basicCaptureAction) {
                    ForEach(TraceSettings.BasicCaptureAction.allCases) { action in
                        Text(action.title).tag(action)
                    }
                }
                TextField("전역 단축키", text: $draft.basicCaptureShortcut)
                Text("예: command+shift+2")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("앱으로 전달 캡처") {
                Picker("완료 후 동작", selection: $draft.deliveryCaptureAction) {
                    ForEach(TraceSettings.DeliveryCaptureAction.allCases) { action in
                        Text(action.title).tag(action)
                    }
                }
                TextField("전역 단축키", text: $draft.deliveryCaptureShortcut)
                Text("전달은 붙여넣기 기반이라 항상 먼저 클립보드에 복사합니다. 저장하지 않는 전달 캡처는 히스토리에 남지 않습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("권한") {
                PermissionRow(
                    title: "Screen Recording",
                    granted: hasScreenRecordingPermission,
                    action: PermissionService.openScreenRecordingSettings
                )
                PermissionRow(
                    title: "Accessibility",
                    granted: hasAccessibilityPermission,
                    action: openAccessibilitySettings
                )
                PermissionRow(
                    title: "Notifications",
                    granted: canPostNotifications,
                    action: openNotificationSettings
                )
            }

        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 620, minHeight: 480)
        .onChange(of: draft) { _, newValue in
            settingsStore.update(newValue)
        }
        .onChange(of: settingsStore.settings) { _, newValue in
            draft = newValue
        }
        .task {
            await refreshPermissionStatuses()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task {
                await refreshPermissionStatuses()
            }
        }
        .onReceive(Self.permissionRefreshTimer) { _ in
            Task {
                await refreshPermissionStatuses()
            }
        }
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: draft.saveDirectory)
        if panel.runModal() == .OK, let url = panel.url {
            draft.saveDirectory = url.path
        }
    }

    private func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationStatus = settings.authorizationStatus
    }

    private func refreshPermissionStatuses() async {
        hasScreenRecordingPermission = PermissionService.hasScreenRecordingPermission
        hasAccessibilityPermission = PermissionService.hasAccessibilityPermission
        await refreshNotificationStatus()
    }

    private var canPostNotifications: Bool {
        notificationStatus == .authorized || notificationStatus == .provisional
    }

    private func openNotificationSettings() {
        PermissionService.openNotificationSettings()
        Task {
            await refreshNotificationStatus()
        }
    }

    private func openAccessibilitySettings() {
        PermissionService.requestAccessibilityPermission()
        PermissionService.openAccessibilitySettings()
    }
}

struct PermissionRow: View {
    let title: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack {
            Label(title, systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(granted ? .green : .orange)
            Spacer()
            Button("설정 열기", action: action)
        }
    }
}
