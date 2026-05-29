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
  String get cancel => 'Annulla';

  @override
  String get delete => 'Elimina';

  @override
  String get save => 'Salva';

  @override
  String get close => 'Chiudi';

  @override
  String get ok => 'OK';

  @override
  String get edit => 'Modifica';

  @override
  String get add => 'Aggiungi';

  @override
  String get remove => 'Rimuovi';

  @override
  String get rename => 'Rinomina';

  @override
  String get confirm => 'Conferma';

  @override
  String get continueAction => 'Continua';

  @override
  String get dismiss => 'Ignora';

  @override
  String get authorize => 'Autorizza';

  @override
  String get register => 'Registra';

  @override
  String get sync => 'Sincronizza';

  @override
  String get assign => 'Assegna';

  @override
  String get unlock => 'Sblocca';

  @override
  String get generate => 'Genera';

  @override
  String get import => 'Importa';

  @override
  String get export => 'Esporta';

  @override
  String get openInBrowser => 'Apri nel browser';

  @override
  String get useThisPassword => 'Usa questa password';

  @override
  String get reviewArrow => 'Verifica →';

  @override
  String get skip => 'Salta';

  @override
  String get keep => 'Mantieni';

  @override
  String get revert => 'Ripristina';

  @override
  String get next => 'Avanti: mappa colonne';

  @override
  String get syncFromVault => 'Sincronizza dall\'archivio';

  @override
  String get createVault => 'Crea archivio';

  @override
  String get pickFile => 'Scegli file';

  @override
  String get noFileSelected => 'Nessun file selezionato';

  @override
  String get chooseFolder => 'Scegli cartella';

  @override
  String get addCustomField => 'Aggiungi campo personalizzato';

  @override
  String get exportFile => 'Esporta file';

  @override
  String get addVault => 'Aggiungi archivio';

  @override
  String get addYubiKey => 'Aggiungi YubiKey';

  @override
  String get noChangesToSave => 'Nessuna modifica da salvare.';

  @override
  String get appearanceTitle => 'Aspetto';

  @override
  String get securityTitle => 'Sicurezza';

  @override
  String get aboutTitle => 'Informazioni su Gabbro';

  @override
  String get generatorTitle => 'Generatore di password';

  @override
  String get importTitle => 'Importa voci';

  @override
  String get exportTitle => 'Esporta archivio';

  @override
  String get changePassphraseTitle => 'Cambia passphrase';

  @override
  String get csvMappingTitle => 'Mappa colonne CSV';

  @override
  String get manageFoldersTitle => 'Gestisci cartelle';

  @override
  String get manageVaultsTitle => 'Gestisci archivi';

  @override
  String get manageYubiKeysTitle => 'Gestisci YubiKey';

  @override
  String get passwordHistoryTitle => 'Cronologia password';

  @override
  String get reviewChangesTitle => 'Verifica modifiche';

  @override
  String get unlockGabbroTitle => 'Sblocca Gabbro';

  @override
  String get sectionTheme => 'Tema';

  @override
  String get sectionTextSize => 'Dimensione testo';

  @override
  String get sectionAlphabetBar => 'Posizione barra alfabetica';

  @override
  String get sectionAccessibility => 'Accessibilità';

  @override
  String get sectionLanguage => 'Lingua';

  @override
  String get sectionForegroundLock => 'Blocco in primo piano';

  @override
  String get sectionBackgroundLock => 'Blocco in background';

  @override
  String get sectionPasswordHistory => 'Cronologia password';

  @override
  String get sectionPassphraseCopyPaste => 'Copia/incolla passphrase';

  @override
  String get sectionVaultList => 'Lista archivi';

  @override
  String get sectionClipboardClear => 'Pulizia appunti';

  @override
  String get sectionCharacterSets => 'Set di caratteri';

  @override
  String get sectionGeneratorLanguage => 'Lingua';

  @override
  String get themeSystem => 'Sistema';

  @override
  String get themeLight => 'Chiaro';

  @override
  String get themeDark => 'Scuro';

  @override
  String get textSizeSmall => 'Piccolo';

  @override
  String get textSizeRegular => 'Normale';

  @override
  String get textSizeLarge => 'Grande';

  @override
  String get textSizeXL => 'XL';

  @override
  String get textSizeXXL => 'XXL';

  @override
  String get alphabetBarNote =>
      'Solo layout telefono — tablet usa sempre sinistra.';

  @override
  String get alphabetBarLeft => 'Sinistra';

  @override
  String get alphabetBarRight => 'Destra';

  @override
  String get highContrastTitle => 'Alto contrasto';

  @override
  String get highContrastSubtitle =>
      'Aumenta il contrasto per una migliore leggibilità';

  @override
  String get languageNote =>
      'Sostituisce la lingua del sistema. «Sistema» segue le impostazioni locali del dispositivo.';

  @override
  String get langSystem => 'Sistema';

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
      'Blocca dopo questo periodo di inattività mentre l\'app è aperta.';

  @override
  String get backgroundLockDescription =>
      'Blocca dopo che l\'app è rimasta in background per questo tempo.';

  @override
  String get passwordHistoryDescription =>
      'Per quanto tempo conservare una password precedente dopo la modifica. «Conserva per sempre» significa che la cronologia viene eliminata solo manualmente.';

  @override
  String get passphraseCopyPasteDescription =>
      'Blocca copia e incolla nei campi passphrase principale. Consigliato: impedisce la fuga della passphrase tramite appunti.';

  @override
  String get passphraseCopyPasteNote =>
      'Nota: questo blocca il menu contestuale pressione lunga e la selezione del testo. Il tasto incolla integrato della tastiera potrebbe funzionare ancora — si tratta di un limite della piattaforma.';

  @override
  String get blockCopyPasteTitle => 'Blocca copia/incolla';

  @override
  String get vaultListDescription =>
      'Mostra un menu a discesa di tutti gli archivi nella schermata di accesso per scegliere quale sbloccare senza andare in Gestisci archivi.';

  @override
  String get showVaultListTitle => 'Mostra lista archivi al login';

  @override
  String get vaultListNote =>
      'Nota di sicurezza: quando questa opzione è DISATTIVATA, la schermata di accesso mostra solo l\'ultimo archivio usato — nessun indizio che altri archivi esistano. Per cambiare archivio bisogna prima sbloccare, poi andare in Menu → Gestisci archivi.';

  @override
  String get clipboardClearDescription =>
      'Pulisci gli appunti dopo questo tempo dalla copia di un segreto. Nota: i gestori degli appunti potrebbero conservarne una copia.';

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
  String get durationNever => 'Mai';

  @override
  String get duration7days => '7 giorni';

  @override
  String get duration30days => '30 giorni';

  @override
  String get duration90days => '90 giorni';

  @override
  String get durationKeepForever => 'Conserva per sempre';

  @override
  String get menuExportVault => 'Esporta archivio';

  @override
  String get menuImportEntries => 'Importa voci';

  @override
  String get menuSyncFromFile => 'Sincronizza da file';

  @override
  String get menuManageVaults => 'Gestisci archivi';

  @override
  String get menuChangePassphrase => 'Cambia passphrase';

  @override
  String get menuManageYubiKeys => 'Gestisci YubiKey';

  @override
  String get menuAppearance => 'Aspetto';

  @override
  String get menuSecurity => 'Sicurezza';

  @override
  String get menuManageFolders => 'Gestisci cartelle';

  @override
  String get menuPasswordGenerator => 'Generatore di password';

  @override
  String get menuAbout => 'Informazioni';

  @override
  String get tooltipSelectEntries => 'Seleziona voci';

  @override
  String get tooltipLockVault => 'Blocca archivio';

  @override
  String get tooltipSelectAll => 'Seleziona tutto';

  @override
  String get tooltipDeselectAll => 'Deseleziona tutto';

  @override
  String get tooltipMenu => 'Menu';

  @override
  String get tooltipCopy => 'Copia';

  @override
  String get tooltipCopied => 'Copiato!';

  @override
  String get tooltipShow => 'Mostra';

  @override
  String get tooltipHide => 'Nascondi';

  @override
  String get tooltipBrowse => 'Sfoglia';

  @override
  String get tooltipEditAlias => 'Modifica alias';

  @override
  String get tooltipRemoveField => 'Rimuovi campo';

  @override
  String get tooltipRename => 'Rinomina';

  @override
  String get tooltipDeleteVault => 'Elimina archivio';

  @override
  String get tooltipAssignToFolder => 'Assegna a cartella';

  @override
  String get tooltipShowPin => 'Mostra PIN';

  @override
  String get tooltipHidePin => 'Nascondi PIN';

  @override
  String get tooltipShowValue => 'Mostra valore';

  @override
  String get tooltipHideValue => 'Nascondi';

  @override
  String get tooltipCancel => 'Annulla';

  @override
  String get tooltipOpenInBrowser => 'Apri nel browser';

  @override
  String get allFolders => 'Tutte le cartelle';

  @override
  String get noFolder => 'Nessuna';

  @override
  String get selectFolder => 'Seleziona una cartella';

  @override
  String get folderName => 'Nome cartella';

  @override
  String get noEntriesMatch => 'Nessuna voce corrisponde alla ricerca.';

  @override
  String get noVaultsRegistered => 'Nessun archivio registrato.';

  @override
  String get noYubiKeysRegistered => 'Nessuna YubiKey registrata';

  @override
  String get selectEntry => 'Seleziona una voce';

  @override
  String get newEntryTitle => 'Nuova voce';

  @override
  String createEntryTitle(String type) {
    return 'Nuovo $type';
  }

  @override
  String editEntryTitle(String type) {
    return 'Modifica $type';
  }

  @override
  String get noUrlFallback => '(nessun URL)';

  @override
  String get noNameFallback => '(nessun nome)';

  @override
  String get untitledFallback => '(senza titolo)';

  @override
  String get gabbroTitle => 'Gabbro';

  @override
  String gabbroVaultTitle(String alias) {
    return 'Gabbro - $alias';
  }

  @override
  String selectedCount(int count) {
    return '$count selezionato/i';
  }

  @override
  String get searchAllFieldsHint => 'Cerca in tutti i campi…';

  @override
  String get searchEntriesHint => 'Cerca voci…';

  @override
  String get searchAllFieldsTooltip => 'Ricerca in tutti i campi';

  @override
  String get searchByTitleTooltip => 'Ricerca per titolo';

  @override
  String get entryTypeAll => 'Tutti';

  @override
  String get entryTypePassword => 'Password';

  @override
  String get entryTypeNote => 'Nota';

  @override
  String get entryTypeCard => 'Carta';

  @override
  String get entryTypeIdentity => 'Identità';

  @override
  String get entryTypeFile => 'File';

  @override
  String get entryTypeCustom => 'Personalizzato';

  @override
  String errorPrefix(String error) {
    return 'Errore: $error';
  }

  @override
  String get navVault => 'Archivio';

  @override
  String get navAppearance => 'Aspetto';

  @override
  String get navSecurity => 'Sicurezza';

  @override
  String get navAbout => 'Info';

  @override
  String get deleteEntryTitle => 'Eliminare la voce?';

  @override
  String get cannotBeUndone => 'Questa azione non può essere annullata.';

  @override
  String get deleteEntryDialogTitle => 'Eliminare la voce?';

  @override
  String deleteEntriesTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Eliminare $count voci?',
      one: 'Eliminare 1 voce?',
    );
    return '$_temp0';
  }

  @override
  String get assignToFolderTitle => 'Assegna a cartella';

  @override
  String get folderConflictTitle => 'Conflitto di cartella';

  @override
  String get syncFailedTitle => 'Sincronizzazione fallita';

  @override
  String get syncFromFileTitle => 'Sincronizza da file';

  @override
  String get nothingToSync =>
      'Niente da sincronizzare — entrambi gli archivi sono già aggiornati.';

  @override
  String importedEntries(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count voci importate.',
      one: '1 voce importata.',
    );
    return '$_temp0';
  }

  @override
  String get exportFileTitle => 'Esporta file';

  @override
  String get saveDecryptedFileTo => 'Salva file decrittato in:';

  @override
  String get exportPathLabel => 'Percorso di esportazione';

  @override
  String exportedToPath(String path) {
    return 'Esportato in $path';
  }

  @override
  String exportFailed(String error) {
    return 'Esportazione fallita: $error';
  }

  @override
  String get openInBrowserTitle => 'Aprire nel browser?';

  @override
  String couldNotOpen(String url) {
    return 'Impossibile aprire $url';
  }

  @override
  String get deleteEntryFromHistoryLabel => 'Elimina voce precedente';

  @override
  String failedToClearHistory(String error) {
    return 'Impossibile cancellare la cronologia: $error';
  }

  @override
  String failedToRevertPassword(String error) {
    return 'Impossibile ripristinare la password: $error';
  }

  @override
  String get renameFolderTitle => 'Rinomina cartella';

  @override
  String get addFolderTitle => 'Aggiungi cartella';

  @override
  String get deleteFolderTitle => 'Elimina cartella';

  @override
  String deleteFolderConfirm(String folder) {
    return 'Eliminare «$folder»?';
  }

  @override
  String get reassignEntriesTo => 'Riassegna voci a';

  @override
  String get clearToNone => 'Reimposta su «Nessuna»';

  @override
  String get renameVaultTitle => 'Rinomina archivio';

  @override
  String get deleteVaultTitle => 'Eliminare l\'archivio?';

  @override
  String get deleteVaultConfirmTitle => 'Sei sicuro?';

  @override
  String get typeDeleteToConfirm => 'Digitare DELETE per confermare';

  @override
  String get typeDeleteWord => 'DELETE';

  @override
  String get touchYourYubiKey => 'Tocca la tua YubiKey';

  @override
  String get noVaultsRegisteredText => 'Nessun archivio registrato.';

  @override
  String get addYubiKeyTitle => 'Aggiungi YubiKey';

  @override
  String get enterYubiKeyPinTitle => 'Inserisci PIN YubiKey';

  @override
  String editAliasForKey(int index) {
    return 'Modifica alias per la chiave $index';
  }

  @override
  String get lastKeyWarning => 'Rimarrà una sola YubiKey registrata.';

  @override
  String get removeKeyConfirm => 'Rimuovere questa chiave?';

  @override
  String get removeKeyVaultConfirm =>
      'Rimuovere questa YubiKey dall\'archivio?';

  @override
  String get yubiKeyRemoved => 'YubiKey rimossa';

  @override
  String failedToRemoveKey(String error) {
    return 'Impossibile rimuovere la chiave: $error';
  }

  @override
  String get yubiKeyAdded => 'YubiKey aggiunta';

  @override
  String failedToAddKey(String error) {
    return 'Impossibile aggiungere la chiave: $error';
  }

  @override
  String failedToSaveAlias(String error) {
    return 'Impossibile salvare l\'alias: $error';
  }

  @override
  String get noFidoDeviceFound =>
      'Nessun dispositivo FIDO2 trovato. Inserisci la tua YubiKey e riprova.';

  @override
  String get transportLabel => 'Trasporto:';

  @override
  String get transportUsb => 'USB';

  @override
  String get transportNfc => 'NFC';

  @override
  String get passphraseLabel => 'Passphrase';

  @override
  String get yubiKeyPinLabel => 'PIN YubiKey';

  @override
  String get pinLabel => 'PIN';

  @override
  String get currentPassphraseLabel => 'Passphrase attuale';

  @override
  String get newPassphraseLabel => 'Nuova passphrase';

  @override
  String get confirmPassphraseLabel => 'Conferma nuova passphrase';

  @override
  String get vaultPassphraseLabel => 'Passphrase archivio';

  @override
  String get aliasLabel => 'Alias';

  @override
  String get aliasHint => 'es. Principale, Chiave lavoro…';

  @override
  String get masterPassphraseLabel => 'Passphrase principale';

  @override
  String get confirmPassphraseLabelShort => 'Conferma passphrase';

  @override
  String get fieldTitle => 'Titolo';

  @override
  String get fieldContent => 'Contenuto';

  @override
  String get fieldFirstName => 'Nome';

  @override
  String get fieldLastName => 'Cognome';

  @override
  String get fieldEmail => 'E-mail (facoltativo)';

  @override
  String get fieldPhone => 'Telefono (facoltativo)';

  @override
  String get fieldAddress => 'Indirizzo (facoltativo)';

  @override
  String get fieldCardLabel => 'Etichetta carta (es. «Visa Platinum»)';

  @override
  String get fieldCardholderName => 'Nome del titolare';

  @override
  String get fieldCardNumber => 'Numero carta';

  @override
  String get fieldExpiry => 'Scadenza (MM/AA)';

  @override
  String get fieldCvv => 'CVV (facoltativo)';

  @override
  String get fieldCardPin => 'PIN (facoltativo)';

  @override
  String get fieldCreditLimit => 'Limite di credito (facoltativo)';

  @override
  String get fieldAccountNumber => 'Numero conto (facoltativo)';

  @override
  String get fieldNotes => 'Note (facoltativo)';

  @override
  String get fieldUrl => 'URL (facoltativo)';

  @override
  String get fieldUsername => 'Nome utente';

  @override
  String get fieldPassword => 'Password';

  @override
  String get fieldSeparator => 'Separatore';

  @override
  String get fieldFolder => 'Cartella';

  @override
  String get fieldLabel => 'Etichetta';

  @override
  String get fieldValue => 'Valore';

  @override
  String get fieldCustomFields => 'Campi personalizzati';

  @override
  String fieldLabelOptional(String label) {
    return '$label (facoltativo)';
  }

  @override
  String get entryTypeNotSupported => 'Tipo di voce non ancora supportato.';

  @override
  String get csvColumnNone => '(nessuno)';

  @override
  String get csvPreviewLabel => 'Anteprima';

  @override
  String get csvImportButton => 'Importa';

  @override
  String get gabbroVaultSection => 'Archivio Gabbro';

  @override
  String get genericCsvSection => 'CSV generico';

  @override
  String get changePassphraseSuccess => 'Passphrase cambiata con successo';

  @override
  String get changePassphraseButton => 'Cambia passphrase';

  @override
  String get continueLabel => 'Continua';

  @override
  String get protectWithYubiKey => 'Proteggi con YubiKey';

  @override
  String get yubiKeySubtitle => 'Chiave di sicurezza hardware (consigliata)';

  @override
  String get accessibilityButton => 'Accessibilità';

  @override
  String get aboutProjectSection => 'Progetto';

  @override
  String get aboutLicenceSection => 'Licenza';

  @override
  String get aboutOpenSourceSection => 'Componenti open source';

  @override
  String get aboutAttributionSection => 'Attribuzioni';

  @override
  String get lengthLabel => 'Lunghezza';

  @override
  String get wordsLabel => 'Parole';

  @override
  String get generateButton => 'Genera';

  @override
  String get usePasswordButton => 'Usa questa password';

  @override
  String get showHidePassword => 'Mostra';

  @override
  String get deleteVaultPostDeletion =>
      'Il tuo archivio è stato eliminato. Creane uno nuovo per continuare.';

  @override
  String get syncFilePassphraseLabel => 'Passphrase archivio';

  @override
  String get historyWarning =>
      'Viene conservato solo 1 valore precedente. La cronologia viene eliminata automaticamente in base alle impostazioni di sicurezza.';

  @override
  String get historyCurrent => 'Attuale';

  @override
  String get historyPrevious => 'Precedente';

  @override
  String historySavedOn(String date) {
    return 'Salvato il $date';
  }

  @override
  String historyExpiresAppend(String saved, String expires) {
    return '$saved · scade il $expires';
  }

  @override
  String importIssueTitle(int index, int total) {
    return 'Problema di importazione ($index di $total)';
  }

  @override
  String importIssueType(String category) {
    return 'Tipo: $category';
  }

  @override
  String get importIssueHelp =>
      'Modifica per correggere e salvare questa voce, o salta per scartarla.';

  @override
  String entriesSkipped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count voci saltate',
      one: '1 voce saltata',
    );
    return '$_temp0';
  }

  @override
  String get skippedEntriesNote =>
      'Queste voci esistono già nel tuo archivio e non sono state sovrascritte:';

  @override
  String syncDeleteEntryContent(String title) {
    return 'L\'altro dispositivo ha eliminato «$title».\n\nEliminarlo anche qui, o mantenerlo?';
  }

  @override
  String folderConflictContent(String title, String local, String incoming) {
    return '«$title» si trova in cartelle diverse su ogni dispositivo.\n\nQuesto dispositivo: $local\nAltro dispositivo: $incoming';
  }

  @override
  String get folderConflictKeepUnfoldered => 'Mantieni senza cartella';

  @override
  String folderConflictKeepLocal(String folder) {
    return 'Mantieni «$folder»';
  }

  @override
  String get folderConflictMoveUnfoldered => 'Sposta senza cartella';

  @override
  String folderConflictMoveIncoming(String folder) {
    return 'Sposta in «$folder»';
  }

  @override
  String vaultSynced(int added, int updated, int deleted) {
    return 'Archivio sincronizzato — $added aggiunto/i, $updated aggiornato/i, $deleted eliminato/i.';
  }

  @override
  String get syncPassphraseMismatch =>
      'Questo file di archivio usa una passphrase diversa. La sincronizzazione è supportata solo tra archivi che condividono la stessa passphrase.';

  @override
  String get reviewSensitiveFields => 'Campi sensibili';

  @override
  String get reviewOtherFields => 'Altri campi';

  @override
  String get reviewPasswordChanged => 'Password modificata';

  @override
  String get reviewCvvChanged => 'CVV modificato';

  @override
  String get reviewPinChanged => 'PIN modificato';

  @override
  String get reviewTransactionPasswordChanged =>
      'Password di transazione modificata';

  @override
  String get tooltipShowValues => 'Mostra valori';

  @override
  String get reviewOld => 'Vecchio';

  @override
  String get reviewNew => 'Nuovo';

  @override
  String get reviewEmpty => '(vuoto)';

  @override
  String get reviewFieldUrl => 'URL';

  @override
  String get reviewFieldNotes => 'Note';

  @override
  String get reviewFieldContent => 'Contenuto';

  @override
  String get reviewFieldEmail => 'E-mail';

  @override
  String get reviewFieldPhone => 'Telefono';

  @override
  String get reviewFieldAddress => 'Indirizzo';

  @override
  String get reviewFieldCardLabel => 'Etichetta carta';

  @override
  String get reviewFieldStatus => 'Stato';

  @override
  String get reviewFieldCardholder => 'Titolare';

  @override
  String get reviewFieldExpiry => 'Scadenza';

  @override
  String get reviewFieldCreditLimit => 'Limite di credito';

  @override
  String get reviewFieldAccountNumber => 'Numero conto';

  @override
  String get reviewFieldNetwork => 'Rete';

  @override
  String get reviewFieldBank => 'Banca';

  @override
  String get reviewFieldFilename => 'Nome file';

  @override
  String get reviewFieldSize => 'Dimensione';

  @override
  String get reviewFieldCardNumber => 'Numero';

  @override
  String get reviewFieldCVV => 'CVV';

  @override
  String get reviewFieldTransactionPassword => 'Password di transazione';

  @override
  String get timestampCreated => 'Creato';

  @override
  String get timestampUpdated => 'Aggiornato';

  @override
  String get timestampUnknown => 'Sconosciuto';

  @override
  String get noTitleFallback => '(nessun titolo)';

  @override
  String get tooltipExportFile => 'Esporta file';

  @override
  String get tooltipEditEntry => 'Modifica voce';

  @override
  String get tooltipDeleteEntry => 'Elimina voce';

  @override
  String get exportLabel => 'Esporta';

  @override
  String get customEntryFieldsHeader => 'Campi';

  @override
  String get copiedNeverClears =>
      'Copiato — gli appunti non vengono mai puliti automaticamente';

  @override
  String get copiedClears30s => 'Copiato — gli appunti verranno puliti in 30s';

  @override
  String get copiedClears60s => 'Copiato — gli appunti verranno puliti in 60s';

  @override
  String get copiedClears2min =>
      'Copiato — gli appunti verranno puliti in 2 min';

  @override
  String get passwordBreakdownTitle => 'Analisi password';

  @override
  String get charTypeUppercase => 'Maiuscola';

  @override
  String get charTypeLowercase => 'Minuscola';

  @override
  String get charTypeDigit => 'Cifra';

  @override
  String get charTypeSymbol => 'Simbolo';

  @override
  String get exportChooseFormat => 'Scegli un formato di esportazione.';

  @override
  String get exportUnencryptedWarning =>
      'Completamente non cifrato — tutti i segreti verranno scritti in testo normale. Conserva questo file in modo sicuro ed eliminalo dopo l\'uso.';

  @override
  String get exportPassphraseOnlyNote =>
      'Protetto solo dalla tua passphrase. La YubiKey non è richiesta per l\'importazione.';

  @override
  String get exportChooseDestinationJson =>
      'Scegli una destinazione per il file JSON esportato.';

  @override
  String get exportChooseDestinationVault =>
      'Scegli una destinazione per il file archivio esportato.';

  @override
  String get exportTwoFilesNote =>
      'Verranno creati due file: vault.gabbro e vault.gabbro.sha256';

  @override
  String get exportSelectDestination => 'Seleziona una destinazione.';

  @override
  String aboutVersion(String version) {
    return 'Versione $version';
  }

  @override
  String get aboutTagline => 'Un gestore di password post-quantistico';

  @override
  String get aboutSourceCode => 'Codice sorgente';

  @override
  String get aboutReportIssue => 'Segnala un problema';

  @override
  String get aboutSupportGabbro => 'Supporta Gabbro';

  @override
  String get aboutLicenceBody =>
      'Gabbro è software libero e open source, distribuito sotto la GNU General Public License v3.0 only (GPL-3.0-only).\n\nSei libero di usare, studiare e ridistribuire questo software secondo i termini di tale licenza.';

  @override
  String get aboutOwnerRole =>
      'Proprietario del progetto, architetto e sviluppatore principale:';

  @override
  String get aboutAiPartner => 'Partner di sviluppo IA:';

  @override
  String get aboutNoTelemetry =>
      'Gabbro non effettua connessioni di rete in uscita. Niente telemetria, niente analitiche, niente account.';

  @override
  String get strengthTierTerrible => 'Terribile';

  @override
  String get strengthTierWeak => 'Debole';

  @override
  String get strengthTierFair => 'Sufficiente';

  @override
  String get strengthTierStrong => 'Forte';

  @override
  String get strengthTierVeryStrong => 'Molto forte';

  @override
  String get strengthTierExcellent => 'Eccellente';

  @override
  String get yubiKeyProtectedNote =>
      'Archivio protetto da YubiKey — il collegamento YubiKey verrà preservato.';

  @override
  String get yubiKeyPinRequired => 'Il PIN YubiKey è obbligatorio';

  @override
  String get tapYubiKeyNow => 'Tocca la tua YubiKey adesso…';

  @override
  String get touchYubiKeyToAuthorize =>
      'Tocca la tua YubiKey per autorizzare questa modifica.';

  @override
  String get currentPassphraseRequired =>
      'La passphrase attuale è obbligatoria';

  @override
  String get newPassphraseRequired => 'È richiesta una nuova passphrase';

  @override
  String get passphraseTooWeak => 'La passphrase è troppo debole';

  @override
  String get confirmPassphraseRequired => 'Conferma la tua nuova passphrase';

  @override
  String get passphrasesDoNotMatch => 'Le passphrase non corrispondono';

  @override
  String get passphrasesMatch => '✓ Le passphrase corrispondono';

  @override
  String get passphrasesNoMatch => '✗ Le passphrase non corrispondono';

  @override
  String entropyDisplay(String tier, String bits) {
    return '$tier · $bits bit';
  }

  @override
  String get transportError => 'Errore di trasporto.';

  @override
  String get authorizationFailed =>
      'Autorizzazione fallita — controlla il PIN e riprova.';

  @override
  String get unlockEnterPassphraseAndPin =>
      'Inserisci passphrase e PIN YubiKey per sbloccare';

  @override
  String get unlockEnterPassphrase => 'Inserisci la passphrase per sbloccare';

  @override
  String unlockEntropyDisplay(String tier, String bits) {
    return '$tier · $bits bit di entropia';
  }

  @override
  String get insertYubiKeyAndTap =>
      'Inserisci la tua YubiKey e toccala quando lampeggia';

  @override
  String get unlockErrorPassphrase =>
      'Impossibile sbloccare l\'archivio. Controlla la passphrase.';

  @override
  String get unlockErrorPassphraseAndPin =>
      'Impossibile sbloccare l\'archivio. Controlla la passphrase e il PIN YubiKey.';

  @override
  String get importSelectFile => 'Seleziona un file.';

  @override
  String get importFileNotFound => 'File non trovato.';

  @override
  String get importEnterPassphrase =>
      'Inserisci la passphrase per questo archivio.';

  @override
  String get importDuplicateWarning =>
      'Le voci il cui UUID esiste già nel tuo archivio verranno saltate automaticamente. Ti verrà mostrato un riepilogo.';

  @override
  String get importGabbroSubtitle =>
      'Sincronizza voci da un altro archivio Gabbro (file .gabbro)';

  @override
  String get importEnpassSubtitle =>
      'Esportazione JSON da Enpass (Strumenti → Esporta)';

  @override
  String get importBitwardenSubtitle =>
      'Esportazione JSON non cifrata da Bitwarden (Strumenti → Esporta archivio)';

  @override
  String get importCsvSubtitle =>
      'Esportazione CSV da qualsiasi gestore di password';

  @override
  String vaultNameAlreadyExists(String alias) {
    return 'Esiste già un archivio chiamato «$alias».';
  }

  @override
  String deleteVaultContent(String alias, String path) {
    return 'Questo eliminerà definitivamente «$alias» e tutti i suoi dati.\n\nFile: $path\n\nQuesta azione non può essere annullata.';
  }

  @override
  String deleteVaultYubikeyContent(String alias, String path) {
    return 'Questo eliminerà definitivamente «$alias» e rimuoverà il suo collegamento YubiKey.\n\nFile: $path\n\nQuesta azione non può essere annullata.';
  }

  @override
  String get yubiKeyAuthorizeDeletion =>
      'Inserisci il PIN e tocca la tua YubiKey per autorizzare questa eliminazione.';

  @override
  String get deleteVaultTooltip => 'Elimina archivio';

  @override
  String get yubiKeySecurityWarning => 'Avviso di sicurezza';

  @override
  String get removeYubiKeyTitle => 'Rimuovi YubiKey';

  @override
  String get yubiKeyLastKeyRiskWarning =>
      'ATTENZIONE: se questa chiave rimanente viene persa, danneggiata o rubata, l\'accesso all\'archivio sarà permanentemente impossibile. Non esiste nessuna procedura di recupero.';

  @override
  String get onlyOneKeyRegisteredWarning =>
      'Solo una chiave registrata. Se questa chiave viene persa, l\'accesso all\'archivio è permanentemente impossibile.';

  @override
  String get tapRegisterNfc => 'Avvicina la chiave al telefono per registrarla';

  @override
  String get tapRegisterUsb =>
      'Una volta connessa, tocca la chiave per registrarla';

  @override
  String get tapActivateNfc =>
      'Avvicina di nuovo la chiave al telefono per attivarla';

  @override
  String get tapActivateUsb =>
      'Una volta connessa, tocca di nuovo la chiave per attivarla';

  @override
  String failedToRegisterKey(String error) {
    return 'Impossibile registrare la chiave: $error';
  }

  @override
  String failedToActivateKey(String error) {
    return 'Impossibile attivare la chiave: $error';
  }

  @override
  String keyDefaultTitle(int index) {
    return 'Chiave $index';
  }

  @override
  String get tapYubiKeyToRegister =>
      'Tocca la tua nuova YubiKey per registrarla…';

  @override
  String get tapYubiKeyToActivate =>
      'Tocca di nuovo la tua nuova YubiKey per attivarla…';

  @override
  String get editAliasTooltip => 'Modifica alias';

  @override
  String get cannotRemoveLastKey => 'Impossibile rimuovere l\'ultima chiave';

  @override
  String get removeKeyTooltip => 'Rimuovi chiave';

  @override
  String manageYubiKeysError(String error) {
    return 'Errore: $error';
  }

  @override
  String get generatorModeClassic => 'Classico';

  @override
  String get generatorModePassphrase => 'Passphrase';

  @override
  String get charSetsHeader => 'Set di caratteri';

  @override
  String get languageHeader => 'Lingua';

  @override
  String get separatorLabel => 'Separatore';

  @override
  String get capitaliseWords => 'Capitalizza le parole';

  @override
  String get appendDigit => 'Aggiungi una cifra';

  @override
  String entropyBitsDisplay(String bits) {
    return '~$bits bit di entropia';
  }

  @override
  String get selectAtLeastOneCharSet => 'Seleziona almeno un set di caratteri';

  @override
  String get passwordMinLengthNote =>
      'Le password hanno almeno 32 caratteri. Se un sito ha un limite più breve, copia i primi caratteri necessari.';

  @override
  String get excludeAmbiguousChars =>
      'Escludi caratteri ambigui (0, O, l, 1, I)';
}
