import AppKit
import SwiftUI

struct DestinationPickerView: View {
    let destinations: [AppDestination]
    let onSkip: () -> Void
    let onSelect: (AppDestination) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 104, maximum: 124), spacing: 14)
    ]

    var body: some View {
        DeliveryPanel {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("앱으로 전달")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                    Text("Command+Tab처럼 실행 중인 앱을 고른 뒤, 붙여넣을 윈도우를 선택합니다.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("건너뛰기", action: onSkip)
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(SecondaryCapsuleButtonStyle())
            }
            .padding(.horizontal, 26)
            .padding(.top, 24)
            .padding(.bottom, 18)

            if destinations.isEmpty {
                Spacer(minLength: 0)
                ContentUnavailableView("실행 중인 앱 없음", systemImage: "app.dashed")
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(destinations) { destination in
                            Button {
                                onSelect(destination)
                            } label: {
                                AppSwitcherTile(destination: destination)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
        }
        .frame(minWidth: 720, minHeight: 460)
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

    private let columns = [
        GridItem(.adaptive(minimum: 230, maximum: 280), spacing: 14)
    ]

    var body: some View {
        DeliveryPanel {
            HStack(alignment: .center, spacing: 14) {
                Button(action: onBack) {
                    Label("앱", systemImage: "chevron.left")
                }
                .buttonStyle(SecondaryCapsuleButtonStyle())

                Image(nsImage: app.icon)
                    .resizable()
                    .frame(width: 38, height: 38)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(app.name)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                    Text(appSpecificDestinations.isEmpty ? "붙여넣을 윈도우를 선택하세요." : "cmux 세부 터미널 또는 앱 윈도우를 선택하세요.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("건너뛰기", action: onSkip)
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(SecondaryCapsuleButtonStyle())
            }
            .padding(.horizontal, 26)
            .padding(.top, 24)
            .padding(.bottom, 18)

            if windows.isEmpty && appSpecificDestinations.isEmpty {
                Spacer(minLength: 0)
                ContentUnavailableView(
                    "선택 가능한 윈도우 없음",
                    systemImage: "macwindow",
                    description: Text("이 앱이 윈도우 정보를 노출하지 않아 자동 전달 대상을 고를 수 없습니다.")
                )
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if !appSpecificDestinations.isEmpty {
                            TargetSectionHeader(
                                title: "cmux 터미널 대상",
                                subtitle: "window / workspace / pane / surface 기준으로 정확한 터미널을 선택합니다."
                            )
                            LazyVGrid(columns: columns, spacing: 14) {
                                ForEach(appSpecificDestinations) { destination in
                                    Button {
                                        onSelectAppSpecificDestination(destination)
                                    } label: {
                                        CmuxTargetCard(destination: destination)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        if !windows.isEmpty {
                            TargetSectionHeader(
                                title: "앱 윈도우",
                                subtitle: "선택한 윈도우를 앞으로 올린 뒤 붙여넣기를 보냅니다."
                            )
                            LazyVGrid(columns: columns, spacing: 14) {
                                ForEach(windows) { window in
                                    Button {
                                        onSelectWindow(window)
                                    } label: {
                                        WindowTargetCard(window: window)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
        }
        .frame(minWidth: 720, minHeight: 520)
    }
}

private struct DeliveryPanel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor).opacity(0.78),
                    Color(nsColor: .controlBackgroundColor).opacity(0.92)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [Color.blue.opacity(0.18), .clear],
                center: .topTrailing,
                startRadius: 40,
                endRadius: 420
            )
            VStack(spacing: 0) {
                content
            }
        }
    }
}

private struct AppSwitcherTile: View {
    let destination: AppDestination

    var body: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .topTrailing) {
                Image(nsImage: destination.icon)
                    .resizable()
                    .frame(width: 58, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: .black.opacity(0.24), radius: 9, y: 5)

                if destination.isActive {
                    Circle()
                        .fill(.green)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 2))
                        .offset(x: 3, y: -3)
                }
            }

            Text(destination.name)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 34, alignment: .top)
        }
        .frame(maxWidth: .infinity, minHeight: 132)
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(destination.isActive ? Color.green.opacity(0.65) : Color.white.opacity(0.16), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct TargetSectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct WindowTargetCard: View {
    let window: AppWindowDestination

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WindowThumbnailView(image: window.thumbnail)
                .frame(maxWidth: .infinity)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(window.title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .lineLimit(2)
                    if window.isMain {
                        Text("현재 메인 윈도우")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.turn.down.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(window.isMain ? Color.green.opacity(0.6) : Color.white.opacity(0.14), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct CmuxTargetCard: View {
    let destination: AppSpecificDestination

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0.68))
                Image(systemName: "terminal")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 5) {
                Text(destination.title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(2)
                if let detail = destination.detail {
                    Text(detail)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.blue.opacity(0.32), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct WindowThumbnailView: View {
    let image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    LinearGradient(
                        colors: [Color.gray.opacity(0.28), Color.gray.opacity(0.10)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "macwindow")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(height: 132)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct SecondaryCapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}
