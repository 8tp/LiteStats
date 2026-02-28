import Foundation
import IOKit
import IOKit.ps
import Darwin

// ---------------------------------------------------------------------------
// StatsModel — @Observable class that owns all system-metric polling.
// Updated on a configurable timer (default 3 s). No busy-waiting.
// ---------------------------------------------------------------------------

/// Represents a single process's memory footprint
struct ProcessMemInfo: Identifiable {
    let id: pid_t
    let name: String
    let memoryMB: Double
}

/// A single point on a trend timeline
struct TrendPoint: Identifiable {
    let id: Int
    let date: Date
    let value: Double   // 0–100
}

@Observable
final class StatsModel {

    // MARK: - Uptime & Thermals

    /// Human-readable uptime string e.g. "2d 5h 12m"
    var uptimeString: String = "—"
    /// Thermal pressure state from ProcessInfo
    var thermalState: String = "Nominal"
    /// Color hint for thermal state
    var thermalSeverity: Int = 0   // 0=nominal, 1=fair, 2=serious, 3=critical
    /// CPU temperature in °C from SMC, nil if unavailable
    var cpuTemperature: Double? = nil

    // MARK: - CPU

    /// CPU usage 0–100 %
    var cpuPercent: Double = 0
    /// Logical CPU core count
    var cpuCores: Int = ProcessInfo.processInfo.processorCount

    // MARK: - RAM

    /// RAM used in bytes
    var ramUsed: UInt64 = 0
    /// RAM total in bytes
    var ramTotal: UInt64 = ProcessInfo.processInfo.physicalMemory
    /// 0–100
    var ramPercent: Double = 0

    // MARK: - Storage

    /// Bytes free on the boot volume
    var storageFree: Int64 = 0
    /// Bytes total on the boot volume
    var storageTotal: Int64 = 0

    // MARK: - Battery

    /// Battery level 0–100, nil if desktop
    var batteryLevel: Int? = nil
    /// true = plugged in / charging
    var batteryCharging: Bool = false
    /// 0–100, nil if no battery
    var batteryHealth: Int? = nil
    /// Charge cycle count, nil if unavailable
    var batteryCycles: Int? = nil
    /// true if a battery exists
    var hasBattery: Bool = false
    /// Human-readable condition string: "Normal", "Service Recommended", etc.
    var batteryCondition: String = "Normal"

    // MARK: - Network

    /// Bytes sent since last sample
    var netBytesSentPerSec: UInt64 = 0
    /// Bytes received since last sample
    var netBytesRecvPerSec: UInt64 = 0
    /// Local IP address
    var localIP: String = "—"

    // MARK: - Top processes by RAM

    /// All processes sorted by memory usage (descending), filtered > 10 MB
    var topProcesses: [ProcessMemInfo] = []

    // MARK: - Trends (rolling history, last ~60 samples)

    var cpuTrend: [TrendPoint] = []
    var ramTrend: [TrendPoint] = []
    private let maxTrendPoints = 60

    // MARK: - Panel visibility (drives expensive polling)

    /// Set by ContentView — when false, process enumeration is skipped.
    var showProcesses: Bool = false
    /// Set to true when the MenuBarExtra panel is visible.
    var panelVisible: Bool = false

    // MARK: - Status bar refresh callback

    /// Called after every refresh so AppDelegate can update the status bar title.
    @ObservationIgnored var onRefresh: (() -> Void)?

    // MARK: - Health summary

    var healthSummary: String = "All systems nominal"

    // MARK: - Preferences

    /// Update interval in seconds (1–10)
    var updateInterval: Double {
        get { _interval }
        set {
            _interval = newValue.clamped(to: 1...10)
            restartTimer()
        }
    }
    private var _interval: Double = 3

    /// Text size adjustment (0–4 points added to base font sizes)
    var textSizeOffset: CGFloat {
        get { _textSizeOffset }
        set {
            _textSizeOffset = max(0, min(4, newValue))
            UserDefaults.standard.set(Double(_textSizeOffset), forKey: "textSizeOffset")
        }
    }
    private var _textSizeOffset: CGFloat = CGFloat(UserDefaults.standard.double(forKey: "textSizeOffset"))

    // MARK: - Private state

    private var prevCPUInfo: host_cpu_load_info_data_t?
    private var timer: Timer?
    private var prevNetBytesIn: UInt64 = 0
    private var prevNetBytesOut: UInt64 = 0
    private var prevNetTimestamp: Date?
    private var smcConnection: io_connect_t = 0
    private let hostPort: mach_port_t = mach_host_self()
    private var trendCounter: Int = 0

    // MARK: - Init

    init() {
        openSMC()

        // Seed network counters so first delta isn't huge
        let (bi, bo) = Self.readNetworkCounters()
        prevNetBytesIn = bi
        prevNetBytesOut = bo
        prevNetTimestamp = Date()

        refresh()
        startTimer()

        // Retry temperature a few times at startup — Apple Silicon clusters
        // may be power-gated on the first poll and return sentinel values.
        for delay in [2.0, 5.0, 10.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.cpuTemperature == nil else { return }
                self.updateTemperature()
            }
        }
    }

    deinit {
        timer?.invalidate()
        closeSMC()
        mach_port_deallocate(mach_task_self_, hostPort)
    }

    // MARK: - Timer management

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: _interval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func restartTimer() {
        timer?.invalidate()
        startTimer()
    }

    // MARK: - Refresh entry point

    func refresh() {
        updateRAM()
        updateCPU()
        updateTrends()

        // When the panel is closed, skip expensive work (battery, storage, processes, etc.)
        guard panelVisible else {
            onRefresh?()
            return
        }

        updateUptime()
        updateThermalState()
        updateTemperature()
        updateStorage()
        updateBattery()
        updateNetwork()
        if showProcesses { updateTopProcesses() }
        updateHealthSummary()
        onRefresh?()
    }

    /// Full refresh — called when the panel opens to immediately populate all fields.
    func fullRefresh() {
        updateRAM()
        updateUptime()
        updateThermalState()
        updateTemperature()
        updateCPU()
        updateStorage()
        updateBattery()
        updateNetwork()
        if showProcesses { updateTopProcesses() }
        updateTrends()
        updateHealthSummary()
        onRefresh?()
    }

    // MARK: - Uptime

    private func updateUptime() {
        var boottime = timeval()
        var size = MemoryLayout<timeval>.size
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]

        guard sysctl(&mib, 2, &boottime, &size, nil, 0) == 0 else {
            uptimeString = "—"
            return
        }

        let bootDate = Date(timeIntervalSince1970: TimeInterval(boottime.tv_sec))
        let elapsed = Date().timeIntervalSince(bootDate)

        let days    = Int(elapsed) / 86400
        let hours   = (Int(elapsed) % 86400) / 3600
        let minutes = (Int(elapsed) % 3600) / 60

        if days > 0 {
            uptimeString = "\(days)d \(hours)h \(minutes)m"
        } else if hours > 0 {
            uptimeString = "\(hours)h \(minutes)m"
        } else {
            uptimeString = "\(minutes)m"
        }
    }

    // MARK: - Thermal state

    private func updateThermalState() {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:
            thermalState = "Nominal"
            thermalSeverity = 0
        case .fair:
            thermalState = "Fair"
            thermalSeverity = 1
        case .serious:
            thermalState = "Serious"
            thermalSeverity = 2
        case .critical:
            thermalState = "Critical"
            thermalSeverity = 3
        @unknown default:
            thermalState = "Unknown"
            thermalSeverity = 0
        }
    }

    // MARK: - Temperature (SMC)

    private func openSMC() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != IO_OBJECT_NULL else { return }
        defer { IOObjectRelease(service) }
        IOServiceOpen(service, mach_task_self_, 0, &smcConnection)
    }

    private func closeSMC() {
        if smcConnection != 0 {
            IOServiceClose(smcConnection)
            smcConnection = 0
        }
    }

    private func smcKeyCode(_ key: String) -> UInt32 {
        key.utf8.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
    }

    private func smcCall(input: inout SMCKeyData_t, output: inout SMCKeyData_t) -> Bool {
        var outputSize = MemoryLayout<SMCKeyData_t>.stride
        let kr = IOConnectCallStructMethod(
            smcConnection, KERNEL_INDEX_SMC,
            &input, MemoryLayout<SMCKeyData_t>.stride,
            &output, &outputSize
        )
        return kr == kIOReturnSuccess
    }

    private func smcReadTemp(key: String) -> Double? {
        guard smcConnection != 0 else { return nil }

        // Step 1: get key info (data type + size)
        var input = SMCKeyData_t()
        var output = SMCKeyData_t()
        input.key = smcKeyCode(key)
        input.data8 = SMC_CMD_READ_KEYINFO
        guard smcCall(input: &input, output: &output) else { return nil }
        let dataSize = output.keyInfo.dataSize
        let dataType = output.keyInfo.dataType
        guard dataSize > 0 else { return nil }

        // Step 2: read bytes
        input = SMCKeyData_t()
        output = SMCKeyData_t()
        input.key = smcKeyCode(key)
        input.keyInfo.dataSize = dataSize
        input.data8 = SMC_CMD_READ_BYTES
        guard smcCall(input: &input, output: &output) else { return nil }

        let b = output.bytes
        let temp: Double
        switch dataType {
        case smcKeyCode("sp78"):
            // big-endian signed 8.8 fixed-point
            let raw = Int16(bitPattern: UInt16(b.0) << 8 | UInt16(b.1))
            temp = Double(raw) / 256.0
        case smcKeyCode("flt "):
            // little-endian 32-bit float (native on Apple Silicon)
            let raw = UInt32(b.0) | UInt32(b.1) << 8 | UInt32(b.2) << 16 | UInt32(b.3) << 24
            temp = Double(Float(bitPattern: raw))
        case smcKeyCode("fpe2"):
            // big-endian unsigned 14.2 fixed-point
            let raw = UInt16(b.0) << 8 | UInt16(b.1)
            temp = Double(raw) / 4.0
        default:
            return nil
        }

        // < 20°C is a sentinel from a powered-down cluster, not a real reading
        return (temp > 20 && temp < 150) ? temp : nil
    }

    private func updateTemperature() {
        // Apple Silicon keys first, then Intel fallbacks
        let keys = ["Tp09", "Tp0T", "Tp01", "Tp05", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0X", "Tp0b",
                    "TC0P", "TC0C", "TC0D"]
        let readings = keys.compactMap { smcReadTemp(key: $0) }
        if let max = readings.max() {
            cpuTemperature = max   // update with fresh valid reading
        }
        // if all readings were sentinel/invalid, keep the previous value
    }

    // MARK: - CPU

    private func updateCPU() {
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        var info = host_cpu_load_info_data_t()

        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(hostPort, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }

        guard kr == KERN_SUCCESS else { return }

        if let prev = prevCPUInfo {
            let userDelta   = Double(info.cpu_ticks.0) - Double(prev.cpu_ticks.0)
            let systemDelta = Double(info.cpu_ticks.1) - Double(prev.cpu_ticks.1)
            let idleDelta   = Double(info.cpu_ticks.2) - Double(prev.cpu_ticks.2)
            let niceDelta   = Double(info.cpu_ticks.3) - Double(prev.cpu_ticks.3)

            let total = userDelta + systemDelta + idleDelta + niceDelta
            if total > 0 {
                cpuPercent = ((userDelta + systemDelta + niceDelta) / total) * 100
            }
        }

        prevCPUInfo = info
    }

    // MARK: - RAM

    private func updateRAM() {
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var vmStats = vm_statistics64_data_t()

        let kr = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(hostPort, HOST_VM_INFO64, $0, &count)
            }
        }

        guard kr == KERN_SUCCESS else { return }

        let pageSize = UInt64(vm_kernel_page_size)
        let internal_  = UInt64(vmStats.internal_page_count)
        let purgeable  = UInt64(vmStats.purgeable_count)
        let wired      = UInt64(vmStats.wire_count)
        let compressor = UInt64(vmStats.compressor_page_count)

        // Match Activity Monitor: app memory (internal - purgeable) + wired + compressor
        let appMemory = internal_ > purgeable ? internal_ - purgeable : 0
        ramUsed  = (appMemory + wired + compressor) * pageSize
        ramTotal = ProcessInfo.processInfo.physicalMemory
        ramPercent = ramTotal > 0 ? (Double(ramUsed) / Double(ramTotal)) * 100 : 0
    }

    // MARK: - Storage

    private func updateStorage() {
        do {
            let values = try URL(fileURLWithPath: "/")
                .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey,
                                          .volumeTotalCapacityKey])
            if let free  = values.volumeAvailableCapacityForImportantUsage {
                storageFree = free
            }
            if let total = values.volumeTotalCapacity {
                storageTotal = Int64(total)
            }
        } catch { }
    }

    // MARK: - Battery

    private func updateBattery() {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources  = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              !sources.isEmpty else {
            hasBattery = false
            batteryLevel = nil
            batteryHealth = nil
            batteryCycles = nil
            return
        }

        for source in sources {
            guard let info = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] else { continue }
            guard (info[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }

            hasBattery = true

            if let current = info[kIOPSCurrentCapacityKey] as? Int,
               let max     = info[kIOPSMaxCapacityKey]     as? Int, max > 0 {
                batteryLevel = Int(Double(current) / Double(max) * 100)
            } else if let current = info[kIOPSCurrentCapacityKey] as? Int {
                batteryLevel = current
            }

            batteryCharging = (info[kIOPSIsChargingKey] as? Bool) ?? false

            if let cycles = info["CycleCount"] as? Int {
                batteryCycles = cycles
            }

            let (health, cycles, condition) = readBatteryHealthFromIORegistry()
            batteryHealth = health
            if batteryCycles == nil { batteryCycles = cycles }
            batteryCondition = condition ?? "Normal"

            break
        }
    }

    /// Reads battery health, cycle count, and condition from IORegistry.
    private func readBatteryHealthFromIORegistry() -> (Int?, Int?, String?) {
        for name in ["AppleSmartBattery", "IOPMPowerSource"] {
            let service = IOServiceGetMatchingService(
                kIOMainPortDefault,
                IOServiceNameMatching(name)
            )
            guard service != IO_OBJECT_NULL else { continue }
            defer { IOObjectRelease(service) }

            func intValue(_ key: String) -> Int? {
                (IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? Int)
            }

            func stringValue(_ key: String) -> String? {
                (IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? String)
            }

            let cycles = intValue("CycleCount")
            let condition = stringValue("BatteryHealthCondition") // "Normal", "Check Battery", "Service Battery"

            let maxCap    = intValue("AppleRawMaxCapacity") ?? intValue("MaxCapacity")
            let designCap = intValue("DesignCapacity")

            if let max = maxCap, let design = designCap, design > 0, max > 0 {
                let ratio = Double(max) / Double(design)
                if ratio > 0.01 && ratio < 1.15 {
                    return (Int(ratio * 100), cycles, condition)
                }
            }

            if let c = cycles { return (nil, c, condition) }
        }

        return (nil, nil, nil)
    }

    // MARK: - Network

    private func updateNetwork() {
        let (bytesIn, bytesOut) = Self.readNetworkCounters()
        let now = Date()

        if let prevTime = prevNetTimestamp {
            let dt = now.timeIntervalSince(prevTime)
            if dt > 0 {
                let dIn  = bytesIn  >= prevNetBytesIn  ? bytesIn  - prevNetBytesIn  : 0
                let dOut = bytesOut >= prevNetBytesOut ? bytesOut - prevNetBytesOut : 0
                netBytesRecvPerSec = UInt64(Double(dIn) / dt)
                netBytesSentPerSec = UInt64(Double(dOut) / dt)
            }
        }

        prevNetBytesIn = bytesIn
        prevNetBytesOut = bytesOut
        prevNetTimestamp = now

        // Update local IP
        localIP = Self.getLocalIPAddress() ?? "—"
    }

    /// Read cumulative network byte counters via getifaddrs
    private static func readNetworkCounters() -> (bytesIn: UInt64, bytesOut: UInt64) {
        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0

        var ifaddr: UnsafeMutablePointer<ifaddrs>? = nil
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return (0, 0) }
        defer { freeifaddrs(ifaddr) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let ifa = cursor {
            let name = String(cString: ifa.pointee.ifa_name)
            // Only count physical interfaces (en*, bridge*)
            if name.hasPrefix("en") || name.hasPrefix("bridge") {
                if let data = ifa.pointee.ifa_data {
                    let networkData = data.assumingMemoryBound(to: if_data.self).pointee
                    totalIn  += UInt64(networkData.ifi_ibytes)
                    totalOut += UInt64(networkData.ifi_obytes)
                }
            }
            cursor = ifa.pointee.ifa_next
        }

        return (totalIn, totalOut)
    }

    /// Get the first non-loopback IPv4 address
    private static func getLocalIPAddress() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>? = nil
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let ifa = cursor {
            let name = String(cString: ifa.pointee.ifa_name)
            if name.hasPrefix("en"), let addr = ifa.pointee.ifa_addr {
                if addr.pointee.sa_family == UInt8(AF_INET) {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                                   &hostname, socklen_t(hostname.count),
                                   nil, 0, NI_NUMERICHOST) == 0 {
                        let ip = String(cString: hostname)
                        if ip != "127.0.0.1" { return ip }
                    }
                }
            }
            cursor = ifa.pointee.ifa_next
        }
        return nil
    }

    // MARK: - Top processes by RAM

    private func updateTopProcesses() {
        // Use proc_listallpids + proc_pidinfo to get memory for each process
        let bufferSize = proc_listallpids(nil, 0)
        guard bufferSize > 0 else { return }

        var pids = [pid_t](repeating: 0, count: Int(bufferSize))
        let actual = proc_listallpids(&pids, Int32(MemoryLayout<pid_t>.size * pids.count))
        guard actual > 0 else { return }

        var results: [ProcessMemInfo] = []

        for i in 0..<Int(actual) {
            let pid = pids[i]
            if pid == 0 { continue }

            var taskInfo = proc_taskallinfo()
            let size = Int32(MemoryLayout<proc_taskallinfo>.size)
            let ret = proc_pidinfo(pid, PROC_PIDTASKALLINFO, 0, &taskInfo, size)
            guard ret == size else { continue }

            let memBytes = taskInfo.ptinfo.pti_resident_size
            let memMB = Double(memBytes) / 1_048_576

            // Only include processes using > 10 MB
            guard memMB > 10 else { continue }

            // Get process name
            var nameBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            _ = proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
            var name = String(cString: nameBuffer)
            if name.isEmpty { name = "pid \(pid)" }

            results.append(ProcessMemInfo(id: pid, name: name, memoryMB: memMB))
        }

        // Sort descending by memory usage, keep only the top 25
        results.sort { $0.memoryMB > $1.memoryMB }
        topProcesses = Array(results.prefix(25))
    }

    // MARK: - Trends

    private func updateTrends() {
        let now = Date()
        trendCounter += 1
        cpuTrend.append(TrendPoint(id: trendCounter, date: now, value: cpuPercent))
        trendCounter += 1
        ramTrend.append(TrendPoint(id: trendCounter, date: now, value: ramPercent))

        if cpuTrend.count > maxTrendPoints { cpuTrend.removeFirst() }
        if ramTrend.count > maxTrendPoints { ramTrend.removeFirst() }
    }

    // MARK: - Health summary

    private func updateHealthSummary() {
        var warnings: [String] = []

        if let health = batteryHealth, health < 80 {
            warnings.append("Battery health low (\(health)%)")
        }
        if thermalSeverity >= 2 {
            warnings.append("Thermal pressure \(thermalState.lowercased())")
        }
        if cpuPercent > 90 {
            warnings.append("CPU usage very high")
        }
        if ramPercent > 90 {
            warnings.append("RAM pressure high")
        }
        if storageTotal > 0 {
            let freePercent = Double(storageFree) / Double(storageTotal) * 100
            if freePercent < 10 {
                warnings.append("Disk space low")
            }
        }

        healthSummary = warnings.isEmpty ? "All systems nominal" : warnings.joined(separator: " · ")
    }
}

// MARK: - Comparable clamping helper

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - SMC types & constants

private let KERNEL_INDEX_SMC: UInt32 = 2
private let SMC_CMD_READ_BYTES: UInt8 = 5
private let SMC_CMD_READ_KEYINFO: UInt8 = 9

private struct SMCKeyData_vers_t {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

private struct SMCKeyData_pLimitData_t {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

private struct SMCKeyData_keyInfo_t {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
    // 3 bytes of trailing padding to match C's sizeof (9 → 12)
    private var _pad0: UInt8 = 0
    private var _pad1: UInt8 = 0
    private var _pad2: UInt8 = 0
}

private struct SMCKeyData_t {
    var key: UInt32 = 0
    var vers = SMCKeyData_vers_t()
    var pLimitData = SMCKeyData_pLimitData_t()
    var keyInfo = SMCKeyData_keyInfo_t()
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (
                    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
                    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
}

// MARK: - libproc declarations (not exposed in Swift by default)

@_silgen_name("proc_listallpids")
func proc_listallpids(_ buffer: UnsafeMutableRawPointer?, _ bufferSize: Int32) -> Int32

@_silgen_name("proc_pidinfo")
func proc_pidinfo(_ pid: Int32, _ flavor: Int32, _ arg: UInt64, _ buffer: UnsafeMutableRawPointer?, _ bufferSize: Int32) -> Int32

@_silgen_name("proc_name")
func proc_name(_ pid: Int32, _ buffer: UnsafeMutableRawPointer?, _ bufferSize: UInt32) -> Int32

@_silgen_name("proc_pidpath")
func proc_pidpath(_ pid: Int32, _ buffer: UnsafeMutableRawPointer?, _ bufferSize: UInt32) -> Int32

let PROC_PIDTASKALLINFO: Int32 = 2
