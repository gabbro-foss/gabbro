import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Hard-coded version string — updated manually when pubspec.yaml version
/// changes. Avoids the package_info_plus dependency for a value that changes
/// rarely and always coincides with other source edits.
const _kAppVersion = '0.1.0';

const _kGitHubUrl = 'https://github.com/Zabamund/gabbro';
const _kIssuesUrl = 'https://github.com/Zabamund/gabbro/issues';
const _kDonateUrl = 'https://github.com/sponsors/Zabamund';
const _kClaudeUrl = 'https://claude.ai';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('About Gabbro')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── App identity ────────────────────────────────────────────
              Text(
                'Gabbro',
                style: textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                'Version $_kAppVersion',
                style: textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                'A post-quantum password manager',
                style: textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              // ── Links ────────────────────────────────────────────────────
              _SectionHeader(label: 'Project'),
              _LinkTile(
                icon: Icons.code,
                label: 'Source code',
                url: _kGitHubUrl,
              ),
              _LinkTile(
                icon: Icons.bug_report_outlined,
                label: 'Report an issue',
                url: _kIssuesUrl,
              ),
              _LinkTile(
                icon: Icons.favorite_outline,
                label: 'Support Gabbro',
                url: _kDonateUrl,
              ),
              const SizedBox(height: 24),

              // ── Licence ──────────────────────────────────────────────────
              _SectionHeader(label: 'Licence'),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Gabbro is free and open source software, licensed under '
                  'the GNU General Public License v3.0 only (GPL-3.0-only).\n\n'
                  'You are free to use, study, and redistribute this software '
                  'under the terms of that licence.',
                  style: textTheme.bodyMedium,
                ),
              ),
              const SizedBox(height: 24),

              // ── Open source components ───────────────────────────────────
              _SectionHeader(label: 'Open source components'),
              ..._kComponents.map(
                (c) => _ComponentTile(
                  name: c.name,
                  licence: c.licence,
                  url: c.url,
                ),
              ),
              const SizedBox(height: 24),

              // ── Attribution ──────────────────────────────────────────────
              _SectionHeader(label: 'Attribution'),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'Project owner, architect, and lead developer:',
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
                  'AI development partner:',
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
                        'Gabbro makes no outbound network connections. '
                        'No telemetry, no analytics, no accounts.',
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
      builder: (context) => AlertDialog(
        title: Text(label),
        content: SelectableText(url),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('Open in browser'),
            onPressed: () async {
              final uri = Uri.parse(url);
              final launched = await launchUrl(
                uri,
                mode: LaunchMode.externalApplication,
              );
              if (!launched && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Could not open $url')),
                );
              }
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
        ],
      ),
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
        builder: (context) => AlertDialog(
          title: Text(name),
          content: SelectableText(url),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Open in browser'),
              onPressed: () async {
                final uri = Uri.parse(url);
                final launched = await launchUrl(
                  uri,
                  mode: LaunchMode.externalApplication,
                );
                if (!launched && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Could not open $url')),
                  );
                }
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
          ],
        ),
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
    name: 'Dart',
    licence: 'BSD-3-Clause',
    url: 'https://github.com/dart-lang/sdk',
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
    name: 'ml-kem',
    licence: 'Apache-2.0 / MIT',
    url: 'https://github.com/RustCrypto/KEMs',
  ),
  _Component(
    name: 'once_cell',
    licence: 'Apache-2.0 / MIT',
    url: 'https://github.com/matklad/once_cell',
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