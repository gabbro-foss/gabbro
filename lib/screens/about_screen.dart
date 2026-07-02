import 'package:flutter/material.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/widgets/gabbro_logo.dart';
import 'package:url_launcher/url_launcher.dart';

/// Injected at build time from `pubspec.yaml` (build metadata stripped) via
/// `--dart-define=APP_VERSION=...` — see BUILD_AND_RELEASE.md. No dependency,
/// no manual drift. Local/dev builds (no define) show "dev".
const _kAppVersion = String.fromEnvironment('APP_VERSION', defaultValue: 'dev');

const _kGitHubUrl = 'https://github.com/Zabamund/gabbro';
const _kIssuesUrl = 'https://github.com/Zabamund/gabbro/issues';
const _kDonateUrl = 'https://github.com/sponsors/Zabamund';
const _kClaudeUrl = 'https://claude.ai';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(l.aboutTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── App identity ────────────────────────────────────────────
              Center(child: GabbroLogo(withText: true, width: 200)),
              const SizedBox(height: 4),
              Text(
                l.aboutVersion(_kAppVersion),
                style: textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                l.aboutTagline,
                style: textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              // ── Links ────────────────────────────────────────────────────
              _SectionHeader(label: l.aboutProjectSection),
              _LinkTile(
                icon: Icons.code,
                label: l.aboutSourceCode,
                url: _kGitHubUrl,
              ),
              _LinkTile(
                icon: Icons.bug_report_outlined,
                label: l.aboutReportIssue,
                url: _kIssuesUrl,
              ),
              _LinkTile(
                icon: Icons.favorite_outline,
                label: l.aboutSupportGabbro,
                url: _kDonateUrl,
              ),
              const SizedBox(height: 24),

              // ── Licence ──────────────────────────────────────────────────
              _SectionHeader(label: l.aboutLicenceSection),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  l.aboutLicenceBody,
                  style: textTheme.bodyMedium,
                ),
              ),
              const SizedBox(height: 24),

              // ── Open source components ───────────────────────────────────
              _SectionHeader(label: l.aboutOpenSourceSection),
              ..._kComponents.map(
                (c) => _ComponentTile(
                  name: c.name,
                  licence: c.licence,
                  url: c.url,
                ),
              ),
              const SizedBox(height: 24),

              // ── Attribution ──────────────────────────────────────────────
              _SectionHeader(label: l.aboutAttributionSection),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  l.aboutOwnerRole,
                  style: textTheme.bodyMedium,
                ),
              ),
              _LinkTile(
                icon: Icons.person_outline,
                label: 'Zabamund',
                url: 'https://github.com/Zabamund',
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  l.aboutAiPartner,
                  style: textTheme.bodyMedium,
                ),
              ),
              _LinkTile(
                icon: Icons.smart_toy_outlined,
                label: 'Claude (Anthropic)',
                url: _kClaudeUrl,
              ),
              const SizedBox(height: 32),

              // ── No telemetry notice ──────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      size: 18,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l.aboutNoTelemetry,
                        style: textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Section header ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}

// ── Link tile — displays a URL as a tappable row ─────────────────────────────
// Tapping shows a dialog with the URL as SelectableText (copy-friendly) and
// an explicit "Open in browser" button. Two-step confirmation: the user sees
// the URL before the browser opens. Uses url_launcher with externalApplication
// mode — opens the system browser, no in-app webview.

class _LinkTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String url;

  const _LinkTile({
    required this.icon,
    required this.label,
    required this.url,
  });

  Future<void> _showUrl(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        final l = AppLocalizations.of(context);
        return AlertDialog(
          title: Text(label),
          content: SelectableText(url),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l.close),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.open_in_new, size: 16),
              label: Text(l.openInBrowser),
              onPressed: () async {
                final uri = Uri.parse(url);
                final launched = await launchUrl(
                  uri,
                  mode: LaunchMode.externalApplication,
                );
                if (!launched && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(AppLocalizations.of(context).couldNotOpen(url))),
                  );
                }
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(label),
      subtitle: Text(
        url,
        style: Theme.of(context).textTheme.bodySmall,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => _showUrl(context),
    );
  }
}

// ── Component tile ───────────────────────────────────────────────────────────

class _ComponentTile extends StatelessWidget {
  final String name;
  final String licence;
  final String url;

  const _ComponentTile({
    required this.name,
    required this.licence,
    required this.url,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(name),
      subtitle: Text(licence),
      trailing: Icon(
        Icons.open_in_new,
        size: 16,
        color: Theme.of(context).colorScheme.outline,
      ),
      onTap: () => showDialog<void>(
        context: context,
        builder: (context) {
          final l = AppLocalizations.of(context);
          return AlertDialog(
            title: Text(name),
            content: SelectableText(url),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l.close),
              ),
              FilledButton.icon(
                icon: const Icon(Icons.open_in_new, size: 16),
                label: Text(l.openInBrowser),
                onPressed: () async {
                  final uri = Uri.parse(url);
                  final launched = await launchUrl(
                    uri,
                    mode: LaunchMode.externalApplication,
                  );
                  if (!launched && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(AppLocalizations.of(context).couldNotOpen(url))),
                    );
                  }
                  if (context.mounted) Navigator.of(context).pop();
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Component data ───────────────────────────────────────────────────────────

class _Component {
  final String name;
  final String licence;
  final String url;
  const _Component({
    required this.name,
    required this.licence,
    required this.url,
  });
}

const _kComponents = [
  _Component(
    name: 'aes-gcm',
    licence: 'Apache-2.0 / MIT',
    url: 'https://github.com/RustCrypto/AEADs',
  ),
  _Component(
    name: 'argon2',
    licence: 'Apache-2.0 / MIT',
    url: 'https://github.com/RustCrypto/password-hashes',
  ),
  _Component(
    name: 'base64',
    licence: 'Apache-2.0 / MIT',
    url: 'https://github.com/marshallpierce/rust-base64',
  ),
  _Component(
    name: 'BIP-39 wordlists (ja, ko, zh-TW)',
    licence: 'MIT',
    url: 'https://github.com/trezor/python-mnemonic',
  ),
  _Component(
    name: 'ChineseWordDiceware (zh-CN)',
    licence: 'CC-BY-4.0',
    url: 'https://github.com/cfbao/ChineseWordDiceware',
  ),
  _Component(
    name: 'Dart',
    licence: 'BSD-3-Clause',
    url: 'https://github.com/dart-lang/sdk',
  ),
  _Component(
    name: 'diceware-wordlist-bg',
    licence: 'CC-BY-4.0',
    url: 'https://github.com/assenv/diceware-wordlist-bg',
  ),
  _Component(
    name: 'Diceware-word-lists (et, uk)',
    licence: 'CC-BY-4.0',
    url: 'https://github.com/agreinhold/Diceware-word-lists',
  ),
  _Component(
    name: 'file_picker',
    licence: 'MIT',
    url: 'https://github.com/miguelpruivo/flutter_file_picker',
  ),
  _Component(
    name: 'Fira Code',
    licence: 'SIL OFL 1.1',
    url: 'https://github.com/tonsky/FiraCode',
  ),
  _Component(
    name: 'Flutter',
    licence: 'BSD-3-Clause',
    url: 'https://github.com/flutter/flutter',
  ),
  _Component(
    name: 'flutter_rust_bridge',
    licence: 'MIT',
    url: 'https://github.com/fzyzcjy/flutter_rust_bridge',
  ),
  _Component(
    name: 'FrequencyWords (hr, lt, lv, kk)',
    licence: 'CC-BY-SA 4.0',
    url: 'https://github.com/hermitdave/FrequencyWords',
  ),
  _Component(
    name: 'freezed_annotation',
    licence: 'MIT',
    url: 'https://github.com/rrousselGit/freezed',
  ),
  _Component(
    name: 'hkdf',
    licence: 'Apache-2.0 / MIT',
    url: 'https://github.com/RustCrypto/KDFs',
  ),
  _Component(
    name: 'intl',
    licence: 'BSD-3-Clause',
    url: 'https://github.com/dart-lang/i18n',
  ),
  _Component(
    name: 'jni',
    licence: 'MIT',
    url: 'https://github.com/jni-rs/jni-rs',
  ),
  _Component(
    name: 'libfido2-sys',
    licence: 'BSD-2-Clause',
    url: 'https://github.com/Yubico/libfido2',
  ),
  _Component(
    name: 'ml-kem',
    licence: 'Apache-2.0 / MIT',
    url: 'https://github.com/RustCrypto/KEMs',
  ),
  _Component(
    name: 'path_provider',
    licence: 'BSD-3-Clause',
    url: 'https://github.com/flutter/packages',
  ),
  _Component(
    name: 'rand',
    licence: 'Apache-2.0 / MIT',
    url: 'https://github.com/rust-random/rand',
  ),
  _Component(
    name: 'Rust',
    licence: 'Apache-2.0 / MIT',
    url: 'https://github.com/rust-lang/rust',
  ),
  _Component(
    name: 'scrollable_positioned_list',
    licence: 'BSD-3-Clause',
    url: 'https://github.com/google/flutter.widgets',
  ),
  _Component(
    name: 'serde / serde_json',
    licence: 'Apache-2.0 / MIT',
    url: 'https://github.com/serde-rs/serde',
  ),
  _Component(
    name: 'sha2',
    licence: 'Apache-2.0 / MIT',
    url: 'https://github.com/RustCrypto/hashes',
  ),
  _Component(
    name: 'url_launcher',
    licence: 'BSD-3-Clause',
    url: 'https://github.com/flutter/packages',
  ),
  _Component(
    name: 'uuid',
    licence: 'Apache-2.0 / MIT',
    url: 'https://github.com/uuid-rs/uuid',
  ),
  _Component(
    name: 'x25519-dalek',
    licence: 'BSD-3-Clause',
    url: 'https://github.com/dalek-cryptography/x25519-dalek',
  ),
  _Component(
    name: 'zeroize',
    licence: 'Apache-2.0 / MIT',
    url: 'https://github.com/RustCrypto/utils',
  ),
];