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
    @State private var runningDeliveryApps: [DeliveryAppOption] = []

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
                Toggle("캡처 후 자동 복사", isOn: $draft.copyToClipboardByDefault)
                Text("끄면 기본 캡처는 클립보드에 자동 복사하지 않습니다. 앱 전달은 붙여넣기 기반이라 전달 순간에는 클립보드를 사용합니다.")
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
                Picker("전달 대상", selection: $draft.deliveryTargetMode) {
                    ForEach(TraceSettings.DeliveryTargetMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                if draft.deliveryTargetMode == .fixedApp {
                    Picker("지정 앱", selection: fixedDeliveryAppSelection) {
                        Text("선택 안 함").tag("")
                        ForEach(deliveryAppOptions) { app in
                            Text(app.name).tag(app.bundleIdentifier)
                        }
                    }
                    Picker("윈도우 처리", selection: $draft.fixedDeliveryAppWindowMode) {
                        ForEach(TraceSettings.FixedAppWindowMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                }
                TextField("전역 단축키", text: $draft.deliveryCaptureShortcut)
                Text("지정 앱은 현재 실행 중인 앱에서 선택합니다. 지정 앱이 전달 시점에 꺼져 있으면 실패 알림을 보냅니다. 저장하지 않는 전달 캡처는 히스토리에 남지 않습니다.")
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
            refreshRunningDeliveryApps()
            await refreshPermissionStatuses()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshRunningDeliveryApps()
            Task {
                await refreshPermissionStatuses()
            }
        }
        .onReceive(Self.permissionRefreshTimer) { _ in
            refreshRunningDeliveryApps()
            Task {
                await refreshPermissionStatuses()
            }
        }
    }

    private var fixedDeliveryAppSelection: Binding<String> {
        Binding(
            get: {
                draft.fixedDeliveryAppBundleIdentifier ?? ""
            },
            set: { bundleIdentifier in
                guard !bundleIdentifier.isEmpty else {
                    draft.fixedDeliveryAppBundleIdentifier = nil
                    draft.fixedDeliveryAppName = nil
                    return
                }

                draft.fixedDeliveryAppBundleIdentifier = bundleIdentifier
                draft.fixedDeliveryAppName = runningDeliveryApps.first {
                    $0.bundleIdentifier == bundleIdentifier
                }?.name ?? draft.fixedDeliveryAppName
            }
        )
    }

    private var deliveryAppOptions: [DeliveryAppOption] {
        guard let bundleIdentifier = draft.fixedDeliveryAppBundleIdentifier,
              !bundleIdentifier.isEmpty,
              !runningDeliveryApps.contains(where: { $0.bundleIdentifier == bundleIdentifier })
        else {
            return runningDeliveryApps
        }

        let name = draft.fixedDeliveryAppName ?? bundleIdentifier
        return [DeliveryAppOption(bundleIdentifier: bundleIdentifier, name: "\(name) (실행 중 아님)")] + runningDeliveryApps
    }

    private func refreshRunningDeliveryApps() {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        runningDeliveryApps = NSWorkspace.shared.runningApplications
            .filter { app in
                app.processIdentifier != ownPID &&
                app.activationPolicy == .regular &&
                app.bundleIdentifier?.isEmpty == false &&
                app.localizedName?.isEmpty == false
            }
            .compactMap { app in
                guard let bundleIdentifier = app.bundleIdentifier,
                      let name = app.localizedName
                else {
                    return nil
                }
                return DeliveryAppOption(bundleIdentifier: bundleIdentifier, name: name)
            }
            .uniquedByBundleIdentifier()
            .sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
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

private struct DeliveryAppOption: Identifiable, Hashable {
    var id: String { bundleIdentifier }
    var bundleIdentifier: String
    var name: String
}

private extension Array where Element == DeliveryAppOption {
    func uniquedByBundleIdentifier() -> [DeliveryAppOption] {
        var seen = Set<String>()
        return filter { seen.insert($0.bundleIdentifier).inserted }
    }
}
