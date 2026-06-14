package com.xauron.platform_serial

import android.hardware.usb.UsbDevice
import com.hoho.android.usbserial.driver.UsbSerialDriver as AndroidUsbSerialDriver

/**
 * Thin abstraction over the open-source usb-serial-for-android driver.
 *
 * The wrapper keeps the rest of the plugin decoupled from the third-party API and
 * makes it easier to add richer metadata and validation in one place.
 */
internal interface UsbSerialDriver {
    val device: UsbDevice
    val driverName: String
    val ports: List<UsbSerialPort>

    companion object {
        fun wrap(driver: AndroidUsbSerialDriver): UsbSerialDriver =
            WrappedUsbSerialDriver(driver)
    }
}

private class WrappedUsbSerialDriver(
    private val delegate: AndroidUsbSerialDriver,
) : UsbSerialDriver {
    override val device: UsbDevice
        get() = delegate.device

    override val driverName: String
        get() = delegate.javaClass.simpleName.removeSuffix("SerialDriver")

    override val ports: List<UsbSerialPort>
        get() = delegate.ports.map(::UsbSerialPort)
}
