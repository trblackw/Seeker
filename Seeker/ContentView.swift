//
//  SeekerApp.swift
//


import SwiftUI
import AppKit
import QuickLookThumbnailing
import Foundation

// MARK: - Utilities & Thumbnail Cache

/// Human-friendly size and date formatters reused across the UI.
enum Formatters {
    static let bytes: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useBytes, .useKB, .useMB, .useGB, .useTB]
        f.countStyle = .file
        return f
    }()

    static let modified: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}

/// Key for caching thumbnails by (url,size,scale)
private struct ThumbKey: Hashable {
    let path: String
    let w: Int
    let h: Int
    let scale: Int
}

/// LRU-ish thumbnail cache backed by NSCache; async fetch via QLThumbnailGenerator.
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, NSImage>()
    private let queue = DispatchQueue(label: "dev.seeker.thumb-cache", qos: .userInitiated)

    func thumbnail(for url: URL, size: CGSize, scale: CGFloat = NSScreen.main?.backingScaleFactor ?? 2.0,
                   completion: @escaping (NSImage?) -> Void) {
        let key = ThumbKey(path: url.path, w: Int(size.width), h: Int(size.height), scale: Int(scale))
        let nsKey = NSString(string: "\(key.path)|\(key.w)x\(key.h)@\(key.scale)x")
        if let hit = cache.object(forKey: nsKey) {
            completion(hit)
            return
        }
        // Request QuickLook representation off the main thread
        queue.async {
            let req = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: scale, representationTypes: .all)
            QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { rep, _ in
                let img = rep?.nsImage
                if let img { self.cache.setObject(img, forKey: nsKey) }
                DispatchQueue.main.async { completion(img) }
            }
        }
    }
}

// MARK: - Directory (main table)

final class DirectoryViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let table = NSTableView()
    private let scroll = NSScrollView()
    private var debounceReloadWorkItem: DispatchWorkItem?

    // UI chrome
    private let header = NSView()
    private let pathLabel = NSTextField(labelWithString: "")
    private let searchField = NSSearchField()
    private let statusBar = NSView()
    private let statusLabel = NSTextField(labelWithString: "")

    // Spotlight
    private var mdq: NSMetadataQuery?
    private var isSearching: Bool = false

    struct Item: Hashable {
        let url: URL
        let isDir: Bool
        let sizeBytes: UInt64?
        let modified: Date?
        var icon: NSImage?
    }
    private var items: [Item] = []
    private let resourceKeys: Set<URLResourceKey> = [
        .isDirectoryKey, .fileSizeKey, .contentTypeKey, .tagNamesKey, .contentModificationDateKey, .isSymbolicLinkKey
    ]

    // Directory to display (later: make this a navigation state)
    private var currentDirectory: URL = FileManager.default.homeDirectoryForCurrentUser

    override func loadView() {
        self.view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = ColorSchemeToken.surface.cgColor

        // Header (path on left, search on right)
        header.wantsLayer = true
        header.layer?.backgroundColor = ColorSchemeToken.surface.cgColor
        pathLabel.font = FontToken.small
        pathLabel.textColor = ColorSchemeToken.textSecondary
        searchField.placeholderString = "Search (Spotlight)…"
        searchField.sendsSearchStringImmediately = true
        searchField.target = self
        searchField.action = #selector(searchChanged)

        table.headerView = nil
        table.rowSizeStyle = .medium
        table.gridStyleMask = []
        table.intercellSpacing = NSSize(width: 0, height: 0)
        table.backgroundColor = ColorSchemeToken.surface
        table.usesAlternatingRowBackgroundColors = false
        table.selectionHighlightStyle = .regular
        table.delegate = self
        table.dataSource = self

        // Columns
        addCol("name", width: 480, title: "Name")
        addCol("size", width: 120, title: "Size")
        addCol("modified", width: 220, title: "Modified")

        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false

        // Status bar
        statusBar.wantsLayer = true
        statusBar.layer?.backgroundColor = ColorSchemeToken.surface.cgColor
        statusLabel.font = FontToken.small
        statusLabel.textColor = ColorSchemeToken.textSecondary

        // Compose view hierarchy
        [header, scroll, statusBar].forEach { view.addSubview($0) }
        header.translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        statusBar.translatesAutoresizingMaskIntoConstraints = false

        // Header subviews
        header.addSubview(pathLabel)
        header.addSubview(searchField)
        pathLabel.translatesAutoresizingMaskIntoConstraints = false
        searchField.translatesAutoresizingMaskIntoConstraints = false

        let headerHeight: CGFloat = 36
        let statusHeight: CGFloat = 24

        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.topAnchor.constraint(equalTo: view.topAnchor),
            header.heightAnchor.constraint(equalToConstant: headerHeight),

            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor),
            scroll.bottomAnchor.constraint(equalTo: statusBar.topAnchor),

            statusBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: statusHeight),

            pathLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: TZ.x4),
            pathLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),

            searchField.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -TZ.x4),
            searchField.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            searchField.widthAnchor.constraint(equalToConstant: 280)
        ])

        // Hairline separators
        header.addHairlineSeparator(edge: .maxY)
        statusBar.addHairlineSeparator(edge: .minY)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        loadDirectory(currentDirectory)
        updatePathLabel()
        updateStatus()
    }

    private func updatePathLabel() {
        pathLabel.stringValue = currentDirectory.path
    }

    private func updateStatus() {
        let count = items.count
        let totalBytes = items.compactMap { $0.sizeBytes }.reduce(0, +)
        let total = Formatters.bytes.string(fromByteCount: Int64(totalBytes))
        statusLabel.stringValue = "\(count) item\(count == 1 ? "" : "s") — \(total)"
        if statusLabel.superview == nil { statusBar.addSubview(statusLabel) }
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            statusLabel.leadingAnchor.constraint(equalTo: statusBar.leadingAnchor, constant: TZ.x4),
            statusLabel.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor)
        ])
    }

    // MARK: Data Loading

    private func loadDirectory(_ url: URL) {
        isSearching = false
        stopSpotlight()
        items.removeAll(keepingCapacity: true)
        table.reloadData()

        let fm = FileManager.default
        let opts: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants, .skipsHiddenFiles]
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: Array(resourceKeys), options: opts) else {
            return
        }

        // Only enumerate the immediate directory level (stop after first depth)
        let baseDepth = url.pathComponents.count

        DispatchQueue.global(qos: .userInitiated).async {
            var batch: [Item] = []
            let batchSize = 64

            for case let itemURL as URL in enumerator {
                // Do not recurse
                let depth = itemURL.pathComponents.count - baseDepth
                if depth > 1 {
                    enumerator.skipDescendants()
                    continue
                }

                do {
                    let rv = try itemURL.resourceValues(forKeys: self.resourceKeys)
                    let isDir = rv.isDirectory ?? false
                    let size = (rv.fileSize != nil) ? UInt64(rv.fileSize!) : nil
                    let modified = rv.contentModificationDate
                    var icon: NSImage? = nil

                    // System icon for dirs immediately; thumbnails for files later
                    if isDir {
                        icon = NSWorkspace.shared.icon(forFile: itemURL.path)
                        icon?.size = NSSize(width: 16, height: 16)
                    }

                    batch.append(Item(url: itemURL, isDir: isDir, sizeBytes: size, modified: modified, icon: icon))

                    if batch.count >= batchSize {
                        self.flush(batch: &batch)
                    }
                } catch {
                    continue
                }
            }
            self.flush(batch: &batch)
            // Trigger thumbnails after list is visible
            DispatchQueue.main.async {
                self.startThumbnailRequests()
                self.updateStatus()
            }
        }
    }

    private func flush(batch: inout [Item]) {
        guard !batch.isEmpty else { return }
        let additions = batch
        batch.removeAll(keepingCapacity: true)
        DispatchQueue.main.async {
            let start = self.items.count
            self.items.append(contentsOf: additions)
            self.table.beginUpdates()
            let rows = IndexSet(integersIn: start..<(start + additions.count))
            self.table.insertRows(at: rows, withAnimation: .effectFade)
            self.table.endUpdates()
            self.updateStatus()
        }
    }

    private func startThumbnailRequests() {
        let size = CGSize(width: 64, height: 64)
        for (idx, item) in items.enumerated() where !item.isDir {
            ThumbnailCache.shared.thumbnail(for: item.url, size: size) { [weak self] image in
                guard let self, let image else { return }
                // Update and reload just the name column for this row
                if idx < self.items.count {
                    self.items[idx].icon = image
                    self.reloadRowDebounced(idx)
                }
            }
        }
    }

    private func reloadRowDebounced(_ row: Int) {
        debounceReloadWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.table.reloadData(forRowIndexes: IndexSet(integer: row),
                                  columnIndexes: IndexSet([0])) // only name column
        }
        debounceReloadWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03, execute: work)
    }

    // MARK: Spotlight search

    @objc private func searchChanged() {
        let q = searchField.stringValue.trimmingCharacters(in: .whitespaces)
        if q.isEmpty {
            loadDirectory(currentDirectory)
            return
        }
        runSpotlight(query: q)
    }

    private func runSpotlight(query q: String) {
        isSearching = true
        stopSpotlight()
        items.removeAll(keepingCapacity: true)
        table.reloadData()
        updateStatus()

        let mq = NSMetadataQuery()
        mq.searchScopes = [currentDirectory.path]
        mq.predicate = NSPredicate(format: "kMDItemFSName CONTAINS[cd] %@", q)

        NotificationCenter.default.addObserver(self, selector: #selector(spotlightDidFinish(_:)),
                                               name: .NSMetadataQueryDidFinishGathering, object: mq)
        NotificationCenter.default.addObserver(self, selector: #selector(spotlightDidUpdate(_:)),
                                               name: .NSMetadataQueryDidUpdate, object: mq)
        mdq = mq
        mq.start()
    }

    private func stopSpotlight() {
        guard let mq = mdq else { return }
        mq.stop()
        NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidFinishGathering, object: mq)
        NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidUpdate, object: mq)
        mdq = nil
    }

    @objc private func spotlightDidFinish(_ note: Notification) {
        consumeSpotlightResults()
    }

    @objc private func spotlightDidUpdate(_ note: Notification) {
        consumeSpotlightResults()
    }

    private func consumeSpotlightResults() {
        guard let mq = mdq else { return }
        var batch: [Item] = []
        for obj in mq.results {
            guard let it = obj as? NSMetadataItem,
                  let path = it.value(forAttribute: kMDItemPath as String) as? String else { continue }
            let url = URL(fileURLWithPath: path)
            let isDir = (it.value(forAttribute: kMDItemFSSize as String) == nil) // rough; refine with URLResourceValues
            let size = (it.value(forAttribute: kMDItemFSSize as String) as? NSNumber).map { UInt64(truncating: $0) }
            let modified = (it.value(forAttribute: kMDItemContentModificationDate as String) as? Date)
            var icon: NSImage? = nil
            if isDir {
                icon = NSWorkspace.shared.icon(forFile: path)
                icon?.size = NSSize(width: 16, height: 16)
            }
            batch.append(Item(url: url, isDir: isDir, sizeBytes: size, modified: modified, icon: icon))
        }
        self.items = batch
        table.reloadData()
        updateStatus()
        startThumbnailRequests()
    }

    // MARK: Columns

    private func addCol(_ id: String, width: CGFloat, title: String) {
        let c = NSTableColumn(identifier: .init(id))
        c.width = width
        c.minWidth = max(120, width * 0.5)
        c.title = title
        table.addTableColumn(c)
    }

    // MARK: Table Data Source

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let colID = tableColumn?.identifier.rawValue ?? "name"
        switch colID {
        case "name":
            let id = NSUserInterfaceItemIdentifier("cell-name")
            let cell = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? {
                let c = NSTableCellView()
                c.identifier = id
                let img = NSImageView()
                img.imageScaling = .scaleProportionallyDown
                img.translatesAutoresizingMaskIntoConstraints = false
                c.imageView = img
                c.addSubview(img)

                let tf = NSTextField(labelWithString: "")
                tf.font = FontToken.ui
                tf.textColor = ColorSchemeToken.textPrimary
                tf.translatesAutoresizingMaskIntoConstraints = false
                c.textField = tf
                c.addSubview(tf)

                NSLayoutConstraint.activate([
                    img.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: TZ.x4),
                    img.centerYAnchor.constraint(equalTo: c.centerYAnchor),
                    img.widthAnchor.constraint(equalToConstant: 16),
                    img.heightAnchor.constraint(equalToConstant: 16),

                    tf.leadingAnchor.constraint(equalTo: img.trailingAnchor, constant: TZ.x3),
                    tf.centerYAnchor.constraint(equalTo: c.centerYAnchor),
                    tf.trailingAnchor.constraint(lessThanOrEqualTo: c.trailingAnchor, constant: -TZ.x4)
                ])
                return c
            }()

            let item = items[row]
            cell.textField?.stringValue = item.url.lastPathComponent + (item.isDir ? " ▸" : "")
            if let icon = item.icon {
                cell.imageView?.image = icon
            } else {
                // fallback system icon
                cell.imageView?.image = NSWorkspace.shared.icon(forFile: item.url.path)
            }
            return cell

        case "size":
            let id = NSUserInterfaceItemIdentifier("cell-size")
            let cell = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? {
                let c = NSTableCellView()
                c.identifier = id
                let tf = NSTextField(labelWithString: "")
                tf.font = FontToken.ui
                tf.textColor = ColorSchemeToken.textSecondary
                tf.translatesAutoresizingMaskIntoConstraints = false
                c.textField = tf
                c.addSubview(tf)
                NSLayoutConstraint.activate([
                    tf.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: TZ.x4),
                    tf.centerYAnchor.constraint(equalTo: c.centerYAnchor)
                ])
                return c
            }()
            let item = items[row]
            cell.textField?.stringValue = item.isDir ? "—" : (item.sizeBytes.map { Formatters.bytes.string(fromByteCount: Int64($0)) } ?? "—")
            return cell

        case "modified":
            let id = NSUserInterfaceItemIdentifier("cell-modified")
            let cell = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? {
                let c = NSTableCellView()
                c.identifier = id
                let tf = NSTextField(labelWithString: "")
                tf.font = FontToken.ui
                tf.textColor = ColorSchemeToken.textSecondary
                tf.translatesAutoresizingMaskIntoConstraints = false
                c.textField = tf
                c.addSubview(tf)
                NSLayoutConstraint.activate([
                    tf.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: TZ.x4),
                    tf.centerYAnchor.constraint(equalTo: c.centerYAnchor)
                ])
                return c
            }()
            let item = items[row]
            if let d = item.modified {
                cell.textField?.stringValue = Formatters.modified.string(from: d)
            } else {
                cell.textField?.stringValue = "—"
            }
            return cell

        default:
            return nil
        }
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { true }

    // MARK: Keyboard navigation
    override func keyDown(with event: NSEvent) {
        // Enter opens
        if event.keyCode == 36 /* Return */ {
            openSelection()
            return
        }
        // Cmd+Up goes to parent
        if event.modifierFlags.contains(.command) && event.keyCode == 126 /* Up Arrow */ {
            goUpDirectory()
            return
        }
        super.keyDown(with: event)
    }

    private func openSelection() {
        let r = table.selectedRow
        guard r >= 0 && r < items.count else { return }
        let item = items[r]
        if item.isDir {
            currentDirectory = item.url
            updatePathLabel()
            loadDirectory(currentDirectory)
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }

    private func goUpDirectory() {
        let parent = currentDirectory.deletingLastPathComponent()
        guard parent.path != currentDirectory.path else { return }
        currentDirectory = parent
        updatePathLabel()
        loadDirectory(currentDirectory)
    }

    // MARK: - Command Palette helpers

    /// Focuses the header search field (used by Command Palette)
    func focusSearch() {
        view.window?.makeFirstResponder(searchField)
    }

    /// Navigates to the parent directory (used by Command Palette)
    func goUpViaCommand() {
        goUpDirectory()
    }

    /// Opens macOS Terminal at the current directory (used by Command Palette)
    func openTerminalHere() {
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-a", "Terminal", currentDirectory.path]
        try? task.run()
    }
}
