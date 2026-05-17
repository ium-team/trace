import SwiftUI

struct CaptureLauncherView: View {
    @State private var selectedPlan: CapturePlan

    let onCancel: () -> Void
    let onCapture: (CapturePlan) -> Void

    init(defaultPlan: CapturePlan, onCancel: @escaping () -> Void, onCapture: @escaping (CapturePlan) -> Void) {
        self._selectedPlan = State(initialValue: defaultPlan)
        self.onCancel = onCancel
        self.onCapture = onCapture
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("캡처 방식 선택")
                    .font(.title2.bold())
                Text("캡처할 범위와 이후 동작을 선택한 뒤 캡처 버튼을 누르세요.")
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(CapturePlan.all) { plan in
                    CapturePlanCard(
                        plan: plan,
                        isSelected: selectedPlan == plan,
                        action: {
                            selectedPlan = plan
                        }
                    )
                }
            }

            HStack {
                Text(selectedPlan.description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("취소", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("캡처") {
                    onCapture(selectedPlan)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .frame(minWidth: 560, minHeight: 360)
    }
}

private struct CapturePlanCard: View {
    let plan: CapturePlan
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: plan.symbolName)
                    .font(.title2)
                    .frame(width: 28)
                    .foregroundStyle(isSelected ? .white : .accentColor)

                VStack(alignment: .leading, spacing: 6) {
                    Text(plan.title)
                        .font(.headline)
                    Text(plan.description)
                        .font(.caption)
                        .foregroundStyle(isSelected ? .white.opacity(0.82) : .secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .background(isSelected ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.18), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}
