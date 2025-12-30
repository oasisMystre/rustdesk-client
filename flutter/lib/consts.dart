import 'package:flutter_hbb/models/ffi_model.dart';

enum DesktopType {
  main("main"),
  cm("cm");

  const DesktopType(this.value);
  final String value;
}

enum GlobalOptions {
  key("key"),
  apiServer("api-server"),
  relayServer("relay-server"),
  approveMode("approve-mode"),
  stopService("stop-service"),
  directServer("direct-server"),
  enableAudio("enable-audio"),
  enableCamera("enable-camera"),
  enableTerminal("enable-terminal"),
  enableKeyboard("enable-keyboard"),
  enableUdpPunch("enable-udp-punch"),
  enableClipboard("enable-clipboard"),
  enableIpv6Punch("enable-ipv6-punch"),
  enableBlockInput("enable-block-input"),
  enableFileTranfer("enable-file-transfer"),
  enableTrustedDevices("enable-trusted-devices"),
  enableRemotePrinter("enable-remote-printer"),
  forceAlwaysRelay("force-always-relay"),
  verificationMethod("verification-method"),
  enableRemoteRestart("enable-remote-restart"),
  customRendezvousServer("custom-rendezvous-server");

  const GlobalOptions(this.value);

  final String value;
}

bool option2bool(GlobalOptions option, String value) {
  bool res;
  if (option.value.startsWith("enable-")) {
    res = value != "N";
  } else if (option.value.startsWith("allow-") ||
      option == GlobalOptions.stopService ||
      option == GlobalOptions.directServer ||
      option == GlobalOptions.forceAlwaysRelay) {
    res = value == "Y";
  } else {
    assert(false);
    res = value != "N";
  }
  return res;
}

String bool2option(GlobalOptions option, bool value) {
  String result;
  if (option.value.startsWith('enable-') &&
      option != GlobalOptions.enableUdpPunch &&
      option != GlobalOptions.enableIpv6Punch) {
    result = value ? 'Y' : 'N';
  } else if (option.value.startsWith('allow-') ||
      option == GlobalOptions.stopService ||
      option == GlobalOptions.directServer ||
      option == GlobalOptions.forceAlwaysRelay) {
    result = value ? 'Y' : 'N';
  } else {
    if (option != GlobalOptions.enableUdpPunch &&
        option != GlobalOptions.enableIpv6Punch) {
      assert(false);
    }
    result = value ? 'Y' : 'N';
  }
  return result;
}

Future<bool> mainGetBoolOption(GlobalOptions key) async {
  return option2bool(key, await bind.mainGetOption(key: key.value));
}

Future<void> mainSetBoolOption(GlobalOptions key, bool value) async {
  return await bind.mainSetOption(
      key: key.value, value: bool2option(key, value));
}
