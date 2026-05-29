import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:gabbro/l10n/app_localizations.dart';

enum _CharType { uppercase, lowercase, digit, symbol }

_CharType _classify(String ch) {
  if (RegExp(r'[A-Z]').hasMatch(ch)) return _CharType.uppercase;
  if (RegExp(r'[a-z]').hasMatch(ch)) return _CharType.lowercase;
  if (RegExp(r'[0-9]').hasMatch(ch)) return _CharType.digit;
  return _CharType.symbol;
}

const _kSymbol = {
  _CharType.uppercase: '▲',
  _CharType.lowercase: '▼',
  _CharType.digit: '●',
  _CharType.symbol: '■',
};

String _labelFor(_CharType t, AppLocalizations l) => switch (t) {
  _CharType.uppercase => l.charTypeUppercase,
  _CharType.lowercase => l.charTypeLowercase,
  _CharType.digit     => l.charTypeDigit,
  _CharType.symbol    => l.charTypeSymbol,
};

const _kExample = {
  _CharType.uppercase: 'A',
  _CharType.lowercase: 'a',
  _CharType.digit: '7',
  _CharType.symbol: r'$',
};

Color _colorFor(_CharType t, Brightness brightness) {
  final dark = brightness == Brightness.dark;
  return switch (t) {
    _CharType.uppercase => Color(dark ? 0xFF90CAF9 : 0xFF1565C0),
    _CharType.lowercase => Color(dark ? 0xFFA5D6A7 : 0xFF2E7D32),
    _CharType.digit     => Color(dark ? 0xFFFFAB40 : 0xFFE65100),
    _CharType.symbol    => Color(dark ? 0xFFCE93D8 : 0xFF6A1B9A),
  };
}

const _kFiraCode = TextStyle(fontFamily: 'FiraCode');

class PasswordBreakdownSheet extends StatefulWidget {
  const PasswordBreakdownSheet({super.key, required this.password});

  final String password;

  @override
  State<PasswordBreakdownSheet> createState() => _PasswordBreakdownSheetState();
}

class _PasswordBreakdownSheetState extends State<PasswordBreakdownSheet> {
  late final ScrollController _scrollController;
  bool _showLeft = false;
  bool _showRight = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_updateChevrons);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _updateChevrons() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final newLeft = pos.pixels > 0;
    final newRight = pos.pixels < pos.maxScrollExtent;
    if (newLeft != _showLeft || newRight != _showRight) {
      setState(() {
        _showLeft = newLeft;
        _showRight = newRight;
      });
    }
  }

  void _scrollByViewport(double direction) {
    if (!_scrollController.hasClients) return;
    final viewport = _scrollController.position.viewportDimension;
    final target = (_scrollController.offset + direction * viewport)
        .clamp(0.0, _scrollController.position.maxScrollExtent);
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
  }

  Widget _scrollChevron({
    required IconData icon,
    required Color primary,
    required Color onPrimary,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: primary,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 16, color: onPrimary),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final muted = cs.onSurfaceVariant;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Drag handle
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Container(
            width: 32,
            height: 4,
            decoration: BoxDecoration(
              color: muted.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        // Title
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            l.passwordBreakdownTitle,
            style: TextStyle(fontSize: 13, color: muted),
          ),
        ),
        // Character columns with chevron hints
        NotificationListener<ScrollMetricsNotification>(
          onNotification: (notification) {
            _updateChevrons();
            return false;
          },
          child: Row(
            children: [
              // Left chevron
              AnimatedOpacity(
                opacity: _showLeft ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 150),
                child: IgnorePointer(
                  ignoring: !_showLeft,
                  child: _scrollChevron(
                    icon: Icons.chevron_left,
                    primary: cs.primary,
                    onPrimary: cs.onPrimary,
                    onTap: () => _scrollByViewport(-1),
                  ),
                ),
              ),
              // Scrollable character row
              Expanded(
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context).copyWith(
                    dragDevices: {
                      PointerDeviceKind.touch,
                      PointerDeviceKind.mouse,
                    },
                  ),
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < widget.password.length; i++)
                          _CharColumn(
                            char: widget.password[i],
                            index: i,
                            brightness: brightness,
                            muted: muted,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              // Right chevron
              AnimatedOpacity(
                opacity: _showRight ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 150),
                child: IgnorePointer(
                  ignoring: !_showRight,
                  child: _scrollChevron(
                    icon: Icons.chevron_right,
                    primary: cs.primary,
                    onPrimary: cs.onPrimary,
                    onTap: () => _scrollByViewport(1),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Divider(thickness: 0.5, color: muted.withValues(alpha: 0.3)),
        // Legend
        Padding(
          padding: EdgeInsets.fromLTRB(
              16, 8, 16, 8 + MediaQuery.of(context).padding.bottom),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final t in _CharType.values)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: _LegendItem(type: t, brightness: brightness),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CharColumn extends StatelessWidget {
  const _CharColumn({
    required this.char,
    required this.index,
    required this.brightness,
    required this.muted,
  });

  final String char;
  final int index;
  final Brightness brightness;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final t = _classify(char);
    final color = _colorFor(t, brightness);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        children: [
          Text(char,
              style: _kFiraCode.copyWith(fontSize: 15, color: color)),
          Text(_kSymbol[t]!,
              style: TextStyle(fontSize: 10, color: color)),
          Text('$index',
              style: TextStyle(fontSize: 9, color: muted)),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.type, required this.brightness});

  final _CharType type;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final color = _colorFor(type, brightness);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(_kSymbol[type]!, style: TextStyle(fontSize: 12, color: color)),
        const SizedBox(width: 3),
        Text(_kExample[type]!,
            style: _kFiraCode.copyWith(fontSize: 12, color: color)),
        const SizedBox(width: 4),
        Text(_labelFor(type, l), style: const TextStyle(fontSize: 11)),
      ],
    );
  }
}