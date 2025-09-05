// MARK: - Window & Root Controllers (minimal)

// Custom sidebar table that prevents any default "open in Finder" behavior
final class SidebarTableView: NSTableView {
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            // Do not let AppKit/Launch Services perform a default open.
            // Route through delegate via selection change only.
            super.mouseDown(with: event) // allow selection to update
            return
        }
        super.mouseDown(with: event)
    }
}
final class LinearWindowController: NSWindowController {
    convenience init(content: NSViewController) {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.isMovableByWindowBackground = true
        w.toolbarStyle = .unified
        w.backgroundColor = ColorSchemeToken.bg
        w.setContentSize(NSSize(width: 1280, height: 800))
        w.minSize = NSSize(width: 900, height: 600)
        self.init(window: w)
        self.contentViewController = content
        w.center()
    }
}

// MARK: - SidebarViewController
final class SidebarViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    struct SidebarEntry {
        let name: String
        let url: URL
    }
    let entries: [SidebarEntry] = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            SidebarEntry(name: "Documents", url: home.appendingPathComponent("Documents")),
            SidebarEntry(name: "Library", url: home.appendingPathComponent("Library")),
            SidebarEntry(name: "Desktop", url: home.appendingPathComponent("Desktop")),
            SidebarEntry(name: "Downloads", url: home.appendingPathComponent("Downloads")),
            SidebarEntry(name: "Music", url: home.appendingPathComponent("Music")),
            SidebarEntry(name: "Pictures", url: home.appendingPathComponent("Pictures")),
            SidebarEntry(name: "Movies", url: home.appendingPathComponent("Movies")),
            SidebarEntry(name: "Public", url: home.appendingPathComponent("Public"))
        ]
    }()
    var firstEntryURL: URL? { entries.first?.url }
    private let table = SidebarTableView()
    private let scroll = NSScrollView()
    weak var delegate: SidebarSelectionDelegate?

    override func loadView() {
        self.view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = ColorSchemeToken.surface.cgColor

        let col = NSTableColumn(identifier: .init("sidebar"))
        col.title = ""
        col.width = 200
        table.addTableColumn(col)
        table.headerView = nil
        table.rowSizeStyle = .medium
        table.allowsMultipleSelection = false
        table.selectionHighlightStyle = .sourceList
        table.target = self
        table.doubleAction = nil
        table.delegate = self
        table.dataSource = self

        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        view.addSubview(scroll)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    // MARK: - Table Data Source/Delegate
    func numberOfRows(in tableView: NSTableView) -> Int {
        return entries.count
    }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("sidebarCell")
        let cell = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? {
            let c = NSTableCellView()
            c.identifier = id
            let tf = NSTextField(labelWithString: "")
            tf.font = FontToken.ui
            tf.textColor = ColorSchemeToken.textPrimary
            c.textField = tf
            c.addSubview(tf)
            tf.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                tf.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 16),
                tf.centerYAnchor.constraint(equalTo: c.centerYAnchor)
            ])
            return c
        }()
        cell.textField?.stringValue = entries[row].name
        return cell
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = table.selectedRow
        guard row >= 0, entries.indices.contains(row) else { return }
        delegate?.sidebarDidSelectDirectory(entries[row].url)
    }
    // For initial selection programmatically if needed
    func selectRow(_ idx: Int) {
        table.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
    }
}

protocol SidebarSelectionDelegate: AnyObject {
    func sidebarDidSelectDirectory(_ url: URL)
}

// MARK: - SeekerRootViewController with Split View
final class SeekerRootViewController: NSSplitViewController, SidebarSelectionDelegate {
    private let sidebarVC = SidebarViewController()
    private let directoryVC = DirectoryListViewController()

    override func viewDidLoad() {
        super.viewDidLoad()

        sidebarVC.delegate = self

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarVC)
        sidebarItem.minimumThickness = 160
        sidebarItem.maximumThickness = 240
        sidebarItem.preferredThicknessFraction = 0
        sidebarItem.canCollapse = false
        sidebarItem.holdingPriority = NSLayoutConstraint.Priority.defaultHigh
        sidebarItem.titlebarSeparatorStyle = .automatic
        sidebarItem.isCollapsed = false

        let mainItem = NSSplitViewItem(viewController: directoryVC)
        mainItem.minimumThickness = 300

        self.addSplitViewItem(sidebarItem)
        self.addSplitViewItem(mainItem)
        // Do not auto-open any folder on launch (avoid system permission prompts).
        // Leave selection empty; user click will drive navigation.
    }

    // SidebarSelectionDelegate
    func sidebarDidSelectDirectory(_ url: URL) {
        directoryVC.selectTarget(url) // shows contents if already authorized, else a non-modal placeholder with a Grant Access button
    }
}

//
//  DirectoryList.swift
//  Seeker
//
//  Directory list view controller and related UI.
//

import AppKit
import SwiftUI

// Custom table view that swallows default double-click "open" behavior
final class DirectoryTableView: NSTableView {
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            // Route to controller explicitly and do not call super to prevent default open
            if let controller = target as? DirectoryListViewController {
                controller.handleRowDoubleClick(self)
                return
            }
        }
        super.mouseDown(with: event)
    }
}

final class DirectoryListViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    // Placeholder for unauthorized locations
    private let placeholder = NSView()
    private let placeholderLabel = NSTextField(labelWithString: "")
    private let placeholderButton = NSButton(title: "Grant Access", target: nil, action: nil)
    private var pendingURLForGrant: URL?
    // Helper: treat folders and symlinks-to-folders as navigable directories
    private func resolvedDirectoryIfAny(for url: URL) -> URL? {
        // Resolve symlinks first
        let resolved = url.resolvingSymlinksInPath()
        // Ask the file system if destination is a directory
        let isDir = (try? resolved.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        return isDir ? resolved : nil
    }

    // UI
    private let header = NSView()
    private let pathLabel = NSTextField(labelWithString: "")
    private let crumbBar = NSStackView()
    private let searchField = NSSearchField()
    private let scroll = NSScrollView()
    private let table = DirectoryTableView()

    // State
    private var items: [URL] = []
    private var filtered: [URL] = []
    private(set) var currentDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    private var query: String = ""

    // Navigation history
    private var backStack: [URL] = []
    private var forwardStack: [URL] = []
    private var crumbURLs: [URL] = []
    private var suppressHistoryPush = false

    // Key monitor for ⌘K focus
    private var keyMonitor: Any?

    override func loadView() {
        self.view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = ColorSchemeToken.bg.cgColor

        // Header
        header.wantsLayer = true
        header.layer?.backgroundColor = ColorSchemeToken.surface.cgColor
        view.addSubview(header)
        header.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.topAnchor.constraint(equalTo: view.topAnchor),
            header.heightAnchor.constraint(equalToConstant: 44)
        ])

        pathLabel.font = FontToken.uiMedium
        pathLabel.textColor = ColorSchemeToken.textSecondary
        header.addSubview(pathLabel)

        // Breadcrumb bar
        crumbBar.orientation = .horizontal
        crumbBar.alignment = .centerY
        crumbBar.spacing = 6
        crumbBar.setContentHuggingPriority(NSLayoutConstraint.Priority.defaultLow, for: .horizontal)
        crumbBar.setContentCompressionResistancePriority(NSLayoutConstraint.Priority.defaultLow, for: .horizontal)
        header.addSubview(crumbBar)

        searchField.placeholderString = "Filter…"
        searchField.font = FontToken.ui
        searchField.focusRingType = .none
        searchField.bezelStyle = .roundedBezel
        searchField.wantsLayer = true
        searchField.layer?.cornerRadius = 8
        searchField.layer?.backgroundColor = ColorSchemeToken.surface.cgColor
        searchField.delegate = self
        header.addSubview(searchField)

        pathLabel.translatesAutoresizingMaskIntoConstraints = false
        pathLabel.isHidden = true // breadcrumb bar supersedes the raw path text

        crumbBar.translatesAutoresizingMaskIntoConstraints = false
        searchField.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            crumbBar.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: TZ.x4),
            crumbBar.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            crumbBar.trailingAnchor.constraint(lessThanOrEqualTo: searchField.leadingAnchor, constant: -TZ.x4),

            searchField.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -TZ.x4),
            searchField.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            searchField.widthAnchor.constraint(equalToConstant: 260)
        ])

        // Table
        let col = NSTableColumn(identifier: .init("name"))
        col.title = "Name"
        col.minWidth = 200
        table.addTableColumn(col)
        table.headerView = nil
        table.delegate = self
        table.dataSource = self
        table.rowSizeStyle = .medium
        table.allowsMultipleSelection = false
        table.selectionHighlightStyle = .regular

        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false

        view.addSubview(scroll)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        table.target = self

        updatePathLabel()
        // Placeholder overlay (hidden by default)
        placeholder.wantsLayer = true
        placeholder.layer?.backgroundColor = NSColor.clear.cgColor
        view.addSubview(placeholder)
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            placeholder.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            placeholder.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            placeholder.topAnchor.constraint(equalTo: header.bottomAnchor),
            placeholder.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        placeholder.isHidden = true

        placeholderLabel.font = FontToken.uiMedium
        placeholderLabel.textColor = ColorSchemeToken.textSecondary
        placeholderLabel.alignment = .center
        placeholder.addSubview(placeholderLabel)

        placeholderButton.target = self
        placeholderButton.action = #selector(grantAccessTapped)
        placeholderButton.bezelStyle = .rounded
        placeholder.addSubview(placeholderButton)

        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            placeholderLabel.centerXAnchor.constraint(equalTo: placeholder.centerXAnchor),
            placeholderLabel.centerYAnchor.constraint(equalTo: placeholder.centerYAnchor, constant: -12),
            placeholderButton.centerXAnchor.constraint(equalTo: placeholder.centerXAnchor),
            placeholderButton.topAnchor.constraint(equalTo: placeholderLabel.bottomAnchor, constant: 8)
        ])

        // No auto-open; wait for user action
        filtered = []
        table.reloadData()
    }
    // Called by sidebar: show directory if already authorized; otherwise present non-blocking CTA
    func selectTarget(_ url: URL) {
        // If we already have access (security-scoped bookmark), open immediately.
        if let accessible = FolderAccessManager.shared.hasAccess(for: url) {
            openDirectory(accessible)
            hidePlaceholder()
        } else {
            // Show placeholder; do not trigger NSOpenPanel yet.
            pendingURLForGrant = url
            showPlaceholder(for: url)
        }
    }

    private func showPlaceholder(for url: URL) {
        placeholderLabel.stringValue = "Seeker needs access to “\(url.lastPathComponent)”."
        placeholder.isHidden = false
        scroll.isHidden = true
    }

    private func hidePlaceholder() {
        placeholder.isHidden = true
        scroll.isHidden = false
    }

    @objc private func grantAccessTapped() {
        guard let url = pendingURLForGrant else { return }
        FolderAccessManager.shared.requestAccess(for: url) { [weak self] granted in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if let u = granted {
                    self.hidePlaceholder()
                    self.openDirectory(u)
                } else {
                    NSSound.beep()
                }
            }
        }
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        // Local key monitor so ⌘K focuses the inline search even without a menu item
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            if event.modifierFlags.contains(.command) {
                if event.charactersIgnoringModifiers?.lowercased() == "k" {
                    self.focusSearch()
                    return nil
                }
                // Arrow keycodes: left=123, right=124
                switch event.keyCode {
                case 123: self.goBack(); return nil
                case 124: self.goForward(); return nil
                default: break
                }
            }
            return event
        }
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        if let m = keyMonitor {
            NSEvent.removeMonitor(m)
            keyMonitor = nil
        }
    }

    private func rebuildBreadcrumb() {
        // Remove existing
        crumbBar.arrangedSubviews.forEach { v in
            crumbBar.removeArrangedSubview(v)
            v.removeFromSuperview()
        }
        crumbURLs.removeAll()
        // Build components from root to current directory
        let comps = currentDirectory.standardizedFileURL.pathComponents
        guard !comps.isEmpty else { return }

        // Accumulate URLs as we go to assign to buttons
        var parts: [URL] = []
        for (i, c) in comps.enumerated() {
            let nextURL: URL
            if i == 0 && c == "/" {
                nextURL = URL(fileURLWithPath: "/")
            } else {
                nextURL = (parts.last ?? URL(fileURLWithPath: "/")).appendingPathComponent(c)
            }
            parts.append(nextURL)

            let btn = NSButton(title: (i == 0 && c == "/") ? "Macintosh HD" : c, target: self, action: #selector(breadcrumbTapped(_:)))
            btn.bezelStyle = .inline
            btn.isBordered = false
            btn.contentTintColor = ColorSchemeToken.textSecondary
            btn.font = FontToken.ui
            btn.setButtonType(.momentaryChange)
            btn.tag = i
            crumbURLs.append(nextURL)
            crumbBar.addArrangedSubview(btn)

            if i < comps.count - 1 {
                let sep = NSTextField(labelWithString: "›")
                sep.textColor = ColorSchemeToken.textSecondary
                sep.font = FontToken.ui
                crumbBar.addArrangedSubview(sep)
            }
        }
    }

    // Ensure sandbox access (if required) before opening a directory
     func navigate(to url: URL) {
        FolderAccessManager.shared.ensureAccess(to: url) { [weak self] (grantedURL: URL?) in
            guard let self = self, let u = grantedURL else {
                NSSound.beep()
                return
            }
            DispatchQueue.main.async {
                self.hidePlaceholder()
                self.openDirectory(u)
            }
        }
    }

    @objc private func breadcrumbTapped(_ sender: NSButton) {
        let idx = sender.tag
        guard idx >= 0 && idx < crumbURLs.count else { return }
        navigate(to: crumbURLs[idx])
    }

    private func updatePathLabel() {
        pathLabel.stringValue = currentDirectory.path
        rebuildBreadcrumb()
    }

    func openDirectory(_ url: URL) {
        if url != currentDirectory && !suppressHistoryPush {
            backStack.append(currentDirectory)
            forwardStack.removeAll()
        }
        currentDirectory = url
        updatePathLabel()
        let fm = FileManager.default
        do {
            let contents = try fm.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .localizedNameKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
            // Sort: folders first, then by localized name
            items = contents.sorted { a, b in
                let aIsDir = (try? a.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                let bIsDir = (try? b.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if aIsDir != bIsDir { return aIsDir && !bIsDir }
                let aName = (try? a.resourceValues(forKeys: [.localizedNameKey]).localizedName) ?? a.lastPathComponent
                let bName = (try? b.resourceValues(forKeys: [.localizedNameKey]).localizedName) ?? b.lastPathComponent
                return aName.localizedCaseInsensitiveCompare(bName) == .orderedAscending
            }
            if query.isEmpty {
                filtered = items
            } else {
                applyFilter()
            }
        } catch {
            items = []
            filtered = []
        }
        table.reloadData()
    }

    func focusSearch() {
        view.window?.makeFirstResponder(searchField)
    }

    func goUpViaCommand() {
        let parent = currentDirectory.deletingLastPathComponent()
        guard parent.path != currentDirectory.path else { return }
        openDirectory(parent)
    }

    func goBack() {
        guard let prev = backStack.popLast() else { NSSound.beep(); return }
        suppressHistoryPush = true
        forwardStack.append(currentDirectory)
        openDirectory(prev)
        suppressHistoryPush = false
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { NSSound.beep(); return }
        suppressHistoryPush = true
        backStack.append(currentDirectory)
        openDirectory(next)
        suppressHistoryPush = false
    }

    func openTerminalHere() {
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-a", "Terminal", currentDirectory.path]
        try? task.run()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        filtered.count
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        // Single click = selection only. No navigation, no external apps.
        // Navigation happens on double‑click (handled by DirectoryTableView → handleRowDoubleClick).
        // This guarantees Finder (or any external handler) is never invoked from a selection.
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("cell")
        let cell = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? {
            let c = NSTableCellView()
            c.identifier = id
            let tf = NSTextField(labelWithString: "")
            tf.font = FontToken.ui
            tf.textColor = ColorSchemeToken.textPrimary
            c.textField = tf
            c.addSubview(tf)
            tf.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                tf.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: TZ.x8),
                tf.centerYAnchor.constraint(equalTo: c.centerYAnchor)
            ])
            return c
        }()

        let url = filtered[row]
        cell.textField?.stringValue = url.lastPathComponent
        return cell
    }

    @objc func handleRowDoubleClick(_ sender: Any) {
        let row = table.clickedRow
        guard row >= 0, filtered.indices.contains(row) else { return }
        let url = filtered[row]
        if let dirURL = resolvedDirectoryIfAny(for: url) {
            // Navigate inside Seeker, obtaining permission if needed
            navigate(to: dirURL)
        } else {
            // File (or non-directory target): keep user inside Seeker for now.
            // Select the row; Quick Look will be wired next.
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
    }

    override func keyDown(with event: NSEvent) {
        // Return/Enter opens the selected folder if applicable
        if event.keyCode == 36 || event.keyCode == 76 { // return or keypad-enter
            let row = table.selectedRow
            if row >= 0, filtered.indices.contains(row) {
                let url = filtered[row]
                if let dirURL = resolvedDirectoryIfAny(for: url) {
                    navigate(to: dirURL)
                    return
                }
            }
        }
        super.keyDown(with: event)
    }

    // MARK: - Search
    func controlTextDidChange(_ obj: Notification) {
        query = searchField.stringValue
        applyFilter()
    }

    private func applyFilter() {
        guard !query.isEmpty else {
            filtered = items
            table.reloadData()
            return
        }
        let q = query.lowercased()
        filtered = items.filter { $0.lastPathComponent.lowercased().contains(q) }
        table.reloadData()
    }
}

// MARK: - FolderAccessManager (sandbox-friendly permission helper)
final class FolderAccessManager {
    static let shared = FolderAccessManager()
    private let keyPrefix = "dev.seeker.bookmark."
    private init() {}

    // Returns an accessible URL if we already hold a security-scoped bookmark; does not prompt.
    func hasAccess(for url: URL) -> URL? {
        return resolveBookmark(for: url)
    }

    // Explicitly prompts the user to grant access to this folder, then stores the bookmark.
    func requestAccess(for url: URL, completion: @escaping (URL?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.directoryURL = url
        panel.message = "Seeker needs permission to read “\(url.lastPathComponent)”."
        panel.prompt = "Grant Access"
        panel.begin { [weak self] resp in
            guard let self = self, resp == .OK, let picked = panel.url else {
                completion(nil)
                return
            }
            self.saveBookmark(forExpectedURL: url, actualURL: picked)
            completion(self.resolveBookmark(for: url))
        }
    }

    func ensureAccess(to url: URL, completion: @escaping (URL?) -> Void) {
        if let resolved = resolveBookmark(for: url) {
            completion(resolved)
        } else {
            completion(nil)
        }
    }

    // Try to use an existing bookmark for this URL or any of its ancestors.
    // Always return a URL that is INSIDE the security-scoped root so FS reads are permitted.
    private func resolveBookmark(for url: URL) -> URL? {
        let target = url.standardizedFileURL
        var probe  = target
        while true {
            if let data = UserDefaults.standard.data(forKey: keyPrefix + probe.path) {
                var stale = false
                if let scopedRoot = try? URL(
                    resolvingBookmarkData: data,
                    options: [.withSecurityScope],
                    relativeTo: nil,
                    bookmarkDataIsStale: &stale
                ), !stale {
                    _ = scopedRoot.startAccessingSecurityScopedResource()

                    // Exact match → just return the scoped root
                    if scopedRoot.standardizedFileURL == probe {
                        // If the target is deeper than probe, append the remainder inside the scope
                        if target == probe { return scopedRoot }
                    }

                    // Build child URL under the scoped root
                    let rootPath   = scopedRoot.standardizedFileURL.path
                    let targetPath = target.path
                    if targetPath.hasPrefix(rootPath) {
                        let remainder = String(targetPath.dropFirst(rootPath.count))
                            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                        if remainder.isEmpty { return scopedRoot }
                        return remainder.split(separator: "/").reduce(scopedRoot) {
                            $0.appendingPathComponent(String($1))
                        }
                    } else {
                        // Best effort: return scoped root
                        return scopedRoot
                    }
                }
            }
            if probe.path == "/" { break }
            probe.deleteLastPathComponent()
        }
        return nil
    }

    private func saveBookmark(forExpectedURL expectedURL: URL, actualURL: URL) {
        if let data = try? actualURL.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(data, forKey: keyPrefix + expectedURL.standardizedFileURL.path)
        }
    }
}
