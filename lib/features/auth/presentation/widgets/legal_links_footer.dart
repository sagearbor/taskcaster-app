import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/config/legal_links.dart';

/// Opens an external legal-page URL. Mirrors [SettingsScreen]'s
/// `_openLegalPage`: defaults to url_launcher, but accepts an override so
/// widget tests can assert which URL a link opens without touching the
/// platform channel.
Future<void> openLegalLink(
  BuildContext context,
  String url, {
  Future<void> Function(Uri uri)? openLink,
}) async {
  final uri = Uri.parse(url);
  final open =
      openLink ?? (Uri u) => launchUrl(u, mode: LaunchMode.externalApplication);
  try {
    await open(uri);
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not open $url')),
    );
  }
}

/// Small "Privacy Policy · Terms" footer for the pre-auth screens. There was
/// previously no link to either legal page anywhere in the auth flow.
class LegalLinksFooter extends StatelessWidget {
  const LegalLinksFooter({super.key, this.openLink});

  /// Overrides how a tapped link is opened; defaults to url_launcher.
  final Future<void> Function(Uri uri)? openLink;

  @override
  Widget build(BuildContext context) {
    final mutedColor = Theme.of(context).colorScheme.onSurfaceVariant;
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _FooterLink(
          label: 'Privacy Policy',
          url: LegalLinks.privacyPolicy,
          openLink: openLink,
        ),
        Text('·', style: TextStyle(color: mutedColor, fontSize: 12.5)),
        _FooterLink(
          label: 'Terms',
          url: LegalLinks.termsOfService,
          openLink: openLink,
        ),
      ],
    );
  }
}

class _FooterLink extends StatelessWidget {
  const _FooterLink({
    required this.label,
    required this.url,
    required this.openLink,
  });

  final String label;
  final String url;
  final Future<void> Function(Uri uri)? openLink;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
      ),
      onPressed: () => openLegalLink(context, url, openLink: openLink),
      child: Text(label),
    );
  }
}

/// "By creating an account you agree to our Terms and Privacy Policy" —
/// consent copy shown on the register screen, with the two legal pages as
/// inline links.
class LegalConsentText extends StatelessWidget {
  const LegalConsentText({super.key, this.openLink});

  final Future<void> Function(Uri uri)? openLink;

  @override
  Widget build(BuildContext context) {
    final mutedStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );
    final linkStyle = mutedStyle?.copyWith(
      color: Theme.of(context).colorScheme.primary,
      fontWeight: FontWeight.w700,
    );

    Widget link(String label, String url) => InkWell(
          onTap: () => openLegalLink(context, url, openLink: openLink),
          child: Text(label, style: linkStyle),
        );

    return Wrap(
      alignment: WrapAlignment.center,
      children: [
        Text('By creating an account you agree to our ', style: mutedStyle),
        link('Terms', LegalLinks.termsOfService),
        Text(' and ', style: mutedStyle),
        link('Privacy Policy', LegalLinks.privacyPolicy),
      ],
    );
  }
}
