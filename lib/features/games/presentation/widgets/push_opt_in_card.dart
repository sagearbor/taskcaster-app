import 'package:flutter/material.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/services/push/web_push_service.dart';
import '../../../auth/domain/repositories/auth_repository.dart';

/// "Want a ping when someone grades this?" — shown on the Posted screen,
/// after the player's first post and nowhere else.
///
/// Timing is the whole point. The browser gives an app exactly ONE chance to
/// ask: say no and it will not re-prompt, ever, on that origin. Asking at app
/// start (which is when Android's notification dialog used to fire — see
/// NotificationPrompt) means asking someone who has not yet seen a single
/// clip. Asking here means asking someone who has just posted and now has a
/// reason to care whether anyone graded it.
///
/// Renders nothing at all unless the browser can do push AND has not already
/// been answered, so it never appears on mobile builds, on Safari without
/// push, or to someone who already opted in or out.
class PushOptInCard extends StatefulWidget {
  /// Injectable for tests; defaults to the real service.
  final WebPushService? service;

  const PushOptInCard({super.key, this.service});

  /// Once per process: having declined on one Posted screen, the player should
  /// not be asked again on the next task's.
  static bool _dismissedThisSession = false;

  /// Test hook — the flag above is static and would otherwise leak between
  /// widget tests.
  @visibleForTesting
  static void resetForTest() => _dismissedThisSession = false;

  @override
  State<PushOptInCard> createState() => _PushOptInCardState();
}

enum _CardState { offering, working, enabled, dismissed }

class _PushOptInCardState extends State<PushOptInCard> {
  late final WebPushService _service = widget.service ?? WebPushService();
  _CardState _state = _CardState.offering;
  bool _failed = false;

  Future<void> _enable() async {
    final uid = sl<AuthRepository>().getCurrentUserId();
    if (uid == null || uid.isEmpty) {
      setState(() => _failed = true);
      return;
    }
    setState(() {
      _state = _CardState.working;
      _failed = false;
    });
    final result = await _service.enable(uid);
    if (!mounted) return;
    setState(() {
      switch (result) {
        case PushOptInResult.enabled:
          _state = _CardState.enabled;
        case PushOptInResult.declined:
        case PushOptInResult.unsupported:
          // The browser said no (or cannot). Re-offering would be nagging
          // that cannot possibly work.
          _state = _CardState.dismissed;
          PushOptInCard._dismissedThisSession = true;
        case PushOptInResult.failed:
          _state = _CardState.offering;
          _failed = true;
      }
    });
  }

  void _dismiss() {
    PushOptInCard._dismissedThisSession = true;
    setState(() => _state = _CardState.dismissed);
  }

  @override
  Widget build(BuildContext context) {
    if (_state == _CardState.dismissed) return const SizedBox.shrink();
    if (_state == _CardState.enabled) {
      return _frame(
        child: const Row(
          children: [
            Icon(Icons.notifications_active, color: Colors.white, size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                "Nice — we'll ping you when someone grades it.",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
    }

    // Offering / working. Hidden entirely when there is nothing to offer:
    // already said no this session, or the browser cannot be asked (no push
    // support, or permission already granted/denied for this origin).
    if (PushOptInCard._dismissedThisSession) return const SizedBox.shrink();
    if (!_service.canPrompt) return const SizedBox.shrink();

    final working = _state == _CardState.working;
    return _frame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Want a ping when someone grades this?',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _failed
                ? "That didn't take — you can try again."
                : 'One notification per clip. Nothing else, ever.',
            style: TextStyle(
              color: _failed ? Colors.amberAccent : Colors.white70,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: working ? null : _enable,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.deepPurple,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: working
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Notify me',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 10),
              TextButton(
                onPressed: working ? null : _dismiss,
                style: TextButton.styleFrom(foregroundColor: Colors.white70),
                child: const Text('No thanks'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _frame({required Widget child}) => Container(
        margin: const EdgeInsets.only(top: 20),
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white24),
        ),
        child: child,
      );
}
