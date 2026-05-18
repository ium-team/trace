import AppKit
import SwiftUI

struct HistoryView: View {
    @Bindable var storage: CaptureStorage
    @State private var selectedItem: CaptureItem?
    @State private var message: String?

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedItem) {
                Section("최근 캡처") {
                    ForEach(storage.captures.prefix(8), id: \.self) { item in
                        HistoryRow(item: item, storage: storage)
                            .tag(item)
                    }
                }

                ForEach(storage.groupedByDay(), id: \.0) { day, items in
                    Section(day) {
                        ForEach(items, id: \.self) { item in
                            HistoryRow(item: item, storage: storage)
                                .tag(item)
                        }
                    }
                }
            }
            .frame(minWidth: 330)
        } detail: {
            if let selectedItem {
                CapturePreview(item: selectedItem, storage: storage, message: $message)
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
            if let selectedItem, storage.captures.contains(selectedItem) {
                return
            }
            selectLatestCaptureIfNeeded(force: true)
        }
        .frame(minWidth: 900, minHeight: 620)
    }

    private func selectLatestCaptureIfNeeded(force: Bool) {
        if !force && selectedItem != nil {
            return
        }
        selectedItem = storage.captures.first
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
                    Text(TraceDateFormatters.displayTime.string(from: item.createdAt))
                    if !storage.fileExists(for: item) {
                        Text("누락")
                            .foregroundStyle(.red)
                    }
                }
                .font(.callout)
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
    @Binding var message: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(TraceDateFormatters.displayDate.string(from: item.createdAt))
                        .font(.headline)
                    Text(item.filePath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
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
        .frame(minWidth: 560, minHeight: 420)
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
