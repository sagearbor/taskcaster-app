import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/invite/invite_link_parser.dart';

/// Six boxed character cells for entering a TaskCaster invite code.
///
/// One real (invisible) [TextField] backs the six painted cells, so focus,
/// the software keyboard, paste and backspace all behave natively:
///
///  * input is auto-uppercased and filtered to letters+digits;
///  * pasting a bare code ("abc234"), a code with separators ("ABC-234") or a
///    full invite URL/deep link (parsed with [InviteLinks]) fills the cells;
///  * [onCompleted] fires once when the 6th character lands (auto-submit);
///  * backspace empties the last filled cell and moves the active cell back.
///
/// Reusable anywhere a 6-char code is typed; currently used by the join-game
/// screen. Pass a [controller] to read/prefill the value from outside.
class SixCharCodeField extends StatefulWidget {
  final TextEditingController? controller;

  /// Called once when the 6th character is entered, with the full code.
  final ValueChanged<String>? onCompleted;

  /// Called on every change with the current (normalized) text.
  final ValueChanged<String>? onChanged;

  final bool enabled;
  final bool autofocus;

  const SixCharCodeField({
    super.key,
    this.controller,
    this.onCompleted,
    this.onChanged,
    this.enabled = true,
    this.autofocus = false,
  });

  static const int length = InviteLinks.codeLength;

  /// Normalizes any raw input — typed characters, a pasted code, or a pasted
  /// invite URL / deep link — into at most [length] uppercase letters+digits.
  ///
  /// URL forms are resolved through [InviteLinks] first (canonical join links
  /// and taskcaster:// deep links), falling back to any `code`/`invite_code`
  /// query parameter, then to stripping the text down to letters and digits.
  static String normalizeInput(String raw) {
    var text = raw.trim();

    // A pasted URL / deep link: pull the code out of it (or drop the URL
    // entirely if it carries none — a link is never literal code input).
    final urlMatch =
        RegExp(r'[A-Za-z][A-Za-z0-9+.-]*://\S+').firstMatch(text);
    if (urlMatch != null) {
      final url = urlMatch.group(0)!;
      final uri = Uri.tryParse(url);
      if (uri != null) {
        final fromLink = InviteLinks.codeFromUri(uri) ??
            InviteLinks.normalizeCode(uri.queryParameters['code']) ??
            InviteLinks.normalizeCode(uri.queryParameters['invite_code']);
        if (fromLink != null) return fromLink;
      }
      text = text.replaceAll(url, '');
    } else if (text.contains('=')) {
      // Pasted query-string fragment, e.g. "code=ABC234" or an install
      // referrer's "invite_code=ABC234&utm_source=…".
      try {
        final params = Uri.splitQueryString(text);
        final fromParams = InviteLinks.normalizeCode(params['code']) ??
            InviteLinks.normalizeCode(params['invite_code']);
        if (fromParams != null) return fromParams;
      } on ArgumentError {
        // Not a query string — fall through to plain cleaning.
      }
    }

    final cleaned = text.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
    return cleaned.length > length ? cleaned.substring(0, length) : cleaned;
  }

  @override
  State<SixCharCodeField> createState() => _SixCharCodeFieldState();
}

class _SixCharCodeFieldState extends State<SixCharCodeField> {
  late final TextEditingController _controller;
  late final bool _ownsController;
  final FocusNode _focusNode = FocusNode();

  /// The last value [widget.onCompleted] fired for, so edits after a complete
  /// code can re-trigger submission but rebuilds can't double-fire it.
  String? _lastSubmitted;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? TextEditingController();
    _controller.addListener(_handleChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_handleChanged);
    if (_ownsController) _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleChanged() {
    final text = _controller.text;
    widget.onChanged?.call(text);
    if (text.length == SixCharCodeField.length && text != _lastSubmitted) {
      _lastSubmitted = text;
      widget.onCompleted?.call(text);
    } else if (text.length < SixCharCodeField.length) {
      _lastSubmitted = null;
    }
    // Repaint the cells.
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final text = _controller.text;
    final activeIndex = text.length.clamp(0, SixCharCodeField.length - 1);
    final hasFocus = _focusNode.hasFocus;

    return Stack(
      children: [
        // The real input: invisible but full-size so taps focus it and the
        // keyboard, paste menu and backspace work exactly like a TextField.
        Positioned.fill(
          child: Opacity(
            opacity: 0,
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              enabled: widget.enabled,
              autofocus: widget.autofocus,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.visiblePassword,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.done,
              inputFormatters: [_CodeInputFormatter()],
              showCursor: false,
            ),
          ),
        ),
        // The six painted cells.
        IgnorePointer(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < SixCharCodeField.length; i++) ...[
                if (i > 0) SizedBox(width: i == 3 ? 14 : 8),
                _CodeCell(
                  char: i < text.length ? text[i] : null,
                  active: widget.enabled && hasFocus && i == activeIndex,
                  enabled: widget.enabled,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Uppercases, strips non-alphanumerics, resolves pasted invite URLs and caps
/// the value at six characters (see [SixCharCodeField.normalizeInput]).
class _CodeInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final normalized = SixCharCodeField.normalizeInput(newValue.text);
    return TextEditingValue(
      text: normalized,
      selection: TextSelection.collapsed(offset: normalized.length),
    );
  }
}

class _CodeCell extends StatelessWidget {
  final String? char;
  final bool active;
  final bool enabled;

  const _CodeCell({required this.char, required this.active, required this.enabled});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 46,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: enabled
            ? scheme.primaryContainer.withOpacity(active ? 0.85 : 0.5)
            : scheme.onSurface.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: active ? scheme.primary : Colors.transparent,
          width: 2,
        ),
      ),
      child: char != null
          ? Text(
              char!,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: scheme.onSurface,
                  ),
            )
          : null,
    );
  }
}
