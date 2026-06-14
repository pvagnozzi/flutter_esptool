import Foundation

/// Strongly typed error values returned by the iOS serial implementation.
enum SerialPortError: LocalizedError {
    case invalidArguments(String)
    case portAlreadyOpen(String)
    case portClosed(String)
    case portNotFound(String)
    case configuration(String)
    case timeout(String)
    case io(String)
    case permissionDenied(String)
    case unsupported(String)

    var code: String {
        switch self {
        case .invalidArguments:
            return "invalidArguments"
        case .portAlreadyOpen:
            return "portAlreadyOpen"
        case .portClosed:
            return "portClosed"
        case .portNotFound:
            return "portNotFound"
        case .configuration:
            return "configurationError"
        case .timeout:
            return "timeout"
        case .io:
            return "ioError"
        case .permissionDenied:
            return "permissionDenied"
        case .unsupported:
            return "unsupported"
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidArguments(let message),
                .portAlreadyOpen(let message),
                .portClosed(let message),
                .portNotFound(let message),
                .configuration(let message),
                .timeout(let message),
                .io(let message),
                .permissionDenied(let message),
                .unsupported(let message):
            return message
        }
    }
}

/// Archived representation of a serial-port configuration.
///
/// The Flutter method call arguments are normalized into this secure-coded type
/// so native operations can safely cache and reuse the configuration.
@objcMembers
final class SerialPortConfiguration: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool = true

    let portName: String
    let baudRate: Int
    let dataBits: Int
    let stopBits: Int
    let parity: Int
    let flowControl: Int
    let readTimeoutMs: Int
    let writeTimeoutMs: Int

    init(
        portName: String,
        baudRate: Int,
        dataBits: Int,
        stopBits: Int,
        parity: Int,
        flowControl: Int,
        readTimeoutMs: Int,
        writeTimeoutMs: Int
    ) throws {
        self.portName = portName
        self.baudRate = baudRate
        self.dataBits = dataBits
        self.stopBits = stopBits
        self.parity = parity
        self.flowControl = flowControl
        self.readTimeoutMs = readTimeoutMs
        self.writeTimeoutMs = writeTimeoutMs
        super.init()
        try validate()
    }

    convenience init(arguments: [String: Any]) throws {
        guard let portName = arguments["portName"] as? String, !portName.isEmpty else {
            throw SerialPortError.invalidArguments("portName must be a non-empty string.")
        }

        let baudRate = arguments["baudRate"] as? Int ?? 9600
        let dataBits = arguments["dataBits"] as? Int ?? 8
        let stopBits = arguments["stopBits"] as? Int ?? 0
        let parity = arguments["parity"] as? Int ?? 0
        let flowControl = arguments["flowControl"] as? Int ?? 0
        let readTimeoutMs = arguments["readTimeout"] as? Int ?? 5_000
        let writeTimeoutMs = arguments["writeTimeout"] as? Int ?? 5_000

        try self.init(
            portName: portName,
            baudRate: baudRate,
            dataBits: dataBits,
            stopBits: stopBits,
            parity: parity,
            flowControl: flowControl,
            readTimeoutMs: readTimeoutMs,
            writeTimeoutMs: writeTimeoutMs
        )
    }

    required init?(coder: NSCoder) {
        guard let portName = coder.decodeObject(of: NSString.self, forKey: "portName") as String? else {
            return nil
        }

        self.portName = portName
        self.baudRate = coder.decodeInteger(forKey: "baudRate")
        self.dataBits = coder.decodeInteger(forKey: "dataBits")
        self.stopBits = coder.decodeInteger(forKey: "stopBits")
        self.parity = coder.decodeInteger(forKey: "parity")
        self.flowControl = coder.decodeInteger(forKey: "flowControl")
        self.readTimeoutMs = coder.decodeInteger(forKey: "readTimeoutMs")
        self.writeTimeoutMs = coder.decodeInteger(forKey: "writeTimeoutMs")
        super.init()
    }

    func encode(with coder: NSCoder) {
        coder.encode(portName, forKey: "portName")
        coder.encode(baudRate, forKey: "baudRate")
        coder.encode(dataBits, forKey: "dataBits")
        coder.encode(stopBits, forKey: "stopBits")
        coder.encode(parity, forKey: "parity")
        coder.encode(flowControl, forKey: "flowControl")
        coder.encode(readTimeoutMs, forKey: "readTimeoutMs")
        coder.encode(writeTimeoutMs, forKey: "writeTimeoutMs")
    }

    func validate() throws {
        guard baudRate > 0 else {
            throw SerialPortError.configuration("baudRate must be greater than zero.")
        }

        guard (5...8).contains(dataBits) else {
            throw SerialPortError.configuration("dataBits must be between 5 and 8.")
        }

        guard (0...2).contains(stopBits) else {
            throw SerialPortError.configuration("stopBits must be 0, 1, or 2.")
        }

        guard (0...4).contains(parity) else {
            throw SerialPortError.configuration("parity must be between 0 and 4.")
        }

        guard (0...2).contains(flowControl) else {
            throw SerialPortError.configuration("flowControl must be between 0 and 2.")
        }

        guard readTimeoutMs >= 0, writeTimeoutMs >= 0 else {
            throw SerialPortError.configuration("Timeout values must be zero or greater.")
        }
    }
}

/// High-level serial-port abstraction used by the plugin.
///
/// A port owns exactly one transport driver and serializes lifecycle changes so
/// open/read/write/close remain deterministic even when invoked from different
/// Flutter isolates or callback queues.
final class SerialPort {
    private let stateQueue = DispatchQueue(
        label: "dev.flutter.platform_serial.ios.port.state",
        qos: .userInitiated
    )

    let descriptor: SerialPortDescriptor
    let configuration: SerialPortConfiguration
    private let driver: UsbSerialDriving

    private var isOpen = false
    private var eventHandler: (([String: Any]) -> Void)?

    init(
        descriptor: SerialPortDescriptor,
        configuration: SerialPortConfiguration,
        driver: UsbSerialDriving
    ) {
        self.descriptor = descriptor
        self.configuration = configuration
        self.driver = driver
    }

    deinit {
        Task {
            try? await close()
        }
    }

    func setEventHandler(_ handler: @escaping ([String: Any]) -> Void) {
        stateQueue.sync {
            eventHandler = handler
        }
    }

    func open() async throws {
        if stateQueue.sync(execute: { isOpen }) {
            throw SerialPortError.portAlreadyOpen(
                "The serial port \(configuration.portName) is already open."
            )
        }

        driver.onData = { [weak self] data in
            self?.emitData(data)
        }
        driver.onError = { [weak self] error in
            self?.emitError(error)
        }

        try await driver.connect(using: configuration)
        stateQueue.sync {
            isOpen = true
            descriptor.isOpen = true
        }
    }

    func close() async throws {
        let wasOpen = stateQueue.sync { () -> Bool in
            let current = isOpen
            isOpen = false
            descriptor.isOpen = false
            return current
        }

        if !wasOpen {
            return
        }

        await driver.disconnect()
    }

    func read(length: Int, timeoutMs: Int?) async throws -> Data {
        try ensureOpen()
        return try await driver.read(
            maximumLength: max(length, 0),
            timeoutMs: timeoutMs ?? configuration.readTimeoutMs
        )
    }

    func write(data: Data, timeoutMs: Int?) async throws -> Int {
        try ensureOpen()
        return try await driver.write(
            data,
            timeoutMs: timeoutMs ?? configuration.writeTimeoutMs
        )
    }

    func bytesAvailable() async throws -> Int {
        try ensureOpen()
        return await driver.bytesAvailable()
    }

    func flush() async throws {
        try ensureOpen()
        try await driver.flush()
    }

    func resetBuffers() async throws {
        try ensureOpen()
        try await driver.resetBuffers()
    }

    private func ensureOpen() throws {
        if !stateQueue.sync(execute: { isOpen }) {
            throw SerialPortError.portClosed(
                "The serial port \(configuration.portName) is not open."
            )
        }
    }

    private func emitData(_ data: Data) {
        let handler = stateQueue.sync { eventHandler }
        handler?([
            "type": "data",
            "portName": configuration.portName,
            "data": Array(data)
        ])
    }

    private func emitError(_ error: Error) {
        let handler = stateQueue.sync { eventHandler }
        handler?([
            "type": "error",
            "portName": configuration.portName,
            "message": error.localizedDescription
        ])
    }
}
