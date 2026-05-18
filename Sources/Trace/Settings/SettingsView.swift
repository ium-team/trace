import AppKit
import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Bindable var settingsStore: SettingsStore
    @State private var draft: TraceSettings
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var isReconcilingNotificationPreference = false
    @State private var shouldEnableNotificationsAfterSystemApproval = false

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
                Toggle("알림센터 알림 표시", isOn: $draft.showSaveNotification)
                notificationPreferenceMessage
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
                    granted: PermissionService.hasScreenRecordingPermission,
                    action: PermissionService.openScreenRecordingSettings
                )
                PermissionRow(
                    title: "Accessibility",
                    granted: PermissionService.hasAccessibilityPermission,
                    action: PermissionService.openAccessibilitySettings
                )
                PermissionRow(
                    title: "Notifications",
                    granted: canPostNotifications,
                    action: openNotificationSettings
                )
            }

            HStack {
                Spacer()
                Button("저장") {
                    settingsStore.update(draft)
                    TraceNotificationCenter.requestIfNeeded(enabled: draft.showSaveNotification)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 620, minHeight: 480)
        .onChange(of: settingsStore.settings) { _, newValue in
            draft = newValue
        }
        .task {
            await refreshNotificationStatus()
            reconcileNotificationPreferenceWithSystem()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task {
                await refreshNotificationStatus()
                reconcileNotificationPreferenceWithSystem()
            }
        }
        .onChange(of: draft.showSaveNotification) { _, enabled in
            guard !isReconcilingNotificationPreference else { return }
            Task {
                await handleNotificationPreferenceChange(enabled: enabled)
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

    private var canPostNotifications: Bool {
        notificationStatus == .authorized || notificationStatus == .provisional
    }

    @ViewBuilder
    private var notificationPreferenceMessage: some View {
        switch notificationStatus {
        case .denied:
            Text("macOS 시스템 설정에서 Trace 알림이 꺼져 있습니다. 여기서 켜려면 먼저 시스템 설정에서 허용해야 합니다.")
                .font(.caption)
                .foregroundStyle(.orange)
        case .notDetermined where draft.showSaveNotification:
            Text("저장하면 macOS 알림 권한을 요청합니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
        default:
            EmptyView()
        }
    }

    private func handleNotificationPreferenceChange(enabled: Bool) async {
        await refreshNotificationStatus()

        guard enabled else {
            shouldEnableNotificationsAfterSystemApproval = false
            return
        }

        switch notificationStatus {
        case .notDetermined:
            _ = await TraceNotificationCenter.requestAuthorization()
            await refreshNotificationStatus()
            if !canPostNotifications {
                forceNotificationPreferenceOff()
            }
        case .denied:
            shouldEnableNotificationsAfterSystemApproval = true
            forceNotificationPreferenceOff()
            PermissionService.openNotificationSettings()
        case .authorized, .provisional:
            break
        case .ephemeral:
            forceNotificationPreferenceOff()
        @unknown default:
            forceNotificationPreferenceOff()
        }
    }

    private func reconcileNotificationPreferenceWithSystem() {
        if shouldEnableNotificationsAfterSystemApproval, canPostNotifications {
            shouldEnableNotificationsAfterSystemApproval = false
            isReconcilingNotificationPreference = true
            draft.showSaveNotification = true
            isReconcilingNotificationPreference = false
            return
        }

        guard draft.showSaveNotification, notificationStatus == .denied else { return }
        forceNotificationPreferenceOff()
    }

    private func forceNotificationPreferenceOff() {
        isReconcilingNotificationPreference = true
        draft.showSaveNotification = false
        isReconcilingNotificationPreference = false
    }

    private func openNotificationSettings() {
        PermissionService.openNotificationSettings()
        Task {
            await refreshNotificationStatus()
            reconcileNotificationPreferenceWithSystem()
        }
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
