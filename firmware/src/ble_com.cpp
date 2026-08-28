#include "definitions.h"
#include "ble_com.h"
#include "deauth.h"
#include "web_interface.h"
#ifdef ENABLE_BLE
#include <NimBLEDevice.h>

static NimBLEServer* pServer = nullptr;
static NimBLECharacteristic* pTx = nullptr;
static bool deviceConnected = false;
static bool ble_authed = false;

static String pendingCmd = "";
static bool pending = false;

#define SERVICE_UUID "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define RX_UUID      "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
#define TX_UUID      "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"

class MyServerCallbacks : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer* pServer) {
    deviceConnected = true;
    ble_send(String("CONNECTED. Envia: LOGIN ") + LOGIN_PASS);
  }
  void onDisconnect(NimBLEServer* pServer) {
    deviceConnected = false;
    ble_authed = false;
    NimBLEDevice::startAdvertising();
  }
};

class RxCallbacks : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* pCharacteristic) {
    std::string v = pCharacteristic->getValue();
    if (v.length()) {
      pendingCmd = String(v.c_str());
      pending = true;
    }
  }
};

void ble_send(const String& msg) {
  if (pTx && deviceConnected) {
    pTx->setValue(msg.c_str());
    pTx->notify();
  }
}

void start_ble() {
  NimBLEDevice::init(BLE_DEVICE_NAME);
  pServer = NimBLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  NimBLEService* pService = pServer->createService(SERVICE_UUID);
  pTx = pService->createCharacteristic(TX_UUID, NIMBLE_PROPERTY::NOTIFY);
  NimBLECharacteristic* pRx = pService->createCharacteristic(RX_UUID, NIMBLE_PROPERTY::WRITE);
  pRx->setCallbacks(new RxCallbacks());

  NimBLEAdvertising* pAdv = NimBLEDevice::getAdvertising();
  NimBLEAdvertisementData advData;
  advData.setFlags(0x06);  // LE General Discoverable, sin BR/EDR
  advData.setName(BLE_DEVICE_NAME);
  advData.addServiceUUID(NimBLEUUID(SERVICE_UUID));
  pAdv->setAdvertisementData(advData);
  NimBLEAdvertisementData scanData;
  scanData.setName(BLE_DEVICE_NAME);
  pAdv->setScanResponseData(scanData);
  pAdv->start();
  DEBUG_PRINTLN("BLE iniciado. Conecta por BLE y envia LOGIN.");
}

// Procesa los comandos recibidos por BLE fuera del callback (en el loop)
void ble_process() {
  if (!pending) return;
  pending = false;
  String cmd = pendingCmd;
  cmd.trim();

  if (cmd.startsWith("LOGIN ")) {
    String p = cmd.substring(6);
    p.trim();
    if (p == LOGIN_PASS) {
      ble_authed = true;
      ble_send("OK autenticado");
    } else {
      ble_send("ERR password incorrecto");
    }
    return;
  }

  if (!ble_authed) {
    ble_send("ERR no autenticado (envia LOGIN <pass>)");
    return;
  }

  if (cmd == "SCAN") {
    do_scan();
    ble_send("SCAN " + last_scan_json);
    return;
  }

  if (cmd.startsWith("DEAUTH ")) {
    int sp = cmd.indexOf(' ', 7);
    if (sp < 0) { ble_send("ERR uso: DEAUTH <net> <reason>"); return; }
    int net = cmd.substring(7, sp).toInt();
    int reason = cmd.substring(sp + 1).toInt();
    if (net < num_networks) {
      start_deauth(net, DEAUTH_TYPE_SINGLE, (uint16_t)reason);
      ble_send("OK deauth iniciado en red " + String(net));
    } else {
      ble_send("ERR numero de red invalido");
    }
    return;
  }

  if (cmd.startsWith("DEAUTHALL ")) {
    int reason = cmd.substring(10).toInt();
    start_deauth(0, DEAUTH_TYPE_ALL, (uint16_t)reason);
    ble_send("OK deauth global iniciado");
    return;
  }

  if (cmd == "STOP") {
    stop_deauth();
    ble_send("OK detenido");
    return;
  }

  if (cmd == "STATUS") {
    ble_send("STATUS eliminadas=" + String(eliminated_stations) + " tipo=" + String(deauth_type));
    return;
  }

  ble_send("ERR comando desconocido");
}
#endif
