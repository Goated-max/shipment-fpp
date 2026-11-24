package com.shipment.bt

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothServerSocket
import android.bluetooth.BluetoothSocket
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.util.Base64
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot
import java.io.IOException
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import kotlin.concurrent.thread

// Bluetooth Classic (RFCOMM) for Godot: scan for nearby phones, host, join.
// Insecure RFCOMM sockets are used, so phones do not have to be paired first.
class ShipmentBt(godot: Godot) : GodotPlugin(godot) {

    companion object {
        val APP_UUID: UUID = UUID.fromString("8f3c2a10-6d1e-4b7a-9c55-5a7e0d1f2b33")
    }

    private val socks = ConcurrentHashMap<Int, BluetoothSocket>()
    private val seen = HashSet<String>()
    private var nextId = 1
    @Volatile private var server: BluetoothServerSocket? = null
    private var receiver: BroadcastReceiver? = null

    override fun getPluginName() = "ShipmentBt"

    override fun getPluginSignals(): Set<SignalInfo> = setOf(
        SignalInfo("peer_connected", Int::class.javaObjectType, String::class.java),
        SignalInfo("peer_disconnected", Int::class.javaObjectType),
        SignalInfo("data_received", Int::class.javaObjectType, String::class.java),
        SignalInfo("device_found", String::class.java, String::class.java),
        SignalInfo("scan_finished"),
        SignalInfo("bt_error", String::class.java)
    )

    private fun adapter(): BluetoothAdapter? = BluetoothAdapter.getDefaultAdapter()

    private fun ui(block: () -> Unit) {
        activity?.runOnUiThread { block() }
    }

    private fun err(msg: String) {
        ui { emitSignal("bt_error", msg) }
    }

    @UsedByGodot
    fun is_enabled(): Boolean = adapter()?.isEnabled == true

    // ---------- scanning ----------
    @UsedByGodot
    fun scan_start(): Boolean {
        val a = adapter()
        val act = activity
        if (a == null || !a.isEnabled || act == null) {
            err("Turn Bluetooth on first")
            return false
        }
        seen.clear()
        unregister()
        val r = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                when (intent.action) {
                    BluetoothDevice.ACTION_FOUND -> {
                        val dev = deviceFrom(intent) ?: return
                        report(dev)
                    }
                    BluetoothAdapter.ACTION_DISCOVERY_FINISHED -> {
                        unregister()
                        ui { emitSignal("scan_finished") }
                    }
                }
            }
        }
        receiver = r
        val f = IntentFilter().apply {
            addAction(BluetoothDevice.ACTION_FOUND)
            addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED)
        }
        if (Build.VERSION.SDK_INT >= 33) {
            act.registerReceiver(r, f, Context.RECEIVER_EXPORTED)
        } else {
            act.registerReceiver(r, f)
        }
        try {
            // Already-paired phones first, then anything new that is discoverable.
            a.bondedDevices?.forEach { report(it) }
            a.startDiscovery()
        } catch (e: SecurityException) {
            unregister()
            err("Bluetooth permission denied. Allow Nearby devices for Shipment FPP in Android Settings.")
            return false
        }
        return true
    }

    @UsedByGodot
    fun scan_stop() {
        try { adapter()?.cancelDiscovery() } catch (e: SecurityException) {}
        unregister()
    }

    private fun report(dev: BluetoothDevice) {
        val name: String = try { dev.name ?: return } catch (e: SecurityException) { return }
        if (name.isBlank()) return          // skip unnamed "unknown" devices
        if (!seen.add(dev.address)) return  // one entry per address
        ui { emitSignal("device_found", name, dev.address) }
    }

    @Suppress("DEPRECATION")
    private fun deviceFrom(intent: Intent): BluetoothDevice? =
        if (Build.VERSION.SDK_INT >= 33)
            intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
        else
            intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)

    private fun unregister() {
        val r = receiver ?: return
        receiver = null
        try { activity?.unregisterReceiver(r) } catch (e: IllegalArgumentException) {}
    }

    // ---------- host / join ----------
    @UsedByGodot
    fun host(maxClients: Int) {
        val a = adapter()
        val act = activity
        if (a == null || !a.isEnabled || act == null) {
            err("Turn Bluetooth on first")
            return
        }
        stop_server()
        try {
            // Makes this phone visible to scanners for 5 minutes. Android asks the player to allow it.
            act.startActivity(
                Intent(BluetoothAdapter.ACTION_REQUEST_DISCOVERABLE)
                    .putExtra(BluetoothAdapter.EXTRA_DISCOVERABLE_DURATION, 300)
            )
        } catch (e: Exception) {}
        thread(isDaemon = true) {
            try {
                val srv = a.listenUsingInsecureRfcommWithServiceRecord("ShipmentFPP", APP_UUID)
                server = srv
                while (true) {
                    val s = srv.accept()
                    if (socks.size >= maxClients) {
                        s.close()
                        continue
                    }
                    attach(s, s.remoteDevice.address)
                }
            } catch (e: IOException) {
                if (server != null) err("Hosting stopped: ${e.message}")
            } catch (e: SecurityException) {
                err("Bluetooth permission denied. Allow Nearby devices for Shipment FPP in Android Settings.")
            }
        }
    }

    @UsedByGodot
    fun join(address: String) {
        val a = adapter()
        if (a == null || !a.isEnabled) {
            err("Turn Bluetooth on first")
            return
        }
        scan_stop()
        thread(isDaemon = true) {
            try {
                val s = a.getRemoteDevice(address).createInsecureRfcommSocketToServiceRecord(APP_UUID)
                s.connect()
                attach(s, address)
            } catch (e: IOException) {
                err("Could not connect. Make sure the host tapped HOST GAME.")
            } catch (e: SecurityException) {
                err("Bluetooth permission denied. Allow Nearby devices for Shipment FPP in Android Settings.")
            } catch (e: IllegalArgumentException) {
                err("Bad Bluetooth address.")
            }
        }
    }

    // ---------- data ----------
    @UsedByGodot
    fun send(id: Int, b64: String): Boolean {
        val s = socks[id] ?: return false
        return try {
            val bytes = Base64.decode(b64, Base64.NO_WRAP)
            synchronized(s) {
                s.outputStream.write(bytes)
                s.outputStream.flush()
            }
            true
        } catch (e: IOException) {
            drop(id)
            false
        }
    }

    @UsedByGodot
    fun close_peer(id: Int) {
        drop(id)
    }

    @UsedByGodot
    fun stop() {
        scan_stop()
        stop_server()
        for (id in socks.keys.toList()) drop(id)
    }

    private fun attach(sock: BluetoothSocket, addr: String) {
        val id = synchronized(this) { nextId++ }
        socks[id] = sock
        ui { emitSignal("peer_connected", id, addr) }
        thread(isDaemon = true) {
            val buf = ByteArray(4096)
            try {
                val input = sock.inputStream
                while (true) {
                    val n = input.read(buf)
                    if (n < 0) break
                    val b64 = Base64.encodeToString(buf.copyOf(n), Base64.NO_WRAP)
                    ui { emitSignal("data_received", id, b64) }
                }
            } catch (e: IOException) {
            } finally {
                drop(id)
            }
        }
    }

    private fun drop(id: Int) {
        val s = socks.remove(id) ?: return
        try { s.close() } catch (e: IOException) {}
        ui { emitSignal("peer_disconnected", id) }
    }

    private fun stop_server() {
        val s = server ?: return
        server = null
        try { s.close() } catch (e: IOException) {}
    }
}
