package com.xauron.platform_serial

import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbManager
import com.hoho.android.usbserial.driver.UsbSerialPort as AndroidUsbSerialPort
import com.hoho.android.usbserial.driver.UsbSerialPort.FlowControl as AndroidFlowControl
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlin.math.min

/**
 * Represents a single opened Android USB serial port.
 *
 * Reads are performed by a dedicated coroutine which continuously copies bytes from the
 * USB driver into an internal buffer. Synchronous Flutter read requests consume from that
 * buffer, while data is also forwarded to the event channel for streaming scenarios.
 */
internal class SerialPort(
    private val usbManager: UsbManager,
    private val descriptor: PortDescriptor,
    private val onEvent: (Map<String, Any?>) -> Unit,
) {
    private val lifecycleMutex = Mutex()
    private val ioMutex = Mutex()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val bufferLock = Object()
    private val pendingBytes = ArrayDeque<Byte>()

    @Volatile
    private var connection: UsbDeviceConnection? = null

    @Volatile
    private var opened = false

    @Volatile
    private var readTimeoutMillis: Int = 5_000

    @Volatile
    private var writeTimeoutMillis: Int = 5_000

    private var readLoopJob: Job? = null

    val portName: String
        get() = descriptor.portName

    val device: UsbDevice
        get() = descriptor.device

    suspend fun open(
        baudRate: Int,
        dataBits: Int,
        stopBits: Int,
        parity: Int,
        flowControl: Int,
        readTimeout: Int,
        writeTimeout: Int,
    ) = lifecycleMutex.withLock {
        if (opened) {
            throw SerialPortException(
                code = "PORT_ALREADY_OPEN",
                message = "The serial port '$portName' is already open.",
            )
        }

        val deviceConnection = usbManager.openDevice(device)
            ?: throw SerialPortException(
                code = "OPEN_FAILED",
                message = "Android could not open USB device '${device.deviceName}'. " +
                    "Verify that OTG is enabled and USB permission was granted.",
            )

        try {
            descriptor.port.open(deviceConnection)
            descriptor.port.setParameters(
                baudRate = baudRate,
                dataBits = validateDataBits(dataBits),
                stopBits = mapStopBits(stopBits),
                parity = mapParity(parity),
            )
            descriptor.port.setFlowControl(mapFlowControl(flowControl))
        } catch (throwable: Throwable) {
            runCatching { descriptor.port.close() }
            runCatching { deviceConnection.close() }
            throw SerialPortException(
                code = "CONFIGURATION_FAILED",
                message = "Failed to configure serial port '$portName': ${throwable.message ?: throwable.javaClass.simpleName}",
                cause = throwable,
            )
        }

        synchronized(bufferLock) {
            pendingBytes.clear()
            bufferLock.notifyAll()
        }

        connection = deviceConnection
        opened = true
        readTimeoutMillis = readTimeout.coerceAtLeast(0)
        writeTimeoutMillis = writeTimeout.coerceAtLeast(0)
        startReadLoop()
    }

    suspend fun close() {
        closeInternal(waitForReadLoop = true)
    }

    suspend fun read(length: Int): ByteArray = withContext(Dispatchers.IO) {
        ensureReadableLength(length)
        waitForIncomingBytes(length)
    }

    suspend fun write(data: ByteArray): Int = withContext(Dispatchers.IO) {
        ensureOpen()
        ioMutex.withLock {
            try {
                descriptor.port.write(data, writeTimeoutMillis)
            } catch (throwable: Throwable) {
                throw SerialPortException(
                    code = "WRITE_FAILED",
                    message = "Failed to write ${data.size} byte(s) to '$portName': ${throwable.message ?: throwable.javaClass.simpleName}",
                    cause = throwable,
                )
            }
        }
    }

    suspend fun bytesAvailable(): Int = withContext(Dispatchers.IO) {
        synchronized(bufferLock) {
            pendingBytes.size
        }
    }

    suspend fun flush() = withContext(Dispatchers.IO) {
        ensureOpen()
        ioMutex.withLock {
            try {
                descriptor.port.purgeHwBuffers(purgeWriteBuffers = true, purgeReadBuffers = false)
            } catch (throwable: Throwable) {
                throw SerialPortException(
                    code = "FLUSH_FAILED",
                    message = "Failed to flush the write buffer for '$portName': ${throwable.message ?: throwable.javaClass.simpleName}",
                    cause = throwable,
                )
            }
        }
    }

    suspend fun resetBuffers() = withContext(Dispatchers.IO) {
        ensureOpen()
        synchronized(bufferLock) {
            pendingBytes.clear()
            bufferLock.notifyAll()
        }

        ioMutex.withLock {
            try {
                descriptor.port.purgeHwBuffers(purgeWriteBuffers = true, purgeReadBuffers = true)
            } catch (throwable: Throwable) {
                throw SerialPortException(
                    code = "RESET_FAILED",
                    message = "Failed to reset the hardware buffers for '$portName': ${throwable.message ?: throwable.javaClass.simpleName}",
                    cause = throwable,
                )
            }
        }
    }

    private fun startReadLoop() {
        readLoopJob = scope.launch {
            val scratchBuffer = ByteArray(DEFAULT_READ_CHUNK_SIZE)
            while (isActive && opened) {
                val bytesRead = try {
                    ioMutex.withLock {
                        descriptor.port.read(scratchBuffer, pollTimeoutMillis())
                    }
                } catch (throwable: Throwable) {
                    if (opened) {
                        emitError(
                            code = "READ_LOOP_FAILED",
                            message = "Read loop for '$portName' stopped: ${throwable.message ?: throwable.javaClass.simpleName}",
                        )
                        closeInternal(waitForReadLoop = false)
                    }
                    break
                }

                if (bytesRead <= 0) {
                    continue
                }

                val payload = scratchBuffer.copyOf(bytesRead)
                synchronized(bufferLock) {
                    payload.forEach(pendingBytes::addLast)
                    bufferLock.notifyAll()
                }

                onEvent(
                    mapOf(
                        "type" to "data",
                        "portName" to portName,
                        "data" to payload,
                        "byteCount" to bytesRead,
                    ),
                )
            }
        }
    }

    private suspend fun closeInternal(waitForReadLoop: Boolean) {
        lifecycleMutex.withLock {
            if (!opened && connection == null) {
                synchronized(bufferLock) {
                    pendingBytes.clear()
                    bufferLock.notifyAll()
                }
                return
            }

            opened = false
        }

        if (waitForReadLoop) {
            readLoopJob?.cancelAndJoin()
        } else {
            readLoopJob?.cancel()
        }
        readLoopJob = null

        ioMutex.withLock {
            runCatching { descriptor.port.close() }
            runCatching { connection?.close() }
            connection = null
        }

        synchronized(bufferLock) {
            pendingBytes.clear()
            bufferLock.notifyAll()
        }

        scope.cancel()
    }

    private fun waitForIncomingBytes(requestedLength: Int): ByteArray {
        val timeoutMillis = readTimeoutMillis.toLong()
        val deadline = if (timeoutMillis == 0L) null else System.currentTimeMillis() + timeoutMillis

        synchronized(bufferLock) {
            while (pendingBytes.isEmpty()) {
                if (!opened) {
                    throw SerialPortException(
                        code = "PORT_CLOSED",
                        message = "The serial port '$portName' is closed.",
                    )
                }

                val remaining = deadline?.minus(System.currentTimeMillis())
                if (remaining != null && remaining <= 0L) {
                    throw SerialPortException(
                        code = "READ_TIMEOUT",
                        message = "Timed out waiting for data from '$portName'.",
                    )
                }

                try {
                    if (remaining == null) {
                        bufferLock.wait()
                    } else {
                        bufferLock.wait(remaining)
                    }
                } catch (interrupted: InterruptedException) {
                    Thread.currentThread().interrupt()
                    throw CancellationException("Interrupted while waiting for serial data.")
                }
            }

            val bytesToRead = min(requestedLength, pendingBytes.size)
            val result = ByteArray(bytesToRead)
            repeat(bytesToRead) { index ->
                result[index] = pendingBytes.removeFirst()
            }
            return result
        }
    }

    private fun ensureOpen() {
        if (!opened) {
            throw SerialPortException(
                code = "PORT_CLOSED",
                message = "The serial port '$portName' is not open.",
            )
        }
    }

    private fun ensureReadableLength(length: Int) {
        if (length <= 0) {
            throw SerialPortException(
                code = "INVALID_ARGUMENT",
                message = "The requested read length must be greater than zero.",
            )
        }
    }

    private fun emitError(code: String, message: String) {
        onEvent(
            mapOf(
                "type" to "error",
                "portName" to portName,
                "code" to code,
                "message" to message,
            ),
        )
    }

    private fun validateDataBits(dataBits: Int): Int {
        if (dataBits !in 5..8) {
            throw SerialPortException(
                code = "INVALID_ARGUMENT",
                message = "Unsupported dataBits value $dataBits. Supported values are 5, 6, 7 and 8.",
            )
        }
        return dataBits
    }

    private fun mapStopBits(stopBits: Int): Int = when (stopBits) {
        0 -> AndroidUsbSerialPort.STOPBITS_1
        1 -> AndroidUsbSerialPort.STOPBITS_1_5
        2 -> AndroidUsbSerialPort.STOPBITS_2
        else -> throw SerialPortException(
            code = "INVALID_ARGUMENT",
            message = "Unsupported stopBits value $stopBits. Expected 0 (1), 1 (1.5) or 2 (2).",
        )
    }

    private fun mapParity(parity: Int): Int = when (parity) {
        0 -> AndroidUsbSerialPort.PARITY_NONE
        1 -> AndroidUsbSerialPort.PARITY_EVEN
        2 -> AndroidUsbSerialPort.PARITY_ODD
        3 -> AndroidUsbSerialPort.PARITY_MARK
        4 -> AndroidUsbSerialPort.PARITY_SPACE
        else -> throw SerialPortException(
            code = "INVALID_ARGUMENT",
            message = "Unsupported parity value $parity. Expected 0-4.",
        )
    }

    private fun mapFlowControl(flowControl: Int): AndroidFlowControl = when (flowControl) {
        0 -> AndroidFlowControl.NONE
        1 -> AndroidFlowControl.RTS_CTS
        2 -> AndroidFlowControl.XON_XOFF
        3 -> AndroidFlowControl.DTR_DSR
        else -> throw SerialPortException(
            code = "INVALID_ARGUMENT",
            message = "Unsupported flowControl value $flowControl. Expected 0 (none), 1 (RTS/CTS), 2 (XON/XOFF) or 3 (DTR/DSR).",
        )
    }

    private fun pollTimeoutMillis(): Int {
        if (readTimeoutMillis <= 0) {
            return 200
        }
        return readTimeoutMillis.coerceIn(minimumValue = 50, maximumValue = 250)
    }

    private companion object {
        const val DEFAULT_READ_CHUNK_SIZE = 4 * 1024
    }
}
