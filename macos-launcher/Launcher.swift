import AppKit
import SwiftUI

@MainActor final class Controller: ObservableObject {
    @Published var title = "准备就绪"
    @Published var detail = "打开百度网盘文件列表，按需下载。"
    @Published var busy = false
    @Published var running = false
    @Published var blocked = false
    private var backend: Process?
    private var instanceLock: InstanceLock?
    private var stopping = false
    private let preview = CommandLine.arguments.contains("--preview")
    let install = Bundle.main.resourceURL!.appendingPathComponent("backend")
    let state = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/BaiduPCS-Rust")
    let downloads = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/BaiduPCS-Rust")
    var executable: URL { install.appendingPathComponent("baidu-netdisk-rust") }

    func initialize() {
        if preview { title = "界面预览"; detail = "预览模式不会启动后端、读取账号或打开网盘页面。"; return }
        do {
            try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            instanceLock = try InstanceLock(state.appendingPathComponent("launcher.lock").path)
        } catch { title = "无法启动"; detail = error.localizedDescription; return }
        Task { await start() }
    }

    func start() async {
        guard !preview, !busy, instanceLock != nil else { return }
        if running { openUI(); return }
        guard backend == nil else { return }
        busy = true; blocked = false; title = "检查系统许可…"
        defer { busy = false }
        guard await SystemAssessment.acceptedBundle(Bundle.main.bundleURL) else {
            blocked = true; title = "等待 macOS 安全确认"
            detail = "系统尚未认可这个应用的签名与公证，或校验未完成。本应用不会解除隔离或绕过检查。请使用已通过公证的完整应用；完成后再点“重新检查并启动”。"
            return
        }
        do {
            let config = state.appendingPathComponent("config/app.toml")
            guard FileManager.default.fileExists(atPath: config.path) else { throw LauncherError.message("找不到数据目录配置。请先按照 macos-launcher/README.md 完成本机安装。") }
            let checker = Bundle.main.resourceURL!.appendingPathComponent("desktop-config-check")
            guard await SystemAssessment.run(checker, arguments: [config.path]) else {
                throw LauncherError.message("配置检查失败。请确认配置完整、下载目录有效、仅监听 127.0.0.1:18888 且自动备份关闭；不会回退到默认配置启动。")
            }
            try LocalPolicy.assertPortFree()
            guard FileManager.default.isExecutableFile(atPath: executable.path),
                  FileManager.default.fileExists(atPath: install.appendingPathComponent("frontend/index.html").path) else {
                throw LauncherError.message("后端或网页资源缺失，请恢复完整官方安装包。")
            }
            let process = Process()
            process.executableURL = executable
            process.currentDirectoryURL = state
            // Do not collect or display backend output: upstream logs can include account data.
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { [weak self] p in
                let status = p.terminationStatus
                Task { @MainActor in self?.ended(status) }
            }
            backend = process
            do { try process.run() } catch { backend = nil; throw error }
            title = "正在启动…"; detail = "正在等待本地服务准备完成。"
            for _ in 0..<60 {
                if stopping || !process.isRunning { return }
                if let data = await request("/health"), LocalPolicy.isExpectedHealth(data), process.isRunning, await ownsListener(process.processIdentifier) {
                    running = true; title = "已启动"; detail = "下载时保留这个窗口即可，无需打开终端。关闭网页不会停止下载。"
                    openUI(); return
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            process.interrupt()
            title = "启动超时"; detail = "已请求停止后端。若仍未退出，请稍候；本应用不会强制结束其他进程。"
        } catch { title = "无法启动"; detail = error.localizedDescription }
    }

    private func ownsListener(_ pid: Int32) async -> Bool {
        await Task.detached {
            let p = Process(); let output = Pipe()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
            p.arguments = ["-nP", "-a", "-p", String(pid), "-iTCP:18888", "-sTCP:LISTEN", "-Fp"]
            p.standardOutput = output; p.standardError = FileHandle.nullDevice
            do {
                try p.run()
                let data = output.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
                return p.terminationStatus == 0 && String(decoding: data, as: UTF8.self).split(separator: "\n").contains(Substring("p\(pid)"))
            } catch { return false }
        }.value
    }

    private func ended(_ status: Int32) {
        backend = nil; running = false
        if stopping { NSApp.reply(toApplicationShouldTerminate: true); return }
        title = "服务已停止"
        detail = "后端退出（状态 \(status)）。请检查下载目录权限、配置和端口后重试；账号和下载文件不会被本窗口删除。"
    }

    func request(_ path: String) async -> Data? {
        var req = URLRequest(url: LocalPolicy.address.appendingPathComponent(path))
        req.timeoutInterval = 1
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }

    func openUI() { if running && !preview { NSWorkspace.shared.open(LocalPolicy.address) } }
    func revealBackend() { NSWorkspace.shared.activateFileViewerSelecting([executable]) }
    func openDownloads() { NSWorkspace.shared.open(downloads) }

    func requestExit() async {
        guard let process = backend, process.isRunning else { NSApp.reply(toApplicationShouldTerminate: true); return }
        let data = await request("/api/v1/downloads/active")
        let count = data.flatMap(LocalPolicy.activeCount)
        let alert = NSAlert()
        alert.messageText = "停止服务并退出？"
        if let count, count > 0 {
            alert.informativeText = "当前有 \(count) 个活跃下载任务。建议先在网页暂停下载，再退出；下次可重新打开查看任务。"
        } else {
            alert.informativeText = "退出会停止后端及所有传输。为避免中断任务，请先在网页确认下载和上传已完成或暂停。"
        }
        alert.addButton(withTitle: "继续运行")
        alert.addButton(withTitle: "停止并退出")
        guard alert.runModal() == .alertSecondButtonReturn else { NSApp.reply(toApplicationShouldTerminate: false); return }
        stopping = true; busy = true; title = "正在安全退出…"; detail = "等待后端保存任务状态。"
        process.interrupt() // Upstream explicitly handles SIGINT for persistence shutdown.
        for _ in 0..<60 {
            if !process.isRunning { return }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        stopping = false; busy = false
        title = "退出仍未完成"; detail = "后端尚未确认结束。窗口保持打开，未强制终止进程；可稍后重试退出。"
        NSApp.reply(toApplicationShouldTerminate: false)
    }
}

struct LauncherView: View {
    @ObservedObject var model: Controller
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("百度网盘 · 本机下载", systemImage: "arrow.down.circle.fill").font(.title2.bold())
            Text(model.title).font(.headline)
            Text(model.detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(model.running ? "打开网盘界面" : "重新检查并启动") { Task { await model.start() } }
                    .buttonStyle(.borderedProminent).disabled(model.busy)
                if model.blocked { Button("显示后端文件") { model.revealBackend() } }
                Button("下载文件夹") { model.openDownloads() }
            }
            Divider()
            HStack {
                Text("仅本机访问 · 不开机自启 · 自动备份已关闭").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("退出") { NSApp.terminate(nil) }
            }
        }.padding(26).frame(width: 560)
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let controller = Controller()
    var window: NSWindow!
    private var quitting = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let existing = NSRunningApplication.runningApplications(withBundleIdentifier: "local.baidupcs.launcher").first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            existing.activate(options: [.activateAllWindows]); NSApp.terminate(nil); return
        }
        let menu = NSMenu(); let item = NSMenuItem(); menu.addItem(item)
        let appMenu = NSMenu(); appMenu.addItem(withTitle: "退出百度网盘启动器", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = appMenu; NSApp.mainMenu = menu
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 612, height: 280), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "BaiduPCS — 本机下载"
        window.contentView = NSHostingView(rootView: LauncherView(model: controller))
        window.delegate = self; window.isReleasedWhenClosed = false
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        controller.initialize()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window?.makeKeyAndOrderFront(nil)
        if controller.running { controller.openUI() }
        return true
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { NSApp.terminate(nil); return false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !quitting else { return .terminateCancel }
        quitting = true
        Task { await controller.requestExit(); quitting = false }
        return .terminateLater
    }
}

@main struct LauncherMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate; app.setActivationPolicy(.regular); app.run()
    }
}
