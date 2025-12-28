import 'package:get/get.dart';
import 'package:flutter_hbb/models/ffi_model.dart';


enum ClientType {
  remote,
  file,
  camera,
  portForward,
  terminal,
}

class Client {
  int id = 0;
  bool file = false;
  String peerId = "";
  bool audio = false;
  bool restart = false;
  bool keyboard = false;
  bool clipboard = false;
  bool isTerminal = false;
  bool recording = false;
  bool blockInput = false;
  bool authorized = false;
  bool disconnected = false;
  bool fromSwitch = false;
  bool inVoiceCall = false;
  bool isViewCamera = false;
  bool isFileTransfer = false;
  bool incomingVoiceCall = false;

  String name = "";
  String portForward = "";

  RxInt unreadChatMessageCount = 0.obs;

  Client(this.id, this.authorized, this.isFileTransfer, this.isViewCamera,
      this.name, this.peerId, this.keyboard, this.clipboard, this.audio);

  Client.fromJson(Map<String, dynamic> json) {
    id = json['id'];
    file = json['file'];
    name = json['name'];
    audio = json['audio'];
    peerId = json['peer_id'];
    restart = json['restart'];
    keyboard = json['keyboard'];
    clipboard = json['clipboard'];
    recording = json['recording'];
    fromSwitch = json['from_switch'];
    authorized = json['authorized'];
    blockInput = json['block_input'];
    portForward = json['port_forward'];
    disconnected = json['disconnected'];
    inVoiceCall = json['in_voice_call'];
    isViewCamera = json['is_view_camera'];
    isTerminal = json['is_terminal'] ?? false;
    isFileTransfer = json['is_file_transfer'];
    incomingVoiceCall = json['incoming_voice_call'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['id'] = id;
    data['file'] = file;
    data['name'] = name;
    data['audio'] = audio;

    data['restart'] = restart;
    data['peer_id'] = peerId;
    data['keyboard'] = keyboard;
    data['recording'] = recording;
    data['clipboard'] = clipboard;
    data['authorized'] = authorized;
    data['is_terminal'] = isTerminal;
    data['from_switch'] = fromSwitch;
    data['block_input'] = blockInput;
    data['port_forward'] = portForward;
    data['disconnected'] = disconnected;
    data['in_voice_call'] = inVoiceCall;
    data['is_view_camera'] = isViewCamera;
    data['is_file_transfer'] = isFileTransfer;
    data['incoming_voice_call'] = incomingVoiceCall;
    return data;
  }

  ClientType type_() {
    if (isFileTransfer) {
      return ClientType.file;
    } else if (isViewCamera) {
      return ClientType.camera;
    } else if (isTerminal) {
      return ClientType.terminal;
    } else if (portForward.isNotEmpty) {
      return ClientType.portForward;
    } else {
      return ClientType.remote;
    }
  }

  void handleVoiceCall(bool accept) {
    bind.cmHandleIncomingVoiceCall(id: id, accept: accept);
  }

  void handleSwitchBack() {
    bind.cmSwitchBack(connId: id);
  }

  Future<void> handleClose() async {
    await bind.cmRemoveDisconnectedConnection(connId: id);
  }

  void closeVoiceCall() {
    bind.cmCloseVoiceCall(id: id);
  }

  void handleElevate() {
    bind.cmElevatePortable(connId: id);
  }

  void handleDisconnect() {
    bind.cmCloseConnection(connId: id);
  }
}
