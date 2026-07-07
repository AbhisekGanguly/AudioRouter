import CoreAudio
import Foundation

/// Helpers for Core Audio *process* objects (entries of kAudioHardwarePropertyProcessObjectList).
extension AudioObjectID {
    static func readProcessList() throws -> [AudioObjectID] {
        try AudioObjectID.system.readObjectList(kAudioHardwarePropertyProcessObjectList)
    }

    func readProcessPID() throws -> pid_t {
        try read(kAudioProcessPropertyPID, defaultValue: pid_t(-1))
    }

    func readProcessBundleID() -> String {
        (try? readString(kAudioProcessPropertyBundleID)) ?? ""
    }

    func readProcessIsRunningOutput() -> Bool {
        ((try? read(kAudioProcessPropertyIsRunningOutput, defaultValue: UInt32(0))) ?? 0) != 0
    }
}

/// Walks the BSD process tree so helper processes (e.g. "Google Chrome Helper")
/// can be attributed to the user-visible app that owns them.
enum ProcessTree {
    static func parentPID(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        let result = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        guard result == 0, size > 0 else { return nil }
        let ppid = info.kp_eproc.e_ppid
        return ppid > 0 ? ppid : nil
    }
}
