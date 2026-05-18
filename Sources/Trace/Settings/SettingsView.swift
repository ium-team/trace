import AppKit
import SwiftUI
import UserNotifications

struct SettingsView: View {
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
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("알림")
                        Text(notificationStatusDescription)
                            .font(.caption)
                            .foregroundStyle(notificationStatus == .denied ? .orange : .secondary)
                    }
                    Spacer()
                    Button("알림 설정 열기", action: openNotificationSettings)
                }
            }

            Section("캡처") {
                Picker("기본 캡처 방식", selection: $draft.defaultCaptureMode) {
                    ForEach(CaptureMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                TextField("전역 단축키", text: $draft.globalShortcut)
                    .disabled(true)
                Text("현재 단축키: command+shift+2, command+shift+3. 단축키를 누르면 캡처 오버레이가 바로 열리고, 오버레이 안에서 범위와 방식을 바꿀 수 있습니다.")
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

    private var notificationStatusDescription: String {
        switch notificationStatus {
        case .authorized, .provisional:
            "macOS 시스템 설정에서 켜져 있습니다."
        case .denied:
            "macOS 시스템 설정에서 꺼져 있습니다."
        case .notDetermined:
            "아직 macOS 알림 권한이 정해지지 않았습니다."
        case .ephemeral:
            "현재 세션에서만 허용되어 있습니다."
        @unknown default:
            "알림 상태를 확인할 수 없습니다."
        }
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
