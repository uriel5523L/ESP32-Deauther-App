#!/usr/bin/env python3
# ESP32-Deauther Companion App
#
# App de escritorio (Python + tkinter) para conectarse al ESP32 por su WiFi
# (AP "ESP32-Deauther" / 192.168.4.1) y controlar TODAS las funciones del
# firmware: escanear redes, lanzar deauth a una red, deauth a todas y detener.
#
# Requisitos:
#   pip install requests
#
# Uso:
#   1. Carga el firmware en tu ESP32 (carpeta /firmware con PlatformIO).
#   2. Conecta tu PC/telefono al WiFi "ESP32-Deauther" / "esp32wroom32".
#   3. Ejecuta:  python esp32_deauther_app.py
#   4. Pulsa "Conectar" e usa los controles.
#
# DISCLAIMER: solo para fines educativos y pruebas en redes propias.

import json
import platform
import subprocess
import threading
import tkinter as tk
from tkinter import messagebox, ttk

import requests

ESP_SSID = "ESP32-Deauther"
ESP_PASS = "esp32wroom32"
DEFAULT_IP = "192.168.4.1"
BASE = "http://{ip}"

REASON_CODES = {
    "0 - Reserved": 0,
    "1 - Unspecified reason": 1,
    "2 - Previous authentication no longer valid": 2,
    "3 - Station leaving/departing IBSS or ESS": 3,
    "4 - Disassociated due to inactivity": 4,
    "5 - Disassociated because AP too busy": 5,
    "6 - Class 2 frame from nonauthenticated STA": 6,
    "7 - Class 3 frame from nonassociated STA": 7,
    "8 - Disassociated because STA leaving BSS": 8,
    "9 - STA requesting (re)assoc is not authenticated": 9,
    "10 - Disassociated: Power Capability unacceptable": 10,
    "11 - Disassociated: Supported Channels unacceptable": 11,
    "12 - Disassociated due to BSS Transition Mgmt": 12,
    "13 - Invalid element": 13,
    "14 - Message integrity code (MIC) failure": 14,
    "15 - 4-Way Handshake timeout": 15,
    "16 - Group Key Handshake timeout": 16,
    "17 - Handshake different from (Re)Assoc/Probe/Beacon": 17,
    "18 - Invalid group cipher": 18,
    "19 - Invalid pairwise cipher": 19,
    "20 - Invalid AKMP": 20,
    "21 - Unsupported RSNE version": 21,
    "22 - Invalid RSNE capabilities": 22,
    "23 - IEEE 802.1X authentication failed": 23,
    "24 - Cipher suite rejected by policy": 24,
}


class DeautherApp:
    def __init__(self, root):
        self.root = root
        self.ip = DEFAULT_IP
        self.networks = []
        self.token = None

        root.title("ESP32-Deauther App")
        root.geometry("760x620")
        root.resizable(True, True)

        self._build_connection_frame()
        self._build_scan_frame()
        self._build_attack_frame()
        self._build_status_frame()
        self._build_log()

        self.log("Listo. Conectate al WiFi '%s' y pulsa Conectar." % ESP_SSID)

    # ------------------------------------------------------------------ UI
    def _build_connection_frame(self):
        f = ttk.LabelFrame(self.root, text="Conexion", padding=8)
        f.pack(fill="x", padx=8, pady=4)

        ttk.Label(f, text="IP del ESP32:").grid(row=0, column=0, sticky="w")
        self.ip_var = tk.StringVar(value=self.ip)
        ttk.Entry(f, textvariable=self.ip_var, width=18).grid(row=0, column=1, padx=4)

        ttk.Label(f, text="Usuario:").grid(row=1, column=0, sticky="w")
        self.user_var = tk.StringVar(value="admin")
        ttk.Entry(f, textvariable=self.user_var, width=18).grid(row=1, column=1, padx=4)

        ttk.Label(f, text="Password:").grid(row=2, column=0, sticky="w")
        self.pass_var = tk.StringVar(value="deauther")
        ttk.Entry(f, textvariable=self.pass_var, show="*", width=18).grid(row=2, column=1, padx=4)

        ttk.Button(f, text="Conectar", command=self.connect).grid(row=0, column=2, padx=4)
        ttk.Button(f, text="Conectar WiFi ESP32", command=self.connect_wifi).grid(row=0, column=3, padx=4)
        ttk.Button(f, text="Abrir Web UI", command=self.open_webui).grid(row=0, column=4, padx=4)

    def _build_scan_frame(self):
        f = ttk.LabelFrame(self.root, text="Redes WiFi", padding=8)
        f.pack(fill="both", expand=True, padx=8, pady=4)

        ttk.Button(f, text="Escanear redes", command=self.scan).pack(anchor="w", pady=2)

        cols = ("num", "ssid", "bssid", "channel", "rssi", "enc")
        self.tree = ttk.Treeview(f, columns=cols, show="headings", height=12)
        self.tree.heading("num", text="#")
        self.tree.heading("ssid", text="SSID")
        self.tree.heading("bssid", text="BSSID")
        self.tree.heading("channel", text="Ch")
        self.tree.heading("rssi", text="RSSI")
        self.tree.heading("enc", text="Encryption")
        self.tree.column("num", width=40)
        self.tree.column("ssid", width=160)
        self.tree.column("bssid", width=170)
        self.tree.column("channel", width=40)
        self.tree.column("rssi", width=60)
        self.tree.column("enc", width=110)
        self.tree.pack(fill="both", expand=True)

    def _build_attack_frame(self):
        f = ttk.LabelFrame(self.root, text="Ataque Deauth", padding=8)
        f.pack(fill="x", padx=8, pady=4)

        ttk.Label(f, text="Reason code:").grid(row=0, column=0, sticky="w")
        self.reason_var = tk.StringVar(value=list(REASON_CODES.keys())[1])
        reasons = ttk.Combobox(f, textvariable=self.reason_var, values=list(REASON_CODES.keys()), width=42, state="readonly")
        reasons.grid(row=0, column=1, columnspan=2, padx=4, sticky="w")

        ttk.Button(f, text="Lanzar Deauth (red seleccionada)", command=self.deauth_single).grid(row=1, column=0, padx=4, pady=4)
        ttk.Button(f, text="Deauth a TODAS las redes", command=self.deauth_all).grid(row=1, column=1, padx=4, pady=4)
        ttk.Button(f, text="Detener", command=self.stop_attack).grid(row=1, column=2, padx=4, pady=4)

    def _build_status_frame(self):
        f = ttk.LabelFrame(self.root, text="Estado", padding=8)
        f.pack(fill="x", padx=8, pady=4)
        self.status_var = tk.StringVar(value="Sin conectar")
        ttk.Label(f, textvariable=self.status_var, foreground="blue").pack(anchor="w")

    def _build_log(self):
        f = ttk.LabelFrame(self.root, text="Log", padding=8)
        f.pack(fill="both", expand=True, padx=8, pady=4)
        self.log_box = tk.Text(f, height=8, state="disabled")
        self.log_box.pack(fill="both", expand=True)

    # ------------------------------------------------------------------ helpers
    def log(self, msg):
        self.log_box.configure(state="normal")
        self.log_box.insert("end", msg + "\n")
        self.log_box.configure(state="disabled")
        self.log_box.see("end")

    def _url(self, path):
        return BASE.format(ip=self.ip_var.get()) + path

    def _req(self, method, path, **kw):
        try:
            url = self._url(path)
            if self.token:
                sep = "&" if "?" in url else "?"
                url += "%stoken=%s" % (sep, self.token)
            r = requests.request(method, url, timeout=8, **kw)
            return r
        except requests.exceptions.RequestException as e:
            self.log("ERROR: %s" % e)
            return None

    # ------------------------------------------------------------------ actions
    def connect(self):
        def work():
            # 1) login para obtener el token
            r = self._req("POST", "/api/login",
                          data={"user": self.user_var.get(), "pass": self.pass_var.get()})
            if r is None or r.status_code != 200:
                self.root.after(0, lambda: self.status_var.set("No conectado / credenciales?"))
                self.root.after(0, lambda: self.log("Login fallo: %s" % (r.text if r else "sin respuesta")))
                return
            self.token = r.json().get("token")
            self.root.after(0, lambda: self.log("Login OK. Token obtenido."))

            # 2) estado
            r2 = self._req("GET", "/api/status")
            if r2 is None or r2.status_code != 200:
                self.root.after(0, lambda: self.status_var.set("No conectado"))
                return
            data = r2.json()
            self.root.after(0, lambda: self.status_var.set(
                "Conectado | deauth_type=%s | eliminadas=%s" % (data.get("deauth_type"), data.get("eliminated_stations"))
            ))
            self.root.after(0, lambda: self.log("Conectado al ESP32 (%s)" % data.get("ap_ip")))
        threading.Thread(target=work, daemon=True).start()

    def connect_wifi(self):
        sys_os = platform.system()
        self.log("Intentando conectar al WiFi '%s'..." % ESP_SSID)
        if sys_os == "Windows":
            try:
                subprocess.run(
                    ["netsh", "wlan", "connect", "ssid=%s" % ESP_SSID, "name=%s" % ESP_SSID],
                    check=False, capture_output=True, text=True,
                )
                self.log("Comando netsh enviado. Si falla, conectate manualmente desde la configuracion de red.")
            except Exception as e:
                self.log("No se pudo conectar automaticamente: %s" % e)
        else:
            self.log("SO %s: conectate manualmente al WiFi '%s' / '%s'." % (sys_os, ESP_SSID, ESP_PASS))

    def open_webui(self):
        import webbrowser
        webbrowser.open(self._url("/"))

    def scan(self):
        def work():
            self.root.after(0, lambda: self.log("Escaneando redes..."))
            r = self._req("GET", "/api/scan")
            if r is None or r.status_code != 200:
                self.root.after(0, lambda: self.log("Fallo el escaneo."))
                return
            try:
                nets = r.json()
            except ValueError:
                self.root.after(0, lambda: self.log("Respuesta invalida del ESP32."))
                return
            self.networks = nets
            self.root.after(0, self._fill_tree, nets)
            self.root.after(0, lambda: self.log("Encontradas %d redes." % len(nets)))
        threading.Thread(target=work, daemon=True).start()

    def _fill_tree(self, nets):
        for row in self.tree.get_children():
            self.tree.delete(row)
        for n in nets:
            self.tree.insert("", "end", values=(
                n.get("num"), n.get("ssid"), n.get("bssid"),
                n.get("channel"), n.get("rssi"), n.get("enc"),
            ))

    def _selected_net_num(self):
        sel = self.tree.selection()
        if not sel:
            messagebox.showwarning("Aviso", "Selecciona una red de la lista.")
            return None
        return int(self.tree.item(sel[0])["values"][0])

    def _reason(self):
        return REASON_CODES[self.reason_var.get()]

    def deauth_single(self):
        num = self._selected_net_num()
        if num is None:
            return
        reason = self._reason()
        self.log("Lanzando Deauth en red #%d (reason %d)..." % (num, reason))
        threading.Thread(target=self._post, args=("/api/deauth", {"net_num": num, "reason": reason}), daemon=True).start()

    def deauth_all(self):
        reason = self._reason()
        if not messagebox.askyesno("Confirmar", "Esto desautentica TODAS las redes y apaga el WiFi del ESP32.\nPara parar tendras que resetear el ESP32.\n¿Continuar?"):
            return
        self.log("Lanzando Deauth en TODAS las redes (reason %d)..." % reason)
        threading.Thread(target=self._post, args=("/api/deauth_all", {"reason": reason}), daemon=True).start()

    def stop_attack(self):
        self.log("Deteniendo ataque Deauth...")
        threading.Thread(target=self._post, args=("/api/stop", {}), daemon=True).start()

    def _post(self, path, data):
        r = self._req("POST", path, data=data)
        if r is None:
            return
        try:
            self.root.after(0, lambda: self.log("Respuesta: %s" % r.text))
        except Exception:
            pass
        if path == "/api/stop":
            self.root.after(0, self.connect)


if __name__ == "__main__":
    root = tk.Tk()
    try:
        from ttkthemes import ThemedTk  # opcional, mejor estetica
        root = ThemedTk(theme="arc")
    except ImportError:
        pass
    DeautherApp(root)
    root.mainloop()
