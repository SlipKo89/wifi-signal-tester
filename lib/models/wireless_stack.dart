/// The four Wi-Fi subsystems a MikroTik can expose. We probe for them in this
/// order and read the registration table from whichever one answers.
enum WirelessStack {
  /// RouterOS 7 WifiWave2: `/interface/wifi`
  wifiWave2,

  /// RouterOS 7 CAPsMAN on the new stack: `/interface/wifi/capsman`
  capsmanNew,

  /// Legacy CAPsMAN: `/caps-man`
  capsmanLegacy,

  /// Classic wireless: `/interface/wireless`
  wireless,
}

extension WirelessStackPaths on WirelessStack {
  /// Menu path of the registration table for this stack.
  String get registrationPath {
    switch (this) {
      case WirelessStack.wifiWave2:
        return '/interface/wifi/registration-table';
      case WirelessStack.capsmanNew:
        return '/interface/wifi/capsman/registration-table';
      case WirelessStack.capsmanLegacy:
        return '/caps-man/registration-table';
      case WirelessStack.wireless:
        return '/interface/wireless/registration-table';
    }
  }

  String get label {
    switch (this) {
      case WirelessStack.wifiWave2:
        return 'WifiWave2';
      case WirelessStack.capsmanNew:
        return 'CAPsMAN (wifi)';
      case WirelessStack.capsmanLegacy:
        return 'CAPsMAN (legacy)';
      case WirelessStack.wireless:
        return 'Wireless';
    }
  }
}

/// Detection order: newest and most centralized first.
const List<WirelessStack> kStackProbeOrder = [
  WirelessStack.capsmanNew,
  WirelessStack.wifiWave2,
  WirelessStack.capsmanLegacy,
  WirelessStack.wireless,
];
