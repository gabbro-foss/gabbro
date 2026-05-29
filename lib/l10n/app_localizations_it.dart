// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class AppLocalizationsIt extends AppLocalizations {
  AppLocalizationsIt([String locale = 'it']) : super(locale);

  @override
  String get appName => 'Gabbro';

  @override
  String get cancel => 'Cancel';

  @override
  String get delete => 'Delete';

  @override
  String get save => 'Save';

  @override
  String get close => 'Close';

  @override
  String get ok => 'OK';

  @override
  String get edit => 'Edit';

  @override
  String get add => 'Add';

  @override
  String get remove => 'Remove';

  @override
  String get rename => 'Rename';

  @override
  String get confirm => 'Confirm';

  @override
  String get continueAction => 'Continue';

  @override
  String get dismiss => 'Dismiss';

  @override
  String get authorize => 'Authorize';

  @override
  String get register => 'Register';

  @override
  String get sync => 'Sync';

  @override
  String get assign => 'Assign';

  @override
  String get unlock => 'Unlock';

  @override
  String get generate => 'Generate';

  @override
  String get import => 'Import';

  @override
  String get export => 'Export';

  @override
  String get openInBrowser => 'Open in browser';

  @override
  String get useThisPassword => 'Use this password';

  @override
  String get reviewArrow => 'Review →';

  @override
  String get skip => 'Skip';

  @override
  String get keep => 'Keep';

  @override
  String get revert => 'Revert';

  @override
  String get next => 'Next: map columns';

  @override
  String get syncFromVault => 'Sync from vault';

  @override
  String get createVault => 'Create vault';

  @override
  String get pickFile => 'Pick file';

  @override
  String get chooseFolder => 'Choose folder';

  @override
  String get addCustomField => 'Add custom field';

  @override
  String get exportFile => 'Export file';

  @override
  String get addVault => 'Add vault';

  @override
  String get addYubiKey => 'Add YubiKey';

  @override
  String get noChangesToSave => 'No changes to save.';

  @override
  String get appearanceTitle => 'Aspetto';

  @override
  String get securityTitle => 'Security';

  @override
  String get aboutTitle => 'About Gabbro';

  @override
  String get generatorTitle => 'Password generator';

  @override
  String get importTitle => 'Import entries';

  @override
  String get exportTitle => 'Export vault';

  @override
  String get changePassphraseTitle => 'Change passphrase';

  @override
  String get csvMappingTitle => 'Map CSV columns';

  @override
  String get manageFoldersTitle => 'Manage folders';

  @override
  String get manageVaultsTitle => 'Manage vaults';

  @override
  String get manageYubiKeysTitle => 'Manage YubiKeys';

  @override
  String get passwordHistoryTitle => 'Password history';

  @override
  String get reviewChangesTitle => 'Review changes';

  @override
  String get unlockGabbroTitle => 'Unlock Gabbro';

  @override
  String get sectionTheme => 'Theme';

  @override
  String get sectionTextSize => 'Text size';

  @override
  String get sectionAlphabetBar => 'Alphabet bar position';

  @override
  String get sectionAccessibility => 'Accessibility';

  @override
  String get sectionLanguage => 'Language';

  @override
  String get sectionForegroundLock => 'Foreground lock';

  @override
  String get sectionBackgroundLock => 'Background lock';

  @override
  String get sectionPasswordHistory => 'Password history';

  @override
  String get sectionPassphraseCopyPaste => 'Passphrase copy/paste';

  @override
  String get sectionVaultList => 'Vault list';

  @override
  String get sectionClipboardClear => 'Clipboard clear';

  @override
  String get sectionCharacterSets => 'Character sets';

  @override
  String get sectionGeneratorLanguage => 'Language';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get textSizeSmall => 'Small';

  @override
  String get textSizeRegular => 'Regular';

  @override
  String get textSizeLarge => 'Large';

  @override
  String get textSizeXL => 'XL';

  @override
  String get textSizeXXL => 'XXL';

  @override
  String get alphabetBarNote => 'Phone layout only — tablet always uses left.';

  @override
  String get alphabetBarLeft => 'Left';

  @override
  String get alphabetBarRight => 'Right';

  @override
  String get highContrastTitle => 'High contrast';

  @override
  String get highContrastSubtitle =>
      'Increases contrast for better readability';

  @override
  String get languageNote =>
      'Overrides the system language. \"System\" follows your device locale.';

  @override
  String get langSystem => 'System';

  @override
  String get langEnglish => 'English';

  @override
  String get langFrench => 'Français';

  @override
  String get langGerman => 'Deutsch';

  @override
  String get langItalian => 'Italiano';

  @override
  String get langSpanish => 'Español';

  @override
  String get foregroundLockDescription =>
      'Lock after this much inactivity while the app is open.';

  @override
  String get backgroundLockDescription =>
      'Lock after the app has been in the background for this long.';

  @override
  String get passwordHistoryDescription =>
      'How long to keep a previous password after it is changed. \"Keep forever\" means history is only deleted manually.';

  @override
  String get passphraseCopyPasteDescription =>
      'Block copy and paste on master passphrase fields. Recommended: prevents passphrase leaking via clipboard.';

  @override
  String get passphraseCopyPasteNote =>
      'Note: this blocks the long-press context menu and text selection. Your keyboard\'s inline paste button may still work — this is a platform limitation that cannot be blocked.';

  @override
  String get blockCopyPasteTitle => 'Block copy/paste';

  @override
  String get vaultListDescription =>
      'Show a dropdown of all vaults on the login screen so you can pick which one to unlock without going to Manage vaults.';

  @override
  String get showVaultListTitle => 'Show vault list on login';

  @override
  String get vaultListNote =>
      'High-security note: when this is OFF, the login screen shows only the last-used vault — no hint that other vaults exist. Trade-off: to switch vaults you must first unlock, then go to Menu → Manage vaults.';

  @override
  String get clipboardClearDescription =>
      'Clear the clipboard this long after copying a secret. Note: clipboard managers may retain a copy.';

  @override
  String get duration30s => '30s';

  @override
  String get duration1min => '1 min';

  @override
  String get duration5min => '5 min';

  @override
  String get duration15min => '15 min';

  @override
  String get duration60s => '60s';

  @override
  String get duration2min => '2 min';

  @override
  String get durationNever => 'Never';

  @override
  String get duration7days => '7 days';

  @override
  String get duration30days => '30 days';

  @override
  String get duration90days => '90 days';

  @override
  String get durationKeepForever => 'Keep forever';

  @override
  String get menuExportVault => 'Export vault';

  @override
  String get menuImportEntries => 'Import entries';

  @override
  String get menuSyncFromFile => 'Sync from file';

  @override
  String get menuManageVaults => 'Manage vaults';

  @override
  String get menuChangePassphrase => 'Change passphrase';

  @override
  String get menuManageYubiKeys => 'Manage YubiKeys';

  @override
  String get menuAppearance => 'Appearance';

  @override
  String get menuSecurity => 'Security';

  @override
  String get menuManageFolders => 'Manage folders';

  @override
  String get menuPasswordGenerator => 'Password generator';

  @override
  String get menuAbout => 'About';

  @override
  String get tooltipSelectEntries => 'Select entries';

  @override
  String get tooltipLockVault => 'Lock vault';

  @override
  String get tooltipMenu => 'Menu';

  @override
  String get tooltipCopy => 'Copy';

  @override
  String get tooltipCopied => 'Copied!';

  @override
  String get tooltipShow => 'Show';

  @override
  String get tooltipHide => 'Hide';

  @override
  String get tooltipBrowse => 'Browse';

  @override
  String get tooltipEditAlias => 'Edit alias';

  @override
  String get tooltipRemoveField => 'Remove field';

  @override
  String get tooltipRename => 'Rename';

  @override
  String get tooltipDeleteVault => 'Delete vault';

  @override
  String get tooltipAssignToFolder => 'Assign to folder';

  @override
  String get tooltipShowPin => 'Show PIN';

  @override
  String get tooltipHidePin => 'Hide PIN';

  @override
  String get tooltipShowValue => 'Show value';

  @override
  String get tooltipHideValue => 'Hide';

  @override
  String get tooltipCancel => 'Cancel';

  @override
  String get tooltipOpenInBrowser => 'Open in browser';

  @override
  String get allFolders => 'All folders';

  @override
  String get noFolder => 'None';

  @override
  String get selectFolder => 'Select a folder';

  @override
  String get folderName => 'Folder name';

  @override
  String get noEntriesMatch => 'No entries match your search.';

  @override
  String get noVaultsRegistered => 'No vaults registered.';

  @override
  String get noYubiKeysRegistered => 'No YubiKeys registered';

  @override
  String get selectEntry => 'Select an entry';

  @override
  String errorPrefix(String error) {
    return 'Error: $error';
  }

  @override
  String get navVault => 'Vault';

  @override
  String get navAppearance => 'Appearance';

  @override
  String get navSecurity => 'Security';

  @override
  String get navAbout => 'About';

  @override
  String get deleteEntryTitle => 'Delete entry?';

  @override
  String get cannotBeUndone => 'This cannot be undone.';

  @override
  String get deleteEntryDialogTitle => 'Delete entry?';

  @override
  String deleteEntriesTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Delete $count entries?',
      one: 'Delete 1 entry?',
    );
    return '$_temp0';
  }

  @override
  String get assignToFolderTitle => 'Assign to folder';

  @override
  String get folderConflictTitle => 'Folder conflict';

  @override
  String get syncFailedTitle => 'Sync failed';

  @override
  String get syncFromFileTitle => 'Sync from file';

  @override
  String get nothingToSync =>
      'Nothing to sync — both vaults are already up to date.';

  @override
  String importedEntries(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Imported $count entries.',
      one: 'Imported 1 entry.',
    );
    return '$_temp0';
  }

  @override
  String get exportFileTitle => 'Export file';

  @override
  String get saveDecryptedFileTo => 'Save decrypted file to:';

  @override
  String get exportPathLabel => 'Export path';

  @override
  String exportedToPath(String path) {
    return 'Exported to $path';
  }

  @override
  String exportFailed(String error) {
    return 'Export failed: $error';
  }

  @override
  String get openInBrowserTitle => 'Open in browser?';

  @override
  String couldNotOpen(String url) {
    return 'Could not open $url';
  }

  @override
  String get deleteEntryFromHistoryLabel => 'Delete previous entry';

  @override
  String failedToClearHistory(String error) {
    return 'Failed to clear history: $error';
  }

  @override
  String failedToRevertPassword(String error) {
    return 'Failed to revert password: $error';
  }

  @override
  String get renameFolderTitle => 'Rename folder';

  @override
  String get addFolderTitle => 'Add folder';

  @override
  String get deleteFolderTitle => 'Delete folder';

  @override
  String deleteFolderConfirm(String folder) {
    return 'Delete \"$folder\"?';
  }

  @override
  String get reassignEntriesTo => 'Reassign entries to';

  @override
  String get clearToNone => 'Clear to \"None\"';

  @override
  String get renameVaultTitle => 'Rename vault';

  @override
  String get deleteVaultTitle => 'Delete vault?';

  @override
  String get deleteVaultConfirmTitle => 'Are you sure?';

  @override
  String get typeDeleteToConfirm => 'Type DELETE to confirm';

  @override
  String get touchYourYubiKey => 'Touch your YubiKey';

  @override
  String get noVaultsRegisteredText => 'No vaults registered.';

  @override
  String get addYubiKeyTitle => 'Add YubiKey';

  @override
  String get enterYubiKeyPinTitle => 'Enter YubiKey PIN';

  @override
  String editAliasForKey(int index) {
    return 'Edit alias for key $index';
  }

  @override
  String get lastKeyWarning => 'This will leave only one registered YubiKey.';

  @override
  String get removeKeyConfirm => 'Are you sure you want to remove this key?';

  @override
  String get removeKeyVaultConfirm => 'Remove this YubiKey from the vault?';

  @override
  String get yubiKeyRemoved => 'YubiKey removed';

  @override
  String failedToRemoveKey(String error) {
    return 'Failed to remove key: $error';
  }

  @override
  String get yubiKeyAdded => 'YubiKey added';

  @override
  String failedToAddKey(String error) {
    return 'Failed to add key: $error';
  }

  @override
  String failedToSaveAlias(String error) {
    return 'Failed to save alias: $error';
  }

  @override
  String get noFidoDeviceFound =>
      'No FIDO2 device found. Insert your YubiKey and try again.';

  @override
  String get transportLabel => 'Transport:';

  @override
  String get transportUsb => 'USB';

  @override
  String get transportNfc => 'NFC';

  @override
  String get passphraseLabel => 'Passphrase';

  @override
  String get yubiKeyPinLabel => 'YubiKey PIN';

  @override
  String get pinLabel => 'PIN';

  @override
  String get currentPassphraseLabel => 'Current passphrase';

  @override
  String get newPassphraseLabel => 'New passphrase';

  @override
  String get confirmPassphraseLabel => 'Confirm new passphrase';

  @override
  String get vaultPassphraseLabel => 'Vault passphrase';

  @override
  String get aliasLabel => 'Alias';

  @override
  String get aliasHint => 'e.g. Primary, Work key…';

  @override
  String get masterPassphraseLabel => 'Master passphrase';

  @override
  String get confirmPassphraseLabelShort => 'Confirm passphrase';

  @override
  String get fieldTitle => 'Title';

  @override
  String get fieldContent => 'Content';

  @override
  String get fieldFirstName => 'First name';

  @override
  String get fieldLastName => 'Last name';

  @override
  String get fieldEmail => 'Email (optional)';

  @override
  String get fieldPhone => 'Phone (optional)';

  @override
  String get fieldAddress => 'Address (optional)';

  @override
  String get fieldCardLabel => 'Card label (e.g. \"Visa Platinum\")';

  @override
  String get fieldCardholderName => 'Cardholder name';

  @override
  String get fieldCardNumber => 'Card number';

  @override
  String get fieldExpiry => 'Expiry (MM/YY)';

  @override
  String get fieldCvv => 'CVV (optional)';

  @override
  String get fieldCardPin => 'PIN (optional)';

  @override
  String get fieldCreditLimit => 'Credit limit (optional)';

  @override
  String get fieldAccountNumber => 'Account number (optional)';

  @override
  String get fieldNotes => 'Notes (optional)';

  @override
  String get fieldUrl => 'URL (optional)';

  @override
  String get fieldUsername => 'Username';

  @override
  String get fieldPassword => 'Password';

  @override
  String get fieldSeparator => 'Separator';

  @override
  String get fieldFolder => 'Folder';

  @override
  String get fieldLabel => 'Label';

  @override
  String get fieldValue => 'Value';

  @override
  String get fieldCustomFields => 'Custom fields';

  @override
  String fieldLabelOptional(String label) {
    return '$label (optional)';
  }

  @override
  String get entryTypeNotSupported => 'Entry type not yet supported.';

  @override
  String get csvColumnNone => '(none)';

  @override
  String get csvPreviewLabel => 'Preview';

  @override
  String get csvImportButton => 'Import';

  @override
  String get gabbroVaultSection => 'Gabbro vault';

  @override
  String get genericCsvSection => 'Generic CSV';

  @override
  String get changePassphraseSuccess => 'Passphrase changed successfully';

  @override
  String get changePassphraseButton => 'Change passphrase';

  @override
  String get protectWithYubiKey => 'Protect with YubiKey';

  @override
  String get accessibilityButton => 'Accessibility';

  @override
  String get aboutProjectSection => 'Project';

  @override
  String get aboutLicenceSection => 'Licence';

  @override
  String get aboutOpenSourceSection => 'Open source components';

  @override
  String get aboutAttributionSection => 'Attribution';

  @override
  String get lengthLabel => 'Length';

  @override
  String get wordsLabel => 'Words';

  @override
  String get generateButton => 'Generate';

  @override
  String get usePasswordButton => 'Use this password';

  @override
  String get showHidePassword => 'Show';

  @override
  String get deleteVaultPostDeletion =>
      'Your vault has been deleted. Create a new one to continue.';

  @override
  String get syncFilePassphraseLabel => 'Vault passphrase';

  @override
  String get historyWarning =>
      'Only 1 previous value is kept. History auto-purges based on your security settings.';

  @override
  String get historyCurrent => 'Current';

  @override
  String get historyPrevious => 'Previous';

  @override
  String historySavedOn(String date) {
    return 'Saved $date';
  }

  @override
  String historyExpiresAppend(String saved, String expires) {
    return '$saved · expires $expires';
  }

  @override
  String importIssueTitle(int index, int total) {
    return 'Import issue ($index of $total)';
  }

  @override
  String importIssueType(String category) {
    return 'Type: $category';
  }

  @override
  String get importIssueHelp =>
      'Edit to correct and save this entry, or skip to discard it.';

  @override
  String entriesSkipped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entries skipped',
      one: '1 entry skipped',
    );
    return '$_temp0';
  }

  @override
  String get skippedEntriesNote =>
      'These entries already exist in your vault and were not overwritten:';

  @override
  String syncDeleteEntryContent(String title) {
    return 'The other device deleted \'$title\'.\n\nDelete it here too, or keep it?';
  }

  @override
  String folderConflictContent(String title, String local, String incoming) {
    return '\'$title\' is in different folders on each device.\n\nThis device: $local\nOther device: $incoming';
  }

  @override
  String get folderConflictKeepUnfoldered => 'Keep unfoldered';

  @override
  String folderConflictKeepLocal(String folder) {
    return 'Keep \"$folder\"';
  }

  @override
  String get folderConflictMoveUnfoldered => 'Move to unfoldered';

  @override
  String folderConflictMoveIncoming(String folder) {
    return 'Move to \"$folder\"';
  }

  @override
  String vaultSynced(int added, int updated, int deleted) {
    return 'Vault synced — $added added, $updated updated, $deleted deleted.';
  }

  @override
  String get syncPassphraseMismatch =>
      'This vault file uses a different passphrase. Sync is only supported between vaults that share a passphrase.';

  @override
  String get reviewSensitiveFields => 'Sensitive fields';

  @override
  String get reviewOtherFields => 'Other fields';

  @override
  String get reviewPasswordChanged => 'Password changed';

  @override
  String get reviewCvvChanged => 'CVV changed';

  @override
  String get reviewPinChanged => 'PIN changed';

  @override
  String get reviewTransactionPasswordChanged => 'Transaction password changed';

  @override
  String get tooltipShowValues => 'Show values';

  @override
  String get reviewOld => 'Old';

  @override
  String get reviewNew => 'New';

  @override
  String get reviewEmpty => '(empty)';
}
