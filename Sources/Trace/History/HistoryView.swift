import AppKit
import SwiftUI

private enum HistorySectionKey: Hashable {
    case pinned
    case recent
    case day(String)
}

struct HistoryView: View {
    @Bindable var storage: CaptureStorage
    @Bindable var settingsStore: SettingsStore

    @State private var selectedItemIDs = Set<CaptureItem.ID>()
    @State private var message: String?
    @State private var pendingName = ""
    @State private var isShowingDeleteConfirmation = false
    @State private var expandedSections = Set<HistorySectionKey>([.pinned, .recent])

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
        NavigationSplitView {
            List(selection: $selectedItemIDs) {
                if !storage.pinnedCaptures.isEmpty {
                    DisclosureGroup(
                        isExpanded: bindingForSection(.pinned),
                        content: {
                            ForEach(storage.pinnedCaptures) { item in
                                HistoryRow(item: item, storage: storage)
                                    .tag(item.id)
                                    .contextMenu { rowContextMenu(for: item) }
                            }
                        },
                        label: {
                            Text("고정")
                        }
                    )
                    .tag(HistorySectionKey.pinned)
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
            .frame(minWidth: 360)
            .contextMenu {
                if selectedCount > 1 {
                    multiSelectionContextMenu
                }
            }
        } detail: {
            if let primarySelectedItem {
                CapturePreview(
                    item: primarySelectedItem,
                    selectedCount: selectedCount,
                    storage: storage,
                    settingsStore: settingsStore,
                    pendingName: $pendingName,
                    message: $message,
                    isShowingDeleteConfirmation: $isShowingDeleteConfirmation,
                    onBatchPin: { setPinned in setPinnedForSelection(setPinned) },
                    onBatchBookmark: { setBookmarked in setBookmarkedForSelection(setBookmarked) },
                    onBatchDelete: { deleteSelection() },
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
            Button {
                toggleSectionExpansion()
            } label: {
                Label("접기/펼치기", systemImage: "sidebar.left")
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
        .frame(minWidth: 980, minHeight: 640)
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
        let defaults: Set<HistorySectionKey> = Set([.pinned, .recent] + dayKeys.prefix(2))
        if expandedSections.isEmpty {
            expandedSections = defaults
        } else {
            expandedSections.formUnion(defaults)
        }
    }

    private func toggleSectionExpansion() {
        if expandedSections.count > 2 {
            expandedSections = [.pinned, .recent]
        } else {
            expandedSections = Set(storage.groupedByDay().map { HistorySectionKey.day($0.0) } + [.pinned, .recent])
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
    let settingsStore: SettingsStore
    @Binding var pendingName: String
    @Binding var message: String?
    @Binding var isShowingDeleteConfirmation: Bool
    let onBatchPin: (_ setPinned: Bool) -> Void
    let onBatchBookmark: (_ setBookmarked: Bool) -> Void
    let onBatchDelete: () -> Void
    let onDeleted: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                HStack(alignment: .center, spacing: 10) {
                    TextField("캡처 이름", text: $pendingName)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 240, maxWidth: 420)
                        .onSubmit(saveName)
                    Button("저장") { saveName() }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedCount != 1 || pendingName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Divider().frame(height: 20)

                    Button {
                        selectedCount > 1 ? onBatchPin(true) : storage.setPinned(!item.isPinned, itemID: item.id)
                    } label: {
                        Label(selectedCount > 1 ? "일괄 고정" : (item.isPinned ? "고정 해제" : "고정"), systemImage: item.isPinned ? "pin.slash" : "pin")
                    }

                    Button {
                        selectedCount > 1 ? onBatchBookmark(true) : storage.setBookmarked(!item.isBookmarked, itemID: item.id)
                    } label: {
                        Label(selectedCount > 1 ? "일괄 북마크" : (item.isBookmarked ? "북마크 해제" : "북마크"), systemImage: item.isBookmarked ? "bookmark.slash" : "bookmark")
                    }

                    Button { copy() } label: {
                        Label("복사", systemImage: "doc.on.clipboard")
                    }
                    Button { reveal() } label: {
                        Label("Finder", systemImage: "finder")
                    }
                    Button(role: .destructive) {
                        isShowingDeleteConfirmation = true
                    } label: {
                        Label(selectedCount > 1 ? "일괄 삭제" : "삭제", systemImage: "trash")
                    }
                }

                HStack {
                    Text(TraceDateFormatters.displayDate.string(from: item.createdAt))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(item.filePath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    HStack(spacing: 8) {
                        Picker("이름 규칙", selection: namingRuleBinding) {
                            ForEach(TraceSettings.FileNameRule.allCases) { rule in
                                Text(rule.title).tag(rule)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 120)

                        if settingsStore.settings.fileNameRule == .dateTime {
                            Picker("날짜 형식", selection: dateFormatBinding) {
                                ForEach(TraceSettings.DateFileNameFormat.allCases) { format in
                                    Text(format.title).tag(format)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 180)
                        } else {
                            Picker("순서 형식", selection: sequenceStyleBinding) {
                                ForEach(TraceSettings.SequenceStyle.allCases) { style in
                                    Text(style.title).tag(style)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 140)
                        }
                    }
                }
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
        .confirmationDialog(selectedCount > 1 ? "선택한 캡처를 삭제할까요?" : "이 캡처를 삭제할까요?", isPresented: $isShowingDeleteConfirmation) {
            Button("삭제", role: .destructive) {
                if selectedCount > 1 {
                    onBatchDelete()
                } else {
                    delete()
                }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("원본 이미지, 썸네일, 히스토리 항목이 함께 삭제됩니다.")
        }
        .frame(minWidth: 580, minHeight: 420)
    }

    private var namingRuleBinding: Binding<TraceSettings.FileNameRule> {
        Binding(
            get: { settingsStore.settings.fileNameRule },
            set: { newValue in
                var updated = settingsStore.settings
                updated.fileNameRule = newValue
                settingsStore.update(updated)
            }
        )
    }

    private var dateFormatBinding: Binding<TraceSettings.DateFileNameFormat> {
        Binding(
            get: { settingsStore.settings.dateFileNameFormat },
            set: { newValue in
                var updated = settingsStore.settings
                updated.dateFileNameFormat = newValue
                settingsStore.update(updated)
            }
        )
    }

    private var sequenceStyleBinding: Binding<TraceSettings.SequenceStyle> {
        Binding(
            get: { settingsStore.settings.sequenceStyle },
            set: { newValue in
                var updated = settingsStore.settings
                updated.sequenceStyle = newValue
                settingsStore.update(updated)
            }
        )
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
