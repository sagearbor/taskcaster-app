import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Small helpers for opening external links (video submissions, invite links)
/// and copying text to the clipboard, with consistent user feedback.
class LinkUtils {
  /// Whether [input] looks like a usable http(s) link.
  ///
  /// Deliberately permissive about *where* the video is hosted (players use
  /// YouTube, Google Photos, Drive, Dropbox, ...) but strict that it is a
  /// real web URL: http/https scheme, a plausible host, and no spaces.
  static bool isLikelyUrl(String? input) {
    final trimmed = input?.trim() ?? '';
    if (trimmed.isEmpty) return false;
    if (trimmed.contains(' ')) return false;

    final uri = Uri.tryParse(trimmed);
    if (uri == null) return false;
    if (uri.scheme != 'http' && uri.scheme != 'https') return false;
    // A real host has at least one dot ("youtu.be", "photos.google.com").
    return uri.host.contains('.');
  }

  /// Friendly description of what's wrong with a pasted link, or null when
  /// [input] is empty (nothing to complain about yet) or a valid URL.
  static String? describeUrlProblem(String? input) {
    final trimmed = input?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    if (isLikelyUrl(trimmed)) return null;

    if (trimmed.contains(' ')) {
      return "Links can't contain spaces — double-check what you pasted.";
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme) {
      // They probably pasted "youtube.com/watch?v=..." without the scheme.
      if (isLikelyUrl('https://$trimmed')) {
        return 'Almost! Add https:// to the front of that link.';
      }
      return "That doesn't look like a link yet — paste the full share URL.";
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return 'Only web links (starting with http:// or https://) work here.';
    }
    return "That doesn't look like a valid link — paste the full share URL.";
  }

  /// Opens [url] in an external browser/app. Surfaces a SnackBar if the link
  /// is missing, malformed, or cannot be launched.
  static Future<void> openExternal(BuildContext context, String? url) async {
    final messenger = ScaffoldMessenger.of(context);
    final trimmed = url?.trim() ?? '';
    if (trimmed.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('No link to open')));
      return;
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null || !(uri.hasScheme && uri.hasAuthority)) {
      messenger.showSnackBar(const SnackBar(content: Text('Invalid link')));
      return;
    }

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) {
      messenger.showSnackBar(SnackBar(content: Text('Could not open $trimmed')));
    }
  }

  /// Copies [text] to the clipboard and confirms with a SnackBar.
  static Future<void> copyToClipboard(
    BuildContext context,
    String text, {
    String label = 'Copied',
  }) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label to clipboard')),
      );
    }
  }
}
