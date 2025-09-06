# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

**Build & Run:**
- Build: `xcodebuild -project Seeker.xcodeproj -scheme Seeker -configuration Debug build`
- Run: Open `Seeker.xcodeproj` in Xcode and press Cmd+R, or use `xcodebuild -project Seeker.xcodeproj -scheme Seeker -configuration Debug run`
- Test: `xcodebuild test -project Seeker.xcodeproj -scheme Seeker -destination 'platform=macOS'`

**Project Management:**
- Open in Xcode: `open Seeker.xcodeproj`
- Clean build: `xcodebuild clean -project Seeker.xcodeproj -scheme Seeker`

## Architecture Overview

Seeker is a macOS file browser application built with Swift and AppKit, featuring a Linear-inspired design system.

**Core Components:**

1. **App Architecture** (`Seeker/SeekerApp.swift`):
   - SwiftUI-based app entry point with `@main SeekerApp`
   - `AppDelegate` manages the main AppKit window via `LinearWindowController`
   - Uses custom `SeekerRootViewController` as the main interface
   - Command palette accessible via Cmd+K (`togglePalette` notification)

2. **Window Management** (`UI/Windows.swift`):
   - `LinearWindowController`: Custom window controller with unified toolbar style
   - `SeekerRootViewController`: Split view controller managing sidebar and directory views
   - `SidebarViewController`: Navigation sidebar with predefined directories (Documents, Desktop, etc.)
   - `DirectoryListViewController`: File browser with table view and breadcrumb navigation
   - Custom table views (`SidebarTableView`, `DirectoryTableView`) prevent default system behaviors

3. **Command Palette** (`UI/CommandPalette.swift`):
   - `CommandPaletteView`: Overlay command interface with fuzzy search
   - Modal interface with search field and results table
   - Custom scoring algorithm for fuzzy matching
   - Keyboard navigation (arrow keys, Enter, Escape)

4. **Design System** (`UI/DesignTokens.swift`):
   - `TZ` enum: 8pt-based spacing scale (x1=4px, x2=8px, etc.)
   - `FontToken`: Inter font family with fallback to system fonts
   - `ColorSchemeToken`: Linear-inspired dark theme colors
   - Utility extensions for card backgrounds and hairline separators

5. **Grouping System** (`UI/Windows.swift`):
   - `SeekerGroup`: Data model for file/folder groups with JSON persistence
   - `GroupStorageManager`: Singleton for group storage in Application Support
   - `DirectoryItem` protocol: Unifies file system items and groups
   - `GroupItem`: Represents groups in directory listings
   - Groups displayed with special icons and accent color highlighting
   - Command palette integration for group management

**Key Patterns:**
- Heavy use of AppKit over SwiftUI for precise control
- Delegate pattern for component communication
- Custom view controllers extending `NSViewController`
- Programmatic Auto Layout with `translatesAutoresizingMaskIntoConstraints = false`
- Tracking areas for hover states and custom mouse interactions
- Protocol-oriented design for unified directory item handling
- JSON persistence for user-created groups

**Multiselection & Groups:**
- Shift-click for range selection in file browser
- Context menu "Create Group…" for multiple selected items
- Groups show as "glorified folders" with special visual treatment
- Group navigation with breadcrumb path indication
- Escape key to exit group view, back button support
- Group management via context menus and command palette

**File Structure:**
- `Seeker/`: Core app files (SeekerApp.swift)
- `UI/`: Reusable UI components, design tokens, and group system
- `Fonts/`: Inter font family files
- Assets in `Seeker/Assets.xcassets`
- Group data stored in `~/Library/Application Support/Seeker/groups.json`

**Design Philosophy:**
- Linear-inspired visual design with dark theme (#1C1C1E background)
- Subtle animations and hover states
- Typography-first approach with Inter font
- Custom table view behaviors to override system defaults
- Groups as organizational layer without modifying file system
- No external dependencies - pure Swift/AppKit implementation