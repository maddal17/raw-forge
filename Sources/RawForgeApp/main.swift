import AppKit
import Foundation
import RawForgeCore
import SwiftUI

@MainActor
final class RawForgeAppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindow: NSWindow?
    private let viewModel = AppViewModel()
    private let keyMonitor = KeyEventMonitor()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments

        // Automated self-check mode for headless bundle verification
        if args.contains("--self-check") {
            let explicitPath = args.firstIndex(of: "--open").flatMap { idx in
                idx + 1 < args.count ? args[idx + 1] : nil
            }

            Task { @MainActor in
                var tempFileURL: URL?
                let checkPath: String
                if let explicitPath, FileManager.default.fileExists(atPath: explicitPath) {
                    checkPath = explicitPath
                } else {
                    let tempURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent("RawForge-SelfCheck-\(UUID().uuidString).dng")
                    let data = SampleRawGenerator.makeLinearDNG(width: 320, height: 240)
                    try? data.write(to: tempURL)
                    tempFileURL = tempURL
                    checkPath = tempURL.path
                }
                let ok = await viewModel.runSelfCheck(testPhotoPath: checkPath)
                if let tempFileURL {
                    try? FileManager.default.removeItem(at: tempFileURL)
                }
                NSApp.terminate(nil)
                exit(ok ? 0 : 1)
            }
            return
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        installMainMenu()

        let rootView = MainWindowView(viewModel: viewModel)
            .preferredColorScheme(.dark)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1400, height: 860),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "RawForge"
        window.minSize = NSSize(width: 1120, height: 700)
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(red: 0.08, green: 0.085, blue: 0.098, alpha: 1.0)
        window.contentView = NSHostingView(rootView: rootView)
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.mainWindow = window

        keyMonitor.install(for: viewModel)
        NSApp.activate(ignoringOtherApps: true)

        if let openIdx = args.firstIndex(of: "--open"), openIdx + 1 < args.count {
            let targetURL = URL(fileURLWithPath: args[openIdx + 1])
            Task { await viewModel.openDroppedOrSelectedURL(targetURL) }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        Task { @MainActor in
            await viewModel.handleDroppedURLs(urls)
        }
        sender.reply(toOpenOrPrint: .success)
    }

    @objc private func openFolderAction(_ sender: Any?) {
        viewModel.openFolderPanel()
    }

    @objc private func openSettingsAction(_ sender: Any?) {
        viewModel.isSettingsPresented = true
    }

    @objc private func exportAction(_ sender: Any?) {
        viewModel.openExportSheet()
    }

    @objc private func switchModeList(_ sender: Any?) {
        viewModel.workspaceMode = .list
    }

    @objc private func switchModeLoupe(_ sender: Any?) {
        viewModel.workspaceMode = .loupe
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()

        // App Menu
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About RawForge", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettingsAction(_:)), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide RawForge", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit RawForge", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        // File Menu
        let fileItem = NSMenuItem()
        mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: "File")
        let openItem = NSMenuItem(title: "Open Photo Folder…", action: #selector(openFolderAction(_:)), keyEquivalent: "o")
        openItem.target = self
        fileMenu.addItem(openItem)
        let exportItem = NSMenuItem(title: "Batch Convert & Export…", action: #selector(exportAction(_:)), keyEquivalent: "e")
        exportItem.target = self
        fileMenu.addItem(exportItem)
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileItem.submenu = fileMenu

        // Edit Menu (essential for copy/paste inside Settings text fields)
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        // View Menu
        let viewItem = NSMenuItem()
        mainMenu.addItem(viewItem)
        let viewMenu = NSMenu(title: "View")
        let listItem = NSMenuItem(title: "List & Label Mode", action: #selector(switchModeList(_:)), keyEquivalent: "1")
        listItem.target = self
        viewMenu.addItem(listItem)
        let loupeItem = NSMenuItem(title: "Big Preview Mode", action: #selector(switchModeLoupe(_:)), keyEquivalent: "2")
        loupeItem.target = self
        viewMenu.addItem(loupeItem)
        viewItem.submenu = viewMenu

        // Window Menu
        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.zoom(_:)), keyEquivalent: "")
        windowItem.submenu = windowMenu

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }
}

let app = NSApplication.shared
let delegate = RawForgeAppDelegate()
app.delegate = delegate
app.run()
