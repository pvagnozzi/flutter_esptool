import Flutter
import Foundation

/// iOS entry point for the platform_serial plugin.
///
/// The plugin exposes a method channel for request/response operations and an
/// event channel for asynchronous data/error notifications emitted by open
/// serial ports.
public final class FlutterSerialPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private static let methodChannelName = "dev.flutter/platform_serial/ios"
    private static let eventChannelName = "dev.flutter/platform_serial/ios/events"

    private let serialPortManager = SerialPortManager()
    private let eventQueue = DispatchQueue(
        label: "dev.flutter.platform_serial.ios.events",
        qos: .userInitiated
    )

    private var eventSink: FlutterEventSink?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let plugin = FlutterSerialPlugin()
        let messenger = registrar.messenger()

        let methodChannel = FlutterMethodChannel(
            name: Self.methodChannelName,
            binaryMessenger: messenger
        )
        registrar.addMethodCallDelegate(plugin, channel: methodChannel)

        let eventChannel = FlutterEventChannel(
            name: Self.eventChannelName,
            binaryMessenger: messenger
        )
        eventChannel.setStreamHandler(plugin)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getAvailablePorts":
            Task {
                await respond(result) {
                    try await self.serialPortManager
                        .availablePorts()
                        .map(\.asDictionary)
                }
            }
        case "openPort":
            guard let arguments = call.arguments as? [String: Any] else {
                result(Self.flutterError(from: SerialPortError.invalidArguments(
                    "openPort requires a configuration dictionary."
                )))
                return
            }

            Task {
                await respond(result) {
                    let configuration = try SerialPortConfiguration(arguments: arguments)
                    try await self.serialPortManager.openPort(
                        configuration: configuration,
                        eventHandler: { [weak self] event in
                            self?.publish(event: event)
                        }
                    )
                    return nil
                }
            }
        case "closePort":
            guard let portName = Self.stringArgument("portName", from: call.arguments) else {
                result(Self.flutterError(from: SerialPortError.invalidArguments(
                    "closePort requires a non-empty portName."
                )))
                return
            }

            Task {
                await respond(result) {
                    try await self.serialPortManager.closePort(named: portName)
                    return nil
                }
            }
        case "readData":
            guard
                let arguments = call.arguments as? [String: Any],
                let portName = arguments["portName"] as? String,
                let length = arguments["length"] as? Int
            else {
                result(Self.flutterError(from: SerialPortError.invalidArguments(
                    "readData requires portName and length."
                )))
                return
            }

            Task {
                await respond(result) {
                    let timeout = arguments["timeout"] as? Int
                    let data = try await self.serialPortManager.readData(
                        from: portName,
                        length: length,
                        timeoutMs: timeout
                    )
                    return FlutterStandardTypedData(bytes: data)
                }
            }
        case "writeData":
            guard
                let arguments = call.arguments as? [String: Any],
                let portName = arguments["portName"] as? String
            else {
                result(Self.flutterError(from: SerialPortError.invalidArguments(
                    "writeData requires portName and data."
                )))
                return
            }

            guard let payload = Self.dataArgument("data", from: arguments) else {
                result(Self.flutterError(from: SerialPortError.invalidArguments(
                    "writeData requires a Uint8List-compatible data payload."
                )))
                return
            }

            Task {
                await respond(result) {
                    let timeout = arguments["timeout"] as? Int
                    return try await self.serialPortManager.writeData(
                        to: portName,
                        data: payload,
                        timeoutMs: timeout
                    )
                }
            }
        case "bytesAvailable":
            guard let portName = Self.stringArgument("portName", from: call.arguments) else {
                result(Self.flutterError(from: SerialPortError.invalidArguments(
                    "bytesAvailable requires a non-empty portName."
                )))
                return
            }

            Task {
                await respond(result) {
                    try await self.serialPortManager.bytesAvailable(on: portName)
                }
            }
        case "resetBuffers":
            guard let portName = Self.stringArgument("portName", from: call.arguments) else {
                result(Self.flutterError(from: SerialPortError.invalidArguments(
                    "resetBuffers requires a non-empty portName."
                )))
                return
            }

            Task {
                await respond(result) {
                    try await self.serialPortManager.resetBuffers(on: portName)
                    return nil
                }
            }
        case "flush":
            guard let portName = Self.stringArgument("portName", from: call.arguments) else {
                result(Self.flutterError(from: SerialPortError.invalidArguments(
                    "flush requires a non-empty portName."
                )))
                return
            }

            Task {
                await respond(result) {
                    try await self.serialPortManager.flush(portName: portName)
                    return nil
                }
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    public func onListen(
        withArguments arguments: Any?,
        eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        eventQueue.async {
            self.eventSink = events
        }
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventQueue.async {
            self.eventSink = nil
        }
        return nil
    }

    private func publish(event: [String: Any]) {
        eventQueue.async {
            self.eventSink?(event)
        }
    }

    @MainActor
    private func respond(_ result: @escaping FlutterResult, operation: () async throws -> Any?) async {
        do {
            result(try await operation())
        } catch {
            result(Self.flutterError(from: error))
        }
    }

    private static func flutterError(from error: Error) -> FlutterError {
        guard let serialError = error as? SerialPortError else {
            return FlutterError(
                code: "unknown",
                message: error.localizedDescription,
                details: nil
            )
        }

        return FlutterError(
            code: serialError.code,
            message: serialError.localizedDescription,
            details: nil
        )
    }

    private static func stringArgument(_ key: String, from arguments: Any?) -> String? {
        guard
            let dictionary = arguments as? [String: Any],
            let value = dictionary[key] as? String,
            !value.isEmpty
        else {
            return nil
        }

        return value
    }

    private static func dataArgument(_ key: String, from arguments: [String: Any]) -> Data? {
        if let typedData = arguments[key] as? FlutterStandardTypedData {
            return typedData.data
        }

        if let bytes = arguments[key] as? [UInt8] {
            return Data(bytes)
        }

        if let bytes = arguments[key] as? [Int] {
            return Data(bytes.compactMap { UInt8(exactly: $0) })
        }

        return nil
    }
}
