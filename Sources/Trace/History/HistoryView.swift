import AppKit
import SwiftUI

struct HistoryView: View {
    @Bindable var storage: CaptureStorage
    @State private var selectedItemID: CaptureItem.ID?
    @State private var message: String?
    @State private var pendingName = ""
    @State private var isShowingDeleteConfirmation = false

    private var selectedItem: CaptureItem? {
        guard let selectedItemID else { return nil }
        return storage.capture(withID: selectedItemID)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedItemID) {
                if !storage.pinnedCaptures.isEmpty {
                    Section("고정") {
                        ForEach(storage.pinnedCaptures) { item in
                            HistoryRow(item: item, storage: storage)
                                .tag(item.id)
                        }
                    }
                }

                Section("최근 캡처") {
                    ForEach(storage.captures.filter { !$0.isPinned }.prefix(8)) { item in
                        HistoryRow(item: item, storage: storage)
                            .tag(item.id)
                    }
                }

                ForEach(storage.groupedByDay(), id: \.0) { day, items in
                    Section(day) {
                        ForEach(items.filter { !$0.isPinned }) { item in
                            HistoryRow(item: item, storage: storage)
                                .tag(item.id)
                        }
                    }
                }
            }
            .frame(minWidth: 330)
        } detail: {
            if let selectedItem {
                CapturePreview(
                    item: selectedItem,
                    storage: storage,
                    pendingName: $pendingName,
                    message: $message,
                    isShowingDeleteConfirmation: $isShowingDeleteConfirmation,
                    onDeleted: selectLatestCaptureAfterDelete
                )
            } else {
                ContentUnavailableView("캡처 선택", systemImage: "photo.on.rectangle")
            }
        }
        .toolbar {
            Button {
                storage.reload()
            } label: {
                Label("새로고침", systemImage: "arrow.clockwise")
            }
        }
        .alert("Trace", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("확인") { message = nil }
        } message: {
            Text(message ?? "")
        }
        .onAppear {
            selectLatestCaptureIfNeeded(force: false)
        }
        .onChange(of: storage.captures) { _, _ in
            if let selectedItemID, storage.capture(withID: selectedItemID) != nil {
                syncPendingName()
                return
            }
            selectLatestCaptureIfNeeded(force: true)
        }
        .onChange(of: selectedItemID) { _, _ in
            syncPendingName()
        }
        .frame(minWidth: 900, minHeight: 620)
    }

    private func selectLatestCaptureIfNeeded(force: Bool) {
        if !force && selectedItemID != nil {
            return
        }
        selectedItemID = storage.captures.first?.id
        syncPendingName()
    }

    private func selectLatestCaptureAfterDelete() {
        selectedItemID = storage.captures.first?.id
        syncPendingName()
    }

    private func syncPendingName() {
        pendingName = selectedItem?.displayTitle ?? ""
    }
}

struct HistoryRow: View {
    let item: CaptureItem
    let storage: CaptureStorage

    var body: some View {
        HStack(spacing: 10) {
            ThumbnailView(url: thumbnailURL)
                .frame(width: 56, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.quaternary, lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(item.displayTitle)
                        .fontWeight(item.isPinned ? .semibold : .regular)
                    if item.isPinned {
                        Image(systemName: "pin.fill")
                            .foregroundStyle(.orange)
                    }
                    if item.isBookmarked {
                        Image(systemName: "bookmark.fill")
                            .foregroundStyle(.blue)
                    }
                    if !storage.fileExists(for: item) {
                        Text("누락")
                            .foregroundStyle(.red)
                    }
                }
                .font(.callout)
                Text(TraceDateFormatters.displayTime.string(from: item.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(item.filePath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if item.deliveryState != .none {
                    Text(deliveryText)
                        .font(.caption)
                        .foregroundStyle(item.deliveryState == .failed ? .red : .secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var thumbnailURL: URL {
        if let thumbnailPath = item.thumbnailPath {
            return storage.absoluteURL(for: thumbnailPath)
        }
        return storage.absoluteURL(for: item.filePath)
    }

    private var deliveryText: String {
        if let app = item.deliveredAppName, !app.isEmpty {
            return "\(item.deliveryState.title): \(app)"
        }
        return item.deliveryState.title
    }
}

struct CapturePreview: View {
    let item: CaptureItem
    let storage: CaptureStorage
    @Binding var pendingName: String
    @Binding var message: String?
    @Binding var isShowingDeleteConfirmation: Bool
    let onDeleted: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        TextField("캡처 이름", text: $pendingName)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 240, maxWidth: 360)
                            .onSubmit(saveName)
                        Button("저장") {
                            saveName()
                        }
                        .disabled(pendingName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    Text(TraceDateFormatters.displayDate.string(from: item.createdAt))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(item.filePath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    storage.setPinned(!item.isPinned, itemID: item.id)
                } label: {
                    Label(item.isPinned ? "고정 해제" : "고정", systemImage: item.isPinned ? "pin.slash" : "pin")
                }
                Button {
                    storage.setBookmarked(!item.isBookmarked, itemID: item.id)
                } label: {
                    Label(item.isBookmarked ? "북마크 해제" : "북마크", systemImage: item.isBookmarked ? "bookmark.slash" : "bookmark")
                }
                Button {
                    copy()
                } label: {
                    Label("복사", systemImage: "doc.on.clipboard")
                }
                Button {
                    reveal()
                } label: {
                    Label("Finder", systemImage: "finder")
                }
                Button(role: .destructive) {
                    isShowingDeleteConfirmation = true
                } label: {
                    Label("삭제", systemImage: "trash")
                }
            }
            .padding()

            Divider()

            if let image = NSImage(contentsOf: storage.absoluteURL(for: item.filePath)) {
                GeometryReader { proxy in
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .background(.black.opacity(0.04))
                }
            } else {
                ContentUnavailableView("파일을 찾을 수 없음", systemImage: "exclamationmark.triangle")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .confirmationDialog("이 캡처를 삭제할까요?", isPresented: $isShowingDeleteConfirmation) {
            Button("삭제", role: .destructive) {
                delete()
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("원본 이미지, 썸네일, 히스토리 항목이 함께 삭제됩니다.")
        }
        .frame(minWidth: 560, minHeight: 420)
    }

    private func saveName() {
        do {
            try storage.rename(itemID: item.id, to: pendingName)
            pendingName = storage.capture(withID: item.id)?.displayTitle ?? pendingName
            message = "캡처 이름을 변경했습니다."
        } catch {
            pendingName = item.displayTitle
            message = error.localizedDescription
        }
    }

    private func copy() {
        do {
            try ClipboardService.copyImageFile(at: storage.absoluteURL(for: item.filePath))
            message = "클립보드에 복사했습니다."
        } catch {
            message = error.localizedDescription
        }
    }

    private func reveal() {
        let url = storage.absoluteURL(for: item.filePath)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            message = "Finder에서 열 파일을 찾을 수 없습니다."
        }
    }

    private func delete() {
        do {
            try storage.delete(itemID: item.id)
            message = "캡처를 삭제했습니다."
            onDeleted()
        } catch {
            message = error.localizedDescription
        }
    }
}

struct ThumbnailView: View {
    let url: URL

    var body: some View {
        if let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                Rectangle().fill(.quaternary)
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
