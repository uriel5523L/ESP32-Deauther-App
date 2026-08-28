import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'models.dart';
import 'controller.dart';
import 'esp_api.dart';
import 'ble_control.dart';

void main() => runApp(const MaterialApp(home: HomePage()));

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _mode = 'wifi';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ESP32-Deauther')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'wifi', label: Text('WiFi')),
                ButtonSegment(value: 'ble', label: Text('Bluetooth')),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _mode == 'wifi'
                  ? const WifiLoginForm()
                  : const BleConnectScreen(),
            ),
          ],
        ),
      ),
    );
  }
}

class WifiLoginForm extends StatefulWidget {
  const WifiLoginForm({super.key});
  @override
  State<WifiLoginForm> createState() => _WifiLoginFormState();
}

class _WifiLoginFormState extends State<WifiLoginForm> {
  final _ip = TextEditingController(text: '192.168.4.1');
  final _user = TextEditingController(text: 'admin');
  final _pass = TextEditingController(text: 'deauther');
  bool _busy = false;
  String _err = '';

  void _login() async {
    setState(() => _busy = true);
    try {
      final c = WifiController(_ip.text.trim());
      await c.login(_user.text.trim(), _pass.text.trim());
      if (!mounted) return;
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => ControlPanel(controller: c)));
    } catch (e) {
      setState(() => _err = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const Text('Conectate al WiFi "ESP32-Deauther" / "esp32wroom32" '
            'y luego inicia sesion.'),
        const SizedBox(height: 12),
        TextField(controller: _ip, decoration: const InputDecoration(labelText: 'IP del ESP32')),
        TextField(controller: _user, decoration: const InputDecoration(labelText: 'Usuario')),
        TextField(controller: _pass, decoration: const InputDecoration(labelText: 'Password'), obscureText: true),
        const SizedBox(height: 12),
        _busy
            ? const Center(child: CircularProgressIndicator())
            : ElevatedButton(onPressed: _login, child: const Text('Iniciar sesion')),
        if (_err.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_err, style: const TextStyle(color: Colors.red)),
          ),
      ],
    );
  }
}

class BleConnectScreen extends StatefulWidget {
  const BleConnectScreen({super.key});
  @override
  State<BleConnectScreen> createState() => _BleConnectScreenState();
}

class _BleConnectScreenState extends State<BleConnectScreen> {
  List<ScanResult> _results = [];
  bool _scanning = false;
  String _msg = 'Pulsa "Escanear" y elige el dispositivo ESP32-Deauther.';

  void _scan() async {
    setState(() => _scanning = true);
    _results = [];
    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
      FlutterBluePlus.scanResults.listen((r) {
        setState(() => _results = r);
      });
      await Future.delayed(const Duration(seconds: 5));
      await FlutterBluePlus.stopScan();
    } catch (e) {
      setState(() => _msg = 'Error BLE: $e');
    } finally {
      setState(() => _scanning = false);
    }
  }

  void _connect(ScanResult r) async {
    try {
      setState(() => _msg = 'Conectando a ${r.device.platformName}...');
      await r.device.connect();
      final c = BleController(r.device);
      await c.init();

      final pass = await showDialog<String>(
        context: context,
        builder: (ctx) {
          final t = TextEditingController(text: 'deauther');
          return AlertDialog(
            title: const Text('Login BLE'),
            content: TextField(
              controller: t,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
              TextButton(onPressed: () => Navigator.pop(ctx, t.text), child: const Text('Entrar')),
            ],
          );
        },
      );
      if (pass == null) {
        await c.disconnect();
        return;
      }
      await c.login(pass.trim());
      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(builder: (_) => ControlPanel(controller: c)));
    } catch (e) {
      setState(() => _msg = 'Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ElevatedButton(
          onPressed: _scanning ? null : _scan,
          child: Text(_scanning ? 'Escaneando...' : 'Escanear BLE'),
        ),
        const SizedBox(height: 8),
        Text(_msg),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            itemCount: _results.length,
            itemBuilder: (_, i) {
              final r = _results[i];
              final name = r.device.platformName.isNotEmpty
                  ? r.device.platformName
                  : r.advertisementData.localName;
              return ListTile(
                title: Text(name),
                subtitle: Text(r.device.remoteId.toString()),
                onTap: () => _connect(r),
              );
            },
          ),
        ),
      ],
    );
  }
}

class ControlPanel extends StatefulWidget {
  final DeautherController controller;
  const ControlPanel({super.key, required this.controller});
  @override
  State<ControlPanel> createState() => _ControlPanelState();
}

class _ControlPanelState extends State<ControlPanel> {
  List<Network> _nets = [];
  int? _selected;
  String _reason = reasonCodes.keys.first;
  String _status = '';
  String _log = '';
  bool _busy = false;

  void _addLog(String s) => setState(() => _log += '$s\n');

  void _scan() async {
    setState(() => _busy = true);
    try {
      final n = await widget.controller.scan();
      setState(() => _nets = n);
      _addLog('Encontradas ${n.length} redes');
    } catch (e) {
      _addLog('Error scan: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  void _deauthSingle() async {
    if (_selected == null) {
      _addLog('Selecciona una red primero');
      return;
    }
    setState(() => _busy = true);
    try {
      final r = await widget.controller.deauthSingle(_selected!, reasonCodes[_reason]!);
      _addLog('Deauth red $_selected: $r');
    } catch (e) {
      _addLog('Error: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  void _deauthAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Deauth a TODAS las redes'),
        content: const Text('El WiFi del ESP32 se apagara. Para parar habra que '
            'resetear la placa. ¿Continuar?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('No')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Si')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final r = await widget.controller.deauthAll(reasonCodes[_reason]!);
      _addLog('Deauth global: $r');
    } catch (e) {
      _addLog('Error: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  void _stop() async {
    setState(() => _busy = true);
    try {
      final r = await widget.controller.stop();
      _addLog('Stop: $r');
    } catch (e) {
      _addLog('Error: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  void _refreshStatus() async {
    try {
      final s = await widget.controller.statusRaw();
      setState(() => _status = s);
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Panel de control')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton(onPressed: _busy ? null : _scan, child: const Text('Escanear redes')),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: _nets.length,
                itemBuilder: (_, i) {
                  final n = _nets[i];
                  return RadioListTile<int>(
                    title: Text('${n.num} - ${n.ssid}'),
                    subtitle: Text('${n.bssid}  Ch:${n.channel}  ${n.rssi}dBm  ${n.enc}'),
                    value: n.num,
                    groupValue: _selected,
                    onChanged: (v) => setState(() => _selected = v),
                  );
                },
              ),
            ),
            DropdownButtonFormField<String>(
              value: _reason,
              items: reasonCodes.keys
                  .map((k) => DropdownMenuItem(value: k, child: Text(k)))
                  .toList(),
              onChanged: (v) => setState(() => _reason = v!),
              decoration: const InputDecoration(labelText: 'Reason code'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: ElevatedButton(onPressed: _busy ? null : _deauthSingle, child: const Text('Deauth red'))),
                const SizedBox(width: 8),
                Expanded(child: ElevatedButton(onPressed: _busy ? null : _deauthAll, child: const Text('Deauth TODAS'))),
                const SizedBox(width: 8),
                Expanded(child: ElevatedButton(onPressed: _busy ? null : _stop, child: const Text('Detener'))),
              ],
            ),
            const SizedBox(height: 8),
            Text('Estado: $_status'),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(8),
                color: Colors.black12,
                child: SingleChildScrollView(child: Text(_log)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
