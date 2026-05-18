import SwiftUI

struct SettingsView: View {
    @Bindable var settingsStore: SettingsStore
    @State private var draft: TraceSettings

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
