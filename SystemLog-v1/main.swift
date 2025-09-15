import Foundation
import Darwin
import IOKit
import IOKit.usb
import IOKit.storage
import IOKit.network
import SystemConfiguration

// MARK: - Logger Configuration
struct LoggerConfig {
    static let logDirectory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("SystemLogs")
    static let logFileName = "system.log"
    static var logFilePath: URL { logDirectory.appendingPathComponent(logFileName) }
}

// MARK: - Log Levels
enum LogLevel: String {
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
    case hardware = "HARDWARE"
    case activity = "ACTIVITY"
    case system = "SYSTEM"
    case usb = "USB"
    case network = "NETWORK"
    case audio = "AUDIO"
    case display = "DISPLAY"
}

// MARK: - System Usage Structures
struct SystemUsage: Codable {
    let memoryUsage: MemoryUsage
    let storageUsage: StorageUsage
    let cpuUsage: CPUUsage
    let networkInterfaces: [NetworkInterfaceDetails]
    let connectedUSBDevices: [USBDeviceDetails]
    let audioDevices: [AudioDeviceDetails]
    let displayDevices: [DisplayDeviceDetails]
    let systemInfo: SystemInfo
}

struct MemoryUsage: Codable {
    let totalGB: Double
    let usedGB: Double
    let freeGB: Double
    let usagePercentage: Double
    let pressureState: String
}

struct StorageUsage: Codable {
    let devices: [StorageDevice]
    let totalGB: Double
    let usedGB: Double
    let freeGB: Double
}

struct StorageDevice: Codable {
    let name: String
    let totalGB: Double
    let usedGB: Double
    let freeGB: Double
    let usagePercentage: Double
    let fileSystem: String
    let mountPoint: String
}

struct CPUUsage: Codable {
    let cores: Int
    let currentUsage: Double
    let loadAverage: LoadAverage
    let architecture: String
    let brand: String
}

struct LoadAverage: Codable {
    let oneMinute: Double
    let fiveMinute: Double
    let fifteenMinute: Double
}

struct NetworkInterfaceDetails: Codable {
    let name: String
    let type: String
    let isActive: Bool
    let macAddress: String?
    let ipAddress: String?
    let speed: String?
    let bytesReceived: Int64?
    let bytesSent: Int64?
}

struct USBDeviceDetails: Codable {
    let name: String
    let vendorID: String
    let productID: String
    let serialNumber: String?
    let speed: String?
    let power: String?
}

struct AudioDeviceDetails: Codable {
    let name: String
    let type: String // "input" or "output"
    let isDefault: Bool
}

struct DisplayDeviceDetails: Codable {
    let name: String
    let resolution: String
    let refreshRate: String?
    let colorDepth: String?
    let isMain: Bool
}

struct SystemInfo: Codable {
    let hostname: String
    let osVersion: String
    let uptime: String
    let bootTime: String
}

// MARK: - Hardware Device Structures
struct USBDevice: Hashable, Codable {
    let vendorID: String
    let productID: String
    let name: String
    let serialNumber: String?
    let locationID: String
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(vendorID)
        hasher.combine(productID)
        hasher.combine(locationID)
    }
}

struct NetworkInterface: Hashable, Codable {
    let name: String
    let type: String
    let macAddress: String?
    let isActive: Bool
}

struct AudioDevice: Hashable, Codable {
    let name: String
    let uid: String
    let isInput: Bool
    let isOutput: Bool
}

struct DisplayDevice: Hashable, Codable {
    let name: String
    let resolution: String
    let isMain: Bool
}

// MARK: - Enhanced Hardware Monitor
class EnhancedHardwareMonitor {
    var previousRAMSize: Int64 = 0
    var previousCPUCount: Int = 0
    var previousStorageDevices: [String] = []
    var previousUSBDevices: Set<USBDevice> = []
    var previousNetworkInterfaces: Set<NetworkInterface> = []
    var previousAudioDevices: Set<AudioDevice> = []
    var previousDisplays: Set<DisplayDevice> = []

    init() {
        do {
            previousRAMSize = try getRAMSize()
            previousCPUCount = try getCPUCount()
            previousStorageDevices = try getStorageDevices()
            previousUSBDevices = Set(getUSBDevices())
            previousNetworkInterfaces = Set(getNetworkInterfaces())
            previousAudioDevices = Set(getAudioDevices())
            previousDisplays = Set(getDisplayDevices())
            print("Enhanced hardware monitor initialized successfully.")
        } catch {
            print("Initial hardware setup failed: \(error.localizedDescription)")
        }
    }

    // MARK: - System Usage Collection
    func getCurrentSystemUsage() -> SystemUsage {
        let memoryUsage = getMemoryUsage()
        let storageUsage = getStorageUsage()
        let cpuUsage = getCPUUsage()
        let networkInterfaces = getNetworkInterfaceDetails()
        let usbDevices = getUSBDeviceDetails()
        let audioDevices = getAudioDeviceDetails()
        let displayDevices = getDisplayDeviceDetails()
        let systemInfo = getSystemInfo()
        
        return SystemUsage(
            memoryUsage: memoryUsage,
            storageUsage: storageUsage,
            cpuUsage: cpuUsage,
            networkInterfaces: networkInterfaces,
            connectedUSBDevices: usbDevices,
            audioDevices: audioDevices,
            displayDevices: displayDevices,
            systemInfo: systemInfo
        )
    }

    func getMemoryUsage() -> MemoryUsage {
        let process = Process()
        process.launchPath = "/usr/bin/vm_stat"
        let pipe = Pipe()
        process.standardOutput = pipe
        
        var totalGB: Double = 0
        var usedGB: Double = 0
        var freeGB: Double = 0
        
        do {
            totalGB = Double(try getRAMSize()) / (1024 * 1024 * 1024)
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                return MemoryUsage(totalGB: totalGB, usedGB: 0, freeGB: totalGB, usagePercentage: 0, pressureState: "unknown")
            }
            
            var free = 0.0, active = 0.0, inactive = 0.0, wired = 0.0
            for line in output.components(separatedBy: .newlines) {
                if line.contains("Pages free:") { free = extractNumber(line) }
                else if line.contains("Pages active:") { active = extractNumber(line) }
                else if line.contains("Pages inactive:") { inactive = extractNumber(line) }
                else if line.contains("Pages wired down:") { wired = extractNumber(line) }
            }
            
            let pageSize = 4096.0
            usedGB = (active + inactive + wired) * pageSize / (1024 * 1024 * 1024)
            freeGB = free * pageSize / (1024 * 1024 * 1024)
            
        } catch {
            print("Memory usage fetch error: \(error.localizedDescription)")
        }
        
        let usagePercentage = totalGB > 0 ? (usedGB / totalGB) * 100 : 0
        return MemoryUsage(
            totalGB: totalGB,
            usedGB: usedGB,
            freeGB: freeGB,
            usagePercentage: usagePercentage,
            pressureState: getMemoryPressure()
        )
    }

    func getStorageUsage() -> StorageUsage {
        var devices: [StorageDevice] = []
        var totalGB: Double = 0
        var usedGB: Double = 0
        var freeGB: Double = 0
        
        let process = Process()
        process.launchPath = "/bin/df"
        process.arguments = ["-h"]
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                return StorageUsage(devices: [], totalGB: 0, usedGB: 0, freeGB: 0)
            }
            
            let lines = output.components(separatedBy: .newlines)
            for line in lines.dropFirst() {
                let components = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if components.count >= 6 && components[0].hasPrefix("/dev/") {
                    let name = components[0]
                    let totalStr = components[1]
                    let usedStr = components[2]
                    let freeStr = components[3]
                    let mountPoint = components[5]
                    
                    let deviceTotal = parseStorageSize(totalStr)
                    let deviceUsed = parseStorageSize(usedStr)
                    let deviceFree = parseStorageSize(freeStr)
                    let usage = deviceTotal > 0 ? (deviceUsed / deviceTotal) * 100 : 0
                    
                    devices.append(StorageDevice(
                        name: name,
                        totalGB: deviceTotal,
                        usedGB: deviceUsed,
                        freeGB: deviceFree,
                        usagePercentage: usage,
                        fileSystem: "APFS", // Default for macOS
                        mountPoint: mountPoint
                    ))
                    
                    totalGB += deviceTotal
                    usedGB += deviceUsed
                    freeGB += deviceFree
                }
            }
        } catch {
            print("Storage usage fetch error: \(error.localizedDescription)")
        }
        
        return StorageUsage(devices: devices, totalGB: totalGB, usedGB: usedGB, freeGB: freeGB)
    }

    func getCPUUsage() -> CPUUsage {
        var cpuCount = 0
        do {
            cpuCount = try getCPUCount()
        } catch {
            print("CPU count fetch error: \(error.localizedDescription)")
        }
        
        let loadAvg = getLoadAverage()
        let architecture = getCPUArchitecture()
        let brand = getCPUBrand()
        let currentUsage = getCurrentCPUUsage()
        
        return CPUUsage(
            cores: cpuCount,
            currentUsage: currentUsage,
            loadAverage: loadAvg,
            architecture: architecture,
            brand: brand
        )
    }

    func getNetworkInterfaceDetails() -> [NetworkInterfaceDetails] {
        var interfaces: [NetworkInterfaceDetails] = []
        
        let process = Process()
        process.launchPath = "/sbin/ifconfig"
        process.arguments = ["-a"]
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return [] }
            
            let blocks = output.components(separatedBy: "\n\n")
            for block in blocks {
                let lines = block.components(separatedBy: .newlines)
                if let firstLine = lines.first, firstLine.contains(":") {
                    let interfaceName = String(firstLine.components(separatedBy: ":")[0])
                    let isActive = firstLine.contains("UP")
                    
                    var macAddress: String?
                    var ipAddress: String?
                    
                    for line in lines {
                        if line.contains("ether") {
                            let components = line.trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces)
                            if components.count > 1 {
                                macAddress = components[1]
                            }
                        } else if line.contains("inet ") && !line.contains("inet6") {
                            let components = line.trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces)
                            if let index = components.firstIndex(of: "inet"), components.count > index + 1 {
                                ipAddress = components[index + 1]
                            }
                        }
                    }
                    
                    interfaces.append(NetworkInterfaceDetails(
                        name: interfaceName,
                        type: getInterfaceType(interfaceName),
                        isActive: isActive,
                        macAddress: macAddress,
                        ipAddress: ipAddress,
                        speed: getInterfaceSpeed(interfaceName),
                        bytesReceived: nil, // Can be enhanced with netstat data
                        bytesSent: nil
                    ))
                }
            }
        } catch {
            print("Network interface details fetch error: \(error.localizedDescription)")
        }
        
        return interfaces
    }

    func getUSBDeviceDetails() -> [USBDeviceDetails] {
        let usbDevices = getUSBDevices()
        return usbDevices.map { device in
            USBDeviceDetails(
                name: device.name,
                vendorID: device.vendorID,
                productID: device.productID,
                serialNumber: device.serialNumber,
                speed: nil, // Can be enhanced with IOKit speed detection
                power: nil
            )
        }
    }

    func getAudioDeviceDetails() -> [AudioDeviceDetails] {
        let audioDevices = getAudioDevices()
        return audioDevices.map { device in
            AudioDeviceDetails(
                name: device.name,
                type: device.isInput ? "input" : "output",
                isDefault: false // Can be enhanced with default device detection
            )
        }
    }

    func getDisplayDeviceDetails() -> [DisplayDeviceDetails] {
        let displays = getDisplayDevices()
        return displays.map { display in
            DisplayDeviceDetails(
                name: display.name,
                resolution: display.resolution,
                refreshRate: nil, // Can be enhanced with refresh rate detection
                colorDepth: nil,
                isMain: display.isMain
            )
        }
    }

    func getSystemInfo() -> SystemInfo {
        return SystemInfo(
            hostname: ProcessInfo.processInfo.hostName,
            osVersion: getOSVersion(),
            uptime: getUptime(),
            bootTime: getBootTime()
        )
    }

    // MARK: - Helper Methods
    func extractNumber(_ line: String) -> Double {
        line.components(separatedBy: .whitespaces).compactMap { Double($0) }.first ?? 0
    }

    func parseStorageSize(_ sizeStr: String) -> Double {
        let cleanStr = sizeStr.replacingOccurrences(of: "Gi", with: "G")
        if let value = Double(cleanStr.dropLast()) {
            let unit = String(cleanStr.suffix(1))
            switch unit.uppercased() {
            case "T": return value * 1024
            case "G": return value
            case "M": return value / 1024
            case "K": return value / (1024 * 1024)
            default: return value / (1024 * 1024 * 1024)
            }
        }
        return 0
    }

    func getMemoryPressure() -> String {
        // Simplified memory pressure detection
        return "normal" // Can be enhanced with actual pressure monitoring
    }

    func getLoadAverage() -> LoadAverage {
        var loadavg = [Double](repeating: 0, count: 3)
        if getloadavg(&loadavg, 3) != -1 {
            return LoadAverage(oneMinute: loadavg[0], fiveMinute: loadavg[1], fifteenMinute: loadavg[2])
        }
        return LoadAverage(oneMinute: 0, fiveMinute: 0, fifteenMinute: 0)
    }

    func getCPUArchitecture() -> String {
        var size: Int = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        return String(cString: machine)
    }

    func getCPUBrand() -> String {
        var size: Int = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var brand = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &brand, &size, nil, 0)
        return String(cString: brand)
    }

    func getCurrentCPUUsage() -> Double {
        // Simplified CPU usage - can be enhanced with more detailed monitoring
        return 0.0
    }

    func getInterfaceSpeed(_ name: String) -> String? {
        // Can be enhanced with actual speed detection
        return nil
    }

    func getOSVersion() -> String {
        return ProcessInfo.processInfo.operatingSystemVersionString
    }

    func getUptime() -> String {
        let uptime = ProcessInfo.processInfo.systemUptime
        let hours = Int(uptime) / 3600
        let minutes = (Int(uptime) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }

    func getBootTime() -> String {
        let bootTime = Date(timeIntervalSinceNow: -ProcessInfo.processInfo.systemUptime)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: bootTime)
    }

    // MARK: - Existing Hardware Change Detection Methods
    func checkAllHardwareChanges() -> [String] {
        var changes: [String] = []
        changes.append(contentsOf: checkBasicHardwareChanges())
        changes.append(contentsOf: checkUSBChanges())
        changes.append(contentsOf: checkNetworkChanges())
        changes.append(contentsOf: checkAudioChanges())
        changes.append(contentsOf: checkDisplayChanges())
        return changes
    }

    func checkBasicHardwareChanges() -> [String] {
        var changes: [String] = []
        do {
            let currentRAM = try getRAMSize()
            if currentRAM != previousRAMSize {
                let changeType = currentRAM > previousRAMSize ? "added" : "removed"
                let sizeDiff = abs(currentRAM - previousRAMSize) / (1024 * 1024 * 1024)
                changes.append("HARDWARE CHANGE: RAM \(changeType): \(sizeDiff) GB")
                previousRAMSize = currentRAM
            }

            let currentCPUCount = try getCPUCount()
            if currentCPUCount != previousCPUCount {
                changes.append("HARDWARE CHANGE: CPU count changed: \(previousCPUCount) → \(currentCPUCount)")
                previousCPUCount = currentCPUCount
            }

            let currentStorageDevices = try getStorageDevices()
            let removedDevices = Set(previousStorageDevices).subtracting(Set(currentStorageDevices))
            let addedDevices = Set(currentStorageDevices).subtracting(Set(previousStorageDevices))
            for device in removedDevices { changes.append("HARDWARE CHANGE: Storage removed: \(device)") }
            for device in addedDevices { changes.append("HARDWARE CHANGE: Storage added: \(device)") }
            if !addedDevices.isEmpty || !removedDevices.isEmpty {
                previousStorageDevices = currentStorageDevices
            }
        } catch {
            changes.append("HARDWARE ERROR: \(error.localizedDescription)")
        }
        return changes
    }

    func checkUSBChanges() -> [String] {
        var changes: [String] = []
        let currentUSBDevices = Set(getUSBDevices())
        
        let removedUSB = previousUSBDevices.subtracting(currentUSBDevices)
        let addedUSB = currentUSBDevices.subtracting(previousUSBDevices)
        
        for device in removedUSB {
            changes.append("USB CHANGE: Device unplugged: \(device.name) (VID: \(device.vendorID), PID: \(device.productID))")
        }
        
        for device in addedUSB {
            changes.append("USB CHANGE: Device plugged: \(device.name) (VID: \(device.vendorID), PID: \(device.productID))")
        }
        
        if !addedUSB.isEmpty || !removedUSB.isEmpty {
            previousUSBDevices = currentUSBDevices
        }
        
        return changes
    }

    func checkNetworkChanges() -> [String] {
        var changes: [String] = []
        let currentNetworkInterfaces = Set(getNetworkInterfaces())
        
        let removedInterfaces = previousNetworkInterfaces.subtracting(currentNetworkInterfaces)
        let addedInterfaces = currentNetworkInterfaces.subtracting(previousNetworkInterfaces)
        
        for interface in removedInterfaces {
            changes.append("NETWORK CHANGE: Interface removed: \(interface.name) (\(interface.type))")
        }
        
        for interface in addedInterfaces {
            changes.append("NETWORK CHANGE: Interface added: \(interface.name) (\(interface.type))")
        }
        
        for current in currentNetworkInterfaces {
            if let previous = previousNetworkInterfaces.first(where: { $0.name == current.name }) {
                if current.isActive != previous.isActive {
                    let status = current.isActive ? "activated" : "deactivated"
                    changes.append("NETWORK CHANGE: Interface \(status): \(current.name)")
                }
            }
        }
        
        if !addedInterfaces.isEmpty || !removedInterfaces.isEmpty {
            previousNetworkInterfaces = currentNetworkInterfaces
        }
        
        return changes
    }

    func checkAudioChanges() -> [String] {
        var changes: [String] = []
        let currentAudioDevices = Set(getAudioDevices())
        
        let removedAudio = previousAudioDevices.subtracting(currentAudioDevices)
        let addedAudio = currentAudioDevices.subtracting(previousAudioDevices)
        
        for device in removedAudio {
            let type = device.isInput ? "input" : "output"
            changes.append("AUDIO CHANGE: \(type) device removed: \(device.name)")
        }
        
        for device in addedAudio {
            let type = device.isInput ? "input" : "output"
            changes.append("AUDIO CHANGE: \(type) device added: \(device.name)")
        }
        
        if !addedAudio.isEmpty || !removedAudio.isEmpty {
            previousAudioDevices = currentAudioDevices
        }
        
        return changes
    }

    func checkDisplayChanges() -> [String] {
        var changes: [String] = []
        let currentDisplays = Set(getDisplayDevices())
        
        let removedDisplays = previousDisplays.subtracting(currentDisplays)
        let addedDisplays = currentDisplays.subtracting(previousDisplays)
        
        for display in removedDisplays {
            changes.append("DISPLAY CHANGE: Monitor disconnected: \(display.name) (\(display.resolution))")
        }
        
        for display in addedDisplays {
            changes.append("DISPLAY CHANGE: Monitor connected: \(display.name) (\(display.resolution))")
        }
        
        if !addedDisplays.isEmpty || !removedDisplays.isEmpty {
            previousDisplays = currentDisplays
        }
        
        return changes
    }

    // MARK: - Hardware Detection Methods (existing code)
    func getUSBDevices() -> [USBDevice] {
        var devices: [USBDevice] = []
        
        let matchingDict = IOServiceMatching(kIOUSBDeviceClassName)
        var iterator: io_iterator_t = 0
        
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator)
        
        if result == kIOReturnSuccess {
            var service = IOIteratorNext(iterator)
            while service != 0 {
                let vendorID = IORegistryEntryCreateCFProperty(service, "idVendor" as CFString, kCFAllocatorDefault, 0)
                let productID = IORegistryEntryCreateCFProperty(service, "idProduct" as CFString, kCFAllocatorDefault, 0)
                let productName = IORegistryEntryCreateCFProperty(service, "USB Product Name" as CFString, kCFAllocatorDefault, 0)
                let serialNumber = IORegistryEntryCreateCFProperty(service, "USB Serial Number" as CFString, kCFAllocatorDefault, 0)
                let locationID = IORegistryEntryCreateCFProperty(service, "locationID" as CFString, kCFAllocatorDefault, 0)
                
                if let vid = vendorID?.takeRetainedValue() as? NSNumber,
                   let pid = productID?.takeRetainedValue() as? NSNumber,
                   let loc = locationID?.takeRetainedValue() as? NSNumber {
                    
                    let name = (productName?.takeRetainedValue() as? String) ?? "Unknown USB Device"
                    let serial = serialNumber?.takeRetainedValue() as? String
                    
                    let device = USBDevice(
                        vendorID: String(format: "0x%04X", vid.uint16Value),
                        productID: String(format: "0x%04X", pid.uint16Value),
                        name: name,
                        serialNumber: serial,
                        locationID: String(format: "0x%08X", loc.uint32Value)
                    )
                    devices.append(device)
                }
                
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
        }
        
        IOObjectRelease(iterator)
        return devices
    }

    func getNetworkInterfaces() -> [NetworkInterface] {
        var interfaces: [NetworkInterface] = []
        
        let process = Process()
        process.launchPath = "/sbin/ifconfig"
        process.arguments = ["-a"]
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return [] }
            
            let lines = output.components(separatedBy: .newlines)
            var currentInterface: String?
            var isActive = false
            var macAddress: String?
            
            for line in lines {
                if !line.hasPrefix("\t") && !line.hasPrefix(" ") && line.contains(":") {
                    if let interface = currentInterface {
                        let type = getInterfaceType(interface)
                        interfaces.append(NetworkInterface(name: interface, type: type, macAddress: macAddress, isActive: isActive))
                    }
                    
                    currentInterface = String(line.components(separatedBy: ":")[0])
                    isActive = line.contains("UP")
                    macAddress = nil
                } else if line.contains("ether") {
                    let components = line.trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces)
                    if components.count > 1 {
                        macAddress = components[1]
                    }
                }
            }
            
            if let interface = currentInterface {
                let type = getInterfaceType(interface)
                interfaces.append(NetworkInterface(name: interface, type: type, macAddress: macAddress, isActive: isActive))
            }
            
        } catch {
            print("Network interface fetch error: \(error.localizedDescription)")
        }
        
        return interfaces
    }

    func getInterfaceType(_ name: String) -> String {
        if name.hasPrefix("en") { return "Ethernet/WiFi" }
        if name.hasPrefix("lo") { return "Loopback" }
        if name.hasPrefix("utun") { return "VPN" }
        if name.hasPrefix("bridge") { return "Bridge" }
        if name.hasPrefix("awdl") { return "AirDrop" }
        return "Unknown"
    }

    func getAudioDevices() -> [AudioDevice] {
        var devices: [AudioDevice] = []
        
        let process = Process()
        process.launchPath = "/usr/sbin/system_profiler"
        process.arguments = ["SPAudioDataType", "-json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return [] }
            
            if let jsonData = output.data(using: .utf8),
               let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let audioData = json["SPAudioDataType"] as? [[String: Any]] {
                
                for item in audioData {
                    if let name = item["_name"] as? String {
                        let uid = (item["coreaudio_device_id"] as? String) ?? UUID().uuidString
                        let hasInput = (item["coreaudio_input_source"] as? String) != nil
                        let hasOutput = (item["coreaudio_output_source"] as? String) != nil
                        
                        if hasInput {
                            devices.append(AudioDevice(name: name, uid: uid + "_input", isInput: true, isOutput: false))
                        }
                        if hasOutput {
                            devices.append(AudioDevice(name: name, uid: uid + "_output", isInput: false, isOutput: true))
                        }
                    }
                }
            }
        } catch {
            print("Audio device fetch error: \(error.localizedDescription)")
        }
        
        return devices
    }

    func getDisplayDevices() -> [DisplayDevice] {
        var devices: [DisplayDevice] = []
        
        let process = Process()
        process.launchPath = "/usr/sbin/system_profiler"
        process.arguments = ["SPDisplaysDataType", "-json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return [] }
            
            if let jsonData = output.data(using: .utf8),
               let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let displaysData = json["SPDisplaysDataType"] as? [[String: Any]] {
                
                for display in displaysData {
                    if let name = display["_name"] as? String {
                        let resolution = (display["_spdisplays_resolution"] as? String) ?? "Unknown"
                        let isMain = (display["spdisplays_main"] as? String) == "spdisplays_yes"
                        
                        devices.append(DisplayDevice(name: name, resolution: resolution, isMain: isMain))
                        
                        if let displays = display["spdisplays_ndrvs"] as? [[String: Any]] {
                            for connectedDisplay in displays {
                                if let connectedName = connectedDisplay["_name"] as? String {
                                    let connectedResolution = (connectedDisplay["_spdisplays_resolution"] as? String) ?? "Unknown"
                                    devices.append(DisplayDevice(name: connectedName, resolution: connectedResolution, isMain: false))
                                }
                            }
                        }
                    }
                }
            }
        } catch {
            print("Display device fetch error: \(error.localizedDescription)")
        }
        
        return devices
    }

    func getRAMSize() throws -> Int64 {
        var size: Int64 = 0
        var sizeSize = MemoryLayout<Int64>.size
        let result = sysctlbyname("hw.memsize", &size, &sizeSize, nil, 0)
        if result != 0 {
            throw NSError(domain: "Hardware", code: Int(result), userInfo: [NSLocalizedDescriptionKey: "RAM fetch failed with code \(result)"])
        }
        return size
    }

    func getCPUCount() throws -> Int {
        var count: Int = 0
        var countSize = MemoryLayout<Int>.size
        let result = sysctlbyname("hw.ncpu", &count, &countSize, nil, 0)
        if result != 0 {
            throw NSError(domain: "Hardware", code: Int(result), userInfo: [NSLocalizedDescriptionKey: "CPU fetch failed with code \(result)"])
        }
        return count
    }

    func getStorageDevices() throws -> [String] {
        let process = Process()
        process.launchPath = "/usr/sbin/diskutil"
        process.arguments = ["list"]
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.qualityOfService = .userInitiated
        do {
            try process.run()
            process.waitUntilExit()
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            if process.terminationStatus != 0, let errorOutput = String(data: errorData, encoding: .utf8), !errorOutput.isEmpty {
                throw NSError(domain: "Hardware", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "diskutil failed: \(errorOutput)"])
            }
            guard let output = String(data: outputData, encoding: .utf8) else {
                throw NSError(domain: "Hardware", code: -1, userInfo: [NSLocalizedDescriptionKey: "diskutil decode failed"])
            }
            let lines = output.components(separatedBy: .newlines)
            var devices: [String] = []
            for line in lines where line.contains("/dev/disk") {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("/dev/disk") { devices.append(trimmed) }
            }
            return devices
        } catch {
            throw error
        }
    }
}

// MARK: - Enhanced System Logger
class EnhancedSystemLogger {
    private let dateFormatter: DateFormatter = { let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HH:mm:ss"; return df }()
    private let isoFormatter: DateFormatter = { let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"; df.timeZone = TimeZone(abbreviation: "UTC"); return df }()
    private var isInitialized = false
    private let hardwareMonitor = EnhancedHardwareMonitor()
    private let n8nWebhookURL = URL(string: "http://localhost:5678/webhook-test/system-log")

    init() {
        do {
            let attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o755]
            try FileManager.default.createDirectory(at: LoggerConfig.logDirectory, withIntermediateDirectories: true, attributes: attributes)
            isInitialized = true
            print("Enhanced system logger initialized at \(LoggerConfig.logDirectory.path)")
        } catch {
            print("Log dir error: \(error.localizedDescription)")
            isInitialized = false
        }
    }

    func log(_ message: String, level: LogLevel = .info) {
        let timestamp = dateFormatter.string(from: Date())
        let entry = "[\(timestamp)] [\(level.rawValue)] \(message)"
        print(entry)
        
        if isInitialized {
            writeToLogFile(entry)
        }
        
        // Send individual change events to n8n
        sendEventToN8n(message: message, level: level)
    }

    private func writeToLogFile(_ entry: String) {
        let fullEntry = entry + "\n"
        do {
            if !FileManager.default.isWritableFile(atPath: LoggerConfig.logDirectory.path) {
                throw NSError(domain: "Logger", code: -1, userInfo: [NSLocalizedDescriptionKey: "No write permission for \(LoggerConfig.logDirectory.path)"])
            }
            if FileManager.default.fileExists(atPath: LoggerConfig.logFilePath.path) {
                if let handle = try? FileHandle(forWritingTo: LoggerConfig.logFilePath) {
                    handle.seekToEndOfFile()
                    handle.write(fullEntry.data(using: .utf8) ?? Data())
                    handle.closeFile()
                }
            } else {
                try fullEntry.write(to: LoggerConfig.logFilePath, atomically: true, encoding: .utf8)
            }
        } catch {
            print("Log write error: \(error.localizedDescription)")
        }
    }

    private func sendEventToN8n(message: String, level: LogLevel) {
        guard let url = n8nWebhookURL else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Get current system usage
        let systemUsage = hardwareMonitor.getCurrentSystemUsage()
        
        let payload: [String: Any] = [
            "timestamp": isoFormatter.string(from: Date()),
            "level": level.rawValue,
            "message": message,
            "macbook_user": "devteam",
            "event_type": "hardware_change",
            "hostname": ProcessInfo.processInfo.hostName,
            "system_usage": try! JSONSerialization.jsonObject(with: JSONEncoder().encode(systemUsage))
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    print("n8n error: \(error.localizedDescription)")
                } else if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 200 {
                        print("n8n success: \(level.rawValue) event sent")
                    } else {
                        print("n8n status: \(httpResponse.statusCode)")
                    }
                }
            }.resume()
        } catch {
            print("n8n JSON error: \(error.localizedDescription)")
        }
    }

    func checkHardwareChanges() {
        let changes = hardwareMonitor.checkAllHardwareChanges()
        
        for change in changes {
            if change.contains("USB") {
                log(change, level: .usb)
            } else if change.contains("NETWORK") {
                log(change, level: .network)
            } else if change.contains("AUDIO") {
                log(change, level: .audio)
            } else if change.contains("DISPLAY") {
                log(change, level: .display)
            } else {
                log(change, level: .hardware)
            }
        }
        
        if changes.isEmpty {
            log("Hardware check completed - no changes detected", level: .info)
        }
    }

    func startMonitoring(interval: TimeInterval = 10.0) {
        log("Starting comprehensive hardware monitoring every \(interval) seconds", level: .info)
        signal(SIGINT) { _ in print("\nStopping..."); exit(0) }
        
        while true {
            checkHardwareChanges()
            Thread.sleep(forTimeInterval: interval)
        }
    }
}

// MARK: - Main
let logger = EnhancedSystemLogger()
logger.startMonitoring(interval: 60.0)
