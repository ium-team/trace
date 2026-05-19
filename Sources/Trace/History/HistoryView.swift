import AppKit
import SwiftUI

private enum HistorySectionKey: Hashable {
    case recent
    case day(String)
}

struct HistoryView: View {
    @Bindable var storage: CaptureStorage

    @State private var selectedItemIDs = Set<CaptureItem.ID>()
    @State private var message: String?
    @State private var pendingName = ""
    @State private var isShowingDeleteConfirmation = false
    @State private var isShowingRenameSheet = false
    @State private var expandedSections = Set<HistorySectionKey>([.recent])
    @State private var isSidebarVisible = true

    private var selectedItems: [CaptureItem] {
        storage.captures.filter { selectedItemIDs.contains($0.id) }
    }

    private var primarySelectedItem: CaptureItem? {
        selectedItems.first
    }

    private var selectedCount: Int {
        selectedItems.count
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebarList
                .frame(width: 360)
                .opacity(isSidebarVisible ? 1 : 0)
                .allowsHitTesting(isSidebarVisible)

            Divider()

            Group {
                if let primarySelectedItem {
                    CapturePreview(
                        item: primarySelectedItem,
                        selectedCount: selectedCount,
                        storage: storage,
                        onRename: openRename,
                    )
                } else {
                    ContentUnavailableView("캡처 선택", systemImage: "photo.on.rectangle")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    toggleSidebar()
                } label: {
                    Label("사이드바", systemImage: "sidebar.left")
                }
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    togglePinnedForSelection()
                } label: {
                    Label(selectedItems.allSatisfy(\.isPinned) ? "고정 해제" : "고정", systemImage: selectedItems.allSatisfy(\.isPinned) ? "pin.slash" : "pin")
                }
                .disabled(selectedCount == 0)

                Button {
                    toggleBookmarkedForSelection()
                } label: {
                    Label(selectedItems.allSatisfy(\.isBookmarked) ? "북마크 해제" : "북마크", systemImage: selectedItems.allSatisfy(\.isBookmarked) ? "bookmark.slash" : "bookmark")
                }
                .disabled(selectedCount == 0)

                Button {
                    copyPrimarySelection()
                } label: {
                    Label("복사", systemImage: "doc.on.clipboard")
                }
                .disabled(selectedCount == 0)

                Button {
                    revealPrimarySelection()
                } label: {
                    Label("Finder", systemImage: "finder")
                }
                .disabled(selectedCount == 0)

                Button(role: .destructive) {
                    isShowingDeleteConfirmation = true
                } label: {
                    Label("삭제", systemImage: "trash")
                }
                .disabled(selectedCount == 0)
            }
        }
        .alert("Trace", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("확인") { message = nil }
        } message: {
            Text(message ?? "")
        }
        .onAppear {
            initializeExpandedSectionsIfNeeded()
            selectLatestCaptureIfNeeded(force: false)
        }
        .onChange(of: storage.captures) { _, _ in
            selectedItemIDs = selectedItemIDs.filter { storage.capture(withID: $0) != nil }
            if selectedItemIDs.isEmpty {
                selectLatestCaptureIfNeeded(force: true)
            }
            syncPendingName()
            initializeExpandedSectionsIfNeeded()
        }
        .onChange(of: selectedItemIDs) { _, _ in
            syncPendingName()
        }
        .sheet(isPresented: $isShowingRenameSheet) {
            VStack(alignment: .leading, spacing: 12) {
                Text("캡처 이름 변경")
                    .font(.headline)
                TextField("이름", text: $pendingName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        renamePrimarySelection()
                    }
                HStack {
                    Spacer()
                    Button("취소", role: .cancel) {
                        isShowingRenameSheet = false
                    }
                    Button("저장") {
                        renamePrimarySelection()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(pendingName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding()
            .frame(width: 340)
        }
        .confirmationDialog(selectedCount > 1 ? "선택한 캡처를 삭제할까요?" : "이 캡처를 삭제할까요?", isPresented: $isShowingDeleteConfirmation) {
            Button("삭제", role: .destructive) {
                deleteSelection()
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("원본 이미지, 썸네일, 히스토리 항목이 함께 삭제됩니다.")
        }
        .frame(minWidth: 980, minHeight: 640)
    }

    private var sidebarList: some View {
        List(selection: $selectedItemIDs) {
            if !storage.pinnedCaptures.isEmpty {
                Section("고정") {
                    ForEach(storage.pinnedCaptures) { item in
                        HistoryRow(item: item, storage: storage)
                            .tag(item.id)
                            .contextMenu { rowContextMenu(for: item) }
                    }
                }
            }

            DisclosureGroup(
                isExpanded: bindingForSection(.recent),
                content: {
                    ForEach(storage.captures.filter { !$0.isPinned }.prefix(8)) { item in
                        HistoryRow(item: item, storage: storage)
                            .tag(item.id)
                            .contextMenu { rowContextMenu(for: item) }
                    }
                },
                label: {
                    Text("최근 캡처")
                }
            )
            .tag(HistorySectionKey.recent)

            ForEach(storage.groupedByDay(), id: \.0) { day, items in
                DisclosureGroup(
                    isExpanded: bindingForSection(.day(day)),
                    content: {
                        ForEach(items.filter { !$0.isPinned }) { item in
                            HistoryRow(item: item, storage: storage)
                                .tag(item.id)
                                .contextMenu { rowContextMenu(for: item) }
                        }
                    },
                    label: {
                        Text(day)
                    }
                )
                .tag(HistorySectionKey.day(day))
            }
        }
        .contextMenu {
            if selectedCount > 1 {
                multiSelectionContextMenu
            }
        }
    }

    private var multiSelectionContextMenu: some View {
        Group {
            Button("고정") { setPinnedForSelection(true) }
            Button("고정 해제") { setPinnedForSelection(false) }
            Divider()
            Button("북마크") { setBookmarkedForSelection(true) }
            Button("북마크 해제") { setBookmarkedForSelection(false) }
            Divider()
            Button("삭제", role: .destructive) { deleteSelection() }
        }
    }

    private func rowContextMenu(for item: CaptureItem) -> some View {
        Group {
            Button(item.isPinned ? "고정 해제" : "고정") {
                storage.setPinned(!item.isPinned, itemID: item.id)
            }
            Button(item.isBookmarked ? "북마크 해제" : "북마크") {
                storage.setBookmarked(!item.isBookmarked, itemID: item.id)
            }
            Divider()
            Button("복사") {
                do {
                    try ClipboardService.copyImageFile(at: storage.absoluteURL(for: item.filePath))
                    message = "클립보드에 복사했습니다."
                } catch {
                    message = error.localizedDescription
                }
            }
            Button("Finder") {
                let url = storage.absoluteURL(for: item.filePath)
                if FileManager.default.fileExists(atPath: url.path) {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } else {
                    message = "Finder에서 열 파일을 찾을 수 없습니다."
                }
            }
            Divider()
            Button("이름 변경") {
                selectedItemIDs = [item.id]
                pendingName = item.displayTitle
            }
            Button("삭제", role: .destructive) {
                selectedItemIDs = [item.id]
                deleteSelection()
            }
        }
    }

    private func bindingForSection(_ key: HistorySectionKey) -> Binding<Bool> {
        Binding(
            get: { expandedSections.contains(key) },
            set: { isExpanded in
                if isExpanded {
                    expandedSections.insert(key)
                } else {
                    expandedSections.remove(key)
                }
            }
        )
    }

    private func initializeExpandedSectionsIfNeeded() {
        let dayKeys = storage.groupedByDay().map { HistorySectionKey.day($0.0) }
        let defaults: Set<HistorySectionKey> = Set([.recent] + dayKeys.prefix(2))
        if expandedSections.isEmpty {
            expandedSections = defaults
        } else {
            expandedSections.formUnion(defaults)
        }
    }

    private func selectLatestCaptureIfNeeded(force: Bool) {
        if !force && !selectedItemIDs.isEmpty {
            return
        }
        if let first = storage.captures.first?.id {
            selectedItemIDs = [first]
        }
        syncPendingName()
    }

    private func selectLatestCaptureAfterDelete() {
        if let first = storage.captures.first?.id {
            selectedItemIDs = [first]
        } else {
            selectedItemIDs = []
        }
        syncPendingName()
    }

    private func syncPendingName() {
        pendingName = primarySelectedItem?.displayTitle ?? ""
    }

    private func setPinnedForSelection(_ pinned: Bool) {
        storage.setPinned(pinned, itemIDs: Array(selectedItemIDs))
    }

    private func setBookmarkedForSelection(_ bookmarked: Bool) {
        storage.setBookmarked(bookmarked, itemIDs: Array(selectedItemIDs))
    }

    private func togglePinnedForSelection() {
        let shouldPin = !selectedItems.allSatisfy(\.isPinned)
        setPinnedForSelection(shouldPin)
    }

    private func toggleBookmarkedForSelection() {
        let shouldBookmark = !selectedItems.allSatisfy(\.isBookmarked)
        setBookmarkedForSelection(shouldBookmark)
    }

    private func copyPrimarySelection() {
        guard let item = primarySelectedItem else { return }
        do {
            try ClipboardService.copyImageFile(at: storage.absoluteURL(for: item.filePath))
            message = "클립보드에 복사했습니다."
        } catch {
            message = error.localizedDescription
        }
    }

    private func revealPrimarySelection() {
        guard let item = primarySelectedItem else { return }
        let url = storage.absoluteURL(for: item.filePath)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            message = "Finder에서 열 파일을 찾을 수 없습니다."
        }
    }

    private func openRename() {
        guard selectedCount == 1 else { return }
        pendingName = primarySelectedItem?.displayTitle ?? ""
        isShowingRenameSheet = true
    }

    private func renamePrimarySelection() {
        guard let item = primarySelectedItem else { return }
        do {
            try storage.rename(itemID: item.id, to: pendingName)
            pendingName = storage.capture(withID: item.id)?.displayTitle ?? pendingName
            message = "캡처 이름을 변경했습니다."
            isShowingRenameSheet = false
        } catch {
            message = error.localizedDescription
        }
    }

    private func toggleSidebar() {
        isSidebarVisible.toggle()
    }

    private func deleteSelection() {
        let count = selectedCount
        do {
            try storage.delete(itemIDs: Array(selectedItemIDs))
            message = count > 1 ? "캡처 \(count)개를 삭제했습니다." : "캡처를 삭제했습니다."
            selectLatestCaptureAfterDelete()
        } catch {
            message = error.localizedDescription
        }
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
    let selectedCount: Int
    let storage: CaptureStorage
    let onRename: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.displayTitle)
                        .font(.headline)
                    Text(TraceDateFormatters.displayDate.string(from: item.createdAt))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(item.filePath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                renameButton
            }
            .padding()
            .background(.background)

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
        .frame(minWidth: 580, minHeight: 420)
    }

    private var renameButton: some View {
        Button {
            onRename()
        } label: {
            Label("이름 변경", systemImage: "pencil")
        }
        .controlSize(.small)
        .disabled(selectedCount != 1)
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
