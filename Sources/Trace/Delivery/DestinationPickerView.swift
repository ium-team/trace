import AppKit
import SwiftUI

struct DestinationPickerView: View {
    let destinations: [AppDestination]
    let onSkip: () -> Void
    let onSelect: (AppDestination) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("전달 대상")
                    .font(.headline)
                Spacer()
                Button("건너뛰기", action: onSkip)
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            if destinations.isEmpty {
                ContentUnavailableView("실행 중인 앱 없음", systemImage: "app.dashed")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(destinations) { destination in
                    Button {
                        onSelect(destination)
                    } label: {
                        HStack(spacing: 12) {
                            Image(nsImage: destination.icon)
                                .resizable()
                                .frame(width: 28, height: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(destination.name)
                                    .font(.body)
                                if destination.isActive {
                                    Text("현재 활성 앱")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 520)
    }
}

struct WindowPickerView: View {
    let app: AppDestination
    let windows: [AppWindowDestination]
    let appSpecificDestinations: [AppSpecificDestination]
    let onBack: () -> Void
    let onSkip: () -> Void
    let onSelectWindow: (AppWindowDestination) -> Void
    let onSelectAppSpecificDestination: (AppSpecificDestination) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("뒤로", action: onBack)
                Text(app.name)
                    .font(.headline)
                Spacer()
                Button("건너뛰기", action: onSkip)
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            if windows.isEmpty && appSpecificDestinations.isEmpty {
                ContentUnavailableView(
                    "선택 가능한 윈도우 없음",
                    systemImage: "macwindow",
                    description: Text("이 앱이 윈도우 정보를 노출하지 않아 자동 전달 대상을 고를 수 없습니다.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if !appSpecificDestinations.isEmpty {
                        Section("앱별 대상") {
                            ForEach(appSpecificDestinations) { destination in
                                Button {
                                    onSelectAppSpecificDestination(destination)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(destination.title)
                                            if let detail = destination.detail {
                                                Text(detail)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer()
                                    }
                                }
                                .buttonStyle(.plain)
                                .padding(.vertical, 4)
                            }
                        }
                    }

                    if !windows.isEmpty {
                        Section("윈도우") {
                            ForEach(windows) { window in
                                Button {
                                    onSelectWindow(window)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(window.title)
                                            if window.isMain {
                                                Text("현재 메인 윈도우")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer()
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
        }
        .frame(minWidth: 420, minHeight: 520)
    }
}
