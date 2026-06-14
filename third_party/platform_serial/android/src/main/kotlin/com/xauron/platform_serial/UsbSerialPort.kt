package com.xauron.platform_serial

import android.hardware.usb.UsbDeviceConnection
import com.hoho.android.usbserial.driver.UsbSerialPort as AndroidUsbSerialPort
import com.hoho.android.usbserial.driver.UsbSerialPort.FlowControl as UsbFlowControl

/**
 * Wrapper around the third-party USB serial port implementation.
 *
 * Keeping all direct driver calls in one place reduces name clashes with the plugin
 * classes and centralizes the contract expected by [SerialPort].
 */
internal class UsbSerialPort(
    private val delegate: AndroidUsbSerialPort,
) {
    val portNumber: Int
        get() = delegate.portNumber

    fun open(connection: UsbDeviceConnection) {
        delegate.open(connection)
    }

    fun close() {
        delegate.close()
    }

    fun setParameters(baudRate: Int, dataBits: Int, stopBits: Int, parity: Int) {
        delegate.setParameters(baudRate, dataBits, stopBits, parity)
    }

    fun setFlowControl(flowControl: UsbFlowControl) {
        delegate.setFlowControl(flowControl)
    }

    fun read(buffer: ByteArray, timeoutMillis: Int): Int =
        delegate.read(buffer, timeoutMillis)

    fun write(buffer: ByteArray, timeoutMillis: Int): Int {
        delegate.write(buffer, timeoutMillis)
        return buffer.size
    }

    fun purgeHwBuffers(purgeWriteBuffers: Boolean, purgeReadBuffers: Boolean) {
        delegate.purgeHwBuffers(purgeWriteBuffers, purgeReadBuffers)
    }
}
