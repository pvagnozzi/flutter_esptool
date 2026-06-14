import Foundation
import Network

#if !targetEnvironment(simulator)
    #if canImport(IOKit)
        import IOKit
    #endif
    #if canImport(IOKit.serial)
        import IOKit.serial
    #endif
    #if canImport(IOKit.usb)
        import IOKit.usb
    #endif
#endif

/// Common transport API used by a [SerialPort].
protocol UsbSerialDriving: AnyObject {
    var onData: ((Data) -> Void)? { get set }
    var onError: ((Error) -> Void)? { get set }

    func connect(using configuration: SerialPortConfiguration) async throws
    func disconnect() async
    func read(maximumLength: Int, timeoutMs: Int) async throws -> Data
    func write(_ data: Data, timeoutMs: Int) async throws -> Int
    func bytesAvailable() async -> Int
    func flush() async throws
    func resetBuffers() async throws
}

/// Network-framework-backed transport used for physical device communication.
///
/// The implementation uses a dedicated dispatch queue for all socket state and
/// buffers. The read API consumes from an in-memory receive buffer populated by
/// NWConnection's recursive receive loop, which keeps reads and stream events
/// consistent.
final class UsbSerialDriver: NSObject, UsbSerialDriving {
    enum EndpointKind: String {
        case unix
        case hostPort
        case mock
    }

    static func makeDriver(for descriptor: SerialPortDescriptor) -> UsbSerialDriving {
        if descriptor.endpointKind == EndpointKind.mock.rawValue {
            return MockUsbSerialDriver(descriptor: descriptor)
        }

        return UsbSerialDriver(descriptor: descriptor)
    }

    static func enumeratePorts(openPortNames: Set<String>) async throws -> [SerialPortDescriptor] {
#if targetEnvironment(simulator)
        return mockDescriptors(openPortNames: openPortNames)
#else
    #if canImport(IOKit) && canImport(IOKit.serial) && canImport(IOKit.usb)
        var iterator: io_iterator_t = 0
        guard let matching = IOServiceMatching(kIOSerialBSDServiceValue) else {
            throw SerialPortError.io("Unable to create the IOKit serial matching dictionary.")
        }

        CFDictionarySetValue(
            matching,
            Unmanaged.passUnretained(kIOSerialBSDTypeKey as CFString).toOpaque(),
            Unmanaged.passUnretained(kIOSerialBSDAllTypes as CFString).toOpaque()
        )

        let status = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard status == KERN_SUCCESS else {
            throw SerialPortError.io("IOKit failed to enumerate serial ports (kern code \(status)).")
        }

        defer {
            IOObjectRelease(iterator)
        }

        var descriptors: [SerialPortDescriptor] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer {
                IOObjectRelease(service)
            }

            guard
                let callout = registryString(service, key: kIOCalloutDeviceKey),
                let ttyName = registryString(service, key: kIOTTYDeviceKey)
            else {
                continue
            }

            let baseName = registryString(service, key: kIOTTYBaseNameKey)
            let productName = registryString(service, key: kUSBProductString)
            let serialNumber = registryString(service, key: kUSBSerialNumberString)
            let vendorId = registryNumber(service, key: kUSBVendorID).map {
                String(format: "%04X", $0)
            }
            let productId = registryNumber(service, key: kUSBProductID).map {
                String(format: "%04X", $0)
            }

            let portName = baseName ?? ttyName
            let description = productName ?? ttyName

            descriptors.append(
                SerialPortDescriptor(
                    portName: portName,
                    portDescription: description,
                    vendorId: vendorId,
                    productId: productId,
                    serialNumber: serialNumber,
                    platform: "ios",
                    endpointKind: EndpointKind.unix.rawValue,
                    endpointValue: callout,
                    isOpen: openPortNames.contains(portName)
                )
            )
        }

        if descriptors.isEmpty {
            return mockDescriptors(openPortNames: openPortNames)
        }

        return descriptors
    #else
        throw SerialPortError.unsupported(
            "This iOS target does not expose the IOKit APIs required for USB serial enumeration."
        )
    #endif
#endif
    }

    static func mockDescriptors(openPortNames: Set<String>) -> [SerialPortDescriptor] {
        [
            SerialPortDescriptor(
                portName: "SIM_USB_001",
                portDescription: "Simulator USB loopback port",
                vendorId: "FFFF",
                productId: "0001",
                serialNumber: "SIM-USB-001",
                platform: "ios-simulator",
                endpointKind: EndpointKind.mock.rawValue,
                endpointValue: "mock://sim_usb_001",
                isOpen: openPortNames.contains("SIM_USB_001")
            ),
            SerialPortDescriptor(
                portName: "SIM_USB_002",
                portDescription: "Simulator diagnostics port",
                vendorId: "FFFF",
                productId: "0002",
                serialNumber: "SIM-USB-002",
                platform: "ios-simulator",
                endpointKind: EndpointKind.mock.rawValue,
                endpointValue: "mock://sim_usb_002",
                isOpen: openPortNames.contains("SIM_USB_002")
            )
        ]
    }

    var onData: ((Data) -> Void)?
    var onError: ((Error) -> Void)?

    private let descriptor: SerialPortDescriptor
    private let queue: DispatchQueue

    private var connection: NWConnection?
    private var isConnected = false
    private var lastError: Error?
    private var inboundBuffer = Data()

    init(
        descriptor: SerialPortDescriptor,
        queue: DispatchQueue? = nil
    ) {
        self.descriptor = descriptor
        self.queue = queue ?? DispatchQueue(
            label: "dev.flutter.platform_serial.ios.transport.\(descriptor.portName)",
            qos: .userInitiated
        )
        super.init()
    }

    func connect(using configuration: SerialPortConfiguration) async throws {
        try configuration.validate()

        if await currentConnectionState() {
            throw SerialPortError.portAlreadyOpen(
                "The serial port \(descriptor.portName) is already connected."
            )
        }

        let connection = try buildConnection()
        self.connection = connection

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await self.awaitReadyState(for: connection)
            }

            if configuration.readTimeoutMs > 0 {
                group.addTask {
                    try await Task.sleep(
                        nanoseconds: UInt64(configuration.readTimeoutMs) * 1_000_000
                    )
                    throw SerialPortError.timeout(
                        "Timed out while opening serial port \(self.descriptor.portName)."
                    )
                }
            }

            _ = try await group.next()
            group.cancelAll()
        }

        queue.async {
            self.isConnected = true
            self.lastError = nil
        }
        startReceiveLoop()
    }

    func disconnect() async {
        let currentConnection = await withCheckedContinuation { continuation in
            queue.async {
                let current = self.connection
                self.connection = nil
                self.isConnected = false
                self.inboundBuffer.removeAll(keepingCapacity: false)
                continuation.resume(returning: current)
            }
        }

        currentConnection?.cancel()
    }

    func read(maximumLength: Int, timeoutMs: Int) async throws -> Data {
        if maximumLength <= 0 {
            return Data()
        }

        let deadline = timeoutMs > 0
            ? Date().addingTimeInterval(TimeInterval(timeoutMs) / 1_000)
            : nil

        while true {
            if let error = await currentError() {
                throw error
            }

            let chunk = await consumeBuffer(maximumLength: maximumLength)
            if !chunk.isEmpty {
                return chunk
            }

            if let deadline, Date() >= deadline {
                throw SerialPortError.timeout(
                    "Timed out waiting for up to \(maximumLength) byte(s) from \(descriptor.portName)."
                )
            }

            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    func write(_ data: Data, timeoutMs: Int) async throws -> Int {
        guard !data.isEmpty else {
            return 0
        }

        let connection = try await activeConnection()

        return try await withThrowingTaskGroup(of: Int.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    connection.send(content: data, completion: .contentProcessed { error in
                        if let error {
                            continuation.resume(
                                throwing: SerialPortError.io(
                                    "Failed to write to \(self.descriptor.portName): \(error.localizedDescription)"
                                )
                            )
                            return
                        }

                        continuation.resume(returning: data.count)
                    })
                }
            }

            if timeoutMs > 0 {
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(timeoutMs) * 1_000_000)
                    throw SerialPortError.timeout(
                        "Timed out while writing \(data.count) byte(s) to \(self.descriptor.portName)."
                    )
                }
            }

            let written = try await group.next() ?? 0
            group.cancelAll()
            return written
        }
    }

    func bytesAvailable() async -> Int {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.inboundBuffer.count)
            }
        }
    }

    func flush() async throws {
        _ = try await activeConnection()
    }

    func resetBuffers() async throws {
        _ = try await activeConnection()
        await withCheckedContinuation { continuation in
            queue.async {
                self.inboundBuffer.removeAll(keepingCapacity: false)
                continuation.resume(returning: ())
            }
        }
    }

    private func buildConnection() throws -> NWConnection {
        guard let endpointKind = EndpointKind(rawValue: descriptor.endpointKind) else {
            throw SerialPortError.configuration(
                "Unsupported endpoint kind \(descriptor.endpointKind)."
            )
        }

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        switch endpointKind {
        case .unix:
            return NWConnection(
                to: .unix(path: descriptor.endpointValue),
                using: parameters
            )
        case .hostPort:
            let components = descriptor.endpointValue.split(separator: ":")
            guard
                components.count == 2,
                let portNumber = UInt16(components[1])
            else {
                throw SerialPortError.configuration(
                    "Endpoint \(descriptor.endpointValue) is not a valid host:port pair."
                )
            }

            guard let port = NWEndpoint.Port(rawValue: portNumber) else {
                throw SerialPortError.configuration(
                    "Port \(portNumber) is not valid for Network.framework."
                )
            }

            return NWConnection(
                host: NWEndpoint.Host(String(components[0])),
                port: port,
                using: parameters
            )
        case .mock:
            throw SerialPortError.unsupported(
                "Mock endpoints must use MockUsbSerialDriver."
            )
        }
    }

    private func awaitReadyState(for connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { continuation in
            var resolved = false

            connection.stateUpdateHandler = { [weak self] state in
                guard !resolved else {
                    return
                }

                switch state {
                case .ready:
                    resolved = true
                    continuation.resume(returning: ())
                case .failed(let error):
                    resolved = true
                    let wrapped = SerialPortError.io(
                        "Failed to connect to \(self?.descriptor.portName ?? "serial port"): \(error.localizedDescription)"
                    )
                    self?.report(error: wrapped)
                    continuation.resume(throwing: wrapped)
                case .cancelled:
                    resolved = true
                    let wrapped = SerialPortError.portClosed(
                        "The connection to \(self?.descriptor.portName ?? "serial port") was cancelled."
                    )
                    continuation.resume(throwing: wrapped)
                default:
                    break
                }
            }

            connection.start(queue: queue)
        }
    }

    private func startReceiveLoop() {
        guard let connection else {
            return
        }

        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 4_096
        ) { [weak self] content, _, isComplete, error in
            guard let self else {
                return
            }

            self.queue.async {
                if let content, !content.isEmpty {
                    self.inboundBuffer.append(content)
                    self.onData?(content)
                }

                if let error {
                    self.report(
                        error: SerialPortError.io(
                            "Read failure on \(self.descriptor.portName): \(error.localizedDescription)"
                        )
                    )
                    return
                }

                if isComplete {
                    self.report(
                        error: SerialPortError.portClosed(
                            "The device \(self.descriptor.portName) closed the connection."
                        )
                    )
                    return
                }

                self.startReceiveLoop()
            }
        }
    }

    private func activeConnection() async throws -> NWConnection {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard self.isConnected, let connection = self.connection else {
                    continuation.resume(
                        throwing: SerialPortError.portClosed(
                            "The serial port \(self.descriptor.portName) is not connected."
                        )
                    )
                    return
                }

                continuation.resume(returning: connection)
            }
        }
    }

    private func currentConnectionState() async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.isConnected)
            }
        }
    }

    private func currentError() async -> Error? {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.lastError)
            }
        }
    }

    private func consumeBuffer(maximumLength: Int) async -> Data {
        await withCheckedContinuation { continuation in
            queue.async {
                guard !self.inboundBuffer.isEmpty else {
                    continuation.resume(returning: Data())
                    return
                }

                let count = min(maximumLength, self.inboundBuffer.count)
                let chunk = self.inboundBuffer.prefix(count)
                self.inboundBuffer.removeFirst(count)
                continuation.resume(returning: Data(chunk))
            }
        }
    }

    private func report(error: Error) {
        lastError = error
        onError?(error)
    }
}

/// Lightweight loopback transport used on the iOS simulator.
final class MockUsbSerialDriver: UsbSerialDriving {
    var onData: ((Data) -> Void)?
    var onError: ((Error) -> Void)?

    private let descriptor: SerialPortDescriptor
    private let queue: DispatchQueue

    private var isConnected = false
    private var inboundBuffer = Data()

    init(descriptor: SerialPortDescriptor) {
        self.descriptor = descriptor
        queue = DispatchQueue(
            label: "dev.flutter.platform_serial.ios.mock.\(descriptor.portName)",
            qos: .userInitiated
        )
    }

    func connect(using configuration: SerialPortConfiguration) async throws {
        try configuration.validate()
        await withCheckedContinuation { continuation in
            queue.async {
                self.isConnected = true
                continuation.resume(returning: ())
            }
        }
    }

    func disconnect() async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.isConnected = false
                self.inboundBuffer.removeAll(keepingCapacity: false)
                continuation.resume(returning: ())
            }
        }
    }

    func read(maximumLength: Int, timeoutMs: Int) async throws -> Data {
        guard maximumLength > 0 else {
            return Data()
        }

        let deadline = timeoutMs > 0
            ? Date().addingTimeInterval(TimeInterval(timeoutMs) / 1_000)
            : nil

        while true {
            let chunk = await withCheckedContinuation { continuation in
                queue.async {
                    guard !self.inboundBuffer.isEmpty else {
                        continuation.resume(returning: Data())
                        return
                    }

                    let count = min(maximumLength, self.inboundBuffer.count)
                    let chunk = self.inboundBuffer.prefix(count)
                    self.inboundBuffer.removeFirst(count)
                    continuation.resume(returning: Data(chunk))
                }
            }

            if !chunk.isEmpty {
                return chunk
            }

            if let deadline, Date() >= deadline {
                throw SerialPortError.timeout(
                    "Timed out waiting for simulator data on \(descriptor.portName)."
                )
            }

            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    func write(_ data: Data, timeoutMs: Int) async throws -> Int {
        _ = timeoutMs

        return try await withCheckedThrowingContinuation { continuation in
            queue.asyncAfter(deadline: .now() + .milliseconds(25)) {
                guard self.isConnected else {
                    let error = SerialPortError.portClosed(
                        "The simulator port \(self.descriptor.portName) is closed."
                    )
                    self.onError?(error)
                    continuation.resume(throwing: error)
                    return
                }

                self.inboundBuffer.append(data)
                self.onData?(data)
                continuation.resume(returning: data.count)
            }
        }
    }

    func bytesAvailable() async -> Int {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.inboundBuffer.count)
            }
        }
    }

    func flush() async throws {
        if !(await isOpen()) {
            throw SerialPortError.portClosed(
                "The simulator port \(descriptor.portName) is closed."
            )
        }
    }

    func resetBuffers() async throws {
        await withCheckedContinuation { continuation in
            queue.async {
                self.inboundBuffer.removeAll(keepingCapacity: false)
                continuation.resume(returning: ())
            }
        }
    }

    private func isOpen() async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.isConnected)
            }
        }
    }
}

#if !targetEnvironment(simulator) && canImport(IOKit) && canImport(IOKit.serial) && canImport(IOKit.usb)
private func registryProperty(
    _ service: io_registry_entry_t,
    key: String
) -> AnyObject? {
    IORegistryEntrySearchCFProperty(
        service,
        kIOServicePlane,
        key as CFString,
        kCFAllocatorDefault,
        IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
    )?.takeRetainedValue()
}

private func registryString(
    _ service: io_registry_entry_t,
    key: String
) -> String? {
    registryProperty(service, key: key) as? String
}

private func registryNumber(
    _ service: io_registry_entry_t,
    key: String
) -> Int? {
    (registryProperty(service, key: key) as? NSNumber)?.intValue
}
#endif
