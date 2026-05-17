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
    }
}
