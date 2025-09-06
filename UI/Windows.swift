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

// Subtle hover-able button used for breadcrumbs
final class HoverButton: NSButton {
    private var tracking: NSTrackingArea?
    private var isHovering = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        bezelStyle = .inline
        wantsLayer = true
        layer?.cornerRadius = 3
        contentTintColor = ColorSchemeToken.textSecondary
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        tracking = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(tracking!)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        layer?.backgroundColor = ColorSchemeToken.surface.withAlphaComponent(0.18).cgColor
        contentTintColor = ColorSchemeToken.textPrimary
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        layer?.backgroundColor = NSColor.clear.cgColor
        contentTintColor = ColorSchemeToken.textSecondary
    }

    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

// MARK: - SidebarViewController
final class SidebarViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    enum SidebarItem {
        case header(String)
        case folder(name: String, url: URL)
        case group(SeekerGroup)
    }
    
    private var sidebarItems: [SidebarItem] = []
    
    private let folderEntries: [(String, String)] = [
        ("Documents", "Documents"),
        ("Desktop", "Desktop"), 
        ("Downloads", "Downloads"),
        ("Music", "Music"),
        ("Pictures", "Pictures"),
        ("Movies", "Movies")
    ]
    
    var firstEntryURL: URL? { 
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Documents")
    }
    
    private let table = SidebarTableView()
    private let scroll = NSScrollView()
    weak var delegate: SidebarSelectionDelegate?

    override func loadView() {
        self.view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = ColorSchemeToken.surface.cgColor
        
        buildSidebarItems()

        let col = NSTableColumn(identifier: .init("sidebar"))
        col.title = ""
        col.width = 200
        table.addTableColumn(col)
        table.headerView = nil
        table.rowSizeStyle = .small
        table.allowsMultipleSelection = false // Disable multiselection for sidebar
        if #available(macOS 11.0, *) {
            table.style = .sourceList
        } else {
            table.selectionHighlightStyle = .sourceList
        }
        
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
        
        // Listen for group changes to refresh sidebar
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshSidebar),
            name: NSNotification.Name("GroupsDidChange"),
            object: nil
        )
    }
    
    private func buildSidebarItems() {
        var items: [SidebarItem] = []
        
        // Folders section
        items.append(.header("FOLDERS"))
        let home = FileManager.default.homeDirectoryForCurrentUser
        for (displayName, folderName) in folderEntries {
            let url = home.appendingPathComponent(folderName)
            items.append(.folder(name: displayName, url: url))
        }
        
        // Groups section
        let allGroups = GroupStorageManager.shared.allGroups()
        if !allGroups.isEmpty {
            items.append(.header("GROUPS"))
            for group in allGroups.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) {
                items.append(.group(group))
            }
        }
        
        sidebarItems = items
    }
    
    @objc private func refreshSidebar() {
        buildSidebarItems()
        table.reloadData()
    }
    
    func refreshGroups() {
        buildSidebarItems()
        table.reloadData()
    }

    // MARK: - Table Data Source/Delegate
    func numberOfRows(in tableView: NSTableView) -> Int {
        return sidebarItems.count
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < sidebarItems.count else { return nil }
        let item = sidebarItems[row]
        
        switch item {
        case .header(let title):
            let id = NSUserInterfaceItemIdentifier("sidebarHeader")
            let cell = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? {
                let c = NSTableCellView()
                c.identifier = id
                let tf = NSTextField(labelWithString: "")
                tf.font = FontToken.small
                tf.textColor = ColorSchemeToken.textSecondary
                tf.alignment = .left
                c.textField = tf
                c.addSubview(tf)
                tf.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    tf.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: TZ.x4),
                    tf.centerYAnchor.constraint(equalTo: c.centerYAnchor),
                    tf.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -TZ.x4)
                ])
                return c
            }()
            cell.textField?.stringValue = title
            return cell
            
        case .folder(let name, _):
            let id = NSUserInterfaceItemIdentifier("sidebarFolder")
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
                    tf.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: TZ.x6),
                    tf.centerYAnchor.constraint(equalTo: c.centerYAnchor),
                    tf.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -TZ.x4)
                ])
                return c
            }()
            cell.textField?.stringValue = name
            return cell
            
        case .group(let group):
            let id = NSUserInterfaceItemIdentifier("sidebarGroup")
            let cell = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? {
                let c = NSTableCellView()
                c.identifier = id
                let tf = NSTextField(labelWithString: "")
                tf.font = FontToken.ui
                tf.textColor = ColorSchemeToken.accent
                c.textField = tf
                c.addSubview(tf)
                tf.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    tf.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: TZ.x6),
                    tf.centerYAnchor.constraint(equalTo: c.centerYAnchor),
                    tf.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -TZ.x4)
                ])
                return c
            }()
            cell.textField?.stringValue = group.name
            return cell
        }
    }
    
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        guard row < sidebarItems.count else { return false }
        
        // Headers are not selectable
        switch sidebarItems[row] {
        case .header:
            return false
        case .folder, .group:
            return true
        }
    }
    
    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = table.selectedRow
        guard row >= 0, row < sidebarItems.count else { return }
        
        switch sidebarItems[row] {
        case .folder(_, let url):
            delegate?.sidebarDidSelectDirectory(url)
        case .group(let group):
            delegate?.sidebarDidSelectGroup(group)
        case .header:
            break // Headers should not trigger selection
        }
    }
    
    // For initial selection programmatically if needed
    func selectRow(_ idx: Int) {
        table.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

protocol SidebarSelectionDelegate: AnyObject {
    func sidebarDidSelectDirectory(_ url: URL)
    func sidebarDidSelectGroup(_ group: SeekerGroup)
}

// MARK: - SeekerRootViewController with Split View
final class SeekerRootViewController: NSSplitViewController, SidebarSelectionDelegate {
    private let sidebarVC = SidebarViewController()
    private let directoryVC = DirectoryListViewController()
    private let commandPalette = CommandPaletteView()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupCommandPalette()

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
    
    private func setupCommandPalette() {
        // Add command palette to view hierarchy but keep it hidden
        view.addSubview(commandPalette, positioned: .above, relativeTo: nil)
        commandPalette.isHidden = true
        commandPalette.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            commandPalette.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            commandPalette.topAnchor.constraint(equalTo: view.topAnchor, constant: TZ.x16),
            commandPalette.widthAnchor.constraint(equalToConstant: 600),
            commandPalette.heightAnchor.constraint(equalToConstant: 400)
        ])
        
        // Listen for command palette toggle
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(toggleCommandPalette),
            name: .togglePalette,
            object: nil
        )
        
        // Setup initial commands
        setupCommands()
    }
    
    @objc private func toggleCommandPalette() {
        if commandPalette.isHidden {
            setupCommands() // Refresh commands
            commandPalette.show()
        } else {
            commandPalette.hide()
        }
    }
    
    private func setupCommands() {
        var commands: [Command] = []
        
        // Navigation commands
        commands.append(Command(title: "Go to Home", subtitle: "Navigate to home directory") {
            self.directoryVC.selectTarget(FileManager.default.homeDirectoryForCurrentUser)
        })
        
        commands.append(Command(title: "Go to Documents", subtitle: "Navigate to documents folder") {
            let docs = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
            self.directoryVC.selectTarget(docs)
        })
        
        commands.append(Command(title: "Go to Desktop", subtitle: "Navigate to desktop folder") {
            let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
            self.directoryVC.selectTarget(desktop)
        })
        
        // Group commands - only show if selection available
        if let currentDir = directoryVC.currentDirectory as URL? {
            let selectedItems = directoryVC.directoryItems(for: directoryVC.table.selectedRowIndexes)
            
            if selectedItems.count > 1 && selectedItems.allSatisfy({ !($0 is GroupItem) }) {
                commands.append(Command(title: "Create Group from Selection", subtitle: "Group \(selectedItems.count) selected items") {
                    self.directoryVC.createGroupFromSelection()
                })
            }
            
            // Show existing groups in current directory
            let groups = GroupStorageManager.shared.groupsInDirectory(currentDir)
            for group in groups {
                commands.append(Command(title: "Open Group: \(group.name)", subtitle: "View \(group.items.count) grouped items") {
                    self.directoryVC.showGroupContents(group)
                })
                
                commands.append(Command(title: "Delete Group: \(group.name)", subtitle: "Remove group (keeps files)") {
                    self.directoryVC.deleteGroup(group)
                })
            }
        }
        
        // File operations
        commands.append(Command(title: "Open Terminal Here", subtitle: "Open terminal in current directory") {
            self.directoryVC.openTerminalHere()
        })
        
        commandPalette.setCommands(commands)
    }

    // SidebarSelectionDelegate
    func sidebarDidSelectDirectory(_ url: URL) {
        directoryVC.selectTarget(url) // shows contents if already authorized, else a non-modal placeholder with a Grant Access button
    }
    
    func sidebarDidSelectGroup(_ group: SeekerGroup) {
        directoryVC.showGroupContents(group)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
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
import Quartz

// MARK: - Group Data Model

struct SeekerGroup: Codable, Identifiable {
    let id: UUID
    var name: String
    var items: [URL]
    var parentDirectory: URL
    var createdAt: Date
    var modifiedAt: Date
    
    init(name: String, items: [URL], parentDirectory: URL) {
        self.id = UUID()
        self.name = name
        self.items = items
        self.parentDirectory = parentDirectory
        self.createdAt = Date()
        self.modifiedAt = Date()
    }
    
    mutating func addItems(_ newItems: [URL]) {
        let uniqueNewItems = newItems.filter { !items.contains($0) }
        items.append(contentsOf: uniqueNewItems)
        modifiedAt = Date()
    }
    
    mutating func removeItems(_ itemsToRemove: [URL]) {
        items.removeAll { itemsToRemove.contains($0) }
        modifiedAt = Date()
    }
    
    mutating func rename(to newName: String) {
        name = newName
        modifiedAt = Date()
    }
}

// MARK: - Group Storage Manager

final class GroupStorageManager {
    static let shared = GroupStorageManager()
    
    private var groups: [SeekerGroup] = []
    private let storageURL: URL
    
    private init() {
        // Store groups in Application Support directory
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let seekerDir = appSupport.appendingPathComponent("Seeker")
        try? FileManager.default.createDirectory(at: seekerDir, withIntermediateDirectories: true)
        self.storageURL = seekerDir.appendingPathComponent("groups.json")
        loadGroups()
    }
    
    // MARK: - Persistence
    
    private func loadGroups() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        
        do {
            let data = try Data(contentsOf: storageURL)
            groups = try JSONDecoder().decode([SeekerGroup].self, from: data)
        } catch {
            print("Failed to load groups: \(error)")
        }
    }
    
    private func saveGroups() {
        do {
            let data = try JSONEncoder().encode(groups)
            try data.write(to: storageURL)
        } catch {
            print("Failed to save groups: \(error)")
        }
    }
    
    // MARK: - Group Management
    
    func createGroup(name: String, items: [URL], parentDirectory: URL) -> SeekerGroup {
        let group = SeekerGroup(name: name, items: items, parentDirectory: parentDirectory)
        groups.append(group)
        saveGroups()
        NotificationCenter.default.post(name: NSNotification.Name("GroupsDidChange"), object: nil)
        return group
    }
    
    func deleteGroup(_ group: SeekerGroup) {
        groups.removeAll { $0.id == group.id }
        saveGroups()
        NotificationCenter.default.post(name: NSNotification.Name("GroupsDidChange"), object: nil)
    }
    
    func updateGroup(_ group: SeekerGroup) {
        if let index = groups.firstIndex(where: { $0.id == group.id }) {
            groups[index] = group
            saveGroups()
            NotificationCenter.default.post(name: NSNotification.Name("GroupsDidChange"), object: nil)
        }
    }
    
    func groupsInDirectory(_ directory: URL) -> [SeekerGroup] {
        return groups.filter { $0.parentDirectory == directory }
    }
    
    func allGroups() -> [SeekerGroup] {
        return groups
    }
    
    func group(withId id: UUID) -> SeekerGroup? {
        return groups.first { $0.id == id }
    }
    
    // MARK: - Group Validation
    
    func validateGroup(_ group: SeekerGroup) -> SeekerGroup {
        // Remove items that no longer exist
        var updatedGroup = group
        let validItems = group.items.filter { FileManager.default.fileExists(atPath: $0.path) }
        
        if validItems.count != group.items.count {
            updatedGroup.items = validItems
            updatedGroup.modifiedAt = Date()
            updateGroup(updatedGroup)
        }
        
        return updatedGroup
    }
}

// MARK: - Directory Item Protocol

protocol DirectoryItem {
    var name: String { get }
    var url: URL { get }
    var isDirectory: Bool { get }
    var modificationDate: Date? { get }
    var size: Int64? { get }
}

// MARK: - File System Item

struct FileSystemItem: DirectoryItem {
    let url: URL
    let resourceValues: URLResourceValues
    
    var name: String { url.lastPathComponent }
    var isDirectory: Bool { resourceValues.isDirectory ?? false }
    var modificationDate: Date? { resourceValues.contentModificationDate }
    var size: Int64? { 
        if let fileSize = resourceValues.fileSize {
            return Int64(fileSize)
        }
        return nil
    }
    
    init(url: URL) throws {
        self.url = url
        self.resourceValues = try url.resourceValues(forKeys: [
            .isDirectoryKey, .contentModificationDateKey, .fileSizeKey
        ])
    }
}

// MARK: - Group Item

struct GroupItem: DirectoryItem {
    let group: SeekerGroup
    
    var name: String { group.name }
    var url: URL { 
        // Create a special URL scheme for groups
        URL(string: "seeker-group://\(group.id.uuidString)")!
    }
    var isDirectory: Bool { true }
    var modificationDate: Date? { group.modifiedAt }
    var size: Int64? { nil }
    
    init(group: SeekerGroup) {
        self.group = GroupStorageManager.shared.validateGroup(group)
    }
}

// Custom navigation button that handles right-click for history menu
final class NavigationButton: NSButton {
    var onRightClick: (() -> Void)?
    
    override func mouseDown(with event: NSEvent) {
        if event.type == .rightMouseDown {
            onRightClick?()
        } else {
            super.mouseDown(with: event)
        }
    }
    
    override func rightMouseDown(with event: NSEvent) {
        print("NavigationButton: Right mouse down detected")
        onRightClick?()
    }
}

// Custom table view that swallows default double-click "open" behavior
final class DirectoryTableView: NSTableView {
    weak var owner: DirectoryListViewController?

        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                if let controller = target as? DirectoryListViewController {
                    controller.handleRowDoubleClick(self)
                    return
                }
            }
            
            // Handle multiselection with Shift key
            let p = convert(event.locationInWindow, from: nil)
            let clickedRow = row(at: p)
            
            if clickedRow >= 0 && event.modifierFlags.contains(.shift) && selectedRowIndexes.count > 0 {
                // Shift-click: extend selection from first selected to clicked row
                let firstSelected = selectedRowIndexes.first ?? clickedRow
                let range = min(firstSelected, clickedRow)...max(firstSelected, clickedRow)
                selectRowIndexes(IndexSet(range), byExtendingSelection: false)
                return
            }
            
            super.mouseDown(with: event)
        }

        override func menu(for event: NSEvent) -> NSMenu? {
            let p = convert(event.locationInWindow, from: nil)
            let r = row(at: p)
            if r >= 0 {
                // If right-clicking on an already selected row, keep existing selection
                if selectedRowIndexes.contains(r) {
                    return owner?.buildContextMenu(for: selectedRowIndexes)
                } else {
                    selectRowIndexes(IndexSet(integer: r), byExtendingSelection: false)
                    return owner?.buildContextMenu(for: IndexSet(integer: r))
                }
            }
            return super.menu(for: event)
        }
}

// Row view that paints a subtle hover background (Linear-like) when not selected
final class HoverRowView: NSTableRowView {
    private var tracking: NSTrackingArea?
    private var isHovering = false

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        tracking = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(tracking!)
    }

    override func mouseEntered(with event: NSEvent) { isHovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent)  { isHovering = false; needsDisplay = true }

    override func drawBackground(in dirtyRect: NSRect) {
        if isSelected {
            super.drawBackground(in: dirtyRect) // let selection draw
            return
        }
        if isHovering {
            (ColorSchemeToken.surface.withAlphaComponent(0.12)).setFill()
            dirtyRect.fill()
        } else {
            super.drawBackground(in: dirtyRect)
        }
    }
}

enum ViewMode {
    case list
    case tree
}

struct TreeNode {
    let item: DirectoryItem
    let depth: Int
    let isExpanded: Bool
    let hasChildren: Bool
    
    init(item: DirectoryItem, depth: Int = 0, isExpanded: Bool = false, hasChildren: Bool = false) {
        self.item = item
        self.depth = depth
        self.isExpanded = isExpanded
        self.hasChildren = hasChildren
    }
}

final class DirectoryListViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    @objc override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    @objc override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = self
        panel.delegate = self
    }

    @objc override func endPreviewPanelControl(_ panel: QLPreviewPanel!) { }
    
    // QLPreviewPanelDataSource
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        return quickLookURLs.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard index >= 0, index < quickLookURLs.count else { return nil }
        return quickLookURLs[index] as NSURL
    }
    // MARK: - Context Menu
    func tableView(_ tableView: NSTableView, menuForRows rows: IndexSet) -> NSMenu? {
        return buildContextMenu(for: rows)
    }

    func buildContextMenu(for rows: IndexSet) -> NSMenu? {
        if rows.isEmpty { return nil }
        table.selectRowIndexes(rows, byExtendingSelection: false)

        let menu = NSMenu()
        let selectedItems = directoryItems(for: rows)
        let hasGroups = selectedItems.contains { $0 is GroupItem }
        let hasRegularFiles = selectedItems.contains { !($0 is GroupItem) }

        let openItem = NSMenuItem(title: "Open", action: #selector(ctxOpen), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        if !hasGroups {
            let quickLook = NSMenuItem(title: "Quick Look", action: #selector(ctxQuickLook), keyEquivalent: "")
            quickLook.target = self
            menu.addItem(quickLook)

            let openTerm = NSMenuItem(title: "Open in Terminal", action: #selector(ctxOpenInTerminal), keyEquivalent: "")
            openTerm.target = self
            menu.addItem(openTerm)
        }

        menu.addItem(NSMenuItem.separator())

        if !hasGroups {
            let duplicate = NSMenuItem(title: "Duplicate", action: #selector(ctxDuplicate), keyEquivalent: "")
            duplicate.target = self
            menu.addItem(duplicate)

            let compress = NSMenuItem(title: "Compress…", action: #selector(ctxCompress), keyEquivalent: "")
            compress.target = self
            menu.addItem(compress)

            let tag = NSMenuItem(title: "Tag…", action: #selector(ctxTag), keyEquivalent: "")
            tag.target = self
            menu.addItem(tag)
        }
        
        // Group actions
        if rows.count > 1 && hasRegularFiles && !hasGroups {
            menu.addItem(NSMenuItem.separator())
            
            let createGroup = NSMenuItem(title: "Create Group…", action: #selector(ctxCreateGroup), keyEquivalent: "")
            createGroup.target = self
            menu.addItem(createGroup)
        }
        
        // Add to existing group (when in regular directory view)
        if !isShowingGroupContents && rows.count >= 1 && hasRegularFiles && !hasGroups {
            let allGroups = GroupStorageManager.shared.allGroups()
            if !allGroups.isEmpty {
                menu.addItem(NSMenuItem.separator())
                
                let addToGroupMenu = NSMenu(title: "Add to Group")
                for group in allGroups.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) {
                    let item = NSMenuItem(title: group.name, action: #selector(ctxAddToExistingGroup(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = group
                    addToGroupMenu.addItem(item)
                }
                
                let addToGroupItem = NSMenuItem(title: "Add to Group", action: nil, keyEquivalent: "")
                addToGroupItem.submenu = addToGroupMenu
                menu.addItem(addToGroupItem)
            }
        }
        
        // Group-specific actions
        if rows.count == 1 && hasGroups {
            menu.addItem(NSMenuItem.separator())
            
            let addToGroup = NSMenuItem(title: "Add Items to Group…", action: #selector(ctxAddToGroup), keyEquivalent: "")
            addToGroup.target = self
            menu.addItem(addToGroup)
            
            let removeFromGroup = NSMenuItem(title: "Remove Items from Group…", action: #selector(ctxRemoveFromGroup), keyEquivalent: "")
            removeFromGroup.target = self
            // Only show if we're viewing group contents
            removeFromGroup.isHidden = !isShowingGroupContents
            menu.addItem(removeFromGroup)
            
            menu.addItem(NSMenuItem.separator())
            
            let renameGroup = NSMenuItem(title: "Rename Group…", action: #selector(ctxRenameGroup), keyEquivalent: "")
            renameGroup.target = self
            menu.addItem(renameGroup)
            
            let deleteGroup = NSMenuItem(title: "Delete Group", action: #selector(ctxDeleteGroup), keyEquivalent: "")
            deleteGroup.target = self
            menu.addItem(deleteGroup)
        }

        if !hasGroups {
            menu.addItem(NSMenuItem.separator())

            let copyPath = NSMenuItem(title: "Copy Path", action: #selector(ctxCopyPath), keyEquivalent: "")
            copyPath.target = self
            menu.addItem(copyPath)

            let renameItem = NSMenuItem(title: "Rename…", action: #selector(ctxRename), keyEquivalent: "")
            renameItem.target = self
            menu.addItem(renameItem)

            let deleteItem = NSMenuItem(title: "Move to Trash", action: #selector(ctxTrash), keyEquivalent: "")
            deleteItem.target = self
            menu.addItem(deleteItem)
        }

        return menu
    }

    // Helper to convert a set of rows into URLs from the active data source
    private func urls(for rows: IndexSet) -> [URL] {
        let rowsArray = rows.compactMap { $0 }
        
        if currentViewMode == .tree {
            return rowsArray.compactMap { idx in
                guard treeNodes.indices.contains(idx) else { return nil }
                let item = treeNodes[idx].item
                
                // For groups, we can't return a file URL, so we skip them in URL-based operations
                if item is GroupItem { return nil }
                return item.url
            }
        } else {
            let items = currentDirectoryItems()
            return rowsArray.compactMap { idx in
                guard items.indices.contains(idx) else { return nil }
                let item = items[idx]
                
                // For groups, we can't return a file URL, so we skip them in URL-based operations
                if item is GroupItem { return nil }
                return item.url
            }
        }
    }
    
    // Helper to get directory items from row indices
    func directoryItems(for rows: IndexSet) -> [DirectoryItem] {
        let rowsArray = rows.compactMap { $0 }
        
        if currentViewMode == .tree {
            return rowsArray.compactMap { idx in
                guard treeNodes.indices.contains(idx) else { return nil }
                return treeNodes[idx].item
            }
        } else {
            let items = currentDirectoryItems()
            return rowsArray.compactMap { idx in
                guard items.indices.contains(idx) else { return nil }
                return items[idx]
            }
        }
    }
    
    @objc private func ctxQuickLook() {
        // Build list of URLs from current selection and show the QL panel
        let selected = urls(for: table.selectedRowIndexes)
        guard !selected.isEmpty else { NSSound.beep(); return }
        quickLookURLs = selected
        QLPreviewPanel.shared()?.makeKeyAndOrderFront(nil)
    }

    // MARK: Context actions
    @objc private func ctxOpen() {
        let rows = table.selectedRowIndexes
        let urls = urls(for: rows)
        guard !urls.isEmpty else { return }
        if urls.count == 1, let dir = resolvedDirectoryIfAny(for: urls[0]) {
            navigate(to: dir)
        } else {
            // Open files with their default apps; folders navigate within Seeker
            for u in urls {
                if resolvedDirectoryIfAny(for: u) != nil { navigate(to: u) }
                else { NSWorkspace.shared.open(u) }
            }
        }
    }
    
    @objc private func ctxDuplicate() {
        let selected = urls(for: table.selectedRowIndexes)
        guard !selected.isEmpty else { return }
        let fm = FileManager.default
        for src in selected {
            let base = src.deletingPathExtension().lastPathComponent
            let ext  = src.pathExtension
            var i = 2
            var dest = src.deletingLastPathComponent()
                .appendingPathComponent("\(base) copy" + (ext.isEmpty ? "" : ".\(ext)"))
            while fm.fileExists(atPath: dest.path) {
                dest = src.deletingLastPathComponent()
                    .appendingPathComponent("\(base) copy \(i)" + (ext.isEmpty ? "" : ".\(ext)"))
                i += 1
            }
            do { try fm.copyItem(at: src, to: dest) } catch { NSSound.beep() }
        }
        openDirectory(currentDirectory)
    }

    @objc private func ctxCompress() {
        // Zip each selection beside its source
        let selected = urls(for: table.selectedRowIndexes)
        guard !selected.isEmpty else { return }
        for src in selected {
            let dest = src.deletingLastPathComponent().appendingPathComponent(src.lastPathComponent + ".zip")
            let task = Process()
            task.launchPath = "/usr/bin/zip"
            task.arguments = ["-r", dest.path, src.lastPathComponent]
            task.currentDirectoryPath = src.deletingLastPathComponent().path
            try? task.run()
        }
    }

    @objc private func ctxTag() {
        let selected = urls(for: table.selectedRowIndexes)
        guard !selected.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = "Add Tags"
        alert.informativeText = "Enter tags separated by commas."
        let tf = NSTextField(string: "")
        tf.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = tf
        alert.addButton(withTitle: "Apply")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            let tags = tf.stringValue
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            for url in selected {
                do {
                    // Use NSURL setter to avoid SDK cases where URLResourceValues.tagNames is get-only
                    let finalTags: [String]? = tags.isEmpty ? nil : tags
                    try (url as NSURL).setResourceValue(finalTags, forKey: .tagNamesKey)
                } catch {
                    NSSound.beep()
                }
            }
            openDirectory(currentDirectory)
        }
    }

    @objc private func ctxOpenInTerminal() {
        let rows = table.selectedRowIndexes
        let urls = urls(for: rows)
        guard let target = urls.first ?? currentRows().first else { return }
        let dir = resolvedDirectoryIfAny(for: target) ?? target.deletingLastPathComponent()
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-a", "Terminal", dir.path]
        try? task.run()
    }

    @objc private func ctxCopyPath() {
        let rows = table.selectedRowIndexes
        let paths = urls(for: rows).map { $0.path }
        guard !paths.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(paths.joined(separator: "\n"), forType: .string)
    }

    @objc private func ctxRename() {
        let rows = table.selectedRowIndexes
        guard rows.count == 1, let url = urls(for: rows).first else { return }

        let alert = NSAlert()
        alert.messageText = "Rename"
        alert.informativeText = "Enter a new name for \(url.lastPathComponent)."
        alert.alertStyle = .informational
        let tf = NSTextField(string: url.lastPathComponent)
        tf.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = tf
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            let newName = tf.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !newName.isEmpty, newName != url.lastPathComponent else { return }
            let dest = url.deletingLastPathComponent().appendingPathComponent(newName)
            do {
                try FileManager.default.moveItem(at: url, to: dest)
                // Refresh directory listing
                openDirectory(currentDirectory)
            } catch {
                NSSound.beep()
            }
        }
    }

    @objc private func ctxTrash() {
        let rows = table.selectedRowIndexes
        let urls = urls(for: rows)
        guard !urls.isEmpty else { return }
        for u in urls {
            _ = try? FileManager.default.trashItem(at: u, resultingItemURL: nil)
        }
        openDirectory(currentDirectory)
    }
    
    @objc private func ctxCreateGroup() {
        let rows = table.selectedRowIndexes
        let urls = urls(for: rows)
        guard urls.count > 1 else { return }
        
        let alert = NSAlert()
        alert.messageText = "Create Group"
        alert.informativeText = "Enter a name for the group containing \(urls.count) items."
        alert.alertStyle = .informational
        
        let tf = NSTextField(string: "New Group")
        tf.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = tf
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        
        if alert.runModal() == .alertFirstButtonReturn {
            let groupName = tf.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !groupName.isEmpty else { return }
            
            _ = GroupStorageManager.shared.createGroup(
                name: groupName,
                items: urls,
                parentDirectory: currentDirectory
            )
            
            // Refresh directory listing to show the new group
            openDirectory(currentDirectory)
        }
    }
    
    @objc private func ctxDeleteGroup() {
        let rows = table.selectedRowIndexes
        let items = directoryItems(for: rows)
        guard let groupItem = items.first as? GroupItem else { return }
        
        deleteGroup(groupItem.group)
    }
    
    @objc private func ctxRenameGroup() {
        let rows = table.selectedRowIndexes
        let items = directoryItems(for: rows)
        guard let groupItem = items.first as? GroupItem else { return }
        
        let alert = NSAlert()
        alert.messageText = "Rename Group"
        alert.informativeText = "Enter a new name for the group."
        alert.alertStyle = .informational
        
        let tf = NSTextField(string: groupItem.group.name)
        tf.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = tf
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        
        if alert.runModal() == .alertFirstButtonReturn {
            let newName = tf.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !newName.isEmpty, newName != groupItem.group.name else { return }
            
            var updatedGroup = groupItem.group
            updatedGroup.rename(to: newName)
            GroupStorageManager.shared.updateGroup(updatedGroup)
            
            // Refresh directory listing
            openDirectory(currentDirectory)
        }
    }
    
    @objc private func ctxAddToGroup() {
        let rows = table.selectedRowIndexes
        let items = directoryItems(for: rows)
        guard let groupItem = items.first as? GroupItem else { return }
        
        // Show file picker to select items to add
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.directoryURL = currentDirectory
        
        if panel.runModal() == .OK {
            var updatedGroup = groupItem.group
            updatedGroup.addItems(panel.urls)
            GroupStorageManager.shared.updateGroup(updatedGroup)
            
            // Refresh display
            if isShowingGroupContents {
                showGroupContents(updatedGroup)
            } else {
                openDirectory(currentDirectory)
            }
        }
    }
    
    @objc private func ctxRemoveFromGroup() {
        guard isShowingGroupContents, let group = currentGroup else { return }
        
        let rows = table.selectedRowIndexes
        let urls = urls(for: rows)
        guard !urls.isEmpty else { return }
        
        let alert = NSAlert()
        alert.messageText = "Remove from Group"
        alert.informativeText = "Remove \(urls.count) item(s) from the group \"\(group.name)\"? The files will remain in their original locations."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        
        if alert.runModal() == .alertFirstButtonReturn {
            var updatedGroup = group
            updatedGroup.removeItems(urls)
            GroupStorageManager.shared.updateGroup(updatedGroup)
            
            // Refresh group contents view
            if updatedGroup.items.isEmpty {
                // If group is now empty, exit group view
                exitGroupView()
            } else {
                showGroupContents(updatedGroup)
            }
        }
    }
    
    @objc private func ctxAddToExistingGroup(_ sender: NSMenuItem) {
        guard let group = sender.representedObject as? SeekerGroup else { return }
        
        let rows = table.selectedRowIndexes
        let urls = urls(for: rows)
        guard !urls.isEmpty else { return }
        
        var updatedGroup = group
        updatedGroup.addItems(urls)
        GroupStorageManager.shared.updateGroup(updatedGroup)
        
        // Show confirmation
        let alert = NSAlert()
        alert.messageText = "Added to Group"
        alert.informativeText = "Added \(urls.count) item(s) to group \"\(group.name)\"."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - Context Menu
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
    private let navigationContainer = NSStackView()
    private let backButton = NavigationButton()
    private let forwardButton = NSButton()
    private let pathLabel = NSTextField(labelWithString: "")
    private let crumbBar = NSStackView()
    private let searchField = NSSearchField()
    private let scopePopUp = NSPopUpButton()
    private let viewModeControl = NSSegmentedControl()
    private let grantHomeButton = NSButton(title: "Grant Home", target: nil, action: nil)
    
    // View mode state
    private var currentViewMode: ViewMode = .list
    private var treeNodes: [TreeNode] = []
    private var expandedFolders: Set<URL> = []
    private var expandedGroups: Set<String> = []
    private let scroll = NSScrollView()
    let table = DirectoryTableView()

    // Preview (right) pane
    private let preview = NSView()
    private let previewImage = NSImageView()
    private let previewTitle = NSTextField(labelWithString: "")
    private let previewSubtitle = NSTextField(labelWithString: "")
    private let previewPrimary = NSButton(title: "Open", target: nil, action: nil)
    

    // Thumbnail cache
    private var thumbCache = NSCache<NSURL, NSImage>()
    // Quick Look state
    private var quickLookURLs: [URL] = []

    // State
    private var items: [URL] = []
    private var filtered: [URL] = []
    private var groupItems: [SeekerGroup] = []
    private var allDirectoryItems: [DirectoryItem] = []
    private var filteredDirectoryItems: [DirectoryItem] = []
    private var currentGroup: SeekerGroup?
    private var isShowingGroupContents = false
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
    enum NavigationEntry {
        case directory(URL)
        case group(SeekerGroup, parentDirectory: URL)
        
        var displayName: String {
            switch self {
            case .directory(let url):
                return url.lastPathComponent
            case .group(let group, _):
                return group.name
            }
        }
        
        var isGroup: Bool {
            if case .group = self { return true }
            return false
        }
    }
    
    private var backStack: [NavigationEntry] = []
    private var forwardStack: [NavigationEntry] = []
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
    
    @objc private func viewModeChanged() {
        currentViewMode = viewModeControl.selectedSegment == 0 ? .list : .tree
        if currentViewMode == .tree {
            // Auto-expand first few folders for demonstration
            autoExpandInitialFolders()
            buildTreeNodes()
        }
        table.reloadData()
    }
    
    private func autoExpandInitialFolders() {
        let items = isShowingSearchResults ? searchResults.compactMap { try? FileSystemItem(url: $0) } : filteredDirectoryItems
        
        // Auto-expand first few folders/groups to show tree structure
        autoExpandItems(items, maxItems: 3, currentDepth: 0, maxDepth: 5)
    }
    
    private func autoExpandItems(_ items: [DirectoryItem], maxItems: Int, currentDepth: Int, maxDepth: Int) {
        guard currentDepth <= maxDepth else { return }
        
        var expandCount = 0
        for item in items {
            if expandCount >= maxItems { break }
            
            if let groupItem = item as? GroupItem {
                if !expandedGroups.contains(groupItem.name) {
                    expandedGroups.insert(groupItem.name)
                    expandCount += 1
                    
                    // Recursively expand children
                    let children = getChildItems(for: item)
                    autoExpandItems(children, maxItems: 2, currentDepth: currentDepth + 1, maxDepth: maxDepth)
                }
            } else if itemHasChildren(item) {
                if !expandedFolders.contains(item.url) {
                    expandedFolders.insert(item.url)
                    expandCount += 1
                    
                    // Recursively expand children
                    let children = getChildItems(for: item)
                    autoExpandItems(children, maxItems: 2, currentDepth: currentDepth + 1, maxDepth: maxDepth)
                }
            }
        }
    }
    
    private func buildTreeNodes() {
        treeNodes = []
        let items: [DirectoryItem]
        if isShowingSearchResults {
            items = searchResults.compactMap { try? FileSystemItem(url: $0) }
        } else {
            items = filteredDirectoryItems
        }
        
        for item in items {
            let node = TreeNode(item: item, depth: 0, isExpanded: isItemExpanded(item), hasChildren: itemHasChildren(item))
            treeNodes.append(node)
            
            // Add children if expanded
            if node.isExpanded && node.hasChildren {
                addChildNodes(for: item, depth: 1)
            }
        }
    }
    
    private func addChildNodes(for item: DirectoryItem, depth: Int) {
        let children = getChildItems(for: item)
        for child in children {
            let node = TreeNode(item: child, depth: depth, isExpanded: isItemExpanded(child), hasChildren: itemHasChildren(child))
            treeNodes.append(node)
            
            if node.isExpanded && node.hasChildren {
                addChildNodes(for: child, depth: depth + 1)
            }
        }
    }
    
    private func isItemExpanded(_ item: DirectoryItem) -> Bool {
        if let groupItem = item as? GroupItem {
            return expandedGroups.contains(groupItem.name)
        } else {
            return expandedFolders.contains(item.url)
        }
    }
    
    private func itemHasChildren(_ item: DirectoryItem) -> Bool {
        if let groupItem = item as? GroupItem {
            return !groupItem.group.items.isEmpty
        } else {
            let url = item.url
            // First check if it's a directory
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else {
                return false
            }
            // Then check if it actually contains any items
            guard let contents = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
                return false
            }
            return !contents.isEmpty
        }
    }
    
    private func getChildItems(for item: DirectoryItem) -> [DirectoryItem] {
        if let groupItem = item as? GroupItem {
            return groupItem.group.items.compactMap { try? FileSystemItem(url: $0) }
        } else {
            let url = item.url
            guard let contents = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
                return []
            }
            return contents.compactMap { try? FileSystemItem(url: $0) }
        }
    }
    
    private func toggleTreeNodeExpansion(for item: DirectoryItem) {
        if let groupItem = item as? GroupItem {
            if expandedGroups.contains(groupItem.name) {
                expandedGroups.remove(groupItem.name)
            } else {
                expandedGroups.insert(groupItem.name)
            }
        } else {
            if expandedFolders.contains(item.url) {
                expandedFolders.remove(item.url)
            } else {
                expandedFolders.insert(item.url)
            }
        }
        
        // Rebuild tree nodes and reload table
        buildTreeNodes()
        table.reloadData()
    }
    
    private func toggleNodeExpansion(for cell: DirectoryCellView) {
        // Find the item corresponding to this cell
        let index = table.row(for: cell)
        guard index >= 0, 
              index < treeNodes.count else { return }
        
        let node = treeNodes[index]
        toggleTreeNodeExpansion(for: node.item)
    }
    
    private func openItem(_ item: DirectoryItem) {
        if let groupItem = item as? GroupItem {
            showGroupContents(groupItem.group)
        } else {
            let url = item.url
            NSWorkspace.shared.open(url)
        }
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
        
        // Navigation buttons
        setupNavigationButtons()

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
        searchField.layer?.cornerRadius = 4
        searchField.layer?.backgroundColor = ColorSchemeToken.surface.cgColor
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(searchFieldChanged(_:))
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = false
        searchField.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(searchField)

        // Scope selector (left of the search field)
        scopePopUp.addItems(withTitles: ["All", "Current Folder"])
        scopePopUp.target = self
        scopePopUp.action = #selector(scopeChanged)
        scopePopUp.font = FontToken.ui
        scopePopUp.bezelStyle = .inline
        scopePopUp.setContentHuggingPriority(.required, for: .horizontal)
        scopePopUp.setContentCompressionResistancePriority(.required, for: .horizontal)
        scopePopUp.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(scopePopUp)
        
        // View mode toggle
        viewModeControl.segmentCount = 2
        viewModeControl.setImage(NSImage(systemSymbolName: "list.bullet", accessibilityDescription: "List View"), forSegment: 0)
        viewModeControl.setImage(NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: "Tree View"), forSegment: 1)
        viewModeControl.selectedSegment = 0
        viewModeControl.target = self
        viewModeControl.action = #selector(viewModeChanged)
        viewModeControl.font = FontToken.ui
        viewModeControl.setContentHuggingPriority(.required, for: .horizontal)
        viewModeControl.setContentCompressionResistancePriority(.required, for: .horizontal)
        viewModeControl.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(viewModeControl)

        // One-click Home access (for sandboxed global search)
        grantHomeButton.target = self
        grantHomeButton.action = #selector(grantHomeAccessTapped)
        grantHomeButton.bezelStyle = .inline
        grantHomeButton.font = FontToken.ui
        grantHomeButton.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(grantHomeButton)

        pathLabel.translatesAutoresizingMaskIntoConstraints = false
        pathLabel.isHidden = true // breadcrumb bar supersedes the raw path text

        crumbBar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            navigationContainer.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: TZ.x4),
            navigationContainer.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            
            crumbBar.leadingAnchor.constraint(equalTo: navigationContainer.trailingAnchor, constant: TZ.x3),
            crumbBar.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            crumbBar.trailingAnchor.constraint(lessThanOrEqualTo: grantHomeButton.leadingAnchor, constant: -TZ.x4),

            grantHomeButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            grantHomeButton.trailingAnchor.constraint(equalTo: scopePopUp.leadingAnchor, constant: -TZ.x3),

            scopePopUp.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            scopePopUp.trailingAnchor.constraint(equalTo: viewModeControl.leadingAnchor, constant: -TZ.x3),
            
            viewModeControl.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            viewModeControl.trailingAnchor.constraint(equalTo: searchField.leadingAnchor, constant: -TZ.x3),

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
        table.rowSizeStyle = .small
        table.allowsMultipleSelection = true
        table.selectionHighlightStyle = .regular
        table.menu = NSMenu()   // enables contextual menu; our subclass supplies items

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
        previewPrimary.bezelStyle = .inline
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
        table.owner = self
        updateHomeAccessButtonVisibility()
        updateNavigationButtons()

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
        placeholderButton.bezelStyle = .inline
        placeholder.addSubview(placeholderButton)

        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            placeholderLabel.centerXAnchor.constraint(equalTo: placeholder.centerXAnchor),
            placeholderLabel.centerYAnchor.constraint(equalTo: placeholder.centerYAnchor, constant: -12),
            placeholderButton.centerXAnchor.constraint(equalTo: placeholder.centerXAnchor),
            placeholderButton.topAnchor.constraint(equalTo: placeholderLabel.bottomAnchor, constant: TZ.x4)
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

            let btn = HoverButton(title: (i == 0 && c == "/") ? "Macintosh HD" : c, target: self, action: #selector(breadcrumbTapped(_:)))
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
            guard let self = self else { return }
            DispatchQueue.main.async {
                if let u = grantedURL {
                    self.hidePlaceholder()
                    self.openDirectory(u)
                } else {
                    // No bookmark yet – behave like the sidebar: show non-modal CTA
                    self.pendingURLForGrant = url
                    self.showPlaceholder(for: url)
                }
            }
        }
    }

    @objc private func breadcrumbTapped(_ sender: NSButton) {
        let idx = sender.tag
        guard idx >= 0 && idx < crumbURLs.count else { return }
        // Use the same flow as the sidebar – either navigate immediately or show grant-access UI
        selectTarget(crumbURLs[idx])
    }
    
    private func setupNavigationButtons() {
        // Configure back button
        backButton.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Back")
        backButton.isBordered = false
        backButton.bezelStyle = .inline
        backButton.target = self
        backButton.action = #selector(backButtonClicked)
        backButton.wantsLayer = true
        backButton.layer?.cornerRadius = 3
        
        // Set up right-click handler for history menu
        backButton.onRightClick = { [weak self] in
            self?.showBackHistoryMenu(for: self?.backButton)
        }
        
        // Configure forward button  
        forwardButton.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Forward")
        forwardButton.isBordered = false
        forwardButton.bezelStyle = .inline
        forwardButton.target = self
        forwardButton.action = #selector(forwardButtonClicked)
        forwardButton.wantsLayer = true
        forwardButton.layer?.cornerRadius = 3
        
        // Setup navigation container
        navigationContainer.orientation = .horizontal
        navigationContainer.alignment = .centerY
        navigationContainer.spacing = 2
        navigationContainer.addArrangedSubview(backButton)
        navigationContainer.addArrangedSubview(forwardButton)
        
        header.addSubview(navigationContainer)
        navigationContainer.translatesAutoresizingMaskIntoConstraints = false
        
        // Set button sizes
        NSLayoutConstraint.activate([
            backButton.widthAnchor.constraint(equalToConstant: 28),
            backButton.heightAnchor.constraint(equalToConstant: 28),
            forwardButton.widthAnchor.constraint(equalToConstant: 28),
            forwardButton.heightAnchor.constraint(equalToConstant: 28)
        ])
    }
    
    private func updateNavigationButtons() {
        backButton.isEnabled = !backStack.isEmpty
        forwardButton.isEnabled = !forwardStack.isEmpty
        
        // Style enabled/disabled states
        backButton.contentTintColor = backStack.isEmpty ? ColorSchemeToken.textSecondary : ColorSchemeToken.textPrimary
        forwardButton.contentTintColor = forwardStack.isEmpty ? ColorSchemeToken.textSecondary : ColorSchemeToken.textPrimary
    }
    
    @objc private func backButtonClicked() {
        goBackOne()
    }
    
    @objc private func forwardButtonClicked() {
        goForwardOne()
    }
    
    private func showBackHistoryMenu(for button: NSButton?) {
        print("showBackHistoryMenu called, backStack.count: \(backStack.count)")
        guard let button = button, !backStack.isEmpty else { 
            print("showBackHistoryMenu: early return - button is nil or backStack is empty")
            return 
        }
        
        let menu = NSMenu()
        
        // Add recent history items (up to 5)
        let recentHistory = Array(backStack.suffix(5).reversed())
        
        for (index, entry) in recentHistory.enumerated() {
            let menuItem = NSMenuItem(title: entry.displayName, action: #selector(navigateToHistoryEntry(_:)), keyEquivalent: "")
            menuItem.target = self
            menuItem.tag = backStack.count - index - 1 // Convert to backStack index
            
            // Add icon for groups vs directories
            if entry.isGroup {
                menuItem.image = NSImage(systemSymbolName: "folder.badge.gearshape", accessibilityDescription: "Group")
            } else {
                menuItem.image = NSImage(systemSymbolName: "folder", accessibilityDescription: "Folder")
            }
            
            menu.addItem(menuItem)
        }
        
        // Show menu below the back button
        print("showBackHistoryMenu: showing menu with \(menu.items.count) items")
        let menuLocation = NSPoint(x: 0, y: button.bounds.height)
        menu.popUp(positioning: menu.items.first, at: menuLocation, in: button)
    }
    
    @objc private func navigateToHistoryEntry(_ sender: NSMenuItem) {
        let targetIndex = sender.tag
        guard targetIndex >= 0 && targetIndex < backStack.count else { return }
        
        // Move all entries after the target to forward stack
        let itemsToMoveToForward = Array(backStack.suffix(backStack.count - targetIndex - 1))
        forwardStack = itemsToMoveToForward + forwardStack
        
        // Remove items from back stack up to and including target
        let targetEntry = backStack[targetIndex]
        backStack.removeLast(backStack.count - targetIndex)
        
        // Navigate to the selected entry
        navigateToEntry(targetEntry)
    }
    
    private func navigateToEntry(_ entry: NavigationEntry) {
        suppressHistoryPush = true
        defer { suppressHistoryPush = false }
        
        switch entry {
        case .directory(let url):
            if isShowingGroupContents {
                exitGroupView()
            }
            openDirectory(url)
        case .group(let group, let parentDir):
            currentDirectory = parentDir
            showGroupContents(group)
        }
        
        updateNavigationButtons()
    }
    
    private func goBackOne() {
        guard !backStack.isEmpty else { return }
        
        let previousEntry = backStack.removeLast()
        
        // Add current state to forward stack
        let currentEntry: NavigationEntry
        if isShowingGroupContents, let group = currentGroup {
            currentEntry = .group(group, parentDirectory: currentDirectory)
        } else {
            currentEntry = .directory(currentDirectory)
        }
        forwardStack.insert(currentEntry, at: 0)
        
        // Navigate to previous entry
        navigateToEntry(previousEntry)
    }
    
    private func goForwardOne() {
        guard !forwardStack.isEmpty else { return }
        
        let nextEntry = forwardStack.removeFirst()
        
        // Add current state to back stack
        let currentEntry: NavigationEntry
        if isShowingGroupContents, let group = currentGroup {
            currentEntry = .group(group, parentDirectory: currentDirectory)
        } else {
            currentEntry = .directory(currentDirectory)
        }
        backStack.append(currentEntry)
        
        // Navigate to next entry
        navigateToEntry(nextEntry)
    }

    private func updatePathLabel() {
        if isShowingGroupContents, let group = currentGroup {
            pathLabel.stringValue = "🗂 \(group.name) (\(group.items.count) items)"
        } else {
            pathLabel.stringValue = currentDirectory.path
        }
        rebuildBreadcrumb()
    }

    func openDirectory(_ url: URL) {
        if url != currentDirectory && !suppressHistoryPush {
            let currentEntry: NavigationEntry
            if isShowingGroupContents, let group = currentGroup {
                currentEntry = .group(group, parentDirectory: currentDirectory)
            } else {
                currentEntry = .directory(currentDirectory)
            }
            backStack.append(currentEntry)
            forwardStack.removeAll()
        }
        
        // Exit group view if we were in one
        if isShowingGroupContents {
            isShowingGroupContents = false
            currentGroup = nil
        }
        
        currentDirectory = url
        updatePathLabel()
        
        // Load file system items
        let fm = FileManager.default
        var fileSystemItems: [DirectoryItem] = []
        do {
            let contents = try fm.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .localizedNameKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
            // Convert URLs to FileSystemItems
            fileSystemItems = contents.compactMap { url in
                try? FileSystemItem(url: url)
            }
        } catch {
            fileSystemItems = []
        }
        
        // Load groups for this directory
        let groups = GroupStorageManager.shared.groupsInDirectory(url)
        let groupItems: [DirectoryItem] = groups.map { GroupItem(group: $0) }
        
        // Combine and sort all items: groups first, then folders, then files
        allDirectoryItems = (groupItems + fileSystemItems).sorted { a, b in
            // Groups first
            let aIsGroup = a is GroupItem
            let bIsGroup = b is GroupItem
            if aIsGroup != bIsGroup { return aIsGroup && !bIsGroup }
            
            // Then folders before files
            if !aIsGroup && !bIsGroup {
                if a.isDirectory != b.isDirectory { return a.isDirectory && !b.isDirectory }
            }
            
            // Finally sort by name
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
        
        // Keep the old URL-based items for compatibility with existing code
        items = fileSystemItems.map { $0.url }
        self.groupItems = groups
        
        if query.isEmpty {
            filtered = items
            filteredDirectoryItems = allDirectoryItems
        } else {
            applyFilter()
        }
        
        // Navigating cancels global search mode and updates home-button visibility
        isShowingSearchResults = false
        searchResults.removeAll()
        updateHomeAccessButtonVisibility()
        table.deselectAll(nil)
        preview.isHidden = true
        table.reloadData()
        updateNavigationButtons()
    }
    
    private func currentRows() -> [URL] {
        return isShowingSearchResults ? searchResults : filtered
    }
    
    private func currentDirectoryItems() -> [DirectoryItem] {
        return isShowingSearchResults ? searchResults.compactMap { try? FileSystemItem(url: $0) } : filteredDirectoryItems
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
        // Use the new navigation system
        goBackOne()
    }

    func goForward() {
        // Use the new navigation system
        goForwardOne()
    }

    func openTerminalHere() {
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-a", "Terminal", currentDirectory.path]
        try? task.run()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        if currentViewMode == .tree {
            return treeNodes.count
        }
        return isShowingSearchResults ? searchResults.count : filteredDirectoryItems.count
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = table.selectedRow
        
        if currentViewMode == .tree {
            guard row >= 0, row < treeNodes.count else {
                preview.isHidden = true
                return
            }
            preview.isHidden = false
            let node = treeNodes[row]
            updatePreview(for: node.item.url)
        } else {
            let rows = currentRows()
            guard row >= 0, rows.indices.contains(row) else {
                preview.isHidden = true
                return
            }
            preview.isHidden = false
            let url = rows[row]
            updatePreview(for: url)
        }
    }


    private final class DirectoryCellView: NSTableCellView {
        let iconView = NSImageView()
        let nameField = NSTextField(labelWithString: "")
        private let indentGuideView = NSView()
        private let disclosureTriangle = NSImageView()
        
        var treeDepth: Int = 0 {
            didSet { updateIndentation() }
        }
        
        var showIndentGuide: Bool = false {
            didSet { updateIndentGuide() }
        }
        
        var hasChildren: Bool = false {
            didSet { updateDisclosureTriangle() }
        }
        
        var isExpanded: Bool = false {
            didSet { updateDisclosureTriangle() }
        }
        
        var isInTreeMode: Bool = false {
            didSet { updateDisclosureTriangle() }
        }
        
        weak var windowController: DirectoryListViewController?
        
        private var leadingConstraint: NSLayoutConstraint!
        private var guideLeadingConstraint: NSLayoutConstraint!
        private var triangleLeadingConstraint: NSLayoutConstraint!

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            identifier = NSUserInterfaceItemIdentifier("cell")
            
            // Indent guide setup
            indentGuideView.wantsLayer = true
            indentGuideView.layer?.backgroundColor = ColorSchemeToken.accent.withAlphaComponent(0.3).cgColor
            indentGuideView.isHidden = true
            addSubview(indentGuideView)
            
            // Disclosure triangle setup
            disclosureTriangle.translatesAutoresizingMaskIntoConstraints = false
            disclosureTriangle.imageScaling = .scaleProportionallyUpOrDown
            disclosureTriangle.symbolConfiguration = .init(pointSize: 10, weight: .medium)
            disclosureTriangle.isHidden = true
            
            // Add click handling for disclosure triangle
            let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(triangleClicked))
            disclosureTriangle.addGestureRecognizer(clickGesture)
            
            addSubview(disclosureTriangle)
            
            iconView.translatesAutoresizingMaskIntoConstraints = false
            iconView.imageScaling = .scaleProportionallyUpOrDown
            iconView.symbolConfiguration = .init(pointSize: 14, weight: .regular)
            addSubview(iconView)

            nameField.translatesAutoresizingMaskIntoConstraints = false
            nameField.font = FontToken.ui
            nameField.textColor = ColorSchemeToken.textPrimary
            addSubview(nameField)
            
            indentGuideView.translatesAutoresizingMaskIntoConstraints = false
            leadingConstraint = iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: TZ.x6)
            guideLeadingConstraint = indentGuideView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: TZ.x6)
            triangleLeadingConstraint = disclosureTriangle.leadingAnchor.constraint(equalTo: leadingAnchor, constant: TZ.x6 - 16)

            NSLayoutConstraint.activate([
                leadingConstraint,
                iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
                iconView.widthAnchor.constraint(equalToConstant: 16),
                iconView.heightAnchor.constraint(equalToConstant: 16),

                nameField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: TZ.x3),
                nameField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -TZ.x4),
                nameField.centerYAnchor.constraint(equalTo: centerYAnchor),
                
                // Disclosure triangle constraints
                triangleLeadingConstraint,
                disclosureTriangle.centerYAnchor.constraint(equalTo: centerYAnchor),
                disclosureTriangle.widthAnchor.constraint(equalToConstant: 12),
                disclosureTriangle.heightAnchor.constraint(equalToConstant: 12),
                
                // Indent guide constraints
                guideLeadingConstraint,
                indentGuideView.topAnchor.constraint(equalTo: topAnchor),
                indentGuideView.bottomAnchor.constraint(equalTo: bottomAnchor),
                indentGuideView.widthAnchor.constraint(equalToConstant: 1)
            ])
            self.textField = nameField
            self.imageView = iconView
        }

        required init?(coder: NSCoder) { fatalError() }
        
        private func updateIndentation() {
            let indentAmount = CGFloat(treeDepth * 20) // 20pt per level
            leadingConstraint.constant = TZ.x6 + indentAmount
            triangleLeadingConstraint.constant = TZ.x6 + indentAmount - 16
        }
        
        private func updateIndentGuide() {
            indentGuideView.isHidden = !showIndentGuide || treeDepth == 0
            if showIndentGuide && treeDepth > 0 {
                // Update the guide position for current depth
                guideLeadingConstraint.constant = TZ.x6 + CGFloat((treeDepth - 1) * 20) + 8
            } else {
                guideLeadingConstraint.constant = TZ.x6
            }
        }
        
        private func updateDisclosureTriangle() {
            // Show triangle for all nodes in tree mode
            disclosureTriangle.isHidden = !isInTreeMode
            if isInTreeMode {
                let triangleName = isExpanded ? "chevron.down" : "chevron.right"
                disclosureTriangle.image = NSImage(systemSymbolName: triangleName, accessibilityDescription: isExpanded ? "Collapse" : "Expand")
                disclosureTriangle.contentTintColor = ColorSchemeToken.textSecondary
            }
        }
        
        @objc private func triangleClicked() {
            windowController?.toggleNodeExpansion(for: self)
        }
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("cell")
        let cell = tableView.makeView(withIdentifier: id, owner: self) as? DirectoryCellView ?? DirectoryCellView()
        
        if currentViewMode == .tree {
            // Tree mode - use tree nodes
            guard row < treeNodes.count else { return cell }
            let node = treeNodes[row]
            let item = node.item
            
            // Set tree properties
            cell.treeDepth = node.depth
            cell.showIndentGuide = node.depth > 0
            cell.hasChildren = node.hasChildren
            cell.isExpanded = node.isExpanded
            cell.isInTreeMode = true
            cell.windowController = self
            
            if let groupItem = item as? GroupItem {
                // Display group with special styling
                cell.nameField.stringValue = groupItem.name
                cell.iconView.image = NSImage(systemSymbolName: "folder.badge.gearshape", accessibilityDescription: "Group")
                cell.nameField.textColor = ColorSchemeToken.accent
                cell.toolTip = "Group containing \(groupItem.group.items.count) items"
            } else {
                // Display regular file/folder
                let url = item.url
                let kind = itemKind(for: url)
                cell.nameField.stringValue = displayName(for: url)
                cell.iconView.image = iconForList(url: url, kind: kind)
                cell.nameField.textColor = ColorSchemeToken.textPrimary
                cell.toolTip = url.path
            }
        } else {
            // List mode - existing logic
            let items = currentDirectoryItems()
            guard row < items.count else { return cell }
            let item = items[row]
            
            // Reset tree properties for list mode
            cell.treeDepth = 0
            cell.showIndentGuide = false
            cell.hasChildren = false
            cell.isExpanded = false
            cell.isInTreeMode = false
            cell.windowController = nil
            
            if let groupItem = item as? GroupItem {
                // Display group with special styling
                cell.nameField.stringValue = groupItem.name
                cell.iconView.image = NSImage(systemSymbolName: "folder.badge.gearshape", accessibilityDescription: "Group")
                cell.nameField.textColor = ColorSchemeToken.accent
                cell.toolTip = "Group containing \(groupItem.group.items.count) items"
            } else {
                // Display regular file/folder
                let url = item.url
                let kind = itemKind(for: url)
                cell.nameField.stringValue = displayName(for: url)
                cell.iconView.image = iconForList(url: url, kind: kind)
                cell.nameField.textColor = ColorSchemeToken.textPrimary
                cell.toolTip = url.path
            }
        }
        
        return cell
    }

    @objc func handleRowDoubleClick(_ sender: Any) {
        let row = table.clickedRow
        
        if currentViewMode == .tree {
            // In tree mode, double-click expands/collapses folders and groups
            guard row >= 0, row < treeNodes.count else { return }
            let node = treeNodes[row]
            
            if node.hasChildren {
                toggleTreeNodeExpansion(for: node.item)
                return
            }
            
            // If it's a file, open it
            if !node.hasChildren {
                openItem(node.item)
            }
        } else {
            // List mode - existing logic
            let items = currentDirectoryItems()
            guard row >= 0, items.indices.contains(row) else { return }
            let item = items[row]
            
            if let groupItem = item as? GroupItem {
                // Navigate into group (show group contents)
                showGroupContents(groupItem.group)
            } else {
                let url = item.url
                if let dirURL = resolvedDirectoryIfAny(for: url) {
                    // Navigate inside Seeker, obtaining permission if needed
                    navigate(to: dirURL)
                } else {
                    // File: open with the default application
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
    
    func showGroupContents(_ group: SeekerGroup) {
        // Validate the group and remove any items that no longer exist
        let validatedGroup = GroupStorageManager.shared.validateGroup(group)
        currentGroup = validatedGroup
        isShowingGroupContents = true
        
        // Create directory items from group's items - ensure all items are included
        var groupFileItems: [DirectoryItem] = []
        for url in validatedGroup.items {
            do {
                let item = try FileSystemItem(url: url)
                groupFileItems.append(item)
            } catch {
                print("Failed to create FileSystemItem for \(url.path): \(error)")
            }
        }
        
        // Sort: directories first, then files, alphabetically within each category
        allDirectoryItems = groupFileItems.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory && !b.isDirectory }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
        
        // Update legacy arrays for compatibility - use validated items
        items = validatedGroup.items
        self.groupItems = [] // No sub-groups when viewing group contents
        
        // Apply current filter state
        if query.isEmpty {
            filtered = items
            filteredDirectoryItems = allDirectoryItems
        } else {
            applyFilter()
        }
        
        // Update UI to show we're in a group
        updatePathLabel()
        isShowingSearchResults = false
        searchResults.removeAll()
        table.deselectAll(nil)
        preview.isHidden = true
        table.reloadData()
        
        // Add to navigation history but don't change currentDirectory
        // Groups are a virtual navigation layer
        if !suppressHistoryPush {
            let currentEntry: NavigationEntry = .directory(currentDirectory)
            backStack.append(currentEntry)
            forwardStack.removeAll()
        }
        
        updateNavigationButtons()
        
        print("Showing group '\(validatedGroup.name)' with \(validatedGroup.items.count) items")
        print("Directory items created: \(allDirectoryItems.count)")
        print("Items: \(allDirectoryItems.map { $0.name }.joined(separator: ", "))")
    }
    
    private func exitGroupView() {
        guard isShowingGroupContents else { return }
        isShowingGroupContents = false
        currentGroup = nil
        
        // Reload the parent directory
        suppressHistoryPush = true
        openDirectory(currentDirectory)
        suppressHistoryPush = false
        updateNavigationButtons()
    }
    
    func createGroupFromSelection() {
        let selectedItems = directoryItems(for: table.selectedRowIndexes)
        let urls = selectedItems.compactMap { item -> URL? in
            guard !(item is GroupItem) else { return nil }
            return item.url
        }
        guard urls.count > 1 else { return }
        
        let alert = NSAlert()
        alert.messageText = "Create Group"
        alert.informativeText = "Enter a name for the group containing \(urls.count) items."
        alert.alertStyle = .informational
        
        let tf = NSTextField(string: "New Group")
        tf.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = tf
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        
        if alert.runModal() == .alertFirstButtonReturn {
            let groupName = tf.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !groupName.isEmpty else { return }
            
            _ = GroupStorageManager.shared.createGroup(
                name: groupName,
                items: urls,
                parentDirectory: currentDirectory
            )
            
            // Refresh directory listing
            if isShowingGroupContents {
                exitGroupView()
            } else {
                openDirectory(currentDirectory)
            }
        }
    }
    
    func deleteGroup(_ group: SeekerGroup) {
        let alert = NSAlert()
        alert.messageText = "Delete Group"
        alert.informativeText = "Are you sure you want to delete the group \"\(group.name)\"? The files will remain unchanged."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete Group")
        alert.addButton(withTitle: "Cancel")
        
        if alert.runModal() == .alertFirstButtonReturn {
            GroupStorageManager.shared.deleteGroup(group)
            
            // Refresh directory listing
            if isShowingGroupContents && currentGroup?.id == group.id {
                exitGroupView()
            } else {
                openDirectory(currentDirectory)
            }
        }
    }

    override func keyDown(with event: NSEvent) {
        // Escape exits group view
        if event.keyCode == 53 && isShowingGroupContents { // Escape
            exitGroupView()
            return
        }
        
        // Return/Enter opens the selected folder or file
        if event.keyCode == 36 || event.keyCode == 76 { // return or keypad-enter
            let row = table.selectedRow
            let items = currentDirectoryItems()
            if row >= 0, items.indices.contains(row) {
                let item = items[row]
                
                if let groupItem = item as? GroupItem {
                    showGroupContents(groupItem.group)
                    return
                } else {
                    let url = item.url
                    if let dirURL = resolvedDirectoryIfAny(for: url) {
                        navigate(to: dirURL)
                        return
                    } else {
                        // Open the file with the default application
                        NSWorkspace.shared.open(url)
                        return
                    }
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
            filteredDirectoryItems = allDirectoryItems
            table.reloadData()
            return
        }
        let q = query.lowercased()
        
        // Filter file system items
        filtered = items.filter { $0.lastPathComponent.lowercased().contains(q) }
        
        // Filter directory items (includes groups)
        filteredDirectoryItems = allDirectoryItems.filter { item in
            item.name.lowercased().contains(q)
        }
        
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

    // MARK: - Context Menu
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



    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        return HoverRowView()
    }
