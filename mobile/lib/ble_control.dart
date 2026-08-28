import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'models.dart';
import 'controller.dart';

const String _serviceUuid = '6e400001b5a3f393e0a9e50e24dcca9e';
const String _rxUuid = '6e400002b5a3f393e0a9e50e24dcca9e';
const String _txUuid = '6e400003b5a3f393e0a9e50e24dcca9e';

String _norm(String u) => u.toLowerCase().replaceAll('-', '');

/// Controlador BLE (Nordic UART). El ESP32 expone un servicio con
/// caracteristica RX (write) y TX (notify). Comandos:
///   LOGIN <pass> | SCAN | DEAUTH <net> <reason> | DEAUTHALL <reason> | STOP | STATUS
class BleController implements DeautherController {
  final BluetoothDevice device;
  BluetoothCharacteristic? _rx;
  BluetoothCharacteristic? _tx;
  final _resp = StreamController<String>.broadcast();
  final List<String> _recv = [];

  BleController(this.device);

  Future<void> init() async {
    final services = await device.discoverServices();
    for (final s in services) {
      if (_norm(s.uuid.toString()) == _serviceUuid) {
        for (final c in s.characteristics) {
          final u = _norm(c.uuid.toString());
          if (u == _rxUuid) _rx = c;
          if (u == _txUuid) _tx = c;
        }
      }
    }
    if (_rx == null || _tx == null) {
      throw Exception('Servicio UART no encontrado en este dispositivo');
    }
    await _tx!.setNotifyValue(true);
    _tx!.onValueReceived.listen((List<int> v) {
      final line = String.fromCharCodes(v).trim();
      if (line.isNotEmpty) {
        _recv.add(line);
        _resp.add(line);
      }
    });
    // Da tiempo a que el ESP32 envíe el saludo "CONNECTED" antes de mandar comandos.
    await Future.delayed(const Duration(milliseconds: 400));
  }

  Future<void> login(String pass) async {
    final line = await _send('LOGIN $pass', expectPrefix: 'OK');
    if (!line.startsWith('OK')) {
      throw Exception('BLE: $line');
    }
  }

  Future<String> _send(String cmd, {String? expectPrefix}) async {
    final completer = Completer<String>();
    late StreamSubscription sub;
    sub = _resp.stream.listen((line) {
      if (expectPrefix == null || line.startsWith(expectPrefix)) {
        if (!completer.isCompleted) {
          completer.complete(line);
          sub.cancel();
        }
      }
    });
    await _rx!.write(utf8.encode(cmd), withoutResponse: false);
    try {
      return await completer.future.timeout(const Duration(seconds: 15));
    } on TimeoutException {
      final got = _recv.isEmpty ? '(sin respuesta)' : _recv.join(' | ');
      throw Exception('BLE: sin respuesta en 15s. Recibido: $got');
    }
  }

  Future<List<Network>> scan() async {
    final line = await _send('SCAN', expectPrefix: 'SCAN ');
    final jsonStr = line.substring('SCAN '.length).trim();
    final List l = jsonDecode(jsonStr);
    return l.map((e) => Network.fromJson(e)).toList();
  }

  Future<String> deauthSingle(int net, int reason) async {
    return _send('DEAUTH $net $reason', expectPrefix: 'OK');
  }

  Future<String> deauthAll(int reason) async {
    return _send('DEAUTHALL $reason', expectPrefix: 'OK');
  }

  Future<String> stop() async {
    return _send('STOP', expectPrefix: 'OK');
  }

  Future<String> statusRaw() async {
    return _send('STATUS', expectPrefix: 'STATUS');
  }

  Future<void> disconnect() async {
    await device.disconnect();
  }
}
