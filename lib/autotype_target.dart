/// Holds the Login whose secret the Linux auto-type trigger should type
/// (ADR-017, per-entry direct-type). The user opens a Login in Gabbro, which
/// registers it here; on trigger the listener reads it and fills that login
/// into the focused window. No picker, so no focus is stolen.
///
/// [clearIf] exists so an older detail screen closing (dispose) does not wipe a
/// target a newer screen has since registered.
class AutotypeTarget {
  String? _loginId;

  /// The id of the Login to type, or `null` when nothing is designated
  /// (no Login open, or the vault has locked).
  String? get loginId => _loginId;

  void setLogin(String id) => _loginId = id;

  void clear() => _loginId = null;

  /// Clear only if [id] is the current target.
  void clearIf(String id) {
    if (_loginId == id) _loginId = null;
  }
}

/// App-wide target shared by the detail screen (which sets it), the lock flow
/// (which clears it), and the auto-type listener (which reads it).
final autotypeTarget = AutotypeTarget();
