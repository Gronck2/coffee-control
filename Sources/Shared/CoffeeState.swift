import Darwin
import Foundation

/// Shared identifiers and the on-disk state that the app writes and the
/// sandboxed control extension reads.
///
/// The app is the only writer. The extension has a read-only sandbox exception
/// for `~/Library/Application Support/coffee-control/` (see
/// `Support/Control.entitlements`), so no App Group is needed. App Groups do not
/// work with ad-hoc signing.
enum CoffeeShared {
    static let appBundleID = "local.coffeecontrol.CoffeeControl"
    static let controlKind = "local.coffeecontrol.CoffeeControl.toggle"
    static let processName = "CoffeeControl"
    static let assertionName = "Coffee Control: keep this Mac awake"
}

struct CoffeeState: Codable, Equatable {
    var on: Bool
    var pid: Int32
    var since: Date?

    static let off = CoffeeState(on: false, pid: 0, since: nil)

    /// Real home directory, also inside the sandbox, where
    /// `FileManager.homeDirectoryForCurrentUser` points at the container.
    static var realHome: URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    static var directory: URL {
        realHome.appendingPathComponent("Library/Application Support/coffee-control", isDirectory: true)
    }

    static var fileURL: URL {
        directory.appendingPathComponent("state.json")
    }

    /// Reads the stored state. A missing or unreadable file means "off".
    static func load() -> CoffeeState {
        guard let data = try? Data(contentsOf: fileURL),
              let state = try? JSONDecoder.coffee.decode(CoffeeState.self, from: data)
        else { return .off }
        return state
    }

    /// The state the control should show: on only while the recorded app
    /// process is still alive. A crashed app leaves `on: true` behind, but its
    /// power assertions die with it, so the control must say "off".
    static var isActive: Bool {
        let state = load()
        return state.on && isCoffeeProcessAlive(pid: state.pid)
    }

    func save() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        let data = try JSONEncoder.coffee.encode(self)
        try data.write(to: Self.fileURL, options: .atomic)
    }

    /// Process check through `sysctl`, which works inside the extension's
    /// sandbox (unlike `kill(pid, 0)`, which may fail with EPERM there).
    static func isCoffeeProcessAlive(pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else {
            return false
        }
        let name = withUnsafeBytes(of: info.kp_proc.p_comm) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        return name == CoffeeShared.processName
    }
}

extension JSONEncoder {
    static var coffee: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
}

extension JSONDecoder {
    static var coffee: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
