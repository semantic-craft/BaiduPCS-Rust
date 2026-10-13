import Foundation
import Darwin

enum LauncherError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let s) = self { return s }; return nil }
}

struct LocalPolicy {
    static let port: UInt16 = 18888
    static let address = URL(string: "http://127.0.0.1:18888")!

    static func isExpectedHealth(_ data: Data) -> Bool {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return false }
        return obj["status"] == "ok" && obj["service"] == "baidu-netdisk-rust"
    }

    static func activeCount(_ data: Data) -> Int? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tasks = obj["data"] as? [[String: Any]] else { return nil }
        return tasks.filter { ["pending", "downloading", "decrypting"].contains(($0["status"] as? String ?? "").lowercased()) }.count
    }

    static func assertPortFree(_ port: UInt16 = port) throws {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw LauncherError.message("无法检查本地端口。") }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard result == 0 else { throw LauncherError.message("本地端口 \(port) 已被占用。请先退出原有服务；本应用不会接管或结束其他进程。") }
    }
}

final class InstanceLock {
    private var fd: Int32 = -1
    init(_ path: String) throws {
        fd = open(path, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw LauncherError.message("无法创建本机运行锁。") }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { close(fd); fd = -1; throw LauncherError.message("启动窗口已在运行，请切回原窗口。") }
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
    }
    deinit { if fd >= 0 { _ = flock(fd, LOCK_UN); close(fd) } }
}

struct SystemAssessment {
    // Each checker is our own short-lived child; timeout never targets the backend.
    static func run(_ executable: URL, arguments: [String], timeout: TimeInterval = 10) async -> Bool {
        await Task.detached {
            let p = Process()
            p.executableURL = executable; p.arguments = arguments
            p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
            do {
                try p.run()
                let deadline = Date().addingTimeInterval(timeout)
                while p.isRunning && Date() < deadline { try? await Task.sleep(nanoseconds: 50_000_000) }
                if p.isRunning { kill(p.processIdentifier, SIGKILL); p.waitUntilExit(); return false }
                return p.terminationStatus == 0
            } catch { return false }
        }.value
    }
    static func acceptedBundle(_ bundle: URL) async -> Bool {
        guard await run(URL(fileURLWithPath: "/usr/bin/codesign"), arguments: ["--verify", "--deep", "--strict", bundle.path]) else { return false }
        return await run(URL(fileURLWithPath: "/usr/sbin/spctl"), arguments: ["--assess", "--type", "execute", bundle.path], timeout: 30)
    }
}
