/// Non-web [PushGateway]: there is no browser Push API here.
///
/// Android and iOS get their pushes through FCM device tokens
/// (`NotificationService.registerToken`), not through this path, so the
/// honest answer on those platforms is "unsupported" and never a prompt.
library;

import 'push_gateway.dart';

class PlatformPushGateway implements PushGateway {
  @override
  PushPermission permission() => PushPermission.unsupported;

  @override
  Future<PushSubscription?> subscribe() async => null;
}
