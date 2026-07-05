// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hungarian (`hu`).
class AppLocalizationsHu extends AppLocalizations {
  AppLocalizationsHu([String locale = 'hu']) : super(locale);

  @override
  String get appName => 'Gabbro';

  @override
  String get filePickerUnavailable =>
      'File dialog unavailable here. Type or paste the path instead.';

  @override
  String get filePickerNoPortal =>
      'File dialog unavailable here. The system file portal isn\'t reachable.';

  @override
  String get cancel => 'Mégse';

  @override
  String get delete => 'Törlés';

  @override
  String get save => 'Mentés';

  @override
  String get close => 'Bezárás';

  @override
  String get ok => 'OK';

  @override
  String get edit => 'Szerkesztés';

  @override
  String get saveConfirmTitle => 'Mentés a Gabbróba';

  @override
  String get saveConfirmUpdate => 'Bejelentkezés frissítése';

  @override
  String get saveConfirmAsNew => 'Mentés új bejelentkezésként';

  @override
  String get saveConfirmChooseAnother => 'Másik bejelentkezés választása';

  @override
  String get saveConfirmAlreadySaved => 'Már mentve ezzel a jelszóval.';

  @override
  String get saveConfirmSwitchVaultHint =>
      'Másik széfbe mentéshez előbb zárolja ezt.';

  @override
  String get autofillNoMatchTitle => 'Nem található hitelesítő adat';

  @override
  String get autofillNoMatchBody =>
      'Egyetlen mentett bejelentkezés sem felel meg ennek az alkalmazásnak vagy webhelynek.';

  @override
  String get add => 'Hozzáadás';

  @override
  String get remove => 'Eltávolítás';

  @override
  String get rename => 'Átnevezés';

  @override
  String get confirm => 'Megerősítés';

  @override
  String get continueAction => 'Folytatás';

  @override
  String get dismiss => 'Elvetés';

  @override
  String get authorize => 'Engedélyezés';

  @override
  String get register => 'Regisztrálás';

  @override
  String get sync => 'Szinkronizálás';

  @override
  String get assign => 'Hozzárendelés';

  @override
  String get unlock => 'Feloldás';

  @override
  String get generate => 'Generálás';

  @override
  String get import => 'Importálás';

  @override
  String get export => 'Exportálás';

  @override
  String get openInBrowser => 'Megnyitás böngészőben';

  @override
  String get useThisPassword => 'Ez a jelszó használata';

  @override
  String get reviewArrow => 'Áttekintés →';

  @override
  String get skip => 'Kihagyás';

  @override
  String get keep => 'Megtartás';

  @override
  String get revert => 'Visszaállítás';

  @override
  String get next => 'Következő: oszlopok hozzárendelése';

  @override
  String get syncFromVault => 'Szinkronizálás széfből';

  @override
  String get createVault => 'Széf létrehozása';

  @override
  String get pickFile => 'Fájl kiválasztása';

  @override
  String get noFileSelected => 'Nincs fájl kiválasztva';

  @override
  String get chooseFolder => 'Mappa kiválasztása';

  @override
  String get addCustomField => 'Egyéni mező hozzáadása';

  @override
  String get exportFile => 'Fájl exportálása';

  @override
  String get addVault => 'Széf hozzáadása';

  @override
  String get addYubiKey => 'YubiKey hozzáadása';

  @override
  String get noChangesToSave => 'Nincsenek mentendő változtatások.';

  @override
  String get appearanceTitle => 'Megjelenés';

  @override
  String get securityTitle => 'Biztonság';

  @override
  String get aboutTitle => 'A Gabbróról';

  @override
  String get generatorTitle => 'Jelszógenerátor';

  @override
  String get importTitle => 'Bejegyzések importálása';

  @override
  String get exportTitle => 'Széf exportálása';

  @override
  String get changePassphraseTitle => 'Jelmondat módosítása';

  @override
  String get csvMappingTitle => 'CSV-oszlopok hozzárendelése';

  @override
  String get manageFoldersTitle => 'Mappák kezelése';

  @override
  String get manageVaultsTitle => 'Széfek kezelése';

  @override
  String get manageYubiKeysTitle => 'YubiKey-ek kezelése';

  @override
  String get reviewChangesTitle => 'Változtatások áttekintése';

  @override
  String get unlockGabbroTitle => 'Gabbro feloldása';

  @override
  String get sectionTheme => 'Téma';

  @override
  String get sectionTextSize => 'Szövegméret';

  @override
  String get sectionAlphabetBar => 'Ábécésor pozíciója';

  @override
  String get sectionAccessibility => 'Akadálymentesítés';

  @override
  String get sectionLanguage => 'Nyelv';

  @override
  String get sectionForegroundLock => 'Előtérzár';

  @override
  String get sectionBackgroundLock => 'Háttérzár';

  @override
  String get sectionPasswordHistory => 'Jelszóelőzmények';

  @override
  String get sectionPassphraseCopyPaste => 'Jelmondat másolása/beillesztése';

  @override
  String get sectionClipboardClear => 'Vágólap törlése';

  @override
  String get sectionCharacterSets => 'Karakterkészletek';

  @override
  String get sectionGeneratorLanguage => 'Nyelv';

  @override
  String get themeSystem => 'Rendszer';

  @override
  String get themeLight => 'Világos';

  @override
  String get themeDark => 'Sötét';

  @override
  String get alphabetBarNote => 'Csak telefonon — táblagépen mindig bal.';

  @override
  String get alphabetBarLeft => 'Bal';

  @override
  String get alphabetBarRight => 'Jobb';

  @override
  String get highContrastTitle => 'Nagy kontraszt';

  @override
  String get highContrastSubtitle =>
      'Növeli a kontrasztot a jobb olvashatóság érdekében';

  @override
  String get languageNote =>
      'Felülírja a rendszer nyelvét. «Rendszer» az eszköz területi beállításait követi.';

  @override
  String get langSystem => 'Rendszer';

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
  String get langBulgarian => 'Български';

  @override
  String get langCzech => 'Čeština';

  @override
  String get langDanish => 'Dansk';

  @override
  String get langGreek => 'Ελληνικά';

  @override
  String get langEstonian => 'Eesti';

  @override
  String get langFinnish => 'Suomi';

  @override
  String get langCroatian => 'Hrvatski';

  @override
  String get langHungarian => 'Magyar';

  @override
  String get langJapanese => '日本語';

  @override
  String get langKazakh => 'Қазақша';

  @override
  String get langKorean => '한국어';

  @override
  String get langLithuanian => 'Lietuvių';

  @override
  String get langLatvian => 'Latviešu';

  @override
  String get langNorwegianBokmal => 'Norsk bokmål';

  @override
  String get langNorwegianNynorsk => 'Norsk nynorsk';

  @override
  String get langPolish => 'Polski';

  @override
  String get langPortugueseBr => 'Português (BR)';

  @override
  String get langPortuguesePt => 'Português (PT)';

  @override
  String get langRussian => 'Русский';

  @override
  String get langSlovak => 'Slovenčina';

  @override
  String get langSlovenian => 'Slovenščina';

  @override
  String get langSerbianLatin => 'Srpski';

  @override
  String get langSwedish => 'Svenska';

  @override
  String get langUkrainian => 'Українська';

  @override
  String get langBasque => 'Euskara';

  @override
  String get langYoruba => 'Yorùbá';

  @override
  String get langChineseSimplified => '中文（简体）';

  @override
  String get langChineseTraditional => '中文（繁體）';

  @override
  String get langDutch => 'Nederlands';

  @override
  String get foregroundLockDescription =>
      'Zárolás ennyi inaktivitás után, amíg az alkalmazás nyitva van.';

  @override
  String get backgroundLockDescription =>
      'Zárolás, miután az alkalmazás ennyi ideig háttérben volt.';

  @override
  String get passwordHistoryDescription =>
      'Meddig őrizze meg egy módosított titok korábbi értékét (jelszó, CVV, PIN).';

  @override
  String get passphraseCopyPasteDescription =>
      'Másolás és beillesztés tiltása a jelmondat mezőkben. Ajánlott: megakadályozza a jelmondat vágólapon keresztüli kiszivárgását.';

  @override
  String get passphraseCopyPasteNote =>
      'Megjegyzés: ez blokkolja a hosszú érintés helyi menüjét és a szövegkijelölést. A billentyűzet beépített beillesztés gombja esetleg még működik — ez platformkorlátozás.';

  @override
  String get blockCopyPasteTitle => 'Másolás/beillesztés tiltása';

  @override
  String get clipboardClearDescription =>
      'A vágólap törlése titok másolása után. Megjegyzés: a vágólap-kezelők megtarthatnak egy másolatot.';

  @override
  String get duration30s => '30 mp';

  @override
  String get duration1min => '1 perc';

  @override
  String get duration5min => '5 perc';

  @override
  String get duration15min => '15 perc';

  @override
  String get duration60s => '60 mp';

  @override
  String get duration2min => '2 perc';

  @override
  String get durationNever => 'Soha';

  @override
  String get duration7days => '7 nap';

  @override
  String get duration30days => '30 nap';

  @override
  String get duration90days => '90 nap';

  @override
  String get durationKeepForever => 'Mindig megőrzi';

  @override
  String get menuExportVault => 'Széf exportálása';

  @override
  String get menuImportEntries => 'Bejegyzések importálása';

  @override
  String get menuSyncFromFile => 'Szinkronizálás fájlból';

  @override
  String get menuManageVaults => 'Széfek kezelése';

  @override
  String get menuChangePassphrase => 'Jelmondat módosítása';

  @override
  String get menuManageYubiKeys => 'YubiKey-ek kezelése';

  @override
  String get menuAppearance => 'Megjelenés';

  @override
  String get menuSecurity => 'Biztonság';

  @override
  String get menuManageFolders => 'Mappák kezelése';

  @override
  String get menuPasswordGenerator => 'Jelszógenerátor';

  @override
  String get menuAbout => 'Névjegy';

  @override
  String get tooltipSelectEntries => 'Bejegyzések kijelölése';

  @override
  String get tooltipLockVault => 'Széf zárolása';

  @override
  String get tooltipSelectAll => 'Összes kijelölése';

  @override
  String get tooltipDeselectAll => 'Összes kijelölés megszüntetése';

  @override
  String get tooltipClearSearch => 'Keresés törlése';

  @override
  String get tooltipMenu => 'Menü';

  @override
  String get tooltipCopy => 'Másolás';

  @override
  String get tooltipCopied => 'Másolva!';

  @override
  String get tooltipShow => 'Megjelenítés';

  @override
  String get tooltipHide => 'Elrejtés';

  @override
  String get tooltipBrowse => 'Böngészés';

  @override
  String get tooltipPreviousPage => 'Előző oldal';

  @override
  String get tooltipNextPage => 'Következő oldal';

  @override
  String get helpEnlargeImage => 'Kép nagyítása';

  @override
  String get tooltipEditAlias => 'Alias szerkesztése';

  @override
  String get tooltipRemoveField => 'Mező eltávolítása';

  @override
  String get tooltipRename => 'Átnevezés';

  @override
  String get tooltipDeleteVault => 'Széf törlése';

  @override
  String get tooltipAssignToFolder => 'Hozzárendelés mappához';

  @override
  String get tooltipShowPin => 'PIN megjelenítése';

  @override
  String get tooltipHidePin => 'PIN elrejtése';

  @override
  String get tooltipShowValue => 'Érték megjelenítése';

  @override
  String get tooltipHideValue => 'Elrejtés';

  @override
  String get tooltipCancel => 'Mégse';

  @override
  String get tooltipOpenInBrowser => 'Megnyitás böngészőben';

  @override
  String get allFolders => 'Összes mappa';

  @override
  String get noFolder => 'Nincs';

  @override
  String get selectFolder => 'Mappa kiválasztása';

  @override
  String get folderName => 'Mappa neve';

  @override
  String get noEntriesMatch => 'Nincs a keresésnek megfelelő bejegyzés.';

  @override
  String get noVaultsRegistered => 'Nincs regisztrált széf.';

  @override
  String get noYubiKeysRegistered => 'Nincs regisztrált YubiKey';

  @override
  String get selectEntry => 'Bejegyzés kiválasztása';

  @override
  String get newEntryTitle => 'Új bejegyzés';

  @override
  String createEntryTitle(String type) {
    return 'Új $type';
  }

  @override
  String editEntryTitle(String type) {
    return '$type szerkesztése';
  }

  @override
  String get noUrlFallback => '(nincs URL)';

  @override
  String get noNameFallback => '(nincs név)';

  @override
  String get untitledFallback => '(névtelen)';

  @override
  String get gabbroTitle => 'Gabbro';

  @override
  String gabbroVaultTitle(String alias) {
    return 'Gabbro - $alias';
  }

  @override
  String selectedCount(int count) {
    return '$count kijelölve';
  }

  @override
  String get searchAllFieldsHint => 'Keresés az összes mezőben…';

  @override
  String get searchEntriesHint => 'Bejegyzések keresése…';

  @override
  String get searchAllFieldsTooltip => 'Az összes mezőben keres';

  @override
  String get searchByTitleTooltip => 'Cím szerint keres';

  @override
  String get entryTypeAll => 'Összes';

  @override
  String get entryTypePassword => 'Jelszó';

  @override
  String get entryTypeNote => 'Megjegyzés';

  @override
  String get entryTypeCard => 'Kártya';

  @override
  String get entryTypeIdentity => 'Személyazonosság';

  @override
  String get entryTypeFile => 'Fájl';

  @override
  String get entryTypeCustom => 'Egyéni';

  @override
  String errorPrefix(String error) {
    return 'Hiba: $error';
  }

  @override
  String get navVault => 'Széf';

  @override
  String get navAppearance => 'Megjelenés';

  @override
  String get navSecurity => 'Biztonság';

  @override
  String get navAbout => 'Névjegy';

  @override
  String get deleteEntryTitle => 'Bejegyzés törlése?';

  @override
  String get cannotBeUndone => 'Ez a művelet nem vonható vissza.';

  @override
  String get deleteEntryDialogTitle => 'Bejegyzés törlése?';

  @override
  String deleteEntriesTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count bejegyzés törlése?',
      one: '1 bejegyzés törlése?',
    );
    return '$_temp0';
  }

  @override
  String get assignToFolderTitle => 'Hozzárendelés mappához';

  @override
  String get folderConflictTitle => 'Mappaütközés';

  @override
  String get syncFailedTitle => 'Szinkronizálás sikertelen';

  @override
  String get syncFromFileTitle => 'Szinkronizálás fájlból';

  @override
  String get nothingToSync =>
      'Nincs szinkronizálnivaló — mindkét széf már naprakész.';

  @override
  String get syncMethodTitle => 'Hogyan legyen alkalmazva ez a szinkronizálás?';

  @override
  String get syncMergeAutomatically => 'Automatikus egyesítés';

  @override
  String get syncReviewAllChanges => 'Összes módosítás áttekintése';

  @override
  String get syncDetailsAction => 'Részletek';

  @override
  String get syncSummaryTitle => 'Szinkronizálás részletei';

  @override
  String get syncSummaryAdded => 'Hozzáadva';

  @override
  String get syncSummaryUpdated => 'Frissítve';

  @override
  String get syncSummaryDeleted => 'Törölve';

  @override
  String get syncStopTitle => 'Megszakítja az áttekintést?';

  @override
  String get syncStopBody =>
      'Válassza ki, hogyan fejezze be a szinkronizálást.';

  @override
  String get syncStopKeepReviewing => 'Áttekintés folytatása';

  @override
  String get syncStopCancel => 'Szinkronizálás megszakítása';

  @override
  String get syncCancelled => 'Szinkronizálás megszakítva.';

  @override
  String importedEntries(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count bejegyzés importálva.',
      one: '1 bejegyzés importálva.',
    );
    return '$_temp0';
  }

  @override
  String get exportFileTitle => 'Fájl exportálása';

  @override
  String get saveDecryptedFileTo => 'Visszafejtett fájl mentése ide:';

  @override
  String get exportPathLabel => 'Exportálás helye';

  @override
  String exportedToPath(String path) {
    return 'Exportálva ide: $path';
  }

  @override
  String exportFailed(String error) {
    return 'Exportálás sikertelen: $error';
  }

  @override
  String get openInBrowserTitle => 'Megnyitás böngészőben?';

  @override
  String couldNotOpen(String url) {
    return 'Nem sikerült megnyitni: $url';
  }

  @override
  String get deleteEntryFromHistoryLabel => 'Korábbi bejegyzés törlése';

  @override
  String get renameFolderTitle => 'Mappa átnevezése';

  @override
  String get addFolderTitle => 'Mappa hozzáadása';

  @override
  String get deleteFolderTitle => 'Mappa törlése';

  @override
  String deleteFolderConfirm(String folder) {
    return '«$folder» törlése?';
  }

  @override
  String get reassignEntriesTo => 'Bejegyzések újbóli hozzárendelése ide:';

  @override
  String get clearToNone => 'Áthelyezés «Nincs» mappába';

  @override
  String get renameVaultTitle => 'Széf átnevezése';

  @override
  String get deleteVaultTitle => 'Széf törlése?';

  @override
  String get deleteVaultConfirmTitle => 'Biztos vagy benne?';

  @override
  String deleteVaultUnderstand(String alias) {
    return 'Megértem, hogy ez véglegesen törli a következőt: \"$alias\", és nem vonható vissza.';
  }

  @override
  String get noBackupFidoDeviceFound =>
      'Nem található tartalék FIDO2-eszköz. Helyezze be a tartalék YubiKey-t.';

  @override
  String get yubikeyOperationFailed => 'A YubiKey-művelet sikertelen.';

  @override
  String get unlockFailed => 'A feloldás sikertelen.';

  @override
  String get csvMapTitleOrUrl =>
      'Rendeljen hozzá legalább Címet vagy URL-t, hogy a bejegyzéseknek legyen nevük.';

  @override
  String get pickAFile => 'Kérjük, válasszon egy fájlt.';

  @override
  String get touchYourYubiKey => 'Érintsd meg a YubiKey-edet';

  @override
  String get noVaultsRegisteredText => 'Nincs regisztrált széf.';

  @override
  String get addYubiKeyTitle => 'YubiKey hozzáadása';

  @override
  String get enterYubiKeyPinTitle => 'YubiKey PIN megadása';

  @override
  String editAliasForKey(int index) {
    return '$index. kulcs aliasának szerkesztése';
  }

  @override
  String get lastKeyWarning => 'Csak egy regisztrált YubiKey marad.';

  @override
  String get removeKeyConfirm =>
      'Biztosan el szeretnéd távolítani ezt a kulcsot?';

  @override
  String get removeKeyVaultConfirm => 'Eltávolítja ezt a YubiKey-t a széfből?';

  @override
  String get yubiKeyRemoved => 'YubiKey eltávolítva';

  @override
  String failedToRemoveKey(String error) {
    return 'A kulcs eltávolítása sikertelen: $error';
  }

  @override
  String get yubiKeyAdded => 'YubiKey hozzáadva';

  @override
  String failedToAddKey(String error) {
    return 'A kulcs hozzáadása sikertelen: $error';
  }

  @override
  String failedToSaveAlias(String error) {
    return 'Az alias mentése sikertelen: $error';
  }

  @override
  String get noFidoDeviceFound =>
      'Nem található FIDO2-eszköz. Csatlakoztasd a YubiKey-edet és próbáld újra.';

  @override
  String get transportLabel => 'Átvitel:';

  @override
  String get transportUsb => 'USB';

  @override
  String get transportNfc => 'NFC';

  @override
  String get passphraseLabel => 'Jelmondat';

  @override
  String get yubiKeyPinLabel => 'YubiKey PIN';

  @override
  String get pinLabel => 'PIN';

  @override
  String get currentPassphraseLabel => 'Jelenlegi jelmondat';

  @override
  String get newPassphraseLabel => 'Új jelmondat';

  @override
  String get confirmPassphraseLabel => 'Új jelmondat megerősítése';

  @override
  String get vaultPassphraseLabel => 'Széf jelmondatja';

  @override
  String get aliasLabel => 'Alias';

  @override
  String get aliasHint => 'pl. Elsődleges, Munkakulcs…';

  @override
  String get masterPassphraseLabel => 'Fő jelmondat';

  @override
  String get confirmPassphraseLabelShort => 'Jelmondat megerősítése';

  @override
  String get fieldTitle => 'Cím';

  @override
  String get fieldContent => 'Tartalom';

  @override
  String get fieldFirstName => 'Keresztnév';

  @override
  String get fieldLastName => 'Vezetéknév';

  @override
  String get fieldEmail => 'E-mail (opcionális)';

  @override
  String get fieldPhone => 'Telefon (opcionális)';

  @override
  String get fieldAddress => 'Cím (opcionális)';

  @override
  String get fieldCardLabel => 'Kártya neve (pl. «Visa Platinum»)';

  @override
  String get fieldCardholderName => 'Kártyabirtokos neve';

  @override
  String get fieldCardNumber => 'Kártyaszám';

  @override
  String get fieldExpiry => 'Lejárat (HH/ÉÉ)';

  @override
  String get fieldCvv => 'CVV (opcionális)';

  @override
  String get fieldCardPin => 'PIN (opcionális)';

  @override
  String get fieldCreditLimit => 'Hitelkeret (opcionális)';

  @override
  String get fieldAccountNumber => 'Számlaszám (opcionális)';

  @override
  String get fieldNotes => 'Megjegyzések (opcionális)';

  @override
  String get fieldUrl => 'URL (opcionális)';

  @override
  String get fieldAndroidAppId => 'Android-alkalmazás azonosító (nem kötelező)';

  @override
  String get fieldAndroidAppIdHelper =>
      'Kitölti ezt a bejelentkezést egy Android-alkalmazásban. Csak a pontos egyezés működik. Az azonosítót az alkalmazás Play Store-linkjében találja, az id= után (pl. id=com.company.app).';

  @override
  String get recentlyUsedApps => 'Nemrég használt alkalmazások';

  @override
  String get fieldUsername => 'Felhasználónév (opcionális)';

  @override
  String get fieldPassword => 'Jelszó';

  @override
  String get fieldSeparator => 'Elválasztó';

  @override
  String get fieldFolder => 'Mappa';

  @override
  String get fieldLabel => 'Felirat';

  @override
  String get fieldValue => 'Érték';

  @override
  String get fieldCustomFields => 'Egyéni mezők';

  @override
  String fieldLabelOptional(String label) {
    return '$label (opcionális)';
  }

  @override
  String get entryTypeNotSupported => 'Ez a bejegyzéstípus még nem támogatott.';

  @override
  String get csvColumnNone => '(nincs)';

  @override
  String get csvPreviewLabel => 'Előnézet';

  @override
  String get csvImportButton => 'Importálás';

  @override
  String get gabbroVaultSection => 'Gabbro széf';

  @override
  String get genericCsvSection => 'Általános CSV';

  @override
  String get changePassphraseSuccess => 'Jelmondat módosítva';

  @override
  String get changePassphraseBiometricDisabled =>
      'Passphrase changed. Biometric unlock was turned off; re-enable it in Settings.';

  @override
  String get changePassphraseButton => 'Jelmondat módosítása';

  @override
  String get continueLabel => 'Folytatás';

  @override
  String get protectWithYubiKey => 'Védelem YubiKey-jel';

  @override
  String get yubiKeySubtitle => 'Hardveres biztonsági kulcs (ajánlott)';

  @override
  String get accessibilityButton => 'Akadálymentesítés';

  @override
  String get aboutProjectSection => 'Projekt';

  @override
  String get aboutLicenceSection => 'Licenc';

  @override
  String get aboutOpenSourceSection => 'Nyílt forráskódú komponensek';

  @override
  String get aboutAttributionSection => 'Köszönetnyilvánítások';

  @override
  String get lengthLabel => 'Hossz';

  @override
  String get wordsLabel => 'Szavak';

  @override
  String get generateButton => 'Generálás';

  @override
  String get usePasswordButton => 'Ez a jelszó használata';

  @override
  String get showHidePassword => 'Megjelenítés';

  @override
  String get deleteVaultPostDeletion =>
      'A széfed törölve lett. Hozz létre egy újat a folytatáshoz.';

  @override
  String get syncFilePassphraseLabel => 'Széf jelmondatja';

  @override
  String get syncSafeToRetry =>
      'Ha egy szinkronizálás megszakad, egyszerűen futtasd le újra. Semmi nem vész el.';

  @override
  String get syncThisVault => 'Ezt a széfet használ';

  @override
  String get syncOtherVault => 'Másik széfet használ';

  @override
  String get historyPrevious => 'Előzmények';

  @override
  String historySavedOn(String date) {
    return 'Mentve: $date';
  }

  @override
  String historyExpiresAppend(String saved, String expires) {
    return '$saved · lejár: $expires';
  }

  @override
  String importIssueTitle(int index, int total) {
    return 'Importálási probléma ($index/$total)';
  }

  @override
  String importIssueType(String category) {
    return 'Típus: $category';
  }

  @override
  String get importIssueHelp =>
      'Szerkeszd, javítsd és mentsd el ezt a bejegyzést, vagy hagyd ki az elvetéséhez.';

  @override
  String entriesSkipped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count bejegyzés kihagyva',
      one: '1 bejegyzés kihagyva',
    );
    return '$_temp0';
  }

  @override
  String get skippedEntriesNote =>
      'Ezek a bejegyzések már léteznek a széfedben, és nem lettek felülírva:';

  @override
  String syncDeleteEntryContent(String title) {
    return 'A másik eszköz törölte a(z) \'$title\' bejegyzést.\n\nTöröld itt is, vagy tartsd meg?';
  }

  @override
  String folderConflictContent(String title, String local, String incoming) {
    return 'A(z) \'$title\' különböző mappákban van a két eszközön.\n\nEz az eszköz: $local\nMásik eszköz: $incoming';
  }

  @override
  String syncFieldConflictContent(String title, String field) {
    return 'A(z) „$title” eltérő értékkel rendelkezik a(z) $field mezőhöz minden eszközön. Megtartja a saját értékét, vagy a másik eszközét használja?';
  }

  @override
  String get syncFieldConflictUseIncoming =>
      'A másik eszköz értékének használata';

  @override
  String get folderConflictKeepUnfoldered => 'Tartás mappa nélkül';

  @override
  String folderConflictKeepLocal(String folder) {
    return '«$folder» megtartása';
  }

  @override
  String get folderConflictMoveUnfoldered => 'Áthelyezés mappa nélkülire';

  @override
  String folderConflictMoveIncoming(String folder) {
    return 'Áthelyezés ide: «$folder»';
  }

  @override
  String vaultSynced(int added, int updated, int deleted) {
    return 'Széf szinkronizálva — $added hozzáadva, $updated frissítve, $deleted törölve.';
  }

  @override
  String get syncPassphraseMismatch =>
      'Ez a széffájl más jelmondatot használ. A szinkronizálás csak az azonos jelmondatot használó széfek között támogatott.';

  @override
  String get reviewSensitiveFields => 'Érzékeny mezők';

  @override
  String get reviewOtherFields => 'Egyéb mezők';

  @override
  String get reviewPasswordChanged => 'Jelszó módosítva';

  @override
  String get reviewCvvChanged => 'CVV módosítva';

  @override
  String get reviewPinChanged => 'PIN módosítva';

  @override
  String get reviewTransactionPasswordChanged => 'Tranzakciós jelszó módosítva';

  @override
  String get tooltipShowValues => 'Értékek megjelenítése';

  @override
  String get reviewOld => 'Régi';

  @override
  String get reviewNew => 'Új';

  @override
  String get reviewEmpty => '(üres)';

  @override
  String get reviewFieldUrl => 'URL';

  @override
  String get reviewFieldNotes => 'Megjegyzések';

  @override
  String get reviewFieldContent => 'Tartalom';

  @override
  String get reviewFieldEmail => 'E-mail';

  @override
  String get reviewFieldPhone => 'Telefon';

  @override
  String get reviewFieldAddress => 'Cím';

  @override
  String get reviewFieldCardLabel => 'Kártya neve';

  @override
  String get reviewFieldStatus => 'Állapot';

  @override
  String get reviewFieldCardholder => 'Kártyabirtokos';

  @override
  String get reviewFieldExpiry => 'Lejárat';

  @override
  String get reviewFieldCreditLimit => 'Hitelkeret';

  @override
  String get reviewFieldAccountNumber => 'Számlaszám';

  @override
  String get reviewFieldNetwork => 'Hálózat';

  @override
  String get reviewFieldBank => 'Bank';

  @override
  String get reviewFieldFilename => 'Fájlnév';

  @override
  String get reviewFieldSize => 'Méret';

  @override
  String get reviewFieldCardNumber => 'Szám';

  @override
  String get reviewFieldCVV => 'CVV';

  @override
  String get reviewFieldTransactionPassword => 'Tranzakciós jelszó';

  @override
  String get timestampCreated => 'Létrehozva';

  @override
  String get timestampUpdated => 'Frissítve';

  @override
  String get timestampUnknown => 'Ismeretlen';

  @override
  String get noTitleFallback => '(nincs cím)';

  @override
  String get tooltipExportFile => 'Fájl exportálása';

  @override
  String get tooltipEditEntry => 'Bejegyzés szerkesztése';

  @override
  String get tooltipDeleteEntry => 'Bejegyzés törlése';

  @override
  String get exportLabel => 'Exportálás';

  @override
  String get customEntryFieldsHeader => 'Mezők';

  @override
  String get copiedNeverClears =>
      'Másolva — a vágólap soha nem törlődik automatikusan';

  @override
  String get copiedClears30s => 'Másolva — a vágólap 30 mp múlva törlődik';

  @override
  String get copiedClears60s => 'Másolva — a vágólap 60 mp múlva törlődik';

  @override
  String get copiedClears2min => 'Másolva — a vágólap 2 perc múlva törlődik';

  @override
  String get passwordBreakdownTitle => 'Jelszóelemzés';

  @override
  String get charTypeUppercase => 'Nagybetűk';

  @override
  String get charTypeLowercase => 'Kisbetűk';

  @override
  String get charTypeDigit => 'Számjegy';

  @override
  String get charTypeSymbol => 'Szimbólum';

  @override
  String get charTypeLetter => 'Betű';

  @override
  String get exportIncludeDate => 'Dátum belefoglalása a fájlnévbe';

  @override
  String get exportChooseFormat => 'Válassz exportálási formátumot.';

  @override
  String get exportUnencryptedWarning =>
      'Teljesen titkosítatlan — minden titok egyszerű szövegként kerül kiírásra. Tárold a fájlt biztonságosan, és töröld használat után.';

  @override
  String get exportPassphraseOnlyNote =>
      'Csak a jelmondat védi. Az importáláshoz nem szükséges YubiKey.';

  @override
  String get exportProtectionKeyProtected =>
      'A jelmondatod és egy YubiKey véd. Az exportált másolat megőrzi ezt a védelmet — az importáláshoz regisztrált YubiKey szükséges.';

  @override
  String get exportWithoutYubikey =>
      'Exportálás YubiKey-védelem nélkül (csak jelmondat)';

  @override
  String get exportWithoutYubikeyWarning =>
      'Az exportált fájl pusztán a jelmondatoddal megnyílik — nincs szükség YubiKeyre. Bárki, aki ismeri a jelmondatot, elolvashatja. Az eredeti széfed változatlan marad.';

  @override
  String get exportChooseDestinationJson =>
      'Válassz célhelyet az exportált JSON-fájlhoz.';

  @override
  String get exportChooseDestinationVault =>
      'Válassz célhelyet az exportált széffájlhoz.';

  @override
  String get exportTwoFilesNote =>
      'Két fájl jön létre: vault.gabbro és vault.gabbro.sha256';

  @override
  String get exportSelectDestination => 'Válassz célhelyet.';

  @override
  String aboutVersion(String version) {
    return '$version verzió';
  }

  @override
  String get aboutTagline => 'Kvantum utáni jelszókezelő';

  @override
  String get aboutSourceCode => 'Forráskód';

  @override
  String get aboutReportIssue => 'Hiba bejelentése';

  @override
  String get aboutSupportGabbro => 'Gabbro támogatása';

  @override
  String get aboutLicenceBody =>
      'A Gabbro szabad és nyílt forráskódú szoftver, a GNU General Public License v3.0 only (GPL-3.0-only) licence alatt.\n\nSzabadon felhasználhatod, tanulmányozhatod és terjesztheted ezt a szoftvert az adott licenc feltételei szerint.';

  @override
  String get aboutOwnerRole =>
      'Projekttulajdonos, tervező és vezető fejlesztő:';

  @override
  String get aboutAiPartner => 'MI fejlesztési partner:';

  @override
  String get aboutNoTelemetry =>
      'A Gabbro nem hoz létre kimenő hálózati kapcsolatokat. Nincs telemetria, nincs analitika, nincs fiók.';

  @override
  String get strengthTierTerrible => 'Borzalmas';

  @override
  String get strengthTierWeak => 'Gyenge';

  @override
  String get strengthTierFair => 'Elfogadható';

  @override
  String get strengthTierStrong => 'Erős';

  @override
  String get strengthTierVeryStrong => 'Nagyon erős';

  @override
  String get strengthTierExcellent => 'Kiváló';

  @override
  String get yubiKeyProtectedNote =>
      'YubiKey-jel védett széf — a YubiKey-kötésed megmarad.';

  @override
  String get yubiKeyPinRequired => 'YubiKey PIN szükséges';

  @override
  String get tapYubiKeyNow => 'Érintsd meg a YubiKey-edet most…';

  @override
  String get touchYubiKeyToAuthorize =>
      'Érintsd meg a YubiKey-edet a változtatás engedélyezéséhez.';

  @override
  String get currentPassphraseRequired => 'A jelenlegi jelmondat kötelező';

  @override
  String get newPassphraseRequired => 'Az új jelmondat kötelező';

  @override
  String get passphraseTooWeak => 'A jelmondat túl gyenge';

  @override
  String get confirmPassphraseRequired => 'Erősítsd meg az új jelmondatot';

  @override
  String get passphrasesDoNotMatch => 'A jelmondatok nem egyeznek';

  @override
  String get passphrasesMatch => '✓ A jelmondatok egyeznek';

  @override
  String get passphrasesNoMatch => '✗ A jelmondatok nem egyeznek';

  @override
  String entropyDisplay(String tier, String bits) {
    return '$tier · $bits bit';
  }

  @override
  String get transportError => 'Átviteli hiba.';

  @override
  String get authorizationFailed =>
      'Engedélyezés sikertelen — ellenőrizd a PIN-t és próbáld újra.';

  @override
  String get unlockEnterPassphraseAndPin =>
      'Add meg a jelmondatot és a YubiKey PIN-t a feloldáshoz';

  @override
  String get unlockEnterPassphrase => 'Add meg a jelmondatot a feloldáshoz';

  @override
  String unlockEntropyDisplay(String tier, String bits) {
    return '$tier · $bits bit entrópia';
  }

  @override
  String get insertYubiKeyAndTap =>
      'Csatlakoztasd a YubiKey-edet, és érintsd meg, amikor villog';

  @override
  String get unlockErrorPassphrase =>
      'Nem sikerült feloldani a széfet. Ellenőrizd a jelmondatot.';

  @override
  String get unlockErrorPassphraseAndPin =>
      'Nem sikerült feloldani a széfet. Ellenőrizd a jelmondatot és a YubiKey PIN-t.';

  @override
  String get importSelectFile => 'Válassz fájlt.';

  @override
  String get importFileNotFound => 'A fájl nem található.';

  @override
  String get importEnterPassphrase => 'Add meg ennek a széfnek a jelmondatát.';

  @override
  String get importSourceKeyProtected =>
      'Ezt a széfet egy YubiKey védi. A szinkronizáláshoz meg kell érintened egy regisztrált kulcsot.';

  @override
  String get importDuplicateWarning =>
      'Az olyan bejegyzések, amelyek UUID-je már létezik a széfedben, automatikusan kimaradnak. Látni fogsz egy összefoglalót.';

  @override
  String get importGabbroSubtitle =>
      'Bejegyzések szinkronizálása másik Gabbro széfből (.gabbro fájl)';

  @override
  String get importEnpassSubtitle =>
      'JSON-exportálás az Enpassból (Eszközök → Exportálás)';

  @override
  String get importBitwardenSubtitle =>
      'Titkosítatlan JSON-exportálás a Bitwardenből (Eszközök → Széf exportálása)';

  @override
  String get importCsvSubtitle => 'CSV-exportálás bármely jelszókezelőből';

  @override
  String get importGooglePmSubtitle =>
      'CSV-exportálás a Google Password Manager-ből (passwords.google.com → Letöltés)';

  @override
  String get importDashlaneSubtitle =>
      'CSV-exportálás a Dashlane-ből (Beállítások → Adatok exportálása → Hitelesítő adatok)';

  @override
  String importSizeLimitNote(String textLimit, String enpassLimit) {
    return 'Maximális fájlméret: $textLimit (CSV, Bitwarden, Dashlane, Google) vagy $enpassLimit (Enpass).';
  }

  @override
  String importFileTooLarge(String limit) {
    return 'Ez a fájl meghaladja a(z) $limit korlátot.';
  }

  @override
  String vaultNameAlreadyExists(String alias) {
    return 'Már létezik «$alias» nevű széf.';
  }

  @override
  String deleteVaultContent(String alias, String path) {
    return 'Ez véglegesen törli a(z) «$alias» széfet és összes adatát.\n\nFájl: $path\n\nEz a művelet nem vonható vissza.';
  }

  @override
  String deleteVaultYubikeyContent(String alias, String path) {
    return 'Ez véglegesen törli a(z) «$alias» széfet és eltávolítja a YubiKey-kötését.\n\nFájl: $path\n\nEz a művelet nem vonható vissza.';
  }

  @override
  String get yubiKeyAuthorizeDeletion =>
      'Add meg a PIN-t és érintsd meg a YubiKey-edet a törlés engedélyezéséhez.';

  @override
  String get deleteVaultTooltip => 'Széf törlése';

  @override
  String get backupEmergencyHeading =>
      'Biztonsági mentések és vészhelyzeti törlés';

  @override
  String get backupResponsibilityBody =>
      'A Gabbro nem készít biztonsági mentést a széfjeiről. Tartson minden széfről egy másolatot egy másik eszközön — a saját biztonsági mentései az egyetlen módja egy törölt vagy elveszett széf helyreállításának.';

  @override
  String get emergencyWipeAndroidBody =>
      'Az eszközön lévő összes Gabbro-adat azonnali megsemmisítéséhez — hitelesítés nélkül, visszafordíthatatlanul — nyissa meg az eszköz Beállításait, keresse meg a Gabbrót az alkalmazások listájában, és válassza az Adatok törlése lehetőséget.';

  @override
  String get emergencyWipeLinuxBody =>
      'Az eszközön lévő összes Gabbro-adat azonnali megsemmisítéséhez — hitelesítés nélkül, visszafordíthatatlanul — törölje ezeket a mappákat egy terminálban. A más helyekre mentett széfek nem ezekben a mappákban találhatók, és külön kell törölni őket.';

  @override
  String get yubiKeySecurityWarning => 'Biztonsági figyelmeztetés';

  @override
  String get removeYubiKeyTitle => 'YubiKey eltávolítása';

  @override
  String get yubiKeyLastKeyRiskWarning =>
      'FIGYELMEZTETÉS: Ha a maradék kulcs elveszik, megsérül vagy ellopják, a széfhez való hozzáférés véglegesen lehetetlenné válik. Nincs visszaállítási lehetőség.';

  @override
  String get onlyOneKeyRegisteredWarning =>
      'Csak egy kulcs van regisztrálva. Ha ez a kulcs elvész, a széfhez való hozzáférés véglegesen lehetetlenné válik.';

  @override
  String get tapRegisterNfc =>
      'Tartsd a kulcsot a telefon közelébe a regisztráláshoz';

  @override
  String get tapRegisterUsb =>
      'Csatlakoztatás után érintsd meg a kulcsot a regisztráláshoz';

  @override
  String get tapActivateNfc =>
      'Tartsd a kulcsot újra a telefon közelébe az aktiváláshoz';

  @override
  String get tapActivateUsb =>
      'Csatlakoztatás után érintsd meg a kulcsot újra az aktiváláshoz';

  @override
  String failedToRegisterKey(String error) {
    return 'A kulcs regisztrálása sikertelen: $error';
  }

  @override
  String failedToActivateKey(String error) {
    return 'A kulcs aktiválása sikertelen: $error';
  }

  @override
  String keyDefaultTitle(int index) {
    return '$index. kulcs';
  }

  @override
  String get tapYubiKeyToRegister =>
      'Érintsd meg az új YubiKey-t a regisztráláshoz…';

  @override
  String get tapYubiKeyToActivate =>
      'Érintsd meg az új YubiKey-t újra az aktiváláshoz…';

  @override
  String get editAliasTooltip => 'Alias szerkesztése';

  @override
  String get cannotRemoveLastKey => 'Az utolsó kulcs nem távolítható el';

  @override
  String get removeKeyTooltip => 'Kulcs eltávolítása';

  @override
  String manageYubiKeysError(String error) {
    return 'Hiba: $error';
  }

  @override
  String get generatorModeClassic => 'Klasszikus';

  @override
  String get generatorModePassphrase => 'Jelmondat';

  @override
  String get charSetsHeader => 'Karakterkészletek';

  @override
  String get languageHeader => 'Nyelv';

  @override
  String get separatorLabel => 'Elválasztó';

  @override
  String get capitaliseWords => 'Szavak nagybetűsítése';

  @override
  String get appendDigit => 'Szám hozzáfűzése';

  @override
  String entropyBitsDisplay(String bits) {
    return '~$bits bit entrópia';
  }

  @override
  String get selectAtLeastOneCharSet =>
      'Válassz legalább egy karakterkészletet';

  @override
  String get passwordMinLengthNote =>
      'A jelszavak legalább 12 karakteresek. Ha egy webhelyen rövidebb korlát érvényes, másold az első szükséges karaktereket.';

  @override
  String get excludeAmbiguousChars =>
      'Félreérthető karakterek kizárása (0, O, l, 1, I)';

  @override
  String get onboardingGetStarted => 'Hozd létre a széfedet a kezdéshez.';

  @override
  String get onboardingVaultName => 'Széf neve';

  @override
  String get onboardingAliasRequired => 'Az alias kötelező';

  @override
  String get onboardingNewVaultLocation =>
      'Új széf helye (ugyanaz, mint korábban)';

  @override
  String get onboardingVaultLocation => 'Széf helye';

  @override
  String get onboardingLoadingPath => 'Betöltés…';

  @override
  String get onboardingPathHint => 'Útvonal a széffájlhoz';

  @override
  String get onboardingPathRequired => 'Az útvonal kötelező';

  @override
  String get onboardingReusePassphraseHint =>
      'Válassz új fő jelmondatot, vagy használd újra az előzőt, ha preferálod.';

  @override
  String get onboardingPassphraseRequired => 'A jelmondat kötelező';

  @override
  String get onboardingConfirmRequired => 'Erősítsd meg a jelmondatot';

  @override
  String get onboardingPrimaryKeyPin => 'Elsődleges kulcs PIN-je';

  @override
  String get onboardingBackupKeyPin => 'Biztonsági másolat kulcs PIN-je';

  @override
  String onboardingKeyNPin(int n) {
    return '$n. kulcs PIN-je';
  }

  @override
  String get onboardingYubikeyTapInstruction =>
      'Minden YubiKey-t kétszer fogsz megérinteni (összesen 4 érintés). A két kulcs között a program felkér a csere elvégzésére.';

  @override
  String get onboardingYubikeySlowNote =>
      'A széf YubiKey-jel való létrehozása 20–30 másodpercet vesz igénybe. Az alkalmazás reagálatlannak tűnhet — ez normális.';

  @override
  String get onboardingStep1Label => 'Elsődleges kulcs regisztrálása';

  @override
  String get onboardingStep1Hint => 'Érintsd meg a YubiKey-edet most';

  @override
  String get onboardingStep2Label => 'Elsődleges kulcs aktiválása';

  @override
  String get onboardingStep2Hint => 'Érintsd meg a YubiKey-edet újra';

  @override
  String get onboardingStep3Label => 'Váltás biztonsági kulcsra';

  @override
  String get onboardingStep3Hint =>
      'Távolítsd el az elsődleges kulcsot, majd csatlakoztasd a biztonsági YubiKey-t';

  @override
  String get onboardingStep4Label => 'Biztonsági kulcs regisztrálása';

  @override
  String get onboardingStep4Hint => 'Érintsd meg a biztonsági YubiKey-edet';

  @override
  String get onboardingStep5Label => 'Biztonsági kulcs aktiválása';

  @override
  String get onboardingStep5Hint =>
      'Érintsd meg a biztonsági YubiKey-edet utoljára';

  @override
  String get textSizePreview =>
      'A gabbró egy mafikus intrusív magmás kőzet, amely durva szemcsés és gazdag Mg-ban és Fe-ben.';

  @override
  String get fieldCardStatus => 'Állapot';

  @override
  String get fieldPaymentNetwork => 'Fizetési hálózat';

  @override
  String get cardStatusActive => 'Aktív';

  @override
  String get cardStatusLapsed => 'Lejárt';

  @override
  String get cardStatusInactive => 'Inaktív';

  @override
  String get validatorTitleRequired => 'A cím kötelező';

  @override
  String get validatorUsernameRequired => 'A felhasználónév kötelező';

  @override
  String get validatorPasswordRequired => 'A jelszó kötelező';

  @override
  String get validatorContentRequired => 'A tartalom kötelező';

  @override
  String get validatorFirstNameRequired => 'A keresztnév kötelező';

  @override
  String get validatorLastNameRequired => 'A vezetéknév kötelező';

  @override
  String get validatorCardLabelRequired => 'A kártya neve kötelező';

  @override
  String get validatorCardholderRequired => 'A kártyabirtokos neve kötelező';

  @override
  String get validatorCardNumberRequired => 'A kártyaszám kötelező';

  @override
  String get validatorCardNumberLength =>
      'A kártyaszámnak 6–19 számjegyből kell állnia';

  @override
  String get validatorExpiryRequired => 'A lejárati dátum kötelező';

  @override
  String get validatorExpiryFormat => 'HH/ÉÉ formátumot használj';

  @override
  String get validatorExpiryMonth => 'A hónapnak 01–12 között kell lennie';

  @override
  String get validatorCvvLength => 'A CVV-nek 3 vagy 4 számjegyből kell állnia';

  @override
  String get validatorLabelRequired => 'A felirat kötelező';

  @override
  String get validatorLabelDuplicate => 'A feliratnak egyedinek kell lennie';

  @override
  String get validatorStatusRequired => 'Az állapot kötelező';

  @override
  String get sectionBiometricUnlock => 'Biometrikus feloldás';

  @override
  String get biometricUnlockDescription =>
      'Ujjlenyomattal vagy arccal oldja fel a széfet a jelmondat begépelése helyett.';

  @override
  String get biometricUnlockTitle => 'Biometrikus feloldás engedélyezése';

  @override
  String get biometricUnlockNote =>
      'Az erre az eszközre regisztrált összes biometrikus azonosító működni fog — nem csak a regisztráláshoz használt.';

  @override
  String get biometricUnavailable =>
      'A biometrikus feloldás nem elérhető ezen az eszközön. Nem találtak biometrikus érzékelőt, vagy a rendszerbeállításokban nem regisztráltak biometrikus azonosítót.';

  @override
  String get biometricDialogTitle => 'A biometrikus feloldásról';

  @override
  String get biometricDialogBody =>
      'Ha engedélyezve van, a Gabbro titkosítja a fő jelmondatot, és ezen az eszközön tárolja, biometrikus azonosítókkal védve. A jelmondat csak feloldáskor kerül visszafejtésre.\n\nA Gabbro soha nem tárolja az ujjlenyomat- vagy arcadatokat — ezek a telefon biztonságos chipjén maradnak.';

  @override
  String get biometricDialogAllBiometrics =>
      'Az erre az eszközre regisztrált összes biometrikus azonosító fel tudja oldani a Gabrót — nem korlátozhatod egy adott ujjlenyomatra.';

  @override
  String get biometricDialogInvalidation =>
      'Ha új biometrikus azonosítót adnak hozzá ehhez a telefonhoz (beleértve egy második ujjlenyomatot is), ez a beállítás automatikusan letiltódik, és újra kell konfigurálni.';

  @override
  String get biometricDialogRecommendation =>
      'Javaslat: hagyd letiltva, ha magas fenyegetési modellel rendelkezel, vagy megosztod ezt az eszközt.';

  @override
  String get biometricInvalidated =>
      'A biometrikus feloldás le lett tiltva, mert az ezen az eszközön lévő biometrikus azonosítók megváltoztak (új ujjlenyomatot vagy arcot adtak hozzá a rendszerbeállításokban). Ez egy biztonsági intézkedés. Add meg újra a jelmondatot, és engedélyezd újra a biometrikus feloldást, ha folytatni szeretnéd ennek a funkciónak a használatát.';

  @override
  String get useBiometrics => 'Biometria használata';

  @override
  String get biometricCancelled =>
      'A biometrikus hitelesítés nem fejeződött be. Add meg a jelmondatot a feloldáshoz.';

  @override
  String get biometricEnrollTitle => 'Jelmondat megadása';

  @override
  String get biometricEnrollDescription =>
      'Add meg a fő jelmondatot a biometrikus feloldás engedélyezéséhez.';

  @override
  String get biometricYubikeyHint =>
      'Add meg alul a YubiKey PIN-t, majd érintsd meg a Biometria használata gombot, majd érintsd meg a YubiKey-edet.';

  @override
  String get helpTitle => 'Súgó';

  @override
  String get menuHelp => 'Súgó';

  @override
  String get helpCaptionCreate =>
      'Széf létrehozása: add meg a nevet, jelmondatot, és opcionálisan védd YubiKey-jel';

  @override
  String get helpCaptionEmpty =>
      'Koppints a + gombra az első bejegyzés hozzáadásához';

  @override
  String get helpCaptionDetail =>
      'Koppints a szem ikonra a jelszó felfedéséhez, majd nyomj hosszan a részletes karakterelemzés megtekintéséhez';

  @override
  String get helpCaptionTitleSearch =>
      'Alapértelmezés szerint a keresősáv csak a bejegyzések címeiben keres';

  @override
  String get helpCaptionFullSearch =>
      'Koppints a nagyítóra az összes mezőben való keresésre való váltáshoz; koppints újra a cím szerinti kereséshez való visszatéréshez';

  @override
  String get helpCaptionFilter =>
      'Használd a szűrőgombokat, hogy csak egy adott típusú bejegyzéseket jelenítsd meg';

  @override
  String get helpCaptionFolders =>
      'Használd a mappaválasztót a bejegyzések mappa szerinti szűréséhez';

  @override
  String get helpCaptionSelect =>
      'Nyomj hosszan egy bejegyzésre a kijelölési módba való lépéshez; adj hozzá több elemet, majd rendeld hozzá mappához vagy töröld. Koppints X-re a kilépéshez.';

  @override
  String get helpCaptionJumpToLetter =>
      'Koppints az indexsávon egy betűre az adott szakaszhoz való ugráshoz';

  @override
  String get helpCaptionBreakdown =>
      'Koppints a szem ikonra a jelszó felfedéséhez, majd nyomj hosszan a részletes karakterelemzés megtekintéséhez';

  @override
  String get helpCaptionManageVaults =>
      'A Széfek kezelése részben átnevezhetsz vagy törölhetsz széfeket, illetve hozzáadhatsz egy újat';

  @override
  String get helpCaptionUnlock => 'Add meg a jelmondatot a széf feloldásához';

  @override
  String get helpCaptionVaultSync =>
      'Titkosított széf szinkronizálási folyamata';

  @override
  String get passphraseNoWordlist =>
      'Az Ön nyelvéhez még nincs szólista. Angolt használ.';

  @override
  String get manageFoldersDefaultNote =>
      'Az alapértelmezett mappák átnevezhetők vagy törölhetők.';

  @override
  String get vaultCorruptBackupAvailable =>
      'Ez a széffájl nem olvasható. Elérhető egy automatikus vészmásolat az utolsó sikeres mentésből.';

  @override
  String get restoreBackupButton => 'Helyreállítás vészmásolatból';

  @override
  String get restoreBackupConfirmTitle =>
      'Helyreállítja a széfet a vészmásolatból?';

  @override
  String get restoreBackupConfirmBody =>
      'Az olvashatatlan széffájlt az utolsó sikeres mentés vészmásolata váltja fel. A feloldáshoz továbbra is szükség van a jelmondatára (és a YubiKey-re, ha regisztrálva van).';

  @override
  String get restoreBackupConfirmAction => 'Helyreállítás';

  @override
  String get backupRestoredMessage =>
      'Vészmásolat helyreállítva. Oldja fel a hitelesítő adataival.';

  @override
  String get backupDialogSafetyCopyNote =>
      'A Gabbro emellett minden széfről egy automatikus vészmásolatot is tárol az eszközön, amely minden mentéskor frissül. Ez csak a fájlsérülés ellen véd — nem biztonsági mentés.';

  @override
  String get vaultUnrecoverableBody =>
      'Ez a széffájl nem olvasható, és a vészmásolata is olvashatatlan. A tartalma nem állítható helyre ezen az eszközön.';

  @override
  String get vaultUnrecoverableBackupHint =>
      'Ha van eszközön kívüli biztonsági mentése, állítsa helyre a széfet abból a másolatból.';

  @override
  String get vaultUnrecoverableNoteLinux =>
      'Az olvashatatlan fájl a lemezen marad, így saját maga törölheti vagy megvizsgálhatja.';

  @override
  String get vaultUnrecoverableNoteAndroid =>
      'Az olvashatatlan fájl az alkalmazás privát tárhelyén található, és csak innen távolítható el.';

  @override
  String get removeVaultFromListButton => 'Eltávolítás a listáról';

  @override
  String get deleteVaultFileButton => 'Fájl törlése';

  @override
  String get removeVaultFromListConfirmTitle =>
      'Eltávolítja a széfet a listáról?';

  @override
  String get removeVaultFromListConfirmBody =>
      'Eltávolítja ezt a széfet a listájáról? A fájl a lemezen marad — ha helyreállítja, később újra hozzáadhatja.';

  @override
  String get deleteVaultFileConfirmTitle =>
      'Véglegesen törli a sérült széffájlt?';

  @override
  String get deleteVaultFileConfirmBody =>
      'Véglegesen törli ezt a széfet? Az olvashatatlan fájl és a vészmásolata eltávolításra kerül erről az eszközről. Ez a művelet nem vonható vissza.';

  @override
  String get restoreFromFileButton =>
      'Helyreállítás biztonsági mentési fájlból';

  @override
  String get vaultRestoredMessage =>
      'Széf helyreállítva. Oldja fel a hitelesítő adataival.';

  @override
  String get restoreFromFileInvalidError =>
      'Ez a fájl nem használható Gabbro-széf.';

  @override
  String get resizeColumns => 'Oszlopok átméretezése';
}
