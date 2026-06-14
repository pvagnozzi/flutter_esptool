package com.xauron.platform_serial

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import com.hoho.android.usbserial.driver.UsbSerialProber
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap

/**
 * Exception type surfaced to the Flutter layer.
 *
 * The [code] is used directly as a [io.flutter.plugin.common.MethodChannel.Result.error]
 * code so Dart receives stable, machine-readable failures.
 */
internal class SerialPortException(
    val code: String,
    override val message: String,
    cause: Throwable? = null,
) : Exception(message, cause)

internal data class PortDescriptor(
    val portName: String,
    val device: UsbDevice,
    val driver: UsbSerialDriver,
    val port: UsbSerialPort,
)

/**
 * Thread-safe central manager for all opened Android serial ports.
 *
 * The manager is responsible for device discovery, permission negotiation and lifecycle
 * coordination for multiple concurrently opened ports.
 */
internal class SerialPortManager(
    private val context: Context,
    private val onEvent: (Map<String, Any?>) -> Unit,
) {
    private val usbManager = context.getSystemService(Context.USB_SERVICE) as UsbManager
    private val openPorts = ConcurrentHashMap<String, SerialPort>()
    private val permissionRequests = ConcurrentHashMap<Int, CompletableDeferred<Boolean>>()
    private val openPortsMutex = Mutex()

    suspend fun getAvailablePorts(): List<Map<String, Any?>> = withContext(Dispatchers.IO) {
        probeDescriptors().map { descriptor ->
            mapOf(
                "portName" to descriptor.portName,
                "description" to buildDescription(descriptor),
                "vendorId" to hexId(descriptor.device.vendorId),
                "productId" to hexId(descriptor.device.productId),
                "serialNumber" to safeSerialNumber(descriptor.device),
                "isOpen" to openPorts.containsKey(descriptor.portName),
                "platform" to "android",
            )
        }
    }

    suspend fun openPort(
        portName: String,
        baudRate: Int,
        dataBits: Int,
        stopBits: Int,
        parity: Int,
        flowControl: Int,
        readTimeout: Int,
        writeTimeout: Int,
    ) = withContext(Dispatchers.IO) {
        openPortsMutex.withLock {
            if (openPorts.containsKey(portName)) {
                throw SerialPortException(
                    code = "PORT_ALREADY_OPEN",
                    message = "The serial port '$portName' is already open.",
                )
            }
        }

        val descriptor = resolveDescriptor(portName)
        ensurePermission(descriptor.device)

        val serialPort = SerialPort(
            usbManager = usbManager,
            descriptor = descriptor,
            onEvent = onEvent,
        )

        try {
            serialPort.open(
                baudRate = baudRate,
                dataBits = dataBits,
                stopBits = stopBits,
                parity = parity,
                flowControl = flowControl,
                readTimeout = readTimeout,
                writeTimeout = writeTimeout,
            )
        } catch (throwable: Throwable) {
            runCatching { serialPort.close() }
            throw throwable
        }

        openPortsMutex.withLock {
            openPorts[portName] = serialPort
        }

        onEvent(
            mapOf(
                "type" to "portOpened",
                "portName" to portName,
                "deviceId" to descriptor.device.deviceId,
            ),
        )
    }

    suspend fun closePort(portName: String) = withContext(Dispatchers.IO) {
        val port = openPortsMutex.withLock {
            openPorts.remove(portName)
        } ?: throw SerialPortException(
            code = "PORT_NOT_FOUND",
            message = "No open serial port named '$portName' was found.",
        )

        port.close()

        onEvent(
            mapOf(
                "type" to "portClosed",
                "portName" to portName,
                "deviceId" to port.device.deviceId,
            ),
        )
    }

    suspend fun readData(portName: String, length: Int): ByteArray =
        requireOpenPort(portName).read(length)

    suspend fun writeData(portName: String, data: ByteArray): Int =
        requireOpenPort(portName).write(data)

    suspend fun bytesAvailable(portName: String): Int =
        requireOpenPort(portName).bytesAvailable()

    suspend fun resetBuffers(portName: String) =
        requireOpenPort(portName).resetBuffers()

    suspend fun flush(portName: String) =
        requireOpenPort(portName).flush()

    suspend fun closePortsForDevice(device: UsbDevice) = withContext(Dispatchers.IO) {
        val portsToClose = openPorts.entries
            .filter { (_, port) -> port.device.deviceId == device.deviceId }
            .map { it.key to it.value }

        portsToClose.forEach { (portName, port) ->
            openPorts.remove(portName)
            runCatching { port.close() }
            onEvent(
                mapOf(
                    "type" to "deviceDetached",
                    "portName" to portName,
                    "deviceId" to device.deviceId,
                    "vendorId" to hexId(device.vendorId),
                    "productId" to hexId(device.productId),
                ),
            )
        }
    }

    suspend fun closeAll() = withContext(Dispatchers.IO) {
        val portsToClose = openPortsMutex.withLock {
            val snapshot = openPorts.values.toList()
            openPorts.clear()
            snapshot
        }
        portsToClose.forEach { runCatching { it.close() } }
    }

    fun closeAllBlocking() {
        runBlocking {
            closeAll()
        }
    }

    fun handlePermissionResult(device: UsbDevice?, granted: Boolean) {
        if (device == null) {
            return
        }
        permissionRequests.remove(device.deviceId)?.complete(granted)
    }

    fun buildDeviceEvent(type: String, device: UsbDevice?): Map<String, Any?> = mapOf(
        "type" to type,
        "deviceId" to device?.deviceId,
        "deviceName" to device?.deviceName,
        "vendorId" to device?.vendorId?.let(::hexId),
        "productId" to device?.productId?.let(::hexId),
        "manufacturerName" to device?.manufacturerName,
        "productName" to device?.productName,
    )

    private suspend fun requireOpenPort(portName: String): SerialPort =
        openPortsMutex.withLock {
            openPorts[portName]
        } ?: throw SerialPortException(
            code = "PORT_NOT_FOUND",
            message = "No open serial port named '$portName' was found.",
        )

    private suspend fun resolveDescriptor(portName: String): PortDescriptor =
        probeDescriptors().firstOrNull { it.portName == portName }
            ?: throw SerialPortException(
                code = "PORT_NOT_FOUND",
                message = "Serial port '$portName' is not currently attached.",
            )

    private suspend fun probeDescriptors(): List<PortDescriptor> = withContext(Dispatchers.IO) {
        UsbSerialProber.getDefaultProber()
            .findAllDrivers(usbManager)
            .flatMap { driver ->
                val wrappedDriver = UsbSerialDriver.wrap(driver)
                wrappedDriver.ports.map { port ->
                    PortDescriptor(
                        portName = createPortName(wrappedDriver.device, port.portNumber),
                        device = wrappedDriver.device,
                        driver = wrappedDriver,
                        port = port,
                    )
                }
            }
            .sortedBy { it.portName }
    }

    private suspend fun ensurePermission(device: UsbDevice) {
        if (usbManager.hasPermission(device)) {
            return
        }

        val deferred = CompletableDeferred<Boolean>()
        val pendingResult = permissionRequests.putIfAbsent(device.deviceId, deferred) ?: deferred.also {
            usbManager.requestPermission(device, createPermissionIntent(device))
        }

        val granted = pendingResult.await()
        if (!granted || !usbManager.hasPermission(device)) {
            throw SerialPortException(
                code = "USB_PERMISSION_DENIED",
                message = "USB permission was denied for device '${device.deviceName}'.",
            )
        }

        permissionRequests.remove(device.deviceId, pendingResult)
    }

    private fun createPermissionIntent(device: UsbDevice): PendingIntent {
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val intent = Intent(FlutterSerialPlugin.ACTION_USB_PERMISSION).setPackage(context.packageName)
        return PendingIntent.getBroadcast(context, device.deviceId, intent, flags)
    }

    private fun createPortName(device: UsbDevice, portNumber: Int): String =
        "usb:${device.deviceId}:$portNumber"

    private fun buildDescription(descriptor: PortDescriptor): String {
        val device = descriptor.device
        val productName = device.productName?.takeIf { it.isNotBlank() }
        val manufacturerName = device.manufacturerName?.takeIf { it.isNotBlank() }
        val vendorProduct = "VID:${hexId(device.vendorId)} PID:${hexId(device.productId)}"
        return listOfNotNull(
            descriptor.driver.driverName,
            manufacturerName,
            productName,
            vendorProduct,
        ).joinToString(" • ")
    }

    private fun safeSerialNumber(device: UsbDevice): String? = try {
        if (usbManager.hasPermission(device)) {
            device.serialNumber
        } else {
            null
        }
    } catch (_: SecurityException) {
        null
    }

    private fun hexId(value: Int): String =
        String.format(Locale.US, "%04X", value)
}
