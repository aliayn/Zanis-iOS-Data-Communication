package com.example.zanis_ios_data_communication

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.*

import android.os.Build

import android.util.Log
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*

import java.util.concurrent.ConcurrentHashMap

class VendorUsbPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    companion object {
        private const val TAG = "VendorUsbPlugin"
        private const val CHANNEL_NAME = "com.zanis.vendor_usb"
        private const val EVENT_CHANNEL_NAME = "com.zanis.vendor_usb/events"
        private const val ACTION_USB_PERMISSION = "com.zanis.vendor_usb.USB_PERMISSION"
    }

    private lateinit var context: Context
    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var eventSink: EventChannel.EventSink? = null

    private var usbManager: UsbManager? = null
    private var currentDevice: UsbDevice? = null
    private var currentConnection: UsbDeviceConnection? = null
    private var currentInterface: UsbInterface? = null

    // Endpoint caching
    private var bulkInEndpoint: UsbEndpoint? = null
    private var bulkOutEndpoint: UsbEndpoint? = null
    private var interruptInEndpoint: UsbEndpoint? = null
    private var interruptOutEndpoint: UsbEndpoint? = null

    private val devicePermissions = ConcurrentHashMap<String, Boolean>()
    private val coroutineScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var readingJob: Job? = null
    private var pendingConnectionResult: MethodChannel.Result? = null
    private var isConnecting = false

    private val usbReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            try {
                when (intent.action) {
                    ACTION_USB_PERMISSION -> {
                        synchronized(this) {
                            val device: UsbDevice? =
                                intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
                            if (device != null) {
                                if (intent.getBooleanExtra(
                                        UsbManager.EXTRA_PERMISSION_GRANTED,
                                        false
                                    )
                                ) {
                                    devicePermissions[getDeviceKey(device)] = true
                                    log("USB permission granted for device: ${device.productName ?: "Unknown"}")
                                    connectToDeviceInternal(device)
                                } else {
                                    devicePermissions[getDeviceKey(device)] = false
                                    log("USB permission denied for device: ${device.productName ?: "Unknown"}")
                                    sendEvent("connection_status", false)
                                    pendingConnectionResult?.error(
                                        "PERMISSION_DENIED",
                                        "USB permission denied",
                                        null
                                    )
                                    pendingConnectionResult = null
                                    isConnecting = false
                                }
                            } else {
                                log("USB permission intent received with null device")
                            }
                        }
                    }

                    UsbManager.ACTION_USB_DEVICE_ATTACHED -> {
                        val device: UsbDevice? = intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
                        device?.let {
                            log("USB device attached: ${it.productName ?: "Unknown"}")
                            sendEvent("device_attached", createDeviceInfo(it))
                        } ?: log("USB device attached but device is null")
                    }

                    UsbManager.ACTION_USB_DEVICE_DETACHED -> {
                        val device: UsbDevice? = intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
                        device?.let {
                            log("USB device detached: ${it.productName ?: "Unknown"}")
                            if (it == currentDevice) {
                                log("Current device detached, disconnecting...")
                                disconnectDevice()
                            }
                            sendEvent("device_detached", createDeviceInfo(it))
                        } ?: log("USB device detached but device is null")
                    }

                }
            } catch (e: Exception) {
                log("Error in USB receiver: ${e.message}")
                // Don't crash the app, just log the error
            }
        }
    }

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        methodChannel = MethodChannel(flutterPluginBinding.binaryMessenger, CHANNEL_NAME)
        methodChannel.setMethodCallHandler(this)

        eventChannel = EventChannel(flutterPluginBinding.binaryMessenger, EVENT_CHANNEL_NAME)
        eventChannel.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        cleanup()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialize" -> {
                initialize()
                result.success(true)
            }

            "scanDevices" -> {
                if (usbManager == null) {
                    result.error("NOT_INITIALIZED", "USB manager not initialized", null)
                    return
                }
                result.success(scanDevices())
            }


            "requestPermission" -> {
                val deviceInfo = call.arguments as? Map<String, Any>
                if (deviceInfo != null) {
                    requestPermission(deviceInfo, result)
                } else {
                    result.error("INVALID_ARGUMENTS", "Device info required", null)
                }
            }

            "connectToDevice" -> {
                val deviceInfo = call.arguments as? Map<String, Any>
                if (deviceInfo != null) {
                    connectToDevice(deviceInfo, result)
                } else {
                    result.error("INVALID_ARGUMENTS", "Device info required", null)
                }
            }

            "disconnect" -> {
                disconnectDevice()
                result.success(true)
            }

            "sendBulkData" -> {
                val args = call.arguments as? Map<String, Any>
                val data = args?.get("data") as? ByteArray
                if (data != null) {
                    sendBulkData(data, result)
                } else {
                    result.error("INVALID_ARGUMENTS", "Data required", null)
                }
            }

            "bulkTransfer" -> {
                val args = call.arguments as? Map<String, Any>
                if (args != null) {
                    performBulkTransfer(args, result)
                } else {
                    result.error("INVALID_ARGUMENTS", "Transfer parameters required", null)
                }
            }

            "interruptTransfer" -> {
                val args = call.arguments as? Map<String, Any>
                if (args != null) {
                    performInterruptTransfer(args, result)
                } else {
                    result.error("INVALID_ARGUMENTS", "Transfer parameters required", null)
                }
            }

            else -> {
                result.notImplemented()
            }
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        log("Event channel listener attached")
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
        log("Event channel listener cancelled")
    }

    private fun initialize() {
        try {
            usbManager = context.getSystemService(Context.USB_SERVICE) as UsbManager

            // Register USB broadcast receiver
            val filter = IntentFilter().apply {
                addAction(ACTION_USB_PERMISSION)
                addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED)
                addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                context.registerReceiver(usbReceiver, filter, Context.RECEIVER_EXPORTED)
            } else {
                ContextCompat.registerReceiver(
                    context,
                    usbReceiver,
                    filter,
                    ContextCompat.RECEIVER_NOT_EXPORTED
                )
            }

            log("Vendor USB plugin initialized")
        } catch (e: Exception) {
            log("Error initializing USB: ${e.message}")
        }
    }

    private fun scanDevices(): List<Map<String, Any>> {
        val devices = mutableListOf<Map<String, Any>>()
        try {
            val deviceList = usbManager?.deviceList
            log("Total devices in system: ${deviceList?.size ?: 0}")

            deviceList?.values?.forEach { device ->
                log(
                    "Found device: VID=${device.vendorId} (0x${device.vendorId.toString(16)}), PID=${device.productId} (0x${
                        device.productId.toString(
                            16
                        )
                    }), Name=${device.productName}"
                )
                log("Device has permission: ${usbManager?.hasPermission(device)}")
                devices.add(createDeviceInfo(device))
            }
            log("Found ${devices.size} USB devices total")
        } catch (e: Exception) {
            log("Error scanning devices: ${e.message}")
        }
        return devices
    }


    private fun createDeviceInfo(device: UsbDevice): Map<String, Any> {
        return try {
            var totalEndpoints = 0
            var hasEndpoints = false
            var endpointDetails = mutableListOf<String>()

            // Properly scan all interfaces and endpoints
            try {
                for (i in 0 until device.interfaceCount) {
                    val usbInterface = device.getInterface(i)
                    val interfaceEndpoints = usbInterface.endpointCount
                    totalEndpoints += interfaceEndpoints

                    log("Interface $i: ${interfaceEndpoints} endpoints, class=${usbInterface.interfaceClass}")

                    // Log endpoint details for debugging
                    for (j in 0 until interfaceEndpoints) {
                        val endpoint = usbInterface.getEndpoint(j)
                        val direction =
                            if (endpoint.direction == UsbConstants.USB_DIR_IN) "IN" else "OUT"
                        val type = when (endpoint.type) {
                            UsbConstants.USB_ENDPOINT_XFER_BULK -> "BULK"
                            UsbConstants.USB_ENDPOINT_XFER_INT -> "INTERRUPT"
                            UsbConstants.USB_ENDPOINT_XFER_CONTROL -> "CONTROL"
                            UsbConstants.USB_ENDPOINT_XFER_ISOC -> "ISOCHRONOUS"
                            else -> "UNKNOWN"
                        }
                        endpointDetails.add("${type}_${direction}(0x${endpoint.address.toString(16)})")
                    }
                }
                hasEndpoints = totalEndpoints > 0

                if (hasEndpoints) {
                    log(
                        "Device has ${totalEndpoints} total endpoints: ${
                            endpointDetails.joinToString(
                                ", "
                            )
                        }"
                    )
                } else {
                    log("Device has no endpoints - might be an accessory device")
                }
            } catch (e: Exception) {
                log("Error scanning endpoints: ${e.message}")
                hasEndpoints = false
            }

            val deviceInfo = mapOf(
                "deviceId" to device.deviceId,
                "deviceName" to (device.deviceName ?: "Unknown"),
                "vendorId" to device.vendorId,
                "productId" to device.productId,
                "manufacturerName" to (device.manufacturerName ?: "Unknown"),
                "productName" to (device.productName ?: "Unknown"),
                "serialNumber" to (device.serialNumber ?: "Unknown"),
                "interfaceCount" to device.interfaceCount,
                "deviceClass" to device.deviceClass,
                "deviceSubclass" to device.deviceSubclass,
                "deviceProtocol" to device.deviceProtocol,
                "hasEndpoints" to hasEndpoints,
                "totalEndpoints" to totalEndpoints,
                "endpointDetails" to endpointDetails.joinToString(", ")
            )

            log(
                "Created device info for ${device.productName}: VID=0x${device.vendorId.toString(16)}, PID=0x${
                    device.productId.toString(
                        16
                    )
                }, Endpoints=${totalEndpoints}"
            )
            deviceInfo
        } catch (e: Exception) {
            log("Error creating device info: ${e.message}")
            val fallbackInfo = mapOf(
                "deviceId" to device.deviceId,
                "deviceName" to "Unknown",
                "vendorId" to device.vendorId,
                "productId" to device.productId,
                "manufacturerName" to "Unknown",
                "productName" to "Unknown",
                "serialNumber" to "Unknown",
                "interfaceCount" to 0,
                "deviceClass" to 0,
                "deviceSubclass" to 0,
                "deviceProtocol" to 0,
                "hasEndpoints" to false,
                "totalEndpoints" to 0,
                "endpointDetails" to ""
            )
            log("Using fallback device info: ${fallbackInfo}")
            fallbackInfo
        }
    }


    private fun getDeviceKey(device: UsbDevice): String {
        return "${device.vendorId}:${device.productId}:${device.deviceName}"
    }


    private fun requestPermission(deviceInfo: Map<String, Any>, result: MethodChannel.Result) {
        val deviceId = deviceInfo["deviceId"] as? Int
        val device = usbManager?.deviceList?.values?.find { it.deviceId == deviceId }

        log("Requesting permission for device ID: $deviceId")

        if (device == null) {
            log("Device not found in USB manager device list")
            result.error("DEVICE_NOT_FOUND", "Device not found", null)
            return
        }

        val deviceKey = getDeviceKey(device)
        log("Device key: $deviceKey")

        // Check if we already have permission
        if (usbManager?.hasPermission(device) == true) {
            log("Device already has permission")
            devicePermissions[deviceKey] = true
            result.success(true)
            return
        }

        if (devicePermissions[deviceKey] == true) {
            log("Permission already granted according to our cache")
            result.success(true)
            return
        }

        try {
            log("Requesting USB permission from system...")
            val pendingIntentFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }

            val permissionIntent = PendingIntent.getBroadcast(
                context, 0, Intent(ACTION_USB_PERMISSION),
                pendingIntentFlags
            )
            usbManager?.requestPermission(device, permissionIntent)
            log("Permission request sent to system")
            result.success(null) // Permission result will come via broadcast
        } catch (e: Exception) {
            log("Error requesting permission: ${e.message}")
            result.error("PERMISSION_ERROR", e.message, null)
        }
    }

    private fun connectToDevice(deviceInfo: Map<String, Any>, result: MethodChannel.Result) {
        val deviceId = deviceInfo["deviceId"] as? Int
        val device = usbManager?.deviceList?.values?.find { it.deviceId == deviceId }

        log("Connect to device called for device ID: $deviceId")

        // Prevent multiple connection attempts
        if (isConnecting) {
            log("Connection already in progress")
            result.error("CONNECTION_IN_PROGRESS", "Connection already in progress", null)
            return
        }

        if (currentDevice != null) {
            log("Already connected to a device, disconnecting first")
            disconnectDevice()
        }

        if (device == null) {
            log("Device not found for connection")
            result.error("DEVICE_NOT_FOUND", "Device not found", null)
            return
        }

        val deviceKey = getDeviceKey(device)
        log("Checking permissions for device: $deviceKey")

        // Check actual USB manager permission first
        if (usbManager?.hasPermission(device) != true) {
            log("Device does not have permission, requesting permission first")
            requestPermission(deviceInfo, result)
            return
        }

        if (devicePermissions[deviceKey] != true) {
            log("Permission not in cache, requesting permission")
            requestPermission(deviceInfo, result)
            return
        }

        log("Device has permission, proceeding with connection")
        // Store the result callback to call after actual connection success/failure
        pendingConnectionResult = result
        connectToDeviceInternal(device)
    }


    private fun connectToDeviceInternal(device: UsbDevice) {
        try {
            // Set connecting state
            isConnecting = true

            // Disconnect current device if any
            disconnectDevice()

            log(
                "Attempting connection to device: VID=0x${device.vendorId.toString(16)}, PID=0x${
                    device.productId.toString(
                        16
                    )
                }"
            )
            log("Device info: ${device.productName}, Manufacturer: ${device.manufacturerName}")

            log("Attempting USB Host mode connection...")
            val connection = usbManager?.openDevice(device)
            if (connection == null) {
                log("Failed to open USB Host connection")
                sendEvent("connection_status", false)
                pendingConnectionResult?.error(
                    "CONNECTION_FAILED",
                    "Failed to open USB connection. Device may be in use, need different permissions, or require driver installation.",
                    null
                )
                pendingConnectionResult = null
                isConnecting = false
                return
            }
            log("Successfully opened USB Host device connection")

            // Find the first available interface
            val usbInterface = if (device.interfaceCount > 0) device.getInterface(0) else null
            if (usbInterface == null) {
                log("No USB interface found")
                connection.close()
                sendEvent("connection_status", false)
                pendingConnectionResult?.error("CONNECTION_FAILED", "No USB interface found", null)
                pendingConnectionResult = null
                isConnecting = false
                return
            }

            // Claim the interface
            if (!connection.claimInterface(usbInterface, true)) {
                log("Failed to claim USB interface")
                connection.close()
                sendEvent("connection_status", false)
                pendingConnectionResult?.error(
                    "CONNECTION_FAILED",
                    "Failed to claim USB interface",
                    null
                )
                pendingConnectionResult = null
                isConnecting = false
                return
            }

            currentDevice = device
            currentConnection = connection
            currentInterface = usbInterface

            // Cache endpoints
            cacheEndpoints(usbInterface)

            // Validate USB Host connection based on endpoints
            val endpointCount = listOfNotNull(
                bulkInEndpoint,
                bulkOutEndpoint,
                interruptInEndpoint,
                interruptOutEndpoint
            ).size
            if (endpointCount == 0) {
                log("Warning: No standard USB endpoints found. This device may require different drivers or connection method.")
                log("Device will remain connected but communication may be limited.")
            }

            log("Successfully connected to USB Host device: ${device.productName ?: "Unknown"}")
            log("Connection details: InterfaceCount=${device.interfaceCount}, Endpoints=${endpointCount}")
            log("Available endpoints - BulkIn: ${bulkInEndpoint != null}, BulkOut: ${bulkOutEndpoint != null}, InterruptIn: ${interruptInEndpoint != null}, InterruptOut: ${interruptOutEndpoint != null}")

            // Only report connected after full validation
            sendEvent("connection_status", true)

            // Send device info
            sendEvent("device_attached", createDeviceInfo(device))

            // Start reading data in background if we have input endpoints
            if (bulkInEndpoint != null || interruptInEndpoint != null) {
                startDataReading()
            } else {
                log("No input endpoints available for data reading")
            }

            // Report success to Flutter
            pendingConnectionResult?.success(true)
            pendingConnectionResult = null
            isConnecting = false

        } catch (e: Exception) {
            log("Error connecting to device: ${e.message}")
            sendEvent("connection_status", false)
            pendingConnectionResult?.error("CONNECTION_ERROR", e.message, null)
            pendingConnectionResult = null
            isConnecting = false
            // Ensure cleanup on error
            disconnectDevice()
        }
    }


    private fun cacheEndpoints(usbInterface: UsbInterface) {
        bulkInEndpoint = null
        bulkOutEndpoint = null
        interruptInEndpoint = null
        interruptOutEndpoint = null

        for (i in 0 until usbInterface.endpointCount) {
            val endpoint = usbInterface.getEndpoint(i)
            when (endpoint.type) {
                UsbConstants.USB_ENDPOINT_XFER_BULK -> {
                    if (endpoint.direction == UsbConstants.USB_DIR_IN) {
                        bulkInEndpoint = endpoint
                        log("Found bulk IN endpoint: ${endpoint.address}")
                    } else {
                        bulkOutEndpoint = endpoint
                        log("Found bulk OUT endpoint: ${endpoint.address}")
                    }
                }

                UsbConstants.USB_ENDPOINT_XFER_INT -> {
                    if (endpoint.direction == UsbConstants.USB_DIR_IN) {
                        interruptInEndpoint = endpoint
                        log("Found interrupt IN endpoint: ${endpoint.address}")
                    } else {
                        interruptOutEndpoint = endpoint
                        log("Found interrupt OUT endpoint: ${endpoint.address}")
                    }
                }
            }
        }
    }

    private fun startDataReading() {
        readingJob?.cancel()

        // Try to find any IN endpoint for reading
        val readEndpoint = bulkInEndpoint ?: interruptInEndpoint
        if (readEndpoint == null) {
            log("No IN endpoint available for reading - device might use alternative communication methods")
            return
        }

        readingJob = coroutineScope.launch {
            log("Starting data reading loop with endpoint: ${readEndpoint.address}")
            var consecutiveErrors = 0
            val maxConsecutiveErrors = 5

            while (isActive && currentConnection != null && readEndpoint != null) {
                try {
                    val buffer = ByteArray(readEndpoint.maxPacketSize)
                    val bytesRead = currentConnection!!.bulkTransfer(
                        readEndpoint, buffer, buffer.size, 100 // 100ms timeout
                    )

                    if (bytesRead > 0) {
                        consecutiveErrors = 0 // Reset error counter on successful read
                        val data = buffer.sliceArray(0 until bytesRead)

                        try {
                            // Try to convert to string, fallback to hex if not UTF-8
                            val dataString = String(data, Charsets.UTF_8)
                            sendEvent("data_received", dataString)
                            log("Received data: $dataString (${bytesRead} bytes)")
                        } catch (charException: Exception) {
                            // If not valid UTF-8, send as hex string
                            val hexString = data.joinToString(" ") {
                                "0x${it.toUByte().toString(16).padStart(2, '0')}"
                            }
                            sendEvent("data_received", hexString)
                            log("Received binary data: $hexString (${bytesRead} bytes)")
                        }
                    } else if (bytesRead < 0) {
                        // Transfer error
                        consecutiveErrors++
                        if (consecutiveErrors >= maxConsecutiveErrors) {
                            log("Too many consecutive transfer errors, stopping data reading")
                            break
                        }
                        delay(200) // Longer delay on transfer error
                    }
                    // bytesRead == 0 means timeout, which is normal

                } catch (e: Exception) {
                    consecutiveErrors++
                    if (isActive) {
                        log("Error reading data: ${e.message} (consecutive errors: $consecutiveErrors)")
                        if (consecutiveErrors >= maxConsecutiveErrors) {
                            log("Too many consecutive errors, stopping data reading")
                            // Disconnect the device as it might be in a bad state
                            disconnectDevice()
                            break
                        }
                    }
                    delay(200) // Longer delay on error
                }
            }
            log("Data reading loop stopped")
        }
    }

    private fun sendBulkData(data: ByteArray, result: MethodChannel.Result) {
        if (currentConnection == null) {
            result.error("NOT_CONNECTED", "Device not connected", null)
            return
        }

        // Try to find any OUT endpoint
        val writeEndpoint = bulkOutEndpoint ?: interruptOutEndpoint
        if (writeEndpoint == null) {
            result.error("NO_ENDPOINT", "No OUT endpoint available for writing", null)
            return
        }

        try {
            val bytesWritten = currentConnection!!.bulkTransfer(
                writeEndpoint, data, data.size, 5000 // 5 second timeout
            )

            if (bytesWritten >= 0) {
                log("Bulk data sent successfully: $bytesWritten bytes")
                result.success(bytesWritten)
            } else {
                result.error("TRANSFER_FAILED", "Bulk transfer failed", null)
            }
        } catch (e: Exception) {
            log("Error sending bulk data: ${e.message}")
            result.error("TRANSFER_ERROR", e.message, null)
        }
    }

    private fun performBulkTransfer(args: Map<String, Any>, result: MethodChannel.Result) {
        val endpoint = args["endpoint"] as? Int ?: 0x02
        val data = args["data"] as? ByteArray
        val timeout = args["timeout"] as? Int ?: 5000

        if (data == null) {
            result.error("INVALID_ARGUMENTS", "Data required", null)
            return
        }

        if (currentConnection == null) {
            result.error("NOT_CONNECTED", "Device not connected", null)
            return
        }

        try {
            val usbEndpoint = if (endpoint and UsbConstants.USB_DIR_IN != 0) {
                bulkInEndpoint
            } else {
                bulkOutEndpoint
            }

            if (usbEndpoint == null) {
                result.error("ENDPOINT_NOT_FOUND", "Bulk endpoint not found", null)
                return
            }

            val bytesTransferred = currentConnection!!.bulkTransfer(
                usbEndpoint, data, data.size, timeout
            )

            if (bytesTransferred >= 0) {
                sendEvent(
                    "bulk_transfer_result", mapOf(
                        "endpoint" to endpoint,
                        "bytesTransferred" to bytesTransferred,
                        "success" to true
                    )
                )
                result.success(true)
            } else {
                result.error("TRANSFER_FAILED", "Bulk transfer failed", null)
            }
        } catch (e: Exception) {
            log("Error performing bulk transfer: ${e.message}")
            result.error("TRANSFER_ERROR", e.message, null)
        }
    }

    private fun performInterruptTransfer(args: Map<String, Any>, result: MethodChannel.Result) {
        val endpoint = args["endpoint"] as? Int ?: 0x81
        val data = args["data"] as? ByteArray
        val timeout = args["timeout"] as? Int ?: 1000

        if (data == null) {
            result.error("INVALID_ARGUMENTS", "Data required", null)
            return
        }

        if (currentConnection == null) {
            result.error("NOT_CONNECTED", "Device not connected", null)
            return
        }

        try {
            val usbEndpoint = if (endpoint and UsbConstants.USB_DIR_IN != 0) {
                interruptInEndpoint
            } else {
                interruptOutEndpoint
            }

            if (usbEndpoint == null) {
                result.error("ENDPOINT_NOT_FOUND", "Interrupt endpoint not found", null)
                return
            }

            val bytesTransferred = currentConnection!!.bulkTransfer(
                usbEndpoint, data, data.size, timeout
            )

            if (bytesTransferred >= 0) {
                sendEvent(
                    "interrupt_transfer_result", mapOf(
                        "endpoint" to endpoint,
                        "bytesTransferred" to bytesTransferred,
                        "success" to true
                    )
                )
                result.success(true)
            } else {
                result.error("TRANSFER_FAILED", "Interrupt transfer failed", null)
            }
        } catch (e: Exception) {
            log("Error performing interrupt transfer: ${e.message}")
            result.error("TRANSFER_ERROR", e.message, null)
        }
    }

    private fun disconnectDevice() {
        try {
            log("Disconnecting device...")

            // Cancel reading job first
            readingJob?.cancel()
            readingJob = null

            // Release interface safely
            currentInterface?.let { usbInterface ->
                try {
                    currentConnection?.releaseInterface(usbInterface)
                    log("Released USB interface")
                } catch (e: Exception) {
                    log("Error releasing interface: ${e.message}")
                }
            }

            // Close connection safely
            currentConnection?.let { connection ->
                try {
                    connection.close()
                    log("Closed USB connection")
                } catch (e: Exception) {
                    log("Error closing connection: ${e.message}")
                }
            }

            // Clear all references
            currentDevice = null
            currentConnection = null
            currentInterface = null

            bulkInEndpoint = null
            bulkOutEndpoint = null
            interruptInEndpoint = null
            interruptOutEndpoint = null

            // Clear connection state
            isConnecting = false
            pendingConnectionResult = null

            sendEvent("connection_status", false)
            log("Device disconnected successfully")

        } catch (e: Exception) {
            log("Error during disconnect: ${e.message}")
            sendEvent("connection_status", false)
            isConnecting = false
            pendingConnectionResult = null
        }
    }


    private fun sendEvent(type: String, payload: Any?) {
        eventSink?.success(
            mapOf(
                "type" to type,
                "payload" to payload,
                "timestamp" to System.currentTimeMillis() / 1000.0
            )
        )
    }

    private fun log(message: String) {
        Log.d(TAG, message)
        sendEvent("log", message)
    }

    private fun cleanup() {
        try {
            context.unregisterReceiver(usbReceiver)
        } catch (e: Exception) {
            Log.e(TAG, "Error unregistering receiver: ${e.message}")
        }

        coroutineScope.cancel()
        disconnectDevice()
        devicePermissions.clear()
    }

} 