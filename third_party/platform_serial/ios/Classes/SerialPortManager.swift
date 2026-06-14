import Foundation

/// Codable-friendly description of a native serial port.
///
/// The descriptor is bridged to Dart as a dictionary and is also secure-coded so
/// it can be archived in future FFI-based or persistence scenarios.
@objcMembers
final class SerialPortDescriptor: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool = true

    let portName: String
    let portDescription: String
    let vendorId: String?
    let productId: String?
    let serialNumber: String?
    let platform: String
    let endpointKind: String
    let endpointValue: String
    var isOpen: Bool

    init(
        portName: String,
        portDescription: String,
        vendorId: String? = nil,
        productId: String? = nil,
        serialNumber: String? = nil,
        platform: String,
        endpointKind: String,
        endpointValue: String,
        isOpen: Bool = false
    ) {
        self.portName = portName
        self.portDescription = portDescription
        self.vendorId = vendorId
        self.productId = productId
        self.serialNumber = serialNumber
        self.platform = platform
        self.endpointKind = endpointKind
        self.endpointValue = endpointValue
        self.isOpen = isOpen
        super.init()
    }

    required init?(coder: NSCoder) {
        guard
            let portName = coder.decodeObject(of: NSString.self, forKey: "portName") as String?,
            let portDescription = coder.decodeObject(of: NSString.self, forKey: "portDescription") as String?,
            let platform = coder.decodeObject(of: NSString.self, forKey: "platform") as String?,
            let endpointKind = coder.decodeObject(of: NSString.self, forKey: "endpointKind") as String?,
            let endpointValue = coder.decodeObject(of: NSString.self, forKey: "endpointValue") as String?
        else {
            return nil
        }

        self.portName = portName
        self.portDescription = portDescription
        self.vendorId = coder.decodeObject(of: NSString.self, forKey: "vendorId") as String?
        self.productId = coder.decodeObject(of: NSString.self, forKey: "productId") as String?
        self.serialNumber = coder.decodeObject(of: NSString.self, forKey: "serialNumber") as String?
        self.platform = platform
        self.endpointKind = endpointKind
        self.endpointValue = endpointValue
        self.isOpen = coder.decodeBool(forKey: "isOpen")
        super.init()
    }

    func encode(with coder: NSCoder) {
        coder.encode(portName, forKey: "portName")
        coder.encode(portDescription, forKey: "portDescription")
        coder.encode(vendorId, forKey: "vendorId")
        coder.encode(productId, forKey: "productId")
        coder.encode(serialNumber, forKey: "serialNumber")
        coder.encode(platform, forKey: "platform")
        coder.encode(endpointKind, forKey: "endpointKind")
        coder.encode(endpointValue, forKey: "endpointValue")
        coder.encode(isOpen, forKey: "isOpen")
    }

    var asDictionary: [String: Any] {
        [
            "portName": portName,
            "description": portDescription,
            "vendorId": vendorId as Any,
            "productId": productId as Any,
            "serialNumber": serialNumber as Any,
            "isOpen": isOpen,
            "platform": platform
        ]
    }
}

/// Coordinates access to open serial ports and hides native transport details
/// from the Flutter plugin entry point.
final class SerialPortManager {
    private let stateQueue = DispatchQueue(
        label: "dev.flutter.platform_serial.ios.manager",
        qos: .userInitiated
    )

    private var openPorts: [String: SerialPort] = [:]

    deinit {
        let ports = stateQueue.sync { Array(openPorts.values) }
        for port in ports {
            Task {
                try? await port.close()
            }
        }
    }

    func availablePorts() async throws -> [SerialPortDescriptor] {
        let openNames = stateQueue.sync { Set(openPorts.keys) }
        return try await UsbSerialDriver.enumeratePorts(openPortNames: openNames)
    }

    func openPort(
        configuration: SerialPortConfiguration,
        eventHandler: @escaping ([String: Any]) -> Void
    ) async throws {
        if stateQueue.sync(execute: { openPorts[configuration.portName] != nil }) {
            throw SerialPortError.portAlreadyOpen(
                "The serial port \(configuration.portName) is already open."
            )
        }

        let descriptor = try await descriptor(for: configuration.portName)
        descriptor.isOpen = true

        let driver = UsbSerialDriver.makeDriver(for: descriptor)
        let port = SerialPort(
            descriptor: descriptor,
            configuration: configuration,
            driver: driver
        )
        port.setEventHandler(eventHandler)

        do {
            try await port.open()
            stateQueue.sync {
                openPorts[configuration.portName] = port
            }
        } catch {
            descriptor.isOpen = false
            throw error
        }
    }

    func closePort(named portName: String) async throws {
        let port = try port(named: portName)
        stateQueue.sync {
            openPorts.removeValue(forKey: portName)
        }
        try await port.close()
    }

    func readData(from portName: String, length: Int, timeoutMs: Int?) async throws -> Data {
        try await port(named: portName).read(length: length, timeoutMs: timeoutMs)
    }

    func writeData(to portName: String, data: Data, timeoutMs: Int?) async throws -> Int {
        try await port(named: portName).write(data: data, timeoutMs: timeoutMs)
    }

    func bytesAvailable(on portName: String) async throws -> Int {
        try await port(named: portName).bytesAvailable()
    }

    func resetBuffers(on portName: String) async throws {
        try await port(named: portName).resetBuffers()
    }

    func flush(portName: String) async throws {
        try await port(named: portName).flush()
    }

    private func descriptor(for portName: String) async throws -> SerialPortDescriptor {
        let descriptors = try await availablePorts()
        if let descriptor = descriptors.first(where: { $0.portName == portName }) {
            return descriptor
        }

        throw SerialPortError.portNotFound(
            "No serial port named \(portName) is currently available."
        )
    }

    private func port(named portName: String) throws -> SerialPort {
        guard let port = stateQueue.sync(execute: { openPorts[portName] }) else {
            throw SerialPortError.portClosed(
                "The serial port \(portName) is not open."
            )
        }

        return port
    }
}
