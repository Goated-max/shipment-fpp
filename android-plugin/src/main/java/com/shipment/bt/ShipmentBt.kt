package com.shipment.bt

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothServerSocket
import android.bluetooth.BluetoothSocket
import android.util.Base64
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot
import java.io.IOException
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import kotlin.concurrent.thread

// Bluetooth Classic (RFCOMM) byte stream for Godot. Data is passed as base64 strings.
// Godot singleton name: "ShipmentBt"
class ShipmentBt(godot: Godot) : GodotPlugin(godot) {

    companion object {
        val APP_UUID: UUID = UUID.fromString("8f3c2a10-6d1e-4b7a-9c55-5a7e0d1f2b33")
    }

    private val socks = ConcurrentHashMap<Int, BluetoothSocket>()
    private var nextId = 1
    @Volatile private var server: BluetoothServerSocket? = null

    override fun getPluginName() = "ShipmentBt"

    override fun getPluginSignals(): Set<SignalInfo> = setOf(
        SignalInfo("peer_connected", Int::class.javaObjectType, String::class.java),
        SignalInfo("peer_disconnected", Int::class.javaObjectType),
        SignalInfo("data_received", Int::class.javaObjectType, String::class.java),
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

    @UsedByGodot
    fun paired_devices(): Array<String> = try {
        adapter()?.bondedDevices?.map { "${it.name}|${it.address}" }?.toTypedArray() ?: arrayOf<String>()
    } catch (e: SecurityException) {
        arrayOf<String>()
    }

    // Accept up to maxClients phones on the fixed app UUID.
    @UsedByGodot
    fun host(maxClients: Int) {
        val a = adapter()
        if (a == null || !a.isEnabled) {
            err("Turn Bluetooth on first")
            return
        }
        stop_server()
        thread(isDaemon = true) {
            try {
                val srv = a.listenUsingRfcommWithServiceRecord("ShipmentFPP", APP_UUID)
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
                if (server != null) err("Bluetooth host stopped: ${e.message}")
            } catch (e: SecurityException) {
                err("Bluetooth permission denied")
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
        thread(isDaemon = true) {
            try {
                try { a.cancelDiscovery() } catch (_: SecurityException) {}
                val dev = a.getRemoteDevice(address)
                val s = dev.createRfcommSocketToServiceRecord(APP_UUID)
                s.connect()
                attach(s, address)
            } catch (e: IOException) {
                err("Could not connect: ${e.message}")
            } catch (e: SecurityException) {
                err("Bluetooth permission denied")
            } catch (e: IllegalArgumentException) {
                err("Bad Bluetooth address")
            }
        }
    }

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
            } catch (_: IOException) {
            } finally {
                drop(id)
            }
        }
    }

    private fun drop(id: Int) {
        val s = socks.remove(id) ?: return
        try { s.close() } catch (_: IOException) {}
        ui { emitSignal("peer_disconnected", id) }
    }

    private fun stop_server() {
        val s = server ?: return
        server = null
        try { s.close() } catch (_: IOException) {}
    }
}
