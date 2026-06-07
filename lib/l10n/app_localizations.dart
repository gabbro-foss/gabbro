import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_bg.dart';
import 'app_localizations_cs.dart';
import 'app_localizations_da.dart';
import 'app_localizations_de.dart';
import 'app_localizations_el.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_et.dart';
import 'app_localizations_eu.dart';
import 'app_localizations_fi.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_hr.dart';
import 'app_localizations_hu.dart';
import 'app_localizations_it.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_kk.dart';
import 'app_localizations_ko.dart';
import 'app_localizations_lt.dart';
import 'app_localizations_lv.dart';
import 'app_localizations_nb.dart';
import 'app_localizations_nl.dart';
import 'app_localizations_nn.dart';
import 'app_localizations_pl.dart';
import 'app_localizations_pt.dart';
import 'app_localizations_ru.dart';
import 'app_localizations_sk.dart';
import 'app_localizations_sl.dart';
import 'app_localizations_sr.dart';
import 'app_localizations_sv.dart';
import 'app_localizations_uk.dart';
import 'app_localizations_yo.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('bg'),
    Locale('cs'),
    Locale('da'),
    Locale('de'),
    Locale('el'),
    Locale('en'),
    Locale('es'),
    Locale('et'),
    Locale('eu'),
    Locale('fi'),
    Locale('fr'),
    Locale('hr'),
    Locale('hu'),
    Locale('it'),
    Locale('ja'),
    Locale('kk'),
    Locale('ko'),
    Locale('lt'),
    Locale('lv'),
    Locale('nb'),
    Locale('nl'),
    Locale('nn'),
    Locale('pl'),
    Locale('pt'),
    Locale('pt', 'BR'),
    Locale('pt', 'PT'),
    Locale('ru'),
    Locale('sk'),
    Locale('sl'),
    Locale('sr'),
    Locale.fromSubtags(languageCode: 'sr', scriptCode: 'Latn'),
    Locale('sv'),
    Locale('uk'),
    Locale('yo'),
    Locale('zh'),
    Locale('zh', 'CN'),
    Locale('zh', 'TW'),
  ];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'Gabbro'**
  String get appName;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @rename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @continueAction.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueAction;

  /// No description provided for @dismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get dismiss;

  /// No description provided for @authorize.
  ///
  /// In en, this message translates to:
  /// **'Authorize'**
  String get authorize;

  /// No description provided for @register.
  ///
  /// In en, this message translates to:
  /// **'Register'**
  String get register;

  /// No description provided for @sync.
  ///
  /// In en, this message translates to:
  /// **'Sync'**
  String get sync;

  /// No description provided for @assign.
  ///
  /// In en, this message translates to:
  /// **'Assign'**
  String get assign;

  /// No description provided for @unlock.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get unlock;

  /// No description provided for @generate.
  ///
  /// In en, this message translates to:
  /// **'Generate'**
  String get generate;

  /// No description provided for @import.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get import;

  /// No description provided for @export.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get export;

  /// No description provided for @openInBrowser.
  ///
  /// In en, this message translates to:
  /// **'Open in browser'**
  String get openInBrowser;

  /// No description provided for @useThisPassword.
  ///
  /// In en, this message translates to:
  /// **'Use this password'**
  String get useThisPassword;

  /// No description provided for @reviewArrow.
  ///
  /// In en, this message translates to:
  /// **'Review →'**
  String get reviewArrow;

  /// No description provided for @skip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skip;

  /// No description provided for @keep.
  ///
  /// In en, this message translates to:
  /// **'Keep'**
  String get keep;

  /// No description provided for @revert.
  ///
  /// In en, this message translates to:
  /// **'Revert'**
  String get revert;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next: map columns'**
  String get next;

  /// No description provided for @syncFromVault.
  ///
  /// In en, this message translates to:
  /// **'Sync from vault'**
  String get syncFromVault;

  /// No description provided for @createVault.
  ///
  /// In en, this message translates to:
  /// **'Create vault'**
  String get createVault;

  /// No description provided for @pickFile.
  ///
  /// In en, this message translates to:
  /// **'Pick file'**
  String get pickFile;

  /// No description provided for @noFileSelected.
  ///
  /// In en, this message translates to:
  /// **'No file selected'**
  String get noFileSelected;

  /// No description provided for @chooseFolder.
  ///
  /// In en, this message translates to:
  /// **'Choose folder'**
  String get chooseFolder;

  /// No description provided for @addCustomField.
  ///
  /// In en, this message translates to:
  /// **'Add custom field'**
  String get addCustomField;

  /// No description provided for @exportFile.
  ///
  /// In en, this message translates to:
  /// **'Export file'**
  String get exportFile;

  /// No description provided for @addVault.
  ///
  /// In en, this message translates to:
  /// **'Add vault'**
  String get addVault;

  /// No description provided for @addYubiKey.
  ///
  /// In en, this message translates to:
  /// **'Add YubiKey'**
  String get addYubiKey;

  /// No description provided for @noChangesToSave.
  ///
  /// In en, this message translates to:
  /// **'No changes to save.'**
  String get noChangesToSave;

  /// No description provided for @appearanceTitle.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearanceTitle;

  /// No description provided for @securityTitle.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get securityTitle;

  /// No description provided for @aboutTitle.
  ///
  /// In en, this message translates to:
  /// **'About Gabbro'**
  String get aboutTitle;

  /// No description provided for @generatorTitle.
  ///
  /// In en, this message translates to:
  /// **'Password generator'**
  String get generatorTitle;

  /// No description provided for @importTitle.
  ///
  /// In en, this message translates to:
  /// **'Import entries'**
  String get importTitle;

  /// No description provided for @exportTitle.
  ///
  /// In en, this message translates to:
  /// **'Export vault'**
  String get exportTitle;

  /// No description provided for @changePassphraseTitle.
  ///
  /// In en, this message translates to:
  /// **'Change passphrase'**
  String get changePassphraseTitle;

  /// No description provided for @csvMappingTitle.
  ///
  /// In en, this message translates to:
  /// **'Map CSV columns'**
  String get csvMappingTitle;

  /// No description provided for @manageFoldersTitle.
  ///
  /// In en, this message translates to:
  /// **'Manage folders'**
  String get manageFoldersTitle;

  /// No description provided for @manageVaultsTitle.
  ///
  /// In en, this message translates to:
  /// **'Manage vaults'**
  String get manageVaultsTitle;

  /// No description provided for @manageYubiKeysTitle.
  ///
  /// In en, this message translates to:
  /// **'Manage YubiKeys'**
  String get manageYubiKeysTitle;

  /// No description provided for @passwordHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Password history'**
  String get passwordHistoryTitle;

  /// No description provided for @reviewChangesTitle.
  ///
  /// In en, this message translates to:
  /// **'Review changes'**
  String get reviewChangesTitle;

  /// No description provided for @unlockGabbroTitle.
  ///
  /// In en, this message translates to:
  /// **'Unlock Gabbro'**
  String get unlockGabbroTitle;

  /// No description provided for @sectionTheme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get sectionTheme;

  /// No description provided for @sectionTextSize.
  ///
  /// In en, this message translates to:
  /// **'Text size'**
  String get sectionTextSize;

  /// No description provided for @sectionAlphabetBar.
  ///
  /// In en, this message translates to:
  /// **'Alphabet bar position'**
  String get sectionAlphabetBar;

  /// No description provided for @sectionAccessibility.
  ///
  /// In en, this message translates to:
  /// **'Accessibility'**
  String get sectionAccessibility;

  /// No description provided for @sectionLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get sectionLanguage;

  /// No description provided for @sectionForegroundLock.
  ///
  /// In en, this message translates to:
  /// **'Foreground lock'**
  String get sectionForegroundLock;

  /// No description provided for @sectionBackgroundLock.
  ///
  /// In en, this message translates to:
  /// **'Background lock'**
  String get sectionBackgroundLock;

  /// No description provided for @sectionPasswordHistory.
  ///
  /// In en, this message translates to:
  /// **'Password history'**
  String get sectionPasswordHistory;

  /// No description provided for @sectionPassphraseCopyPaste.
  ///
  /// In en, this message translates to:
  /// **'Passphrase copy/paste'**
  String get sectionPassphraseCopyPaste;

  /// No description provided for @sectionVaultList.
  ///
  /// In en, this message translates to:
  /// **'Vault list'**
  String get sectionVaultList;

  /// No description provided for @sectionClipboardClear.
  ///
  /// In en, this message translates to:
  /// **'Clipboard clear'**
  String get sectionClipboardClear;

  /// No description provided for @sectionCharacterSets.
  ///
  /// In en, this message translates to:
  /// **'Character sets'**
  String get sectionCharacterSets;

  /// No description provided for @sectionGeneratorLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get sectionGeneratorLanguage;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @textSizeSmall.
  ///
  /// In en, this message translates to:
  /// **'Small'**
  String get textSizeSmall;

  /// No description provided for @textSizeRegular.
  ///
  /// In en, this message translates to:
  /// **'Regular'**
  String get textSizeRegular;

  /// No description provided for @textSizeLarge.
  ///
  /// In en, this message translates to:
  /// **'Large'**
  String get textSizeLarge;

  /// No description provided for @textSizeXL.
  ///
  /// In en, this message translates to:
  /// **'XL'**
  String get textSizeXL;

  /// No description provided for @textSizeXXL.
  ///
  /// In en, this message translates to:
  /// **'XXL'**
  String get textSizeXXL;

  /// No description provided for @alphabetBarNote.
  ///
  /// In en, this message translates to:
  /// **'Phone layout only — tablet always uses left.'**
  String get alphabetBarNote;

  /// No description provided for @alphabetBarLeft.
  ///
  /// In en, this message translates to:
  /// **'Left'**
  String get alphabetBarLeft;

  /// No description provided for @alphabetBarRight.
  ///
  /// In en, this message translates to:
  /// **'Right'**
  String get alphabetBarRight;

  /// No description provided for @highContrastTitle.
  ///
  /// In en, this message translates to:
  /// **'High contrast'**
  String get highContrastTitle;

  /// No description provided for @highContrastSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Increases contrast for better readability'**
  String get highContrastSubtitle;

  /// No description provided for @languageNote.
  ///
  /// In en, this message translates to:
  /// **'Overrides the system language. \"System\" follows your device locale.'**
  String get languageNote;

  /// No description provided for @langSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get langSystem;

  /// No description provided for @langEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get langEnglish;

  /// No description provided for @langFrench.
  ///
  /// In en, this message translates to:
  /// **'Français'**
  String get langFrench;

  /// No description provided for @langGerman.
  ///
  /// In en, this message translates to:
  /// **'Deutsch'**
  String get langGerman;

  /// No description provided for @langItalian.
  ///
  /// In en, this message translates to:
  /// **'Italiano'**
  String get langItalian;

  /// No description provided for @langSpanish.
  ///
  /// In en, this message translates to:
  /// **'Español'**
  String get langSpanish;

  /// No description provided for @langBulgarian.
  ///
  /// In en, this message translates to:
  /// **'Български'**
  String get langBulgarian;

  /// No description provided for @langCzech.
  ///
  /// In en, this message translates to:
  /// **'Čeština'**
  String get langCzech;

  /// No description provided for @langDanish.
  ///
  /// In en, this message translates to:
  /// **'Dansk'**
  String get langDanish;

  /// No description provided for @langGreek.
  ///
  /// In en, this message translates to:
  /// **'Ελληνικά'**
  String get langGreek;

  /// No description provided for @langEstonian.
  ///
  /// In en, this message translates to:
  /// **'Eesti'**
  String get langEstonian;

  /// No description provided for @langFinnish.
  ///
  /// In en, this message translates to:
  /// **'Suomi'**
  String get langFinnish;

  /// No description provided for @langCroatian.
  ///
  /// In en, this message translates to:
  /// **'Hrvatski'**
  String get langCroatian;

  /// No description provided for @langHungarian.
  ///
  /// In en, this message translates to:
  /// **'Magyar'**
  String get langHungarian;

  /// No description provided for @langJapanese.
  ///
  /// In en, this message translates to:
  /// **'日本語'**
  String get langJapanese;

  /// No description provided for @langKazakh.
  ///
  /// In en, this message translates to:
  /// **'Қазақша'**
  String get langKazakh;

  /// No description provided for @langKorean.
  ///
  /// In en, this message translates to:
  /// **'한국어'**
  String get langKorean;

  /// No description provided for @langLithuanian.
  ///
  /// In en, this message translates to:
  /// **'Lietuvių'**
  String get langLithuanian;

  /// No description provided for @langLatvian.
  ///
  /// In en, this message translates to:
  /// **'Latviešu'**
  String get langLatvian;

  /// No description provided for @langNorwegianBokmal.
  ///
  /// In en, this message translates to:
  /// **'Norsk bokmål'**
  String get langNorwegianBokmal;

  /// No description provided for @langNorwegianNynorsk.
  ///
  /// In en, this message translates to:
  /// **'Norsk nynorsk'**
  String get langNorwegianNynorsk;

  /// No description provided for @langPolish.
  ///
  /// In en, this message translates to:
  /// **'Polski'**
  String get langPolish;

  /// No description provided for @langPortugueseBr.
  ///
  /// In en, this message translates to:
  /// **'Português (BR)'**
  String get langPortugueseBr;

  /// No description provided for @langPortuguesePt.
  ///
  /// In en, this message translates to:
  /// **'Português (PT)'**
  String get langPortuguesePt;

  /// No description provided for @langRussian.
  ///
  /// In en, this message translates to:
  /// **'Русский'**
  String get langRussian;

  /// No description provided for @langSlovak.
  ///
  /// In en, this message translates to:
  /// **'Slovenčina'**
  String get langSlovak;

  /// No description provided for @langSlovenian.
  ///
  /// In en, this message translates to:
  /// **'Slovenščina'**
  String get langSlovenian;

  /// No description provided for @langSerbianLatin.
  ///
  /// In en, this message translates to:
  /// **'Srpski'**
  String get langSerbianLatin;

  /// No description provided for @langSwedish.
  ///
  /// In en, this message translates to:
  /// **'Svenska'**
  String get langSwedish;

  /// No description provided for @langUkrainian.
  ///
  /// In en, this message translates to:
  /// **'Українська'**
  String get langUkrainian;

  /// No description provided for @langBasque.
  ///
  /// In en, this message translates to:
  /// **'Euskara'**
  String get langBasque;

  /// No description provided for @langYoruba.
  ///
  /// In en, this message translates to:
  /// **'Yorùbá'**
  String get langYoruba;

  /// No description provided for @langChineseSimplified.
  ///
  /// In en, this message translates to:
  /// **'中文（简体）'**
  String get langChineseSimplified;

  /// No description provided for @langChineseTraditional.
  ///
  /// In en, this message translates to:
  /// **'中文（繁體）'**
  String get langChineseTraditional;

  /// No description provided for @langDutch.
  ///
  /// In en, this message translates to:
  /// **'Nederlands'**
  String get langDutch;

  /// No description provided for @foregroundLockDescription.
  ///
  /// In en, this message translates to:
  /// **'Lock after this much inactivity while the app is open.'**
  String get foregroundLockDescription;

  /// No description provided for @backgroundLockDescription.
  ///
  /// In en, this message translates to:
  /// **'Lock after the app has been in the background for this long.'**
  String get backgroundLockDescription;

  /// No description provided for @passwordHistoryDescription.
  ///
  /// In en, this message translates to:
  /// **'How long to keep a previous password after it is changed. \"Keep forever\" means history is only deleted manually.'**
  String get passwordHistoryDescription;

  /// No description provided for @passphraseCopyPasteDescription.
  ///
  /// In en, this message translates to:
  /// **'Block copy and paste on master passphrase fields. Recommended: prevents passphrase leaking via clipboard.'**
  String get passphraseCopyPasteDescription;

  /// No description provided for @passphraseCopyPasteNote.
  ///
  /// In en, this message translates to:
  /// **'Note: this blocks the long-press context menu and text selection. Your keyboard\'s inline paste button may still work — this is a platform limitation that cannot be blocked.'**
  String get passphraseCopyPasteNote;

  /// No description provided for @blockCopyPasteTitle.
  ///
  /// In en, this message translates to:
  /// **'Block copy/paste'**
  String get blockCopyPasteTitle;

  /// No description provided for @vaultListDescription.
  ///
  /// In en, this message translates to:
  /// **'Show a dropdown of all vaults on the login screen so you can pick which one to unlock without going to Manage vaults.'**
  String get vaultListDescription;

  /// No description provided for @showVaultListTitle.
  ///
  /// In en, this message translates to:
  /// **'Show vault list on login'**
  String get showVaultListTitle;

  /// No description provided for @vaultListNote.
  ///
  /// In en, this message translates to:
  /// **'High-security note: when this is OFF, the login screen shows only the last-used vault — no hint that other vaults exist. Trade-off: to switch vaults you must first unlock, then go to Menu → Manage vaults.'**
  String get vaultListNote;

  /// No description provided for @clipboardClearDescription.
  ///
  /// In en, this message translates to:
  /// **'Clear the clipboard this long after copying a secret. Note: clipboard managers may retain a copy.'**
  String get clipboardClearDescription;

  /// No description provided for @duration30s.
  ///
  /// In en, this message translates to:
  /// **'30s'**
  String get duration30s;

  /// No description provided for @duration1min.
  ///
  /// In en, this message translates to:
  /// **'1 min'**
  String get duration1min;

  /// No description provided for @duration5min.
  ///
  /// In en, this message translates to:
  /// **'5 min'**
  String get duration5min;

  /// No description provided for @duration15min.
  ///
  /// In en, this message translates to:
  /// **'15 min'**
  String get duration15min;

  /// No description provided for @duration60s.
  ///
  /// In en, this message translates to:
  /// **'60s'**
  String get duration60s;

  /// No description provided for @duration2min.
  ///
  /// In en, this message translates to:
  /// **'2 min'**
  String get duration2min;

  /// No description provided for @durationNever.
  ///
  /// In en, this message translates to:
  /// **'Never'**
  String get durationNever;

  /// No description provided for @duration7days.
  ///
  /// In en, this message translates to:
  /// **'7 days'**
  String get duration7days;

  /// No description provided for @duration30days.
  ///
  /// In en, this message translates to:
  /// **'30 days'**
  String get duration30days;

  /// No description provided for @duration90days.
  ///
  /// In en, this message translates to:
  /// **'90 days'**
  String get duration90days;

  /// No description provided for @durationKeepForever.
  ///
  /// In en, this message translates to:
  /// **'Keep forever'**
  String get durationKeepForever;

  /// No description provided for @menuExportVault.
  ///
  /// In en, this message translates to:
  /// **'Export vault'**
  String get menuExportVault;

  /// No description provided for @menuImportEntries.
  ///
  /// In en, this message translates to:
  /// **'Import entries'**
  String get menuImportEntries;

  /// No description provided for @menuSyncFromFile.
  ///
  /// In en, this message translates to:
  /// **'Sync from file'**
  String get menuSyncFromFile;

  /// No description provided for @menuManageVaults.
  ///
  /// In en, this message translates to:
  /// **'Manage vaults'**
  String get menuManageVaults;

  /// No description provided for @menuChangePassphrase.
  ///
  /// In en, this message translates to:
  /// **'Change passphrase'**
  String get menuChangePassphrase;

  /// No description provided for @menuManageYubiKeys.
  ///
  /// In en, this message translates to:
  /// **'Manage YubiKeys'**
  String get menuManageYubiKeys;

  /// No description provided for @menuAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get menuAppearance;

  /// No description provided for @menuSecurity.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get menuSecurity;

  /// No description provided for @menuManageFolders.
  ///
  /// In en, this message translates to:
  /// **'Manage folders'**
  String get menuManageFolders;

  /// No description provided for @menuPasswordGenerator.
  ///
  /// In en, this message translates to:
  /// **'Password generator'**
  String get menuPasswordGenerator;

  /// No description provided for @menuAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get menuAbout;

  /// No description provided for @tooltipSelectEntries.
  ///
  /// In en, this message translates to:
  /// **'Select entries'**
  String get tooltipSelectEntries;

  /// No description provided for @tooltipLockVault.
  ///
  /// In en, this message translates to:
  /// **'Lock vault'**
  String get tooltipLockVault;

  /// No description provided for @tooltipSelectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get tooltipSelectAll;

  /// No description provided for @tooltipDeselectAll.
  ///
  /// In en, this message translates to:
  /// **'Deselect all'**
  String get tooltipDeselectAll;

  /// No description provided for @tooltipMenu.
  ///
  /// In en, this message translates to:
  /// **'Menu'**
  String get tooltipMenu;

  /// No description provided for @tooltipCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get tooltipCopy;

  /// No description provided for @tooltipCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied!'**
  String get tooltipCopied;

  /// No description provided for @tooltipShow.
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get tooltipShow;

  /// No description provided for @tooltipHide.
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get tooltipHide;

  /// No description provided for @tooltipBrowse.
  ///
  /// In en, this message translates to:
  /// **'Browse'**
  String get tooltipBrowse;

  /// No description provided for @tooltipEditAlias.
  ///
  /// In en, this message translates to:
  /// **'Edit alias'**
  String get tooltipEditAlias;

  /// No description provided for @tooltipRemoveField.
  ///
  /// In en, this message translates to:
  /// **'Remove field'**
  String get tooltipRemoveField;

  /// No description provided for @tooltipRename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get tooltipRename;

  /// No description provided for @tooltipDeleteVault.
  ///
  /// In en, this message translates to:
  /// **'Delete vault'**
  String get tooltipDeleteVault;

  /// No description provided for @tooltipAssignToFolder.
  ///
  /// In en, this message translates to:
  /// **'Assign to folder'**
  String get tooltipAssignToFolder;

  /// No description provided for @tooltipShowPin.
  ///
  /// In en, this message translates to:
  /// **'Show PIN'**
  String get tooltipShowPin;

  /// No description provided for @tooltipHidePin.
  ///
  /// In en, this message translates to:
  /// **'Hide PIN'**
  String get tooltipHidePin;

  /// No description provided for @tooltipShowValue.
  ///
  /// In en, this message translates to:
  /// **'Show value'**
  String get tooltipShowValue;

  /// No description provided for @tooltipHideValue.
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get tooltipHideValue;

  /// No description provided for @tooltipCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get tooltipCancel;

  /// No description provided for @tooltipOpenInBrowser.
  ///
  /// In en, this message translates to:
  /// **'Open in browser'**
  String get tooltipOpenInBrowser;

  /// No description provided for @allFolders.
  ///
  /// In en, this message translates to:
  /// **'All folders'**
  String get allFolders;

  /// No description provided for @noFolder.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get noFolder;

  /// No description provided for @selectFolder.
  ///
  /// In en, this message translates to:
  /// **'Select a folder'**
  String get selectFolder;

  /// No description provided for @folderName.
  ///
  /// In en, this message translates to:
  /// **'Folder name'**
  String get folderName;

  /// No description provided for @noEntriesMatch.
  ///
  /// In en, this message translates to:
  /// **'No entries match your search.'**
  String get noEntriesMatch;

  /// No description provided for @noVaultsRegistered.
  ///
  /// In en, this message translates to:
  /// **'No vaults registered.'**
  String get noVaultsRegistered;

  /// No description provided for @noYubiKeysRegistered.
  ///
  /// In en, this message translates to:
  /// **'No YubiKeys registered'**
  String get noYubiKeysRegistered;

  /// No description provided for @selectEntry.
  ///
  /// In en, this message translates to:
  /// **'Select an entry'**
  String get selectEntry;

  /// No description provided for @newEntryTitle.
  ///
  /// In en, this message translates to:
  /// **'New entry'**
  String get newEntryTitle;

  /// No description provided for @createEntryTitle.
  ///
  /// In en, this message translates to:
  /// **'New {type}'**
  String createEntryTitle(String type);

  /// No description provided for @editEntryTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit {type}'**
  String editEntryTitle(String type);

  /// No description provided for @noUrlFallback.
  ///
  /// In en, this message translates to:
  /// **'(no URL)'**
  String get noUrlFallback;

  /// No description provided for @noNameFallback.
  ///
  /// In en, this message translates to:
  /// **'(no name)'**
  String get noNameFallback;

  /// No description provided for @untitledFallback.
  ///
  /// In en, this message translates to:
  /// **'(untitled)'**
  String get untitledFallback;

  /// No description provided for @gabbroTitle.
  ///
  /// In en, this message translates to:
  /// **'Gabbro'**
  String get gabbroTitle;

  /// No description provided for @gabbroVaultTitle.
  ///
  /// In en, this message translates to:
  /// **'Gabbro - {alias}'**
  String gabbroVaultTitle(String alias);

  /// No description provided for @selectedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String selectedCount(int count);

  /// No description provided for @searchAllFieldsHint.
  ///
  /// In en, this message translates to:
  /// **'Search all fields…'**
  String get searchAllFieldsHint;

  /// No description provided for @searchEntriesHint.
  ///
  /// In en, this message translates to:
  /// **'Search entries…'**
  String get searchEntriesHint;

  /// No description provided for @searchAllFieldsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Searching all fields'**
  String get searchAllFieldsTooltip;

  /// No description provided for @searchByTitleTooltip.
  ///
  /// In en, this message translates to:
  /// **'Searching by title'**
  String get searchByTitleTooltip;

  /// No description provided for @entryTypeAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get entryTypeAll;

  /// No description provided for @entryTypePassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get entryTypePassword;

  /// No description provided for @entryTypeNote.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get entryTypeNote;

  /// No description provided for @entryTypeCard.
  ///
  /// In en, this message translates to:
  /// **'Card'**
  String get entryTypeCard;

  /// No description provided for @entryTypeIdentity.
  ///
  /// In en, this message translates to:
  /// **'Identity'**
  String get entryTypeIdentity;

  /// No description provided for @entryTypeFile.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get entryTypeFile;

  /// No description provided for @entryTypeCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get entryTypeCustom;

  /// No description provided for @errorPrefix.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String errorPrefix(String error);

  /// No description provided for @navVault.
  ///
  /// In en, this message translates to:
  /// **'Vault'**
  String get navVault;

  /// No description provided for @navAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get navAppearance;

  /// No description provided for @navSecurity.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get navSecurity;

  /// No description provided for @navAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get navAbout;

  /// No description provided for @deleteEntryTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete entry?'**
  String get deleteEntryTitle;

  /// No description provided for @cannotBeUndone.
  ///
  /// In en, this message translates to:
  /// **'This cannot be undone.'**
  String get cannotBeUndone;

  /// No description provided for @deleteEntryDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete entry?'**
  String get deleteEntryDialogTitle;

  /// No description provided for @deleteEntriesTitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Delete 1 entry?} other{Delete {count} entries?}}'**
  String deleteEntriesTitle(int count);

  /// No description provided for @assignToFolderTitle.
  ///
  /// In en, this message translates to:
  /// **'Assign to folder'**
  String get assignToFolderTitle;

  /// No description provided for @folderConflictTitle.
  ///
  /// In en, this message translates to:
  /// **'Folder conflict'**
  String get folderConflictTitle;

  /// No description provided for @syncFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Sync failed'**
  String get syncFailedTitle;

  /// No description provided for @syncFromFileTitle.
  ///
  /// In en, this message translates to:
  /// **'Sync from file'**
  String get syncFromFileTitle;

  /// No description provided for @nothingToSync.
  ///
  /// In en, this message translates to:
  /// **'Nothing to sync — both vaults are already up to date.'**
  String get nothingToSync;

  /// No description provided for @importedEntries.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Imported 1 entry.} other{Imported {count} entries.}}'**
  String importedEntries(int count);

  /// No description provided for @exportFileTitle.
  ///
  /// In en, this message translates to:
  /// **'Export file'**
  String get exportFileTitle;

  /// No description provided for @saveDecryptedFileTo.
  ///
  /// In en, this message translates to:
  /// **'Save decrypted file to:'**
  String get saveDecryptedFileTo;

  /// No description provided for @exportPathLabel.
  ///
  /// In en, this message translates to:
  /// **'Export path'**
  String get exportPathLabel;

  /// No description provided for @exportedToPath.
  ///
  /// In en, this message translates to:
  /// **'Exported to {path}'**
  String exportedToPath(String path);

  /// No description provided for @exportFailed.
  ///
  /// In en, this message translates to:
  /// **'Export failed: {error}'**
  String exportFailed(String error);

  /// No description provided for @openInBrowserTitle.
  ///
  /// In en, this message translates to:
  /// **'Open in browser?'**
  String get openInBrowserTitle;

  /// No description provided for @couldNotOpen.
  ///
  /// In en, this message translates to:
  /// **'Could not open {url}'**
  String couldNotOpen(String url);

  /// No description provided for @deleteEntryFromHistoryLabel.
  ///
  /// In en, this message translates to:
  /// **'Delete previous entry'**
  String get deleteEntryFromHistoryLabel;

  /// No description provided for @failedToClearHistory.
  ///
  /// In en, this message translates to:
  /// **'Failed to clear history: {error}'**
  String failedToClearHistory(String error);

  /// No description provided for @failedToRevertPassword.
  ///
  /// In en, this message translates to:
  /// **'Failed to revert password: {error}'**
  String failedToRevertPassword(String error);

  /// No description provided for @renameFolderTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename folder'**
  String get renameFolderTitle;

  /// No description provided for @addFolderTitle.
  ///
  /// In en, this message translates to:
  /// **'Add folder'**
  String get addFolderTitle;

  /// No description provided for @deleteFolderTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete folder'**
  String get deleteFolderTitle;

  /// No description provided for @deleteFolderConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{folder}\"?'**
  String deleteFolderConfirm(String folder);

  /// No description provided for @reassignEntriesTo.
  ///
  /// In en, this message translates to:
  /// **'Reassign entries to'**
  String get reassignEntriesTo;

  /// No description provided for @clearToNone.
  ///
  /// In en, this message translates to:
  /// **'Clear to \"None\"'**
  String get clearToNone;

  /// No description provided for @renameVaultTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename vault'**
  String get renameVaultTitle;

  /// No description provided for @deleteVaultTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete vault?'**
  String get deleteVaultTitle;

  /// No description provided for @deleteVaultConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Are you sure?'**
  String get deleteVaultConfirmTitle;

  /// No description provided for @typeDeleteToConfirm.
  ///
  /// In en, this message translates to:
  /// **'Type DELETE to confirm'**
  String get typeDeleteToConfirm;

  /// No description provided for @typeDeleteWord.
  ///
  /// In en, this message translates to:
  /// **'DELETE'**
  String get typeDeleteWord;

  /// No description provided for @touchYourYubiKey.
  ///
  /// In en, this message translates to:
  /// **'Touch your YubiKey'**
  String get touchYourYubiKey;

  /// No description provided for @noVaultsRegisteredText.
  ///
  /// In en, this message translates to:
  /// **'No vaults registered.'**
  String get noVaultsRegisteredText;

  /// No description provided for @addYubiKeyTitle.
  ///
  /// In en, this message translates to:
  /// **'Add YubiKey'**
  String get addYubiKeyTitle;

  /// No description provided for @enterYubiKeyPinTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter YubiKey PIN'**
  String get enterYubiKeyPinTitle;

  /// No description provided for @editAliasForKey.
  ///
  /// In en, this message translates to:
  /// **'Edit alias for key {index}'**
  String editAliasForKey(int index);

  /// No description provided for @lastKeyWarning.
  ///
  /// In en, this message translates to:
  /// **'This will leave only one registered YubiKey.'**
  String get lastKeyWarning;

  /// No description provided for @removeKeyConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to remove this key?'**
  String get removeKeyConfirm;

  /// No description provided for @removeKeyVaultConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove this YubiKey from the vault?'**
  String get removeKeyVaultConfirm;

  /// No description provided for @yubiKeyRemoved.
  ///
  /// In en, this message translates to:
  /// **'YubiKey removed'**
  String get yubiKeyRemoved;

  /// No description provided for @failedToRemoveKey.
  ///
  /// In en, this message translates to:
  /// **'Failed to remove key: {error}'**
  String failedToRemoveKey(String error);

  /// No description provided for @yubiKeyAdded.
  ///
  /// In en, this message translates to:
  /// **'YubiKey added'**
  String get yubiKeyAdded;

  /// No description provided for @failedToAddKey.
  ///
  /// In en, this message translates to:
  /// **'Failed to add key: {error}'**
  String failedToAddKey(String error);

  /// No description provided for @failedToSaveAlias.
  ///
  /// In en, this message translates to:
  /// **'Failed to save alias: {error}'**
  String failedToSaveAlias(String error);

  /// No description provided for @noFidoDeviceFound.
  ///
  /// In en, this message translates to:
  /// **'No FIDO2 device found. Insert your YubiKey and try again.'**
  String get noFidoDeviceFound;

  /// No description provided for @transportLabel.
  ///
  /// In en, this message translates to:
  /// **'Transport:'**
  String get transportLabel;

  /// No description provided for @transportUsb.
  ///
  /// In en, this message translates to:
  /// **'USB'**
  String get transportUsb;

  /// No description provided for @transportNfc.
  ///
  /// In en, this message translates to:
  /// **'NFC'**
  String get transportNfc;

  /// No description provided for @passphraseLabel.
  ///
  /// In en, this message translates to:
  /// **'Passphrase'**
  String get passphraseLabel;

  /// No description provided for @yubiKeyPinLabel.
  ///
  /// In en, this message translates to:
  /// **'YubiKey PIN'**
  String get yubiKeyPinLabel;

  /// No description provided for @pinLabel.
  ///
  /// In en, this message translates to:
  /// **'PIN'**
  String get pinLabel;

  /// No description provided for @currentPassphraseLabel.
  ///
  /// In en, this message translates to:
  /// **'Current passphrase'**
  String get currentPassphraseLabel;

  /// No description provided for @newPassphraseLabel.
  ///
  /// In en, this message translates to:
  /// **'New passphrase'**
  String get newPassphraseLabel;

  /// No description provided for @confirmPassphraseLabel.
  ///
  /// In en, this message translates to:
  /// **'Confirm new passphrase'**
  String get confirmPassphraseLabel;

  /// No description provided for @vaultPassphraseLabel.
  ///
  /// In en, this message translates to:
  /// **'Vault passphrase'**
  String get vaultPassphraseLabel;

  /// No description provided for @aliasLabel.
  ///
  /// In en, this message translates to:
  /// **'Alias'**
  String get aliasLabel;

  /// No description provided for @aliasHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Primary, Work key…'**
  String get aliasHint;

  /// No description provided for @masterPassphraseLabel.
  ///
  /// In en, this message translates to:
  /// **'Master passphrase'**
  String get masterPassphraseLabel;

  /// No description provided for @confirmPassphraseLabelShort.
  ///
  /// In en, this message translates to:
  /// **'Confirm passphrase'**
  String get confirmPassphraseLabelShort;

  /// No description provided for @fieldTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get fieldTitle;

  /// No description provided for @fieldContent.
  ///
  /// In en, this message translates to:
  /// **'Content'**
  String get fieldContent;

  /// No description provided for @fieldFirstName.
  ///
  /// In en, this message translates to:
  /// **'First name'**
  String get fieldFirstName;

  /// No description provided for @fieldLastName.
  ///
  /// In en, this message translates to:
  /// **'Last name'**
  String get fieldLastName;

  /// No description provided for @fieldEmail.
  ///
  /// In en, this message translates to:
  /// **'Email (optional)'**
  String get fieldEmail;

  /// No description provided for @fieldPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone (optional)'**
  String get fieldPhone;

  /// No description provided for @fieldAddress.
  ///
  /// In en, this message translates to:
  /// **'Address (optional)'**
  String get fieldAddress;

  /// No description provided for @fieldCardLabel.
  ///
  /// In en, this message translates to:
  /// **'Card label (e.g. \"Visa Platinum\")'**
  String get fieldCardLabel;

  /// No description provided for @fieldCardholderName.
  ///
  /// In en, this message translates to:
  /// **'Cardholder name'**
  String get fieldCardholderName;

  /// No description provided for @fieldCardNumber.
  ///
  /// In en, this message translates to:
  /// **'Card number'**
  String get fieldCardNumber;

  /// No description provided for @fieldExpiry.
  ///
  /// In en, this message translates to:
  /// **'Expiry (MM/YY)'**
  String get fieldExpiry;

  /// No description provided for @fieldCvv.
  ///
  /// In en, this message translates to:
  /// **'CVV (optional)'**
  String get fieldCvv;

  /// No description provided for @fieldCardPin.
  ///
  /// In en, this message translates to:
  /// **'PIN (optional)'**
  String get fieldCardPin;

  /// No description provided for @fieldCreditLimit.
  ///
  /// In en, this message translates to:
  /// **'Credit limit (optional)'**
  String get fieldCreditLimit;

  /// No description provided for @fieldAccountNumber.
  ///
  /// In en, this message translates to:
  /// **'Account number (optional)'**
  String get fieldAccountNumber;

  /// No description provided for @fieldNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes (optional)'**
  String get fieldNotes;

  /// No description provided for @fieldUrl.
  ///
  /// In en, this message translates to:
  /// **'URL (optional)'**
  String get fieldUrl;

  /// No description provided for @fieldUsername.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get fieldUsername;

  /// No description provided for @fieldPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get fieldPassword;

  /// No description provided for @fieldSeparator.
  ///
  /// In en, this message translates to:
  /// **'Separator'**
  String get fieldSeparator;

  /// No description provided for @fieldFolder.
  ///
  /// In en, this message translates to:
  /// **'Folder'**
  String get fieldFolder;

  /// No description provided for @fieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Label'**
  String get fieldLabel;

  /// No description provided for @fieldValue.
  ///
  /// In en, this message translates to:
  /// **'Value'**
  String get fieldValue;

  /// No description provided for @fieldCustomFields.
  ///
  /// In en, this message translates to:
  /// **'Custom fields'**
  String get fieldCustomFields;

  /// No description provided for @fieldLabelOptional.
  ///
  /// In en, this message translates to:
  /// **'{label} (optional)'**
  String fieldLabelOptional(String label);

  /// No description provided for @entryTypeNotSupported.
  ///
  /// In en, this message translates to:
  /// **'Entry type not yet supported.'**
  String get entryTypeNotSupported;

  /// No description provided for @csvColumnNone.
  ///
  /// In en, this message translates to:
  /// **'(none)'**
  String get csvColumnNone;

  /// No description provided for @csvPreviewLabel.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get csvPreviewLabel;

  /// No description provided for @csvImportButton.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get csvImportButton;

  /// No description provided for @gabbroVaultSection.
  ///
  /// In en, this message translates to:
  /// **'Gabbro vault'**
  String get gabbroVaultSection;

  /// No description provided for @genericCsvSection.
  ///
  /// In en, this message translates to:
  /// **'Generic CSV'**
  String get genericCsvSection;

  /// No description provided for @changePassphraseSuccess.
  ///
  /// In en, this message translates to:
  /// **'Passphrase changed successfully'**
  String get changePassphraseSuccess;

  /// No description provided for @changePassphraseButton.
  ///
  /// In en, this message translates to:
  /// **'Change passphrase'**
  String get changePassphraseButton;

  /// No description provided for @continueLabel.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueLabel;

  /// No description provided for @protectWithYubiKey.
  ///
  /// In en, this message translates to:
  /// **'Protect with YubiKey'**
  String get protectWithYubiKey;

  /// No description provided for @yubiKeySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Hardware security key (recommended)'**
  String get yubiKeySubtitle;

  /// No description provided for @accessibilityButton.
  ///
  /// In en, this message translates to:
  /// **'Accessibility'**
  String get accessibilityButton;

  /// No description provided for @aboutProjectSection.
  ///
  /// In en, this message translates to:
  /// **'Project'**
  String get aboutProjectSection;

  /// No description provided for @aboutLicenceSection.
  ///
  /// In en, this message translates to:
  /// **'Licence'**
  String get aboutLicenceSection;

  /// No description provided for @aboutOpenSourceSection.
  ///
  /// In en, this message translates to:
  /// **'Open source components'**
  String get aboutOpenSourceSection;

  /// No description provided for @aboutAttributionSection.
  ///
  /// In en, this message translates to:
  /// **'Attribution'**
  String get aboutAttributionSection;

  /// No description provided for @lengthLabel.
  ///
  /// In en, this message translates to:
  /// **'Length'**
  String get lengthLabel;

  /// No description provided for @wordsLabel.
  ///
  /// In en, this message translates to:
  /// **'Words'**
  String get wordsLabel;

  /// No description provided for @generateButton.
  ///
  /// In en, this message translates to:
  /// **'Generate'**
  String get generateButton;

  /// No description provided for @usePasswordButton.
  ///
  /// In en, this message translates to:
  /// **'Use this password'**
  String get usePasswordButton;

  /// No description provided for @showHidePassword.
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get showHidePassword;

  /// No description provided for @deleteVaultPostDeletion.
  ///
  /// In en, this message translates to:
  /// **'Your vault has been deleted. Create a new one to continue.'**
  String get deleteVaultPostDeletion;

  /// No description provided for @syncFilePassphraseLabel.
  ///
  /// In en, this message translates to:
  /// **'Vault passphrase'**
  String get syncFilePassphraseLabel;

  /// No description provided for @historyWarning.
  ///
  /// In en, this message translates to:
  /// **'Only 1 previous value is kept. History auto-purges based on your security settings.'**
  String get historyWarning;

  /// No description provided for @historyCurrent.
  ///
  /// In en, this message translates to:
  /// **'Current'**
  String get historyCurrent;

  /// No description provided for @historyPrevious.
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get historyPrevious;

  /// No description provided for @historySavedOn.
  ///
  /// In en, this message translates to:
  /// **'Saved {date}'**
  String historySavedOn(String date);

  /// No description provided for @historyExpiresAppend.
  ///
  /// In en, this message translates to:
  /// **'{saved} · expires {expires}'**
  String historyExpiresAppend(String saved, String expires);

  /// No description provided for @importIssueTitle.
  ///
  /// In en, this message translates to:
  /// **'Import issue ({index} of {total})'**
  String importIssueTitle(int index, int total);

  /// No description provided for @importIssueType.
  ///
  /// In en, this message translates to:
  /// **'Type: {category}'**
  String importIssueType(String category);

  /// No description provided for @importIssueHelp.
  ///
  /// In en, this message translates to:
  /// **'Edit to correct and save this entry, or skip to discard it.'**
  String get importIssueHelp;

  /// No description provided for @entriesSkipped.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 entry skipped} other{{count} entries skipped}}'**
  String entriesSkipped(int count);

  /// No description provided for @skippedEntriesNote.
  ///
  /// In en, this message translates to:
  /// **'These entries already exist in your vault and were not overwritten:'**
  String get skippedEntriesNote;

  /// No description provided for @syncDeleteEntryContent.
  ///
  /// In en, this message translates to:
  /// **'The other device deleted \'{title}\'.\n\nDelete it here too, or keep it?'**
  String syncDeleteEntryContent(String title);

  /// No description provided for @folderConflictContent.
  ///
  /// In en, this message translates to:
  /// **'\'{title}\' is in different folders on each device.\n\nThis device: {local}\nOther device: {incoming}'**
  String folderConflictContent(String title, String local, String incoming);

  /// No description provided for @folderConflictKeepUnfoldered.
  ///
  /// In en, this message translates to:
  /// **'Keep unfoldered'**
  String get folderConflictKeepUnfoldered;

  /// No description provided for @folderConflictKeepLocal.
  ///
  /// In en, this message translates to:
  /// **'Keep \"{folder}\"'**
  String folderConflictKeepLocal(String folder);

  /// No description provided for @folderConflictMoveUnfoldered.
  ///
  /// In en, this message translates to:
  /// **'Move to unfoldered'**
  String get folderConflictMoveUnfoldered;

  /// No description provided for @folderConflictMoveIncoming.
  ///
  /// In en, this message translates to:
  /// **'Move to \"{folder}\"'**
  String folderConflictMoveIncoming(String folder);

  /// No description provided for @vaultSynced.
  ///
  /// In en, this message translates to:
  /// **'Vault synced — {added} added, {updated} updated, {deleted} deleted.'**
  String vaultSynced(int added, int updated, int deleted);

  /// No description provided for @syncPassphraseMismatch.
  ///
  /// In en, this message translates to:
  /// **'This vault file uses a different passphrase. Sync is only supported between vaults that share a passphrase.'**
  String get syncPassphraseMismatch;

  /// No description provided for @reviewSensitiveFields.
  ///
  /// In en, this message translates to:
  /// **'Sensitive fields'**
  String get reviewSensitiveFields;

  /// No description provided for @reviewOtherFields.
  ///
  /// In en, this message translates to:
  /// **'Other fields'**
  String get reviewOtherFields;

  /// No description provided for @reviewPasswordChanged.
  ///
  /// In en, this message translates to:
  /// **'Password changed'**
  String get reviewPasswordChanged;

  /// No description provided for @reviewCvvChanged.
  ///
  /// In en, this message translates to:
  /// **'CVV changed'**
  String get reviewCvvChanged;

  /// No description provided for @reviewPinChanged.
  ///
  /// In en, this message translates to:
  /// **'PIN changed'**
  String get reviewPinChanged;

  /// No description provided for @reviewTransactionPasswordChanged.
  ///
  /// In en, this message translates to:
  /// **'Transaction password changed'**
  String get reviewTransactionPasswordChanged;

  /// No description provided for @tooltipShowValues.
  ///
  /// In en, this message translates to:
  /// **'Show values'**
  String get tooltipShowValues;

  /// No description provided for @reviewOld.
  ///
  /// In en, this message translates to:
  /// **'Old'**
  String get reviewOld;

  /// No description provided for @reviewNew.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get reviewNew;

  /// No description provided for @reviewEmpty.
  ///
  /// In en, this message translates to:
  /// **'(empty)'**
  String get reviewEmpty;

  /// No description provided for @reviewFieldUrl.
  ///
  /// In en, this message translates to:
  /// **'URL'**
  String get reviewFieldUrl;

  /// No description provided for @reviewFieldNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get reviewFieldNotes;

  /// No description provided for @reviewFieldContent.
  ///
  /// In en, this message translates to:
  /// **'Content'**
  String get reviewFieldContent;

  /// No description provided for @reviewFieldEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get reviewFieldEmail;

  /// No description provided for @reviewFieldPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get reviewFieldPhone;

  /// No description provided for @reviewFieldAddress.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get reviewFieldAddress;

  /// No description provided for @reviewFieldCardLabel.
  ///
  /// In en, this message translates to:
  /// **'Card label'**
  String get reviewFieldCardLabel;

  /// No description provided for @reviewFieldStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get reviewFieldStatus;

  /// No description provided for @reviewFieldCardholder.
  ///
  /// In en, this message translates to:
  /// **'Cardholder'**
  String get reviewFieldCardholder;

  /// No description provided for @reviewFieldExpiry.
  ///
  /// In en, this message translates to:
  /// **'Expiry'**
  String get reviewFieldExpiry;

  /// No description provided for @reviewFieldCreditLimit.
  ///
  /// In en, this message translates to:
  /// **'Credit limit'**
  String get reviewFieldCreditLimit;

  /// No description provided for @reviewFieldAccountNumber.
  ///
  /// In en, this message translates to:
  /// **'Account number'**
  String get reviewFieldAccountNumber;

  /// No description provided for @reviewFieldNetwork.
  ///
  /// In en, this message translates to:
  /// **'Network'**
  String get reviewFieldNetwork;

  /// No description provided for @reviewFieldBank.
  ///
  /// In en, this message translates to:
  /// **'Bank'**
  String get reviewFieldBank;

  /// No description provided for @reviewFieldFilename.
  ///
  /// In en, this message translates to:
  /// **'Filename'**
  String get reviewFieldFilename;

  /// No description provided for @reviewFieldSize.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get reviewFieldSize;

  /// No description provided for @reviewFieldCardNumber.
  ///
  /// In en, this message translates to:
  /// **'Number'**
  String get reviewFieldCardNumber;

  /// No description provided for @reviewFieldCVV.
  ///
  /// In en, this message translates to:
  /// **'CVV'**
  String get reviewFieldCVV;

  /// No description provided for @reviewFieldTransactionPassword.
  ///
  /// In en, this message translates to:
  /// **'Transaction password'**
  String get reviewFieldTransactionPassword;

  /// No description provided for @timestampCreated.
  ///
  /// In en, this message translates to:
  /// **'Created'**
  String get timestampCreated;

  /// No description provided for @timestampUpdated.
  ///
  /// In en, this message translates to:
  /// **'Updated'**
  String get timestampUpdated;

  /// No description provided for @timestampUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get timestampUnknown;

  /// No description provided for @noTitleFallback.
  ///
  /// In en, this message translates to:
  /// **'(no title)'**
  String get noTitleFallback;

  /// No description provided for @tooltipExportFile.
  ///
  /// In en, this message translates to:
  /// **'Export file'**
  String get tooltipExportFile;

  /// No description provided for @tooltipEditEntry.
  ///
  /// In en, this message translates to:
  /// **'Edit entry'**
  String get tooltipEditEntry;

  /// No description provided for @tooltipDeleteEntry.
  ///
  /// In en, this message translates to:
  /// **'Delete entry'**
  String get tooltipDeleteEntry;

  /// No description provided for @exportLabel.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get exportLabel;

  /// No description provided for @customEntryFieldsHeader.
  ///
  /// In en, this message translates to:
  /// **'Fields'**
  String get customEntryFieldsHeader;

  /// No description provided for @copiedNeverClears.
  ///
  /// In en, this message translates to:
  /// **'Copied — clipboard never clears automatically'**
  String get copiedNeverClears;

  /// No description provided for @copiedClears30s.
  ///
  /// In en, this message translates to:
  /// **'Copied — clipboard clears in 30s'**
  String get copiedClears30s;

  /// No description provided for @copiedClears60s.
  ///
  /// In en, this message translates to:
  /// **'Copied — clipboard clears in 60s'**
  String get copiedClears60s;

  /// No description provided for @copiedClears2min.
  ///
  /// In en, this message translates to:
  /// **'Copied — clipboard clears in 2 min'**
  String get copiedClears2min;

  /// No description provided for @passwordBreakdownTitle.
  ///
  /// In en, this message translates to:
  /// **'Password breakdown'**
  String get passwordBreakdownTitle;

  /// No description provided for @charTypeUppercase.
  ///
  /// In en, this message translates to:
  /// **'Uppercase'**
  String get charTypeUppercase;

  /// No description provided for @charTypeLowercase.
  ///
  /// In en, this message translates to:
  /// **'Lowercase'**
  String get charTypeLowercase;

  /// No description provided for @charTypeDigit.
  ///
  /// In en, this message translates to:
  /// **'Digit'**
  String get charTypeDigit;

  /// No description provided for @charTypeSymbol.
  ///
  /// In en, this message translates to:
  /// **'Symbol'**
  String get charTypeSymbol;

  /// No description provided for @charTypeLetter.
  ///
  /// In en, this message translates to:
  /// **'Letter'**
  String get charTypeLetter;

  /// No description provided for @exportIncludeDate.
  ///
  /// In en, this message translates to:
  /// **'Include date in filename'**
  String get exportIncludeDate;

  /// No description provided for @exportChooseFormat.
  ///
  /// In en, this message translates to:
  /// **'Choose an export format.'**
  String get exportChooseFormat;

  /// No description provided for @exportUnencryptedWarning.
  ///
  /// In en, this message translates to:
  /// **'Completely unencrypted — all secrets will be written in plain text. Store this file securely and delete it after use.'**
  String get exportUnencryptedWarning;

  /// No description provided for @exportPassphraseOnlyNote.
  ///
  /// In en, this message translates to:
  /// **'Protected by your passphrase only. YubiKey is not required to import.'**
  String get exportPassphraseOnlyNote;

  /// No description provided for @exportChooseDestinationJson.
  ///
  /// In en, this message translates to:
  /// **'Choose a destination for your exported JSON file.'**
  String get exportChooseDestinationJson;

  /// No description provided for @exportChooseDestinationVault.
  ///
  /// In en, this message translates to:
  /// **'Choose a destination for your exported vault file.'**
  String get exportChooseDestinationVault;

  /// No description provided for @exportTwoFilesNote.
  ///
  /// In en, this message translates to:
  /// **'Two files will be written: vault.gabbro and vault.gabbro.sha256'**
  String get exportTwoFilesNote;

  /// No description provided for @exportSelectDestination.
  ///
  /// In en, this message translates to:
  /// **'Select a destination.'**
  String get exportSelectDestination;

  /// No description provided for @aboutVersion.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String aboutVersion(String version);

  /// No description provided for @aboutTagline.
  ///
  /// In en, this message translates to:
  /// **'A post-quantum password manager'**
  String get aboutTagline;

  /// No description provided for @aboutSourceCode.
  ///
  /// In en, this message translates to:
  /// **'Source code'**
  String get aboutSourceCode;

  /// No description provided for @aboutReportIssue.
  ///
  /// In en, this message translates to:
  /// **'Report an issue'**
  String get aboutReportIssue;

  /// No description provided for @aboutSupportGabbro.
  ///
  /// In en, this message translates to:
  /// **'Support Gabbro'**
  String get aboutSupportGabbro;

  /// No description provided for @aboutLicenceBody.
  ///
  /// In en, this message translates to:
  /// **'Gabbro is free and open source software, licensed under the GNU General Public License v3.0 only (GPL-3.0-only).\n\nYou are free to use, study, and redistribute this software under the terms of that licence.'**
  String get aboutLicenceBody;

  /// No description provided for @aboutOwnerRole.
  ///
  /// In en, this message translates to:
  /// **'Project owner, architect, and lead developer:'**
  String get aboutOwnerRole;

  /// No description provided for @aboutAiPartner.
  ///
  /// In en, this message translates to:
  /// **'AI development partner:'**
  String get aboutAiPartner;

  /// No description provided for @aboutNoTelemetry.
  ///
  /// In en, this message translates to:
  /// **'Gabbro makes no outbound network connections. No telemetry, no analytics, no accounts.'**
  String get aboutNoTelemetry;

  /// No description provided for @strengthTierTerrible.
  ///
  /// In en, this message translates to:
  /// **'Terrible'**
  String get strengthTierTerrible;

  /// No description provided for @strengthTierWeak.
  ///
  /// In en, this message translates to:
  /// **'Weak'**
  String get strengthTierWeak;

  /// No description provided for @strengthTierFair.
  ///
  /// In en, this message translates to:
  /// **'Fair'**
  String get strengthTierFair;

  /// No description provided for @strengthTierStrong.
  ///
  /// In en, this message translates to:
  /// **'Strong'**
  String get strengthTierStrong;

  /// No description provided for @strengthTierVeryStrong.
  ///
  /// In en, this message translates to:
  /// **'Very strong'**
  String get strengthTierVeryStrong;

  /// No description provided for @strengthTierExcellent.
  ///
  /// In en, this message translates to:
  /// **'Excellent'**
  String get strengthTierExcellent;

  /// No description provided for @yubiKeyProtectedNote.
  ///
  /// In en, this message translates to:
  /// **'YubiKey-protected vault — your YubiKey binding will be preserved.'**
  String get yubiKeyProtectedNote;

  /// No description provided for @yubiKeyPinRequired.
  ///
  /// In en, this message translates to:
  /// **'YubiKey PIN is required'**
  String get yubiKeyPinRequired;

  /// No description provided for @tapYubiKeyNow.
  ///
  /// In en, this message translates to:
  /// **'Tap your YubiKey now…'**
  String get tapYubiKeyNow;

  /// No description provided for @touchYubiKeyToAuthorize.
  ///
  /// In en, this message translates to:
  /// **'Touch your YubiKey to authorize this change.'**
  String get touchYubiKeyToAuthorize;

  /// No description provided for @currentPassphraseRequired.
  ///
  /// In en, this message translates to:
  /// **'Current passphrase is required'**
  String get currentPassphraseRequired;

  /// No description provided for @newPassphraseRequired.
  ///
  /// In en, this message translates to:
  /// **'New passphrase is required'**
  String get newPassphraseRequired;

  /// No description provided for @passphraseTooWeak.
  ///
  /// In en, this message translates to:
  /// **'Passphrase is too weak'**
  String get passphraseTooWeak;

  /// No description provided for @confirmPassphraseRequired.
  ///
  /// In en, this message translates to:
  /// **'Please confirm your new passphrase'**
  String get confirmPassphraseRequired;

  /// No description provided for @passphrasesDoNotMatch.
  ///
  /// In en, this message translates to:
  /// **'Passphrases do not match'**
  String get passphrasesDoNotMatch;

  /// No description provided for @passphrasesMatch.
  ///
  /// In en, this message translates to:
  /// **'✓ Passphrases match'**
  String get passphrasesMatch;

  /// No description provided for @passphrasesNoMatch.
  ///
  /// In en, this message translates to:
  /// **'✗ Passphrases do not match'**
  String get passphrasesNoMatch;

  /// No description provided for @entropyDisplay.
  ///
  /// In en, this message translates to:
  /// **'{tier} · {bits} bits'**
  String entropyDisplay(String tier, String bits);

  /// No description provided for @transportError.
  ///
  /// In en, this message translates to:
  /// **'Transport error.'**
  String get transportError;

  /// No description provided for @authorizationFailed.
  ///
  /// In en, this message translates to:
  /// **'Authorization failed — check your PIN and try again.'**
  String get authorizationFailed;

  /// No description provided for @unlockEnterPassphraseAndPin.
  ///
  /// In en, this message translates to:
  /// **'Enter your passphrase and YubiKey PIN to unlock'**
  String get unlockEnterPassphraseAndPin;

  /// No description provided for @unlockEnterPassphrase.
  ///
  /// In en, this message translates to:
  /// **'Enter your passphrase to unlock'**
  String get unlockEnterPassphrase;

  /// No description provided for @unlockEntropyDisplay.
  ///
  /// In en, this message translates to:
  /// **'{tier} · {bits} bits of entropy'**
  String unlockEntropyDisplay(String tier, String bits);

  /// No description provided for @insertYubiKeyAndTap.
  ///
  /// In en, this message translates to:
  /// **'Insert your YubiKey and tap when it flashes'**
  String get insertYubiKeyAndTap;

  /// No description provided for @unlockErrorPassphrase.
  ///
  /// In en, this message translates to:
  /// **'Could not unlock vault. Check your passphrase.'**
  String get unlockErrorPassphrase;

  /// No description provided for @unlockErrorPassphraseAndPin.
  ///
  /// In en, this message translates to:
  /// **'Could not unlock vault. Check your passphrase and YubiKey PIN.'**
  String get unlockErrorPassphraseAndPin;

  /// No description provided for @importSelectFile.
  ///
  /// In en, this message translates to:
  /// **'Select a file.'**
  String get importSelectFile;

  /// No description provided for @importFileNotFound.
  ///
  /// In en, this message translates to:
  /// **'File not found.'**
  String get importFileNotFound;

  /// No description provided for @importEnterPassphrase.
  ///
  /// In en, this message translates to:
  /// **'Enter the passphrase for this vault.'**
  String get importEnterPassphrase;

  /// No description provided for @importDuplicateWarning.
  ///
  /// In en, this message translates to:
  /// **'Entries whose UUID already exists in your vault will be skipped automatically. You will be shown a summary.'**
  String get importDuplicateWarning;

  /// No description provided for @importGabbroSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sync entries from another Gabbro vault (.gabbro file)'**
  String get importGabbroSubtitle;

  /// No description provided for @importEnpassSubtitle.
  ///
  /// In en, this message translates to:
  /// **'JSON export from Enpass (Tools → Export)'**
  String get importEnpassSubtitle;

  /// No description provided for @importBitwardenSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Unencrypted JSON export from Bitwarden (Tools → Export Vault)'**
  String get importBitwardenSubtitle;

  /// No description provided for @importCsvSubtitle.
  ///
  /// In en, this message translates to:
  /// **'CSV export from any password manager'**
  String get importCsvSubtitle;

  /// No description provided for @vaultNameAlreadyExists.
  ///
  /// In en, this message translates to:
  /// **'A vault named \"{alias}\" already exists.'**
  String vaultNameAlreadyExists(String alias);

  /// No description provided for @deleteVaultContent.
  ///
  /// In en, this message translates to:
  /// **'This will permanently delete \"{alias}\" and all its data.\n\nFile: {path}\n\nThis cannot be undone.'**
  String deleteVaultContent(String alias, String path);

  /// No description provided for @deleteVaultYubikeyContent.
  ///
  /// In en, this message translates to:
  /// **'This will permanently delete \"{alias}\" and remove its YubiKey binding.\n\nFile: {path}\n\nThis cannot be undone.'**
  String deleteVaultYubikeyContent(String alias, String path);

  /// No description provided for @yubiKeyAuthorizeDeletion.
  ///
  /// In en, this message translates to:
  /// **'Enter your PIN and touch your YubiKey to authorize this deletion.'**
  String get yubiKeyAuthorizeDeletion;

  /// No description provided for @deleteVaultTooltip.
  ///
  /// In en, this message translates to:
  /// **'Delete vault'**
  String get deleteVaultTooltip;

  /// No description provided for @yubiKeySecurityWarning.
  ///
  /// In en, this message translates to:
  /// **'Security warning'**
  String get yubiKeySecurityWarning;

  /// No description provided for @removeYubiKeyTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove YubiKey'**
  String get removeYubiKeyTitle;

  /// No description provided for @yubiKeyLastKeyRiskWarning.
  ///
  /// In en, this message translates to:
  /// **'WARNING: if that remaining key is lost, damaged, or stolen, vault access will be permanently impossible. There is no recovery path.'**
  String get yubiKeyLastKeyRiskWarning;

  /// No description provided for @onlyOneKeyRegisteredWarning.
  ///
  /// In en, this message translates to:
  /// **'Only one key registered. If this key is lost, vault access is permanently impossible.'**
  String get onlyOneKeyRegisteredWarning;

  /// No description provided for @tapRegisterNfc.
  ///
  /// In en, this message translates to:
  /// **'Hold key to phone to register'**
  String get tapRegisterNfc;

  /// No description provided for @tapRegisterUsb.
  ///
  /// In en, this message translates to:
  /// **'Once connected, tap the key to register'**
  String get tapRegisterUsb;

  /// No description provided for @tapActivateNfc.
  ///
  /// In en, this message translates to:
  /// **'Hold key to phone again to activate'**
  String get tapActivateNfc;

  /// No description provided for @tapActivateUsb.
  ///
  /// In en, this message translates to:
  /// **'Once connected, tap the key again to activate'**
  String get tapActivateUsb;

  /// No description provided for @failedToRegisterKey.
  ///
  /// In en, this message translates to:
  /// **'Failed to register key: {error}'**
  String failedToRegisterKey(String error);

  /// No description provided for @failedToActivateKey.
  ///
  /// In en, this message translates to:
  /// **'Failed to activate key: {error}'**
  String failedToActivateKey(String error);

  /// No description provided for @keyDefaultTitle.
  ///
  /// In en, this message translates to:
  /// **'Key {index}'**
  String keyDefaultTitle(int index);

  /// No description provided for @tapYubiKeyToRegister.
  ///
  /// In en, this message translates to:
  /// **'Tap your new YubiKey to register…'**
  String get tapYubiKeyToRegister;

  /// No description provided for @tapYubiKeyToActivate.
  ///
  /// In en, this message translates to:
  /// **'Tap your new YubiKey again to activate…'**
  String get tapYubiKeyToActivate;

  /// No description provided for @editAliasTooltip.
  ///
  /// In en, this message translates to:
  /// **'Edit alias'**
  String get editAliasTooltip;

  /// No description provided for @cannotRemoveLastKey.
  ///
  /// In en, this message translates to:
  /// **'Cannot remove the last key'**
  String get cannotRemoveLastKey;

  /// No description provided for @removeKeyTooltip.
  ///
  /// In en, this message translates to:
  /// **'Remove key'**
  String get removeKeyTooltip;

  /// No description provided for @manageYubiKeysError.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String manageYubiKeysError(String error);

  /// No description provided for @generatorModeClassic.
  ///
  /// In en, this message translates to:
  /// **'Classic'**
  String get generatorModeClassic;

  /// No description provided for @generatorModePassphrase.
  ///
  /// In en, this message translates to:
  /// **'Passphrase'**
  String get generatorModePassphrase;

  /// No description provided for @charSetsHeader.
  ///
  /// In en, this message translates to:
  /// **'Character sets'**
  String get charSetsHeader;

  /// No description provided for @languageHeader.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageHeader;

  /// No description provided for @separatorLabel.
  ///
  /// In en, this message translates to:
  /// **'Separator'**
  String get separatorLabel;

  /// No description provided for @capitaliseWords.
  ///
  /// In en, this message translates to:
  /// **'Capitalise words'**
  String get capitaliseWords;

  /// No description provided for @appendDigit.
  ///
  /// In en, this message translates to:
  /// **'Append a digit'**
  String get appendDigit;

  /// No description provided for @entropyBitsDisplay.
  ///
  /// In en, this message translates to:
  /// **'~{bits} bits entropy'**
  String entropyBitsDisplay(String bits);

  /// No description provided for @selectAtLeastOneCharSet.
  ///
  /// In en, this message translates to:
  /// **'Select at least one character set'**
  String get selectAtLeastOneCharSet;

  /// No description provided for @passwordMinLengthNote.
  ///
  /// In en, this message translates to:
  /// **'Passwords are at least 32 characters. If a site has a shorter limit, copy the first characters you need.'**
  String get passwordMinLengthNote;

  /// No description provided for @excludeAmbiguousChars.
  ///
  /// In en, this message translates to:
  /// **'Exclude ambiguous characters (0, O, l, 1, I)'**
  String get excludeAmbiguousChars;

  /// No description provided for @onboardingGetStarted.
  ///
  /// In en, this message translates to:
  /// **'Create your vault to get started.'**
  String get onboardingGetStarted;

  /// No description provided for @onboardingVaultName.
  ///
  /// In en, this message translates to:
  /// **'Vault name'**
  String get onboardingVaultName;

  /// No description provided for @onboardingAliasRequired.
  ///
  /// In en, this message translates to:
  /// **'Alias is required'**
  String get onboardingAliasRequired;

  /// No description provided for @onboardingNewVaultLocation.
  ///
  /// In en, this message translates to:
  /// **'New vault location (same as before)'**
  String get onboardingNewVaultLocation;

  /// No description provided for @onboardingVaultLocation.
  ///
  /// In en, this message translates to:
  /// **'Vault location'**
  String get onboardingVaultLocation;

  /// No description provided for @onboardingLoadingPath.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get onboardingLoadingPath;

  /// No description provided for @onboardingPathHint.
  ///
  /// In en, this message translates to:
  /// **'Path to vault file'**
  String get onboardingPathHint;

  /// No description provided for @onboardingPathRequired.
  ///
  /// In en, this message translates to:
  /// **'Path is required'**
  String get onboardingPathRequired;

  /// No description provided for @onboardingReusePassphraseHint.
  ///
  /// In en, this message translates to:
  /// **'Choose a new master passphrase, or re-use your previous one if you prefer.'**
  String get onboardingReusePassphraseHint;

  /// No description provided for @onboardingPassphraseRequired.
  ///
  /// In en, this message translates to:
  /// **'Passphrase is required'**
  String get onboardingPassphraseRequired;

  /// No description provided for @onboardingConfirmRequired.
  ///
  /// In en, this message translates to:
  /// **'Please confirm your passphrase'**
  String get onboardingConfirmRequired;

  /// No description provided for @onboardingPrimaryKeyPin.
  ///
  /// In en, this message translates to:
  /// **'Primary key PIN'**
  String get onboardingPrimaryKeyPin;

  /// No description provided for @onboardingBackupKeyPin.
  ///
  /// In en, this message translates to:
  /// **'Backup key PIN'**
  String get onboardingBackupKeyPin;

  /// No description provided for @onboardingKeyNPin.
  ///
  /// In en, this message translates to:
  /// **'Key {n} PIN'**
  String onboardingKeyNPin(int n);

  /// No description provided for @onboardingYubikeyTapInstruction.
  ///
  /// In en, this message translates to:
  /// **'You will tap each YubiKey twice (4 taps total). Between the two keys, you will be prompted to swap.'**
  String get onboardingYubikeyTapInstruction;

  /// No description provided for @onboardingYubikeySlowNote.
  ///
  /// In en, this message translates to:
  /// **'Vault creation with YubiKey takes 20–30 seconds. The app may appear unresponsive — this is normal.'**
  String get onboardingYubikeySlowNote;

  /// No description provided for @onboardingStep1Label.
  ///
  /// In en, this message translates to:
  /// **'Register primary key'**
  String get onboardingStep1Label;

  /// No description provided for @onboardingStep1Hint.
  ///
  /// In en, this message translates to:
  /// **'Touch your YubiKey now'**
  String get onboardingStep1Hint;

  /// No description provided for @onboardingStep2Label.
  ///
  /// In en, this message translates to:
  /// **'Activate primary key'**
  String get onboardingStep2Label;

  /// No description provided for @onboardingStep2Hint.
  ///
  /// In en, this message translates to:
  /// **'Touch your YubiKey again'**
  String get onboardingStep2Hint;

  /// No description provided for @onboardingStep3Label.
  ///
  /// In en, this message translates to:
  /// **'Swap to backup key'**
  String get onboardingStep3Label;

  /// No description provided for @onboardingStep3Hint.
  ///
  /// In en, this message translates to:
  /// **'Remove your primary key, then connect your backup YubiKey'**
  String get onboardingStep3Hint;

  /// No description provided for @onboardingStep4Label.
  ///
  /// In en, this message translates to:
  /// **'Register backup key'**
  String get onboardingStep4Label;

  /// No description provided for @onboardingStep4Hint.
  ///
  /// In en, this message translates to:
  /// **'Touch your backup YubiKey'**
  String get onboardingStep4Hint;

  /// No description provided for @onboardingStep5Label.
  ///
  /// In en, this message translates to:
  /// **'Activate backup key'**
  String get onboardingStep5Label;

  /// No description provided for @onboardingStep5Hint.
  ///
  /// In en, this message translates to:
  /// **'Touch your backup YubiKey one final time'**
  String get onboardingStep5Hint;

  /// No description provided for @textSizePreview.
  ///
  /// In en, this message translates to:
  /// **'Gabbro is an intrusive igneous rock that is Mg- and Fe-rich and coarse-grained.'**
  String get textSizePreview;

  /// No description provided for @fieldCardStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get fieldCardStatus;

  /// No description provided for @fieldPaymentNetwork.
  ///
  /// In en, this message translates to:
  /// **'Payment network'**
  String get fieldPaymentNetwork;

  /// No description provided for @cardStatusActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get cardStatusActive;

  /// No description provided for @cardStatusLapsed.
  ///
  /// In en, this message translates to:
  /// **'Lapsed'**
  String get cardStatusLapsed;

  /// No description provided for @cardStatusInactive.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get cardStatusInactive;

  /// No description provided for @validatorTitleRequired.
  ///
  /// In en, this message translates to:
  /// **'Title is required'**
  String get validatorTitleRequired;

  /// No description provided for @validatorUsernameRequired.
  ///
  /// In en, this message translates to:
  /// **'Username is required'**
  String get validatorUsernameRequired;

  /// No description provided for @validatorPasswordRequired.
  ///
  /// In en, this message translates to:
  /// **'Password is required'**
  String get validatorPasswordRequired;

  /// No description provided for @validatorContentRequired.
  ///
  /// In en, this message translates to:
  /// **'Content is required'**
  String get validatorContentRequired;

  /// No description provided for @validatorFirstNameRequired.
  ///
  /// In en, this message translates to:
  /// **'First name is required'**
  String get validatorFirstNameRequired;

  /// No description provided for @validatorLastNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Last name is required'**
  String get validatorLastNameRequired;

  /// No description provided for @validatorCardLabelRequired.
  ///
  /// In en, this message translates to:
  /// **'Card label is required'**
  String get validatorCardLabelRequired;

  /// No description provided for @validatorCardholderRequired.
  ///
  /// In en, this message translates to:
  /// **'Cardholder name is required'**
  String get validatorCardholderRequired;

  /// No description provided for @validatorCardNumberRequired.
  ///
  /// In en, this message translates to:
  /// **'Card number is required'**
  String get validatorCardNumberRequired;

  /// No description provided for @validatorCardNumberLength.
  ///
  /// In en, this message translates to:
  /// **'Card number must be 6–19 digits'**
  String get validatorCardNumberLength;

  /// No description provided for @validatorExpiryRequired.
  ///
  /// In en, this message translates to:
  /// **'Expiry is required'**
  String get validatorExpiryRequired;

  /// No description provided for @validatorExpiryFormat.
  ///
  /// In en, this message translates to:
  /// **'Use MM/YY format'**
  String get validatorExpiryFormat;

  /// No description provided for @validatorExpiryMonth.
  ///
  /// In en, this message translates to:
  /// **'Month must be 01–12'**
  String get validatorExpiryMonth;

  /// No description provided for @validatorCvvLength.
  ///
  /// In en, this message translates to:
  /// **'CVV must be 3 or 4 digits'**
  String get validatorCvvLength;

  /// No description provided for @validatorLabelRequired.
  ///
  /// In en, this message translates to:
  /// **'Label required'**
  String get validatorLabelRequired;

  /// No description provided for @validatorStatusRequired.
  ///
  /// In en, this message translates to:
  /// **'Status is required'**
  String get validatorStatusRequired;

  /// No description provided for @sectionBiometricUnlock.
  ///
  /// In en, this message translates to:
  /// **'Biometric unlock'**
  String get sectionBiometricUnlock;

  /// No description provided for @biometricUnlockDescription.
  ///
  /// In en, this message translates to:
  /// **'Use your fingerprint or face to unlock the vault instead of typing your passphrase.'**
  String get biometricUnlockDescription;

  /// No description provided for @biometricUnlockTitle.
  ///
  /// In en, this message translates to:
  /// **'Enable biometric unlock'**
  String get biometricUnlockTitle;

  /// No description provided for @biometricUnlockNote.
  ///
  /// In en, this message translates to:
  /// **'All biometrics enrolled on this device will work — not just the one used to enrol.'**
  String get biometricUnlockNote;

  /// No description provided for @biometricUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Biometric unlock is not available on this device. No biometric sensor was found or no biometrics are enrolled in system settings.'**
  String get biometricUnavailable;

  /// No description provided for @biometricDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'About biometric unlock'**
  String get biometricDialogTitle;

  /// No description provided for @biometricDialogBody.
  ///
  /// In en, this message translates to:
  /// **'When enabled, Gabbro encrypts your master passphrase and stores it on this device, protected by your biometrics. Your passphrase is decrypted only at the moment of unlock.\n\nYour fingerprint or face data is never stored by Gabbro — it stays in your phone\'s secure chip.'**
  String get biometricDialogBody;

  /// No description provided for @biometricDialogAllBiometrics.
  ///
  /// In en, this message translates to:
  /// **'All biometrics currently enrolled on this device will be able to unlock Gabbro — you cannot restrict it to a specific fingerprint.'**
  String get biometricDialogAllBiometrics;

  /// No description provided for @biometricDialogInvalidation.
  ///
  /// In en, this message translates to:
  /// **'If any new biometric is added to this phone (including a second fingerprint), this setting will be automatically disabled and you will need to set it up again.'**
  String get biometricDialogInvalidation;

  /// No description provided for @biometricDialogRecommendation.
  ///
  /// In en, this message translates to:
  /// **'Recommendation: keep this disabled if you have a high threat model or share this device.'**
  String get biometricDialogRecommendation;

  /// No description provided for @biometricInvalidated.
  ///
  /// In en, this message translates to:
  /// **'Biometric unlock was disabled because the biometrics on this device changed (a new fingerprint or face was added in system settings). This is a security measure. Please re-enter your passphrase and enable biometric unlock again if you wish to continue using this feature.'**
  String get biometricInvalidated;

  /// No description provided for @useBiometrics.
  ///
  /// In en, this message translates to:
  /// **'Use biometrics'**
  String get useBiometrics;

  /// No description provided for @biometricCancelled.
  ///
  /// In en, this message translates to:
  /// **'Biometric authentication was not completed. Enter your passphrase to unlock.'**
  String get biometricCancelled;

  /// No description provided for @biometricEnrollTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter your passphrase'**
  String get biometricEnrollTitle;

  /// No description provided for @biometricEnrollDescription.
  ///
  /// In en, this message translates to:
  /// **'Enter your master passphrase to enable biometric unlock.'**
  String get biometricEnrollDescription;

  /// No description provided for @biometricYubikeyHint.
  ///
  /// In en, this message translates to:
  /// **'Enter your YubiKey PIN below, then tap Use biometrics, then tap your YubiKey.'**
  String get biometricYubikeyHint;

  /// No description provided for @helpTitle.
  ///
  /// In en, this message translates to:
  /// **'Help'**
  String get helpTitle;

  /// No description provided for @menuHelp.
  ///
  /// In en, this message translates to:
  /// **'Help'**
  String get menuHelp;

  /// No description provided for @helpCaptionCreate.
  ///
  /// In en, this message translates to:
  /// **'Create a vault: enter a name, passphrase, and optionally protect it with a YubiKey'**
  String get helpCaptionCreate;

  /// No description provided for @helpCaptionEmpty.
  ///
  /// In en, this message translates to:
  /// **'Tap + to add your first entry'**
  String get helpCaptionEmpty;

  /// No description provided for @helpCaptionDetail.
  ///
  /// In en, this message translates to:
  /// **'Tap the eye icon to reveal a password, then long-press it to view a detailed character breakdown'**
  String get helpCaptionDetail;

  /// No description provided for @helpCaptionTitleSearch.
  ///
  /// In en, this message translates to:
  /// **'By default, the search bar searches entry titles only'**
  String get helpCaptionTitleSearch;

  /// No description provided for @helpCaptionFullSearch.
  ///
  /// In en, this message translates to:
  /// **'Tap the magnifying glass to switch to full-field search; tap again to return to title-only'**
  String get helpCaptionFullSearch;

  /// No description provided for @helpCaptionFilter.
  ///
  /// In en, this message translates to:
  /// **'Use the filter chips to show only entries of a specific type'**
  String get helpCaptionFilter;

  /// No description provided for @helpCaptionFolders.
  ///
  /// In en, this message translates to:
  /// **'Use the folder picker to filter entries by folder'**
  String get helpCaptionFolders;

  /// No description provided for @helpCaptionSelect.
  ///
  /// In en, this message translates to:
  /// **'Long-tap an entry to enter select mode; add more items, then assign to a folder or delete. Tap X to exit.'**
  String get helpCaptionSelect;

  /// No description provided for @helpCaptionJumpToLetter.
  ///
  /// In en, this message translates to:
  /// **'Tap a letter on the index bar to jump to that section'**
  String get helpCaptionJumpToLetter;

  /// No description provided for @helpCaptionBreakdown.
  ///
  /// In en, this message translates to:
  /// **'Tap the eye icon to reveal a password, then long-press it to view a detailed character breakdown'**
  String get helpCaptionBreakdown;

  /// No description provided for @helpCaptionManageVaults.
  ///
  /// In en, this message translates to:
  /// **'In Manage vaults, rename or delete vaults, or add a new one'**
  String get helpCaptionManageVaults;

  /// No description provided for @helpCaptionUnlock.
  ///
  /// In en, this message translates to:
  /// **'Enter your passphrase to unlock your vault'**
  String get helpCaptionUnlock;

  /// No description provided for @helpCaptionVaultSync.
  ///
  /// In en, this message translates to:
  /// **'Encrypted vault sync process'**
  String get helpCaptionVaultSync;

  /// No description provided for @passphraseNoWordlist.
  ///
  /// In en, this message translates to:
  /// **'No wordlist for your language yet. Using English.'**
  String get passphraseNoWordlist;

  /// No description provided for @manageFoldersDefaultNote.
  ///
  /// In en, this message translates to:
  /// **'Default folders can be renamed or deleted.'**
  String get manageFoldersDefaultNote;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>[
    'bg',
    'cs',
    'da',
    'de',
    'el',
    'en',
    'es',
    'et',
    'eu',
    'fi',
    'fr',
    'hr',
    'hu',
    'it',
    'ja',
    'kk',
    'ko',
    'lt',
    'lv',
    'nb',
    'nl',
    'nn',
    'pl',
    'pt',
    'ru',
    'sk',
    'sl',
    'sr',
    'sv',
    'uk',
    'yo',
    'zh',
  ].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+script codes are specified.
  switch (locale.languageCode) {
    case 'sr':
      {
        switch (locale.scriptCode) {
          case 'Latn':
            return AppLocalizationsSrLatn();
        }
        break;
      }
  }

  // Lookup logic when language+country codes are specified.
  switch (locale.languageCode) {
    case 'pt':
      {
        switch (locale.countryCode) {
          case 'BR':
            return AppLocalizationsPtBr();
          case 'PT':
            return AppLocalizationsPtPt();
        }
        break;
      }
    case 'zh':
      {
        switch (locale.countryCode) {
          case 'CN':
            return AppLocalizationsZhCn();
          case 'TW':
            return AppLocalizationsZhTw();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'bg':
      return AppLocalizationsBg();
    case 'cs':
      return AppLocalizationsCs();
    case 'da':
      return AppLocalizationsDa();
    case 'de':
      return AppLocalizationsDe();
    case 'el':
      return AppLocalizationsEl();
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'et':
      return AppLocalizationsEt();
    case 'eu':
      return AppLocalizationsEu();
    case 'fi':
      return AppLocalizationsFi();
    case 'fr':
      return AppLocalizationsFr();
    case 'hr':
      return AppLocalizationsHr();
    case 'hu':
      return AppLocalizationsHu();
    case 'it':
      return AppLocalizationsIt();
    case 'ja':
      return AppLocalizationsJa();
    case 'kk':
      return AppLocalizationsKk();
    case 'ko':
      return AppLocalizationsKo();
    case 'lt':
      return AppLocalizationsLt();
    case 'lv':
      return AppLocalizationsLv();
    case 'nb':
      return AppLocalizationsNb();
    case 'nl':
      return AppLocalizationsNl();
    case 'nn':
      return AppLocalizationsNn();
    case 'pl':
      return AppLocalizationsPl();
    case 'pt':
      return AppLocalizationsPt();
    case 'ru':
      return AppLocalizationsRu();
    case 'sk':
      return AppLocalizationsSk();
    case 'sl':
      return AppLocalizationsSl();
    case 'sr':
      return AppLocalizationsSr();
    case 'sv':
      return AppLocalizationsSv();
    case 'uk':
      return AppLocalizationsUk();
    case 'yo':
      return AppLocalizationsYo();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
