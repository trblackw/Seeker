//
//  Windows.swift
//  Seeker
//
//  Houses Seeker's main window and root split view controllers.
//

import AppKit
import SwiftUI

// MARK: - Linear-style window

final class LinearWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class LinearWindowController: NSWindowController {
    convenience init(content: NSViewController) {
        let w = LinearWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 760),
            styleMask: [.titled, .fullSizeContentView, .closable, .miniaturizable, .resizable],
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
        w.contentViewController = content
        w.center()
    }
}

// MARK: - Root Split Controller (Sidebar | Main | Inspector)

final class SeekerRootViewController: NSSplitViewController {
    private let sidebarVC = SidebarViewController()
    private let mainVC = DirectoryViewController()
    private let inspectorVC = InspectorViewController()
    // Command Palette overlay
    private let palette = CommandPaletteView()

    override func viewDidLoad() {
        super.viewDidLoad()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        view.wantsLayer = true
        view.layer?.backgroundColor = ColorSchemeToken.bg.cgColor

        let left = NSSplitViewItem(viewController: sidebarVC)
        left.minimumThickness = 180
        left.canCollapse = true

        let center = NSSplitViewItem(viewController: mainVC)

        let right = NSSplitViewItem(viewController: inspectorVC)
        right.minimumThickness = 260
        right.canCollapse = true

        addSplitViewItem(left)
        addSplitViewItem(center)
        addSplitViewItem(right)

        // Command palette overlay
        view.addSubview(palette)
        palette.translatesAutoresizingMaskIntoConstraints = false
        // Command palette overlay constraints (responsive)
        var paletteConstraints: [NSLayoutConstraint] = [
            palette.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            palette.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            // Keep generous margins while allowing the palette to grow with the window
            palette.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: TZ.x12),
            palette.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -TZ.x12),
            // Absolute caps so it never becomes comically large/tall
            palette.widthAnchor.constraint(lessThanOrEqualToConstant: 1000),
            palette.heightAnchor.constraint(lessThanOrEqualToConstant: 520)
        ]

        // Preferred width when space allows (soft constraint)
        let preferredWidth = palette.widthAnchor.constraint(equalToConstant: 820)
        preferredWidth.priority = .defaultLow
        paletteConstraints.append(preferredWidth)

        NSLayoutConstraint.activate(paletteConstraints)
        palette.isHidden = true
        buildCommands()

        // Observe global toggle (from ⌘K CommandMenu)
        NotificationCenter.default.addObserver(self, selector: #selector(togglePaletteFromMenu), name: .togglePalette, object: nil)
    }

    @objc private func togglePaletteFromMenu() { togglePalette() }

    private func togglePalette() {
        if palette.isHidden {
            palette.show()
        } else {
            palette.hide()
        }
    }

    private func buildCommands() {
        weak var weakSelf = self
        let cmds: [Command] = [
            Command(title: "Focus Search", subtitle: "⌘F") { weakSelf?.mainVC.focusSearch() },
            Command(title: "Go Up", subtitle: "⌘↑") { weakSelf?.mainVC.goUpViaCommand() },
            Command(title: "Toggle Inspector", subtitle: "⌘I") { weakSelf?.toggleInspector() },
            Command(title: "Open Terminal Here", subtitle: nil) { weakSelf?.mainVC.openTerminalHere() }
        ]
        palette.setCommands(cmds)
    }

    private func toggleInspector() {
        guard let inspectorItem = splitViewItems.last else { return }
        inspectorItem.isCollapsed.toggle()
    }

    // Fallback: handle ⌘K here too in case menu doesn't fire
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "k" {
            togglePalette()
            return
        }
        super.keyDown(with: event)
    }
}

// MARK: - Sidebar (Linear-style placeholder)

final class SidebarViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    private let outline = NSOutlineView()
    private let scroll = NSScrollView()
    private var items: [String] = ["Favorites", "Recents", "Downloads", "Documents", "Desktop"]

    override func loadView() {
        self.view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = ColorSchemeToken.surface.cgColor

        outline.headerView = nil
        outline.rowSizeStyle = .small
        outline.selectionHighlightStyle = .sourceList
        outline.backgroundColor = ColorSchemeToken.surface
        outline.intercellSpacing = NSSize(width: 0, height: 4)
        outline.dataSource = self
        outline.delegate = self

        let col = NSTableColumn(identifier: .init("col"))
        outline.addTableColumn(col)
        outline.outlineTableColumn = col

        scroll.documentView = outline
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

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int { items.count }
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { false }
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any { items[index] }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("cell")
        let cell = outlineView.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? {
            let c = NSTableCellView()
            c.identifier = id
            let tf = NSTextField(labelWithString: "")
            tf.font = FontToken.ui
            tf.textColor = ColorSchemeToken.textPrimary
            c.textField = tf
            c.addSubview(tf)
            tf.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                tf.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: TZ.x4),
                tf.centerYAnchor.constraint(equalTo: c.centerYAnchor)
            ])
            return c
        }()

        if let name = item as? String {
            cell.textField?.stringValue = name
        }
        return cell
    }
}

// MARK: - Inspector (SwiftUI embedded)

final class InspectorViewController: NSViewController {
    override func loadView() {
        let root = NSHostingView(rootView: InspectorPanel())
        self.view = root
    }
}

struct InspectorPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Inspector").font(.system(size: 12, weight: .medium))
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            Divider().opacity(0.2)
            VStack(alignment: .leading, spacing: 8) {
                labeledRow("Kind", "Folder")
                labeledRow("Size", "—")
                labeledRow("Modified", "Today 10:22")
                labeledRow("Tags", "work, design")
            }.padding(12)
            Spacer()
        }
        .background(Color(nsColor: ColorSchemeToken.surface))
    }

    @ViewBuilder
    private func labeledRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary).font(.system(size: 12))
            Spacer()
            Text(value).font(.system(size: 12))
        }
    }
}
