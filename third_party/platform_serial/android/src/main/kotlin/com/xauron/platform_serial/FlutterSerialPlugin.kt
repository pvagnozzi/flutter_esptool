package com.xauron.platform_serial

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * Main Android entry point for the platform_serial plugin.
 *
 * The plugin exposes a single [MethodChannel] for imperative operations and a broadcast
 * [EventChannel] for device attach/detach, permission and incoming serial data events.
 */
class FlutterSerialPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler, ActivityAware {
    private lateinit var applicationContext: Context
    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private lateinit var serialPortManager: SerialPortManager

    private val mainHandler = Handler(Looper.getMainLooper())
    private val pluginScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    private var activity: Activity? = null
    private var usbReceiver: BroadcastReceiver? = null
    private var eventSink: EventChannel.EventSink? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        serialPortManager = SerialPortManager(applicationContext, ::emitEvent)
        setUpChannels(binding.binaryMessenger)
        registerUsbReceiver()
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        usbReceiver?.let { receiver ->
            runCatching { applicationContext.unregisterReceiver(receiver) }
        }
        usbReceiver = null
        eventSink = null
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        serialPortManager.closeAllBlocking()
        pluginScope.cancel()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getAvailablePorts" -> launchResult(result) {
                serialPortManager.getAvailablePorts()
            }

            "openPort" -> launchResult(result) {
                serialPortManager.openPort(
                    portName = call.requiredString("portName"),
                    baudRate = call.requiredInt("baudRate"),
                    dataBits = call.requiredInt("dataBits"),
                    stopBits = call.requiredInt("stopBits"),
                    parity = call.requiredInt("parity"),
                    flowControl = call.requiredInt("flowControl"),
                    readTimeout = call.requiredInt("readTimeout"),
                    writeTimeout = call.requiredInt("writeTimeout"),
                )
                null
            }

            "closePort" -> launchResult(result) {
                serialPortManager.closePort(call.requiredString("portName"))
                null
            }

            "readData" -> launchResult(result) {
                serialPortManager.readData(
                    portName = call.requiredString("portName"),
                    length = call.requiredInt("length"),
                )
            }

            "writeData" -> launchResult(result) {
                serialPortManager.writeData(
                    portName = call.requiredString("portName"),
                    data = call.requiredBytes("data"),
                )
            }

            "bytesAvailable" -> launchResult(result) {
                serialPortManager.bytesAvailable(call.requiredString("portName"))
            }

            "resetBuffers" -> launchResult(result) {
                serialPortManager.resetBuffers(call.requiredString("portName"))
                null
            }

            "flush" -> launchResult(result) {
                serialPortManager.flush(call.requiredString("portName"))
                null
            }

            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    private fun setUpChannels(binaryMessenger: BinaryMessenger) {
        methodChannel = MethodChannel(binaryMessenger, METHOD_CHANNEL_NAME)
        eventChannel = EventChannel(binaryMessenger, EVENT_CHANNEL_NAME)
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
    }

    private fun launchResult(result: MethodChannel.Result, block: suspend () -> Any?) {
        pluginScope.launch {
            try {
                result.success(block())
            } catch (cancellation: CancellationException) {
                result.error("CANCELLED", cancellation.message ?: "Operation cancelled.", null)
            } catch (throwable: Throwable) {
                val serialException = throwable as? SerialPortException
                result.error(
                    serialException?.code ?: "UNKNOWN",
                    serialException?.message ?: (throwable.message ?: throwable.javaClass.simpleName),
                    null,
                )
            }
        }
    }

    private fun registerUsbReceiver() {
        if (usbReceiver != null) {
            return
        }

        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                val usbDevice = intent.usbDevice()
                when (intent.action) {
                    ACTION_USB_PERMISSION -> {
                        val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
                        serialPortManager.handlePermissionResult(usbDevice, granted)
                        emitEvent(
                            serialPortManager.buildDeviceEvent(
                                type = "usbPermission",
                                device = usbDevice,
                            ) + ("granted" to granted),
                        )
                    }

                    UsbManager.ACTION_USB_DEVICE_ATTACHED -> {
                        emitEvent(serialPortManager.buildDeviceEvent("deviceAttached", usbDevice))
                    }

                    UsbManager.ACTION_USB_DEVICE_DETACHED -> {
                        pluginScope.launch {
                            serialPortManager.closePortsForDevice(usbDevice ?: return@launch)
                        }
                        emitEvent(serialPortManager.buildDeviceEvent("deviceDetached", usbDevice))
                    }
                }
            }
        }

        val filter = IntentFilter().apply {
            addAction(ACTION_USB_PERMISSION)
            addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED)
            addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            applicationContext.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            applicationContext.registerReceiver(receiver, filter)
        }

        usbReceiver = receiver
    }

    private fun emitEvent(event: Map<String, Any?>) {
        mainHandler.post {
            eventSink?.success(event)
        }
    }

    private fun Intent.usbDevice(): UsbDevice? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            getParcelableExtra(UsbManager.EXTRA_DEVICE, UsbDevice::class.java)
        } else {
            @Suppress("DEPRECATION")
            getParcelableExtra(UsbManager.EXTRA_DEVICE)
        }

    private fun MethodCall.requiredString(key: String): String =
        argument<String>(key)?.takeIf { it.isNotBlank() }
            ?: throw SerialPortException(
                code = "INVALID_ARGUMENT",
                message = "Missing required String argument '$key'.",
            )

    private fun MethodCall.requiredInt(key: String): Int =
        argument<Int>(key)
            ?: throw SerialPortException(
                code = "INVALID_ARGUMENT",
                message = "Missing required Int argument '$key'.",
            )

    private fun MethodCall.requiredBytes(key: String): ByteArray =
        when (val value = (arguments as? Map<*, *>)?.get(key)) {
            is ByteArray -> value
            is List<*> -> value.map {
                (it as? Number)?.toByte()
                    ?: throw SerialPortException(
                        code = "INVALID_ARGUMENT",
                        message = "Argument '$key' contains a non-numeric value.",
                    )
            }.toByteArray()

            else -> throw SerialPortException(
                code = "INVALID_ARGUMENT",
                message = "Missing required byte array argument '$key'.",
            )
        }

    companion object {
        internal const val ACTION_USB_PERMISSION = "com.example.platform_serial.USB_PERMISSION"

        private const val METHOD_CHANNEL_NAME = "dev.flutter/platform_serial"
        private const val EVENT_CHANNEL_NAME = "dev.flutter/platform_serial_events"
    }
}
