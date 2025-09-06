//
//  CommandPalette.swift
//  Seeker
//
//  Linear-style ⌘K command palette overlay.
//  Shows a searchable list of commands with fuzzy matching,
//  keyboard navigation, and ESC to close.
//

import AppKit

// Basic command model
struct Command {
    let title: String
    let subtitle: String?
    let action: () -> Void
}

final class CommandPaletteView: NSView, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {

    // MARK: - UI Elements
    private let container = NSVisualEffectView()
    private let search = NSSearchField()
    private let table = NSTableView()
    private let scroll = NSScrollView()

    // Data
    private var all: [Command] = []
    private var results: [Command] = []
    private var selectedRow: Int = 0

    // MARK: - Init
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = .clear
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Public
    func setCommands(_ cmds: [Command]) {
        self.all = cmds
        filter("")
        selectRow(0)
    }

    func focusSearch() { window?.makeFirstResponder(search) }

    // MARK: - UI Setup
    private func setupUI() {
        // Container (card)
        container.material = .hudWindow
        container.blendingMode = .behindWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 4
        container.layer?.masksToBounds = true
        container.layer?.backgroundColor = ColorSchemeToken.surface.withAlphaComponent(0.98).cgColor

        addSubview(container)
        container.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor),
            container.topAnchor.constraint(equalTo: topAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        // Search
        search.placeholderString = "Type a command…"
        search.font = FontToken.ui
        search.delegate = self
        search.sendsSearchStringImmediately = true
        search.recentsAutosaveName = "dev.seeker.commandpalette.search"

        // Table
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false

        table.headerView = nil
        table.rowHeight = 32
        table.intercellSpacing = NSSize(width: 0, height: 0)
        table.backgroundColor = .clear
        table.selectionHighlightStyle = .regular
        table.allowsEmptySelection = false
        table.allowsMultipleSelection = false
        table.delegate = self
        table.dataSource = self

        let col = NSTableColumn(identifier: .init("cmd"))
        col.resizingMask = .autoresizingMask
        table.addTableColumn(col)

        // Layout
        container.addSubview(search)
        container.addSubview(scroll)
        search.translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            search.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: TZ.x4),
            search.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -TZ.x4),
            search.topAnchor.constraint(equalTo: container.topAnchor, constant: TZ.x4),

            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: search.bottomAnchor, constant: TZ.x3),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        container.addHairlineSeparator(edge: .maxY)
    }

    // MARK: - Search delegate
    func controlTextDidChange(_ obj: Notification) {
        filter(search.stringValue)
    }

    private func filter(_ q: String) {
        if q.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            results = all
        } else {
            results = all.sorted { score($0.title, q) > score($1.title, q) }
        }
        table.reloadData()
        selectRow(0)
    }

    // simple fuzzy scorer
    private func score(_ s: String, _ q: String) -> Int {
        let s = s.lowercased()
        let q = q.lowercased()
        var score = 0
        var idx = s.startIndex
        for ch in q {
            if let found = s[idx...].firstIndex(of: ch) {
                score += 2
                if found == idx { score += 1 }
                idx = s.index(after: found)
            } else { score -= 1 }
        }
        if s.hasPrefix(q) { score += 3 }
        return score
    }

    // MARK: - Table
    func numberOfRows(in tableView: NSTableView) -> Int { results.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("cell")
        let cell = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? {
            let c = NSTableCellView()
            c.identifier = id

            let title = NSTextField(labelWithString: "")
            title.font = FontToken.uiMedium
            title.textColor = ColorSchemeToken.textPrimary
            title.tag = 1

            let sub = NSTextField(labelWithString: "")
            sub.font = FontToken.small
            sub.textColor = ColorSchemeToken.textSecondary
            sub.tag = 2

            c.addSubview(title)
            c.addSubview(sub)
            title.translatesAutoresizingMaskIntoConstraints = false
            sub.translatesAutoresizingMaskIntoConstraints = false

            NSLayoutConstraint.activate([
                title.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: TZ.x3),
                title.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -TZ.x3),
                title.topAnchor.constraint(equalTo: c.topAnchor, constant: TZ.x2),

                sub.leadingAnchor.constraint(equalTo: title.leadingAnchor),
                sub.trailingAnchor.constraint(equalTo: title.trailingAnchor),
                sub.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 1),
                sub.bottomAnchor.constraint(equalTo: c.bottomAnchor, constant: -TZ.x2)
            ])

            return c
        }()

        let cmd = results[row]
        (cell.viewWithTag(1) as? NSTextField)?.stringValue = cmd.title
        (cell.viewWithTag(2) as? NSTextField)?.stringValue = cmd.subtitle ?? ""

        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        selectedRow = table.selectedRow
    }

    // MARK: - Selection & Execution
    private func selectRow(_ r: Int) {
        guard results.indices.contains(r) else { return }
        selectedRow = r
        table.selectRowIndexes(IndexSet(integer: r), byExtendingSelection: false)
        table.scrollRowToVisible(r)
    }

    private func runSelected() {
        guard results.indices.contains(selectedRow) else { return }
        let cmd = results[selectedRow]
        hide()
        cmd.action()
    }

    // MARK: - Show/Hide
    func show() {
        isHidden = false
        alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().alphaValue = 1
        }
        focusSearch()
    }

    func hide() {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().alphaValue = 0
        } completionHandler: {
            self.isHidden = true
        }
    }

    // MARK: - First Responder & Keyboard
    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            window?.makeFirstResponder(self)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        hide()
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36: // Return
            runSelected()
        case 125: // Down
            selectRow(min(selectedRow + 1, max(0, results.count - 1)))
        case 126: // Up
            selectRow(max(selectedRow - 1, 0))
        case 53: // ESC
            hide()
        default:
            super.keyDown(with: event)
        }
    }
}
   
