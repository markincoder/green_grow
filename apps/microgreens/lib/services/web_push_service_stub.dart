Future<String> webPushDeviceId() async => '';

bool get webPushIsSupported => false;

Future<bool> webPushEnsureSubscribed() async => false;

Future<void> webPushUnsubscribe() async {}

Future<void> webPushSyncSchedule(
  List<dynamic> items, {
  List<String> ackIds = const [],
}) async {}

void webPushShowSetup() {}

void webPushHideSetup() {}

void webPushMarkFlutterReady() {}

void webPushSignalNotifyFlowDone(bool granted) {}

bool webPushPermissionGranted() => false;

String webPushPermissionStatus() => 'denied';

void webPushOnNotifyGranted(void Function() callback) {}

void webPushOnAskNotify(void Function() callback) {}
