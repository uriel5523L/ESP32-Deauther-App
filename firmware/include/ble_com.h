#ifndef BLE_COM_H
#define BLE_COM_H

#include <Arduino.h>

void start_ble();
void ble_process();
void ble_send(const String& msg);

#endif
