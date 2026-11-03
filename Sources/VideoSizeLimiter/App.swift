import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VideoSizeCore

@MainActor
final class AppModel: ObservableObject {
    enum Stage { case intake, reading, size, working, done }
    @Published var stage: Stage = .intake { didSet { resize?(stage) } }
    @Published var source: URL?
    @Published var info: MediaInfo?
    @Published var target = UserDefaults.standard.string(forKey: "lastTargetMB") ?? "25"
    @Published var error: String?
    @Published var progress = 0.0
    @Published var status = ""
    @Published var output: URL?
    var resize: ((Stage) -> Void)?
    private var cancellation: Cancellation?
    var busy: Bool { stage == .working || stage == .reading }
    var targetValid: Bool { (try? Compressor.targetBytes(megabytes: target)) != nil }

    func choose() {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Choose video"
        if panel.runModal() == .OK, let url = panel.url { select(url) }
    }

    func paste() {
        guard !busy else { return }
        let board = NSPasteboard.general
        if let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], let url = urls.first {
            select(url); return
        }
        if let text = board.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) {
            if let url = URL(string: text), url.isFileURL { select(url); return }
            let path = (text as NSString).expandingTildeInPath
            if path.hasPrefix("/") { select(URL(fileURLWithPath: path)); return }
        }
        error = "Copy a video file in Finder or copy its full file path, then paste again."
    }

    func select(_ url: URL) {
        guard !busy else { return }
        guard url.isFileURL, FileManager.default.isReadableFile(atPath: url.path) else {
            error = "This file cannot be read. Choose a local video file."; return
        }
        error = nil; output = nil; source = url; stage = .reading
        let token = Cancellation(); cancellation = token
        Task {
            do {
                let media = try await Task.detached { try Compressor(tools: Tools.discover()).probe(url, cancellation: token) }.value
                info = media; stage = .size
            } catch is CancellationError { source = nil; info = nil; stage = .intake }
            catch { self.error = error.localizedDescription; source = nil; info = nil; stage = .intake }
            cancellation = nil
        }
    }

    func compress() {
        guard let source, stage == .size else { return }
        do {
            let bytes = try Compressor.targetBytes(megabytes: target)
            let tools = try Tools.discover()
            UserDefaults.standard.set(target, forKey: "lastTargetMB")
            let token = Cancellation(); cancellation = token
            error = nil; progress = 0; status = "Reading video…"; stage = .working
            let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/Videos", isDirectory: true)
            Task { [self] in
                do {
                    let result = try await Task.detached { [weak self] in
                        try Compressor(tools: tools).compress(source: source, targetBytes: bytes, directory: directory, cancellation: token) { update in
                            Task { @MainActor [weak self] in
                                guard self?.stage == .working else { return }
                                self?.progress = update.fraction; self?.status = update.message
                            }
                        }
                    }.value
                    output = result; stage = .done
                    NSWorkspace.shared.activateFileViewerSelecting([result])
                } catch is CancellationError { stage = .size; status = "" }
                catch { self.error = error.localizedDescription; stage = .size }
                cancellation = nil
            }
        } catch { self.error = error.localizedDescription }
    }

    func cancel() { cancellation?.cancel(); status = "Cancelling…" }
    func reset() { guard !busy else { return }; source = nil; info = nil; output = nil; error = nil; stage = .intake }
    func reveal() { if let output { NSWorkspace.shared.activateFileViewerSelecting([output]) } }
}

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var dragOver = false
    @FocusState private var sizeFocused: Bool
    private let accent = Color.accentColor
    var body: some View {
        VStack(spacing: 20) {
            switch model.stage {
            case .intake:
                VStack(spacing: 14) {
                    Image(systemName: "film.stack").font(.system(size: 44, weight: .light)).foregroundStyle(accent)
                    Text("Make room for your video").font(.system(size: 22, weight: .semibold))
                    Text("Drop a video here").font(.title3)
                    Text("Keep its format. Give it a size limit.").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 28)
                .background(accent.opacity(dragOver ? 0.14 : 0.035), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(accent.opacity(dragOver ? 0.8 : 0.25), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
                HStack(spacing: 12) {
                    Button("Choose video…", action: model.choose).keyboardShortcut("o").buttonStyle(.borderedProminent)
                    Button("Paste video", action: model.paste)
                }
                Text("Copy a file in Finder, then press ⌘V").font(.caption).foregroundStyle(.secondary)
            case .reading:
                ProgressView().controlSize(.small)
                Text("Reading video…").foregroundStyle(.secondary)
                Button("Cancel", action: model.cancel)
            case .size:
                fileHeader
                VStack(alignment: .leading, spacing: 10) {
                    Text("Maximum file size").font(.headline)
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        TextField("25", text: $model.target).textFieldStyle(.plain)
                            .font(.system(size: 38, weight: .medium, design: .rounded))
                            .focused($sizeFocused).onSubmit { if model.targetValid { model.compress() } }
                            .accessibilityLabel("Maximum file size in megabytes")
                        Text("MB").font(.title2).foregroundStyle(.secondary)
                    }
                    Divider()
                    Text("Saves to ~/Documents/Videos").font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button("Back", action: model.reset).keyboardShortcut(.escape, modifiers: [])
                    Spacer()
                    Button("Compress video", action: model.compress).buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction).disabled(!model.targetValid)
                }
            case .working:
                fileHeader
                VStack(alignment: .leading, spacing: 10) {
                    ProgressView(value: model.progress)
                    HStack {
                        Text(model.status)
                        Spacer()
                        Text(model.progress, format: .percent.precision(.fractionLength(0))).monospacedDigit()
                    }.font(.caption).foregroundStyle(.secondary)
                }
                Button("Cancel", action: model.cancel).keyboardShortcut(.escape, modifiers: [])
            case .done:
                Image(systemName: "checkmark.circle.fill").font(.system(size: 38)).foregroundStyle(.green)
                Text("Your video is ready").font(.title2.weight(.semibold))
                if let output = model.output {
                    Text(output.lastPathComponent).lineLimit(1).truncationMode(.middle)
                    if let size = try? output.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                        Text(String(format: "%.3f MB · saved in Documents/Videos", Double(size) / 1_000_000)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Button("Compress another", action: model.reset)
                    Button("Show in Finder", action: model.reveal).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                }
            }
            if let error = model.error {
                ScrollView { Text(error).font(.callout).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }
                    .frame(maxHeight: 100)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .onChange(of: model.stage) { _, stage in if stage == .size { sizeFocused = true } }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $dragOver) { providers in
            guard !model.busy, let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { Task { @MainActor in model.select(url) } }
            }
            return true
        }
    }
    private var fileHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "video.fill").font(.title2).foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 4) {
                Text(model.source?.lastPathComponent ?? "Video").font(.headline).lineLimit(1).truncationMode(.middle)
                if let info = model.info, let video = info.video {
                    Text("\((video.codec_name ?? "Video").uppercased()) · \(video.width ?? 0) × \(video.height ?? 0) · \(Int(info.duration.rounded())) sec")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = AppModel()
    var window: NSWindow!
    var pasteMonitor: Any?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        buildMenu()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 380), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Video Size Limiter"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: ContentView(model: model))
        model.resize = { [weak self] stage in
            guard let window = self?.window else { return }
            let height: CGFloat = stage == .intake ? 380 : (stage == .size ? 310 : 290)
            let size = NSSize(width: stage == .intake ? 460 : 420, height: height + (self?.model.error == nil ? 0 : 110))
            var frame = window.frame
            let content = window.frameRect(forContentRect: NSRect(origin: .zero, size: size)).size
            frame.origin.y += frame.height - content.height
            frame.size = content
            window.setFrame(frame, display: true, animate: true)
        }
        window.center(); window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        pasteMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window.isKeyWindow else { return event }
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
               event.charactersIgnoringModifiers == "v", self.model.stage == .intake || self.model.stage == .done {
                self.model.paste(); return nil
            }
            return event
        }
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        if let url = urls.first { model.select(url); window?.makeKeyAndOrderFront(nil) }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window.makeKeyAndOrderFront(nil); return true
    }
    func applicationWillTerminate(_ notification: Notification) { model.cancel() }
    private func buildMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem(); menu.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "About Video Size Limiter", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Video Size Limiter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let fileItem = NSMenuItem(); menu.addItem(fileItem)
        let file = NSMenu(title: "File"); fileItem.submenu = file
        let open = file.addItem(withTitle: "Open video…", action: #selector(openVideo), keyEquivalent: "o"); open.target = self
        file.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let editItem = NSMenuItem(); menu.addItem(editItem)
        let edit = NSMenu(title: "Edit"); editItem.submenu = edit
        for (title, selector, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.addItem(withTitle: title, action: Selector(selector), keyEquivalent: key)
        }
        NSApp.mainMenu = menu
    }
    @objc func openVideo() { model.choose() }
}

@main
enum VideoSizeLimiterApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
