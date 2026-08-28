#ifndef WEB_INTERFACE_H
#define WEB_INTERFACE_H

#include <Arduino.h>

void start_web_interface();
void web_interface_handle_client();

// Compartido con el modulo BLE para escanear y leer resultados
extern int num_networks;
extern String last_scan_json;
void do_scan();

#endif
