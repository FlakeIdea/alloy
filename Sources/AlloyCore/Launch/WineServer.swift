import Darwin
import Foundation

@_silgen_name("bootstrap_look_up")
private func bootstrap_look_up(_ bootstrap: mach_port_t, _ name: UnsafePointer<CChar>,
                               _ port: UnsafeMutablePointer<mach_port_t>) -> kern_return_t

/// Whether an environment's wineserver is running, and with MSync.
///
/// Every Windows program in an environment shares one wineserver, and Wine refuses to start a program whose MSync
/// setting differs from the server's ("Server is running with WINEMSYNC but this process is not", or the reverse
/// failing in msync_init). That happens when a game with MSync turned off starts while Steam, another game, or a
/// server still winding down after a game ran with it on. Alloy asks the server before each start and follows it.
public enum WineServer {
    public enum State: Equatable, Sendable {
        case stopped
        case running(msync: Bool)
    }

    /// Wine's server folder for a prefix: `/tmp/.wine-<uid>/server-<device>-<inode>` of the prefix folder.
    static func identity(of prefix: URL) -> (folder: String, inode: String)? {
        var st = stat()
        guard stat(prefix.path, &st) == 0 else { return nil }
        let device = String(UInt64(UInt32(bitPattern: st.st_dev)), radix: 16)
        let inode = String(UInt64(st.st_ino), radix: 16)
        return ("/tmp/.wine-\(getuid())/server-\(device)-\(inode)", inode)
    }

    /// The running wineserver holds a write lock on `lock` in its folder for as long as it runs; MSync registers the
    /// Mach service `wine-<inode>-msync`, which disappears with the server.
    public static func state(of prefix: WinePrefix) -> State {
        guard let id = identity(of: prefix.path) else { return .stopped }
        let fd = open(id.folder + "/lock", O_RDONLY)
        guard fd >= 0 else { return .stopped }
        defer { close(fd) }
        var lock = flock()
        lock.l_type = Int16(F_WRLCK)
        lock.l_whence = Int16(SEEK_SET)
        guard fcntl(fd, F_GETLK, &lock) == 0, lock.l_type != Int16(F_UNLCK) else { return .stopped }
        var port: mach_port_t = 0
        let found = bootstrap_look_up(bootstrap_port, "wine-\(id.inode)-msync", &port) == KERN_SUCCESS
        if found { mach_port_deallocate(mach_task_self_, port) }
        return .running(msync: found)
    }
}
