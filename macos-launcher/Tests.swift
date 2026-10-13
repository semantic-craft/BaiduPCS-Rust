import Foundation
import Darwin

@main struct Tests {
    static func main() async throws {
        assert(LocalPolicy.isExpectedHealth(Data(#"{"status":"ok","service":"baidu-netdisk-rust"}"#.utf8)))
        assert(!LocalPolicy.isExpectedHealth(Data(#"{"status":"ok","service":"other"}"#.utf8)))
        assert(LocalPolicy.activeCount(Data(#"{"data":[{"status":"Downloading"},{"status":"Paused"},{"status":"Pending"},{"status":"Decrypting"}]}"#.utf8)) == 3)
        assert(LocalPolicy.activeCount(Data(#"{"error":"authentication required"}"#.utf8)) == nil)
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        let first = try InstanceLock(path)
        withExtendedLifetime(first) {
            do { _ = try InstanceLock(path); fatalError("Duplicate launcher lock accepted") } catch {}
        }
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(fd); try? FileManager.default.removeItem(atPath: path) }
        var addr = sockaddr_in(); addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET); addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &addr) { p in p.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        assert(bound == 0)
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &addr) { p in p.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) } }
        do { try LocalPolicy.assertPortFree(UInt16(bigEndian: addr.sin_port)); fatalError("Occupied port accepted") } catch {}
        let allow = await SystemAssessment.run(URL(fileURLWithPath: "/usr/bin/true"), arguments: [])
        let deny = await SystemAssessment.run(URL(fileURLWithPath: "/usr/bin/false"), arguments: [])
        let timeout = await SystemAssessment.run(URL(fileURLWithPath: "/bin/sleep"), arguments: ["2"], timeout: 0.1)
        assert(allow && !deny && !timeout)
        print("PASS: service health identity, active/unknown task states, exclusive instance lock, occupied port, checker rejection and timeout")
    }
}
