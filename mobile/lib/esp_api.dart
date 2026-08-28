import 'dart:convert';
import 'package:http/http.dart' as http;
import 'models.dart';
import 'controller.dart';

/// Controlador para hablar con el ESP32 por HTTP (WiFi).
/// Requiere login previo para obtener el token.
class WifiController implements DeautherController {
  final String ip;
  String? token;

  WifiController(this.ip);

  String get base => 'http://$ip';

  Future<void> login(String user, String pass) async {
    final r = await http
        .post(Uri.parse('$base/api/login'),
            body: {'user': user, 'pass': pass})
        .timeout(const Duration(seconds: 8));
    if (r.statusCode != 200) {
      throw Exception('Credenciales incorrectas');
    }
    token = jsonDecode(r.body)['token'];
  }

  Map<String, String> get _q => {'token': token ?? ''};

  Future<List<Network>> scan() async {
    final r = await http
        .get(Uri.parse('$base/api/scan').replace(queryParameters: _q))
        .timeout(const Duration(seconds: 12));
    final List l = jsonDecode(r.body);
    return l.map((e) => Network.fromJson(e)).toList();
  }

  Future<String> deauthSingle(int net, int reason) async {
    await http.post(Uri.parse('$base/api/deauth').replace(queryParameters: _q),
        body: {'net_num': '$net', 'reason': '$reason'});
    return 'OK';
  }

  Future<String> deauthAll(int reason) async {
    await http.post(Uri.parse('$base/api/deauth_all').replace(queryParameters: _q),
        body: {'reason': '$reason'});
    return 'OK';
  }

  Future<String> stop() async {
    await http.post(Uri.parse('$base/api/stop').replace(queryParameters: _q));
    return 'OK';
  }

  Future<Map<String, dynamic>> status() async {
    final r = await http
        .get(Uri.parse('$base/api/status').replace(queryParameters: _q));
    return jsonDecode(r.body);
  }

  Future<String> statusRaw() async => jsonEncode(await status());
}
