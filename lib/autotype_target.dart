/// The Login the trigger will type (ADR-017): no picker, so no focus is
/// stolen. [clearIf] stops an older detail screen's dispose wiping a target a
/// newer screen registered.
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
