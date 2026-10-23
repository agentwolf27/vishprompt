import Darwin
import Foundation

/// Reads process information in-process, with libproc and sysctl.
///
/// The probes used to spawn `ps` for the whole process table and `lsof` for a working
/// directory: two process launches, each up to a 1.5 s timeout, on every terminal dictation.
/// These calls read the same facts directly, for only the processes under the terminal.
enum ProcessInspector {
    /// Direct children of `pid`.
    static func children(of pid: Int32) -> [Int32] {
        var buffer = [pid_t](repeating: 0, count: 512)
        let result = proc_listchildpids(pid, &buffer, Int32(buffer.count * MemoryLayout<pid_t>.size))
        guard result > 0 else { return [] }
        // Documented as a count of pids; older systems returned bytes. Accept either.
        let count = Int(result) <= buffer.count ? Int(result) : Int(result) / MemoryLayout<pid_t>.size
        return Array(buffer.prefix(min(count, buffer.count))).filter { $0 > 0 }
    }

    /// The full command line of `pid`, as `ps -o args=` would print it, or nil when the
    /// process is gone or belongs to another user.
    static func arguments(of pid: Int32) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }

        // Layout: argc (Int32), the executable path, NUL padding, then argc NUL-terminated
        // arguments, then the environment, which is never read.
        let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        var index = MemoryLayout<Int32>.size
        while index < size, buffer[index] != 0 { index += 1 }   // executable path
        while index < size, buffer[index] == 0 { index += 1 }   // padding
        var arguments: [String] = []
        while arguments.count < Int(argc), index < size {
            let start = index
            while index < size, buffer[index] != 0 { index += 1 }
            arguments.append(String(decoding: buffer[start..<index], as: UTF8.self))
            index += 1
        }
        return arguments.isEmpty ? nil : arguments.joined(separator: " ")
    }

    /// The working directory of `pid`.
    static func workingDirectory(of pid: Int32) -> URL? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = withUnsafePointer(to: &info.pvi_cdir.vip_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
        }
        return path.isEmpty ? nil : URL(filePath: path, directoryHint: .isDirectory)
    }

    /// Every process under `pid`, as the entries `ProcessTree` walks, bounded so a
    /// pathological tree cannot stall a dictation.
    static func descendants(of pid: Int32, limit: Int = 500) -> [ProcessTree.Entry] {
        var entries: [ProcessTree.Entry] = []
        var queue = [pid]
        while !queue.isEmpty, entries.count < limit {
            let parent = queue.removeFirst()
            for child in children(of: parent) {
                guard let args = arguments(of: child) else { continue }
                entries.append(ProcessTree.Entry(pid: child, parent: parent, command: args))
                queue.append(child)
            }
        }
        return entries
    }
}
