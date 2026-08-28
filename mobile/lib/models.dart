class Network {
  final int num;
  final String ssid;
  final String bssid;
  final int channel;
  final int rssi;
  final String enc;

  Network({
    required this.num,
    required this.ssid,
    required this.bssid,
    required this.channel,
    required this.rssi,
    required this.enc,
  });

  factory Network.fromJson(Map<String, dynamic> j) => Network(
        num: j['num'] ?? 0,
        ssid: j['ssid'] ?? '',
        bssid: j['bssid'] ?? '',
        channel: j['channel'] ?? 0,
        rssi: j['rssi'] ?? 0,
        enc: j['enc'] ?? '',
      );
}

const Map<String, int> reasonCodes = {
  '0 - Reserved': 0,
  '1 - Unspecified reason': 1,
  '2 - Previous authentication no longer valid': 2,
  '3 - Station leaving/departing IBSS or ESS': 3,
  '4 - Disassociated due to inactivity': 4,
  '5 - Disassociated because AP too busy': 5,
  '6 - Class 2 frame from nonauthenticated STA': 6,
  '7 - Class 3 frame from nonassociated STA': 7,
  '8 - Disassociated because STA leaving BSS': 8,
  '9 - STA requesting (re)assoc is not authenticated': 9,
  '10 - Disassociated: Power Capability unacceptable': 10,
  '11 - Disassociated: Supported Channels unacceptable': 11,
  '12 - Disassociated due to BSS Transition Mgmt': 12,
  '13 - Invalid element': 13,
  '14 - Message integrity code (MIC) failure': 14,
  '15 - 4-Way Handshake timeout': 15,
  '16 - Group Key Handshake timeout': 16,
  '17 - Handshake different from (Re)Assoc/Probe/Beacon': 17,
  '18 - Invalid group cipher': 18,
  '19 - Invalid pairwise cipher': 19,
  '20 - Invalid AKMP': 20,
  '21 - Unsupported RSNE version': 21,
  '22 - Invalid RSNE capabilities': 22,
  '23 - IEEE 802.1X authentication failed': 23,
  '24 - Cipher suite rejected by policy': 24,
};
