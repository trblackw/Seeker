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
        guard row >= 0, row < entries.count else { return }
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
import UniformTypeIdentifiers
import QuickLookThumbnailing

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
    private let scopePopUp = NSPopUpButton()
    private let grantHomeButton = NSButton(title: "Grant Home", target: nil, action: nil)
    private let scroll = NSScrollView()
    private let table = DirectoryTableView()

    // Preview (right) pane
    private let preview = NSView()
    private let previewImage = NSImageView()
    private let previewTitle = NSTextField(labelWithString: "")
    private let previewSubtitle = NSTextField(labelWithString: "")
    private let previewPrimary = NSButton(title: "Open", target: nil, action: nil)
    

    // Thumbnail cache
    private var thumbCache = NSCache<NSURL, NSImage>()

    // State
    private var items: [URL] = []
    private var filtered: [URL] = []
    private(set) var currentDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    private var query: String = ""
    private enum SearchScope { case all, currentFolder }
    private var searchScope: SearchScope = .all
    private var isShowingSearchResults = false
    private var searchResults: [URL] = []
    private var metadataQuery: NSMetadataQuery?
    private var homeURL: URL { FileManager.default.homeDirectoryForCurrentUser }

    private func updateHomeAccessButtonVisibility() {
        // Hide if we already have a bookmark for the home folder
        let has = FolderAccessManager.shared.hasAccess(for: homeURL) != nil
        grantHomeButton.isHidden = has
    }

    private func removeMetadataObservers() {
        if let mq = metadataQuery {
            NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidStartGathering, object: mq)
            NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidUpdate, object: mq)
            NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidFinishGathering, object: mq)
        }
    }

    // Navigation history
    private var backStack: [URL] = []
    private var forwardStack: [URL] = []
    private var crumbURLs: [URL] = []
    private var suppressHistoryPush = false

    // Key monitor for ⌘K focus
    private var keyMonitor: Any?
    
    @objc private func scopeChanged(_ sender: Any? = nil) {
        // 0 = All, 1 = Current Folder
        searchScope = (scopePopUp.indexOfSelectedItem == 0) ? .all : .currentFolder
        // Re-run current search to reflect new scope
        controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    }
    
    @objc private func grantHomeAccessTapped() {
        FolderAccessManager.shared.requestAccess(for: homeURL) { [weak self] granted in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if granted != nil {
                    self.updateHomeAccessButtonVisibility()
                    // If we’re already in All scope with a query, refresh Spotlight results
                    if self.searchScope == .all && !self.query.isEmpty {
                        self.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
                    }
                } else {
                    NSSound.beep()
                }
            }
        }
    }

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

        searchField.placeholderString = "Search…"
        searchField.font = FontToken.ui
        searchField.focusRingType = .none
        searchField.bezelStyle = .roundedBezel
        searchField.wantsLayer = true
        searchField.layer?.cornerRadius = 8
        searchField.layer?.backgroundColor = ColorSchemeToken.surface.cgColor
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(searchFieldChanged(_:))
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = false
        header.addSubview(searchField)

        // Scope selector (left of the search field)
        scopePopUp.addItems(withTitles: ["All", "Current Folder"])
        scopePopUp.target = self
        scopePopUp.action = #selector(scopeChanged)
        scopePopUp.font = FontToken.ui
        scopePopUp.bezelStyle = .rounded
        header.addSubview(scopePopUp)

        // One-click Home access (for sandboxed global search)
        grantHomeButton.target = self
        grantHomeButton.action = #selector(grantHomeAccessTapped)
        grantHomeButton.bezelStyle = .rounded
        grantHomeButton.font = FontToken.ui
        header.addSubview(grantHomeButton)

        pathLabel.translatesAutoresizingMaskIntoConstraints = false
        pathLabel.isHidden = true // breadcrumb bar supersedes the raw path text

        crumbBar.translatesAutoresizingMaskIntoConstraints = false
        searchField.translatesAutoresizingMaskIntoConstraints = false
        scopePopUp.translatesAutoresizingMaskIntoConstraints = false
        grantHomeButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            crumbBar.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: TZ.x4),
            crumbBar.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            crumbBar.trailingAnchor.constraint(lessThanOrEqualTo: grantHomeButton.leadingAnchor, constant: -TZ.x4),

            grantHomeButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            grantHomeButton.trailingAnchor.constraint(equalTo: scopePopUp.leadingAnchor, constant: -TZ.x3),

            scopePopUp.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            scopePopUp.trailingAnchor.constraint(equalTo: searchField.leadingAnchor, constant: -TZ.x3),

            searchField.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -TZ.x4),
            searchField.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            searchField.widthAnchor.constraint(equalToConstant: 260)
        ])

        preview.isHidden = true

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

        // Right preview panel
        preview.wantsLayer = true
        preview.layer?.backgroundColor = ColorSchemeToken.surface.cgColor
        view.addSubview(preview)
        preview.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            preview.leadingAnchor.constraint(equalTo: scroll.trailingAnchor),
            preview.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            preview.topAnchor.constraint(equalTo: header.bottomAnchor),
            preview.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            preview.widthAnchor.constraint(equalToConstant: 280)
        ])

        // Preview subviews
        previewImage.imageScaling = .scaleProportionallyUpOrDown
        preview.addSubview(previewImage)
        previewTitle.font = FontToken.uiMedium
        previewTitle.textColor = ColorSchemeToken.textPrimary
        previewTitle.lineBreakMode = .byTruncatingMiddle
        preview.addSubview(previewTitle)
        previewSubtitle.font = FontToken.ui
        previewSubtitle.textColor = ColorSchemeToken.textSecondary
        previewSubtitle.lineBreakMode = .byTruncatingMiddle
        preview.addSubview(previewSubtitle)
        previewPrimary.target = self
        previewPrimary.action = #selector(openSelected)
        previewPrimary.bezelStyle = .rounded
        preview.addSubview(previewPrimary)

        previewImage.translatesAutoresizingMaskIntoConstraints = false
        previewTitle.translatesAutoresizingMaskIntoConstraints = false
        previewSubtitle.translatesAutoresizingMaskIntoConstraints = false
        previewPrimary.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            previewImage.topAnchor.constraint(equalTo: preview.topAnchor, constant: TZ.x8),
            previewImage.centerXAnchor.constraint(equalTo: preview.centerXAnchor),
            previewImage.widthAnchor.constraint(equalToConstant: 180),
            previewImage.heightAnchor.constraint(equalToConstant: 120),

            previewTitle.topAnchor.constraint(equalTo: previewImage.bottomAnchor, constant: TZ.x5),
            previewTitle.leadingAnchor.constraint(equalTo: preview.leadingAnchor, constant: TZ.x5),
            previewTitle.trailingAnchor.constraint(equalTo: preview.trailingAnchor, constant: -TZ.x5),

            previewSubtitle.topAnchor.constraint(equalTo: previewTitle.bottomAnchor, constant: TZ.x2),
            previewSubtitle.leadingAnchor.constraint(equalTo: preview.leadingAnchor, constant: TZ.x5),
            previewSubtitle.trailingAnchor.constraint(equalTo: preview.trailingAnchor, constant: -TZ.x5),

            previewPrimary.topAnchor.constraint(equalTo: previewSubtitle.bottomAnchor, constant: TZ.x6),
            previewPrimary.leadingAnchor.constraint(equalTo: preview.leadingAnchor, constant: TZ.x5)
        ])

        table.target = self
        updateHomeAccessButtonVisibility()

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

    @objc private func searchFieldChanged(_ sender: NSSearchField) {
        performSearchUpdate(with: sender.stringValue)
    }

    private func performSearchUpdate(with raw: String) {
        query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            isShowingSearchResults = false
            searchResults.removeAll()
            filtered = items
            table.reloadData()
            return
        }
        switch searchScope {
        case .all:
            metadataQuery?.stop()
            removeMetadataObservers()
            let mq = NSMetadataQuery()
            metadataQuery = mq
            // Use only local / indexed scopes. Do NOT mix with iCloud scopes,
            // otherwise NSMetadataQuery throws an exception.
            var scopes: [String] = [
                NSMetadataQueryIndexedLocalComputerScope,
                NSMetadataQueryIndexedNetworkScope,
                NSMetadataQueryUserHomeScope
            ]
            // Fallback for older systems where `NSMetadataQueryUserHomeScope` may be
            // unavailable at runtime — just remove it if the symbol is empty.
            scopes = scopes.filter { !$0.isEmpty }
            mq.searchScopes = scopes
            mq.predicate = NSPredicate(
                format: "(kMDItemFSName CONTAINS[cd] %@) OR (kMDItemDisplayName CONTAINS[cd] %@)",
                query, query
            )
            NotificationCenter.default.addObserver(self, selector: #selector(metadataQueryStarted(_:)), name: .NSMetadataQueryDidStartGathering, object: mq)
            NotificationCenter.default.addObserver(self, selector: #selector(metadataQueryUpdated(_:)), name: .NSMetadataQueryDidUpdate, object: mq)
            NotificationCenter.default.addObserver(self, selector: #selector(metadataQueryUpdated(_:)), name: .NSMetadataQueryDidFinishGathering, object: mq)
            isShowingSearchResults = true
            searchResults.removeAll()
            table.reloadData()
            mq.start()
        case .currentFolder:
            isShowingSearchResults = false
            applyFilter()
        }
    }
    private enum ItemKind { case folder, file }

    private func itemKind(for url: URL) -> ItemKind {
        ((try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false) ? .folder : .file
    }

    private func displayName(for url: URL) -> String {
        (try? url.resourceValues(forKeys: [.localizedNameKey]).localizedName) ?? url.lastPathComponent
    }

    private func iconForList(url: URL, kind: ItemKind) -> NSImage {
        if kind == .folder, let img = NSImage(systemSymbolName: "folder", accessibilityDescription: nil) { return img }
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            return NSWorkspace.shared.icon(for: type)
        }
        return NSWorkspace.shared.icon(forFile: url.path)
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
        preview.isHidden = true
    }

    private func hidePlaceholder() {
        placeholder.isHidden = true
        scroll.isHidden = false
        preview.isHidden = true
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
        // Navigating cancels global search mode and updates home-button visibility
        isShowingSearchResults = false
        searchResults.removeAll()
        updateHomeAccessButtonVisibility()
        table.deselectAll(nil)
        preview.isHidden = true
        table.reloadData()
    }
    
    private func currentRows() -> [URL] {
          return isShowingSearchResults ? searchResults : filtered
      }
    
    deinit {
        removeMetadataObservers()
        metadataQuery?.stop()
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
        currentRows().count
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = table.selectedRow
        let rows = currentRows()
        guard row >= 0, rows.indices.contains(row) else {
            preview.isHidden = true
            return
        }
        preview.isHidden = false
        let url = rows[row]
        updatePreview(for: url)
    }


    private final class DirectoryCellView: NSTableCellView {
        let iconView = NSImageView()
        let nameField = NSTextField(labelWithString: "")

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            identifier = NSUserInterfaceItemIdentifier("cell")
            iconView.translatesAutoresizingMaskIntoConstraints = false
            iconView.imageScaling = .scaleProportionallyUpOrDown
            iconView.symbolConfiguration = .init(pointSize: 14, weight: .regular)
            addSubview(iconView)

            nameField.translatesAutoresizingMaskIntoConstraints = false
            nameField.font = FontToken.ui
            nameField.textColor = ColorSchemeToken.textPrimary
            addSubview(nameField)

            NSLayoutConstraint.activate([
                iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: TZ.x6),
                iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
                iconView.widthAnchor.constraint(equalToConstant: 16),
                iconView.heightAnchor.constraint(equalToConstant: 16),

                nameField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: TZ.x3),
                nameField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -TZ.x4),
                nameField.centerYAnchor.constraint(equalTo: centerYAnchor)
            ])
            self.textField = nameField
            self.imageView = iconView
        }

        required init?(coder: NSCoder) { fatalError() }
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("cell")
        let cell = tableView.makeView(withIdentifier: id, owner: self) as? DirectoryCellView ?? DirectoryCellView()
        let url = currentRows()[row]
        let kind = itemKind(for: url)
        cell.nameField.stringValue = displayName(for: url)
        cell.iconView.image = iconForList(url: url, kind: kind)
        cell.toolTip = url.path
        return cell
    }

    @objc func handleRowDoubleClick(_ sender: Any) {
        let row = table.clickedRow
        let rows = currentRows()
        guard row >= 0, rows.indices.contains(row) else { return }
        let url = rows[row]
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
            let rows = currentRows()
            if row >= 0, rows.indices.contains(row) {
                let url = rows[row]
                if let dirURL = resolvedDirectoryIfAny(for: url) {
                    navigate(to: dirURL)
                    return
                }
            }
        }
        super.keyDown(with: event)
    }
    
    @objc private func metadataQueryStarted(_ note: Notification) {
        // optional: spinner/progress later
    }

    @objc private func metadataQueryUpdated(_ note: Notification) {
        guard let mq = metadataQuery else { return }
        mq.disableUpdates()
        var urls: [URL] = []
        for i in 0..<mq.resultCount {
            if let item = mq.result(at: i) as? NSMetadataItem,
               let path = item.value(forAttribute: kMDItemPath as String) as? String {
                urls.append(URL(fileURLWithPath: path))
            }
            if urls.count > 5000 { break } // safety cap
        }
        mq.enableUpdates()
        self.isShowingSearchResults = true
        self.searchResults = urls
        self.table.reloadData()
        self.preview.isHidden = true
    }

    // MARK: - Search
    func controlTextDidChange(_ obj: Notification) {
        let text = (obj.object as? NSSearchField)?.stringValue ?? searchField.stringValue
        performSearchUpdate(with: text)
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
    private func humanSize(_ bytes: Int64) -> String {
        let fmt = ByteCountFormatter()
        fmt.allowedUnits = [.useMB, .useGB, .useKB]
        fmt.countStyle = .file
        return fmt.string(fromByteCount: bytes)
    }

    private func quickFolderStats(_ url: URL, limit: Int = 500) async -> (count: Int, bytes: Int64) {
        var count = 0
        var bytes: Int64 = 0
        let fm = FileManager.default
        if let en = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
            for case let u as URL in en {
                if count >= limit { break }
                let rv = try? u.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                if rv?.isRegularFile == true {
                    bytes += Int64(rv?.fileSize ?? 0)
                }
                count += 1
            }
        }
        return (count, bytes)
    }

    private func generateThumbnail(for url: URL, side: CGFloat = 256) async -> NSImage {
        if let cached = thumbCache.object(forKey: url as NSURL) { return cached }
        let req = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: side, height: side), scale: 2, representationTypes: .all)
        let gen = QLThumbnailGenerator.shared
        do {
            let rep = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<QLThumbnailRepresentation, Error>) in
                gen.generateBestRepresentation(for: req) { r, e in
                    if let r = r { cont.resume(returning: r) } else { cont.resume(throwing: e ?? NSError(domain: "thumb", code: -1)) }
                }
            }
            let img = rep.nsImage
            thumbCache.setObject(img, forKey: url as NSURL)
            return img
        } catch {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
    }

    private func updatePreview(for url: URL) {
        let kind = itemKind(for: url)
        previewTitle.stringValue = displayName(for: url)
        previewSubtitle.stringValue = ""
        previewImage.image = iconForList(url: url, kind: kind)
        previewPrimary.toolTip = "Open"

        if kind == .folder {
            Task.detached { [weak self] in
                guard let self else { return }
                let (cnt, bytes) = await self.quickFolderStats(url)
                await MainActor.run {
                    self.previewSubtitle.stringValue = "\(cnt) items · \(self.humanSize(bytes))"
                    self.previewImage.image = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil) ?? self.previewImage.image
                }
            }
        } else {
            Task.detached { [weak self] in
                guard let self else { return }
                let rv = try? url.resourceValues(forKeys: [.contentTypeKey, .fileSizeKey])
                let sizeStr = self.humanSize(Int64(rv?.fileSize ?? 0))
                let kindStr = rv?.contentType?.localizedDescription ?? "File"
                let thumb = await self.generateThumbnail(for: url, side: 360)
                await MainActor.run {
                    self.previewSubtitle.stringValue = "\(kindStr) · \(sizeStr)"
                    self.previewImage.image = thumb
                }
            }
        }
    }

    @objc private func openSelected() {
        let row = table.selectedRow
        let rows = currentRows()
        guard row >= 0, rows.indices.contains(row) else { return }
        let url = rows[row]
        if itemKind(for: url) == .folder {
            navigate(to: url)
        } else {
            // Keep in-app for now; no Finder. We will wire Quick Look panel later.
            NSSound.beep()
        }
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


