// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get appName => 'Gabbro';

  @override
  String get filePickerUnavailable =>
      'File dialog unavailable here. Type or paste the path instead.';

  @override
  String get filePickerNoPortal =>
      'File dialog unavailable here. The system file portal isn\'t reachable.';

  @override
  String get cancel => '취소';

  @override
  String get delete => '삭제';

  @override
  String get save => '저장';

  @override
  String get close => '닫기';

  @override
  String get ok => '확인';

  @override
  String get edit => '편집';

  @override
  String get saveConfirmTitle => 'Gabbro에 저장';

  @override
  String get saveConfirmUpdate => '이 로그인 업데이트';

  @override
  String get saveConfirmAsNew => '새 로그인으로 저장';

  @override
  String get saveConfirmChooseAnother => '다른 로그인 선택';

  @override
  String get saveConfirmAlreadySaved => '이 비밀번호로 이미 저장됨.';

  @override
  String get saveConfirmSwitchVaultHint => '다른 볼트에 저장하려면 먼저 이 볼트를 잠그세요.';

  @override
  String get autofillNoMatchTitle => '자격 증명을 찾을 수 없음';

  @override
  String get autofillNoMatchBody => '이 앱 또는 사이트와 일치하는 저장된 로그인이 없습니다.';

  @override
  String get add => '추가';

  @override
  String get remove => '제거';

  @override
  String get rename => '이름 변경';

  @override
  String get confirm => '확인';

  @override
  String get continueAction => '계속';

  @override
  String get dismiss => '닫기';

  @override
  String get authorize => '승인';

  @override
  String get register => '등록';

  @override
  String get sync => '동기화';

  @override
  String get assign => '할당';

  @override
  String get unlock => '잠금 해제';

  @override
  String get generate => '생성';

  @override
  String get import => '가져오기';

  @override
  String get export => '내보내기';

  @override
  String get openInBrowser => '브라우저에서 열기';

  @override
  String get useThisPassword => '이 비밀번호 사용';

  @override
  String get reviewArrow => '검토 →';

  @override
  String get skip => '건너뛰기';

  @override
  String get keep => '유지';

  @override
  String get revert => '되돌리기';

  @override
  String get next => '다음: 열 매핑';

  @override
  String get syncFromVault => '볼트에서 동기화';

  @override
  String get createVault => '볼트 만들기';

  @override
  String get pickFile => '파일 선택';

  @override
  String get noFileSelected => '파일이 선택되지 않았습니다';

  @override
  String get chooseFolder => '폴더 선택';

  @override
  String get addCustomField => '사용자 정의 필드 추가';

  @override
  String get exportFile => '파일 내보내기';

  @override
  String get addVault => '볼트 추가';

  @override
  String get addYubiKey => 'YubiKey 추가';

  @override
  String get noChangesToSave => '저장할 변경 사항이 없습니다.';

  @override
  String get appearanceTitle => '외관';

  @override
  String get securityTitle => '보안';

  @override
  String get aboutTitle => 'Gabbro 정보';

  @override
  String get generatorTitle => '비밀번호 생성기';

  @override
  String get importTitle => '항목 가져오기';

  @override
  String get exportTitle => '볼트 내보내기';

  @override
  String get changePassphraseTitle => '암호 문구 변경';

  @override
  String get csvMappingTitle => 'CSV 열 매핑';

  @override
  String get manageFoldersTitle => '폴더 관리';

  @override
  String get manageVaultsTitle => '볼트 관리';

  @override
  String get manageYubiKeysTitle => 'YubiKey 관리';

  @override
  String get passwordHistoryTitle => '비밀번호 기록';

  @override
  String get reviewChangesTitle => '변경 사항 검토';

  @override
  String get unlockGabbroTitle => 'Gabbro 잠금 해제';

  @override
  String get sectionTheme => '테마';

  @override
  String get sectionTextSize => '글자 크기';

  @override
  String get sectionAlphabetBar => '알파벳 바 위치';

  @override
  String get sectionAccessibility => '접근성';

  @override
  String get sectionLanguage => '언어';

  @override
  String get sectionForegroundLock => '포그라운드 잠금';

  @override
  String get sectionBackgroundLock => '백그라운드 잠금';

  @override
  String get sectionPasswordHistory => '비밀번호 기록';

  @override
  String get sectionPassphraseCopyPaste => '암호 문구 복사/붙여넣기';

  @override
  String get sectionClipboardClear => '클립보드 지우기';

  @override
  String get sectionCharacterSets => '문자 세트';

  @override
  String get sectionGeneratorLanguage => '언어';

  @override
  String get themeSystem => '시스템';

  @override
  String get themeLight => '라이트';

  @override
  String get themeDark => '다크';

  @override
  String get textSizeSmall => '작음';

  @override
  String get textSizeRegular => '보통';

  @override
  String get textSizeLarge => '큼';

  @override
  String get textSizeXL => 'XL';

  @override
  String get textSizeXXL => 'XXL';

  @override
  String get alphabetBarNote => '스마트폰에서만 사용 — 태블릿은 항상 왼쪽을 사용합니다.';

  @override
  String get alphabetBarLeft => '왼쪽';

  @override
  String get alphabetBarRight => '오른쪽';

  @override
  String get highContrastTitle => '고대비';

  @override
  String get highContrastSubtitle => '가독성을 높이기 위해 대비를 강화합니다';

  @override
  String get languageNote => '시스템 언어를 재정의합니다. «시스템»은 기기의 지역 설정을 따릅니다.';

  @override
  String get langSystem => '시스템';

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
  String get foregroundLockDescription => '앱이 열려 있을 때 이 비활성 시간 이후 잠급니다.';

  @override
  String get backgroundLockDescription => '앱이 이 시간 동안 백그라운드에 있은 후 잠급니다.';

  @override
  String get passwordHistoryDescription =>
      '변경 후 이전 비밀번호를 보관하는 기간. «항상 유지»는 수동으로만 기록이 삭제됨을 의미합니다.';

  @override
  String get passphraseCopyPasteDescription =>
      '암호 문구 필드에서 복사 및 붙여넣기를 차단합니다. 권장: 클립보드를 통한 문구 유출을 방지합니다.';

  @override
  String get passphraseCopyPasteNote =>
      '참고: 이렇게 하면 길게 누르기 컨텍스트 메뉴와 텍스트 선택이 차단됩니다. 키보드 내장 붙여넣기 버튼은 여전히 작동할 수 있습니다 — 이는 플랫폼 제한입니다.';

  @override
  String get blockCopyPasteTitle => '복사/붙여넣기 차단';

  @override
  String get clipboardClearDescription =>
      '비밀을 복사한 후 클립보드를 지웁니다. 참고: 클립보드 관리자가 복사본을 유지할 수 있습니다.';

  @override
  String get duration30s => '30초';

  @override
  String get duration1min => '1분';

  @override
  String get duration5min => '5분';

  @override
  String get duration15min => '15분';

  @override
  String get duration60s => '60초';

  @override
  String get duration2min => '2분';

  @override
  String get durationNever => '없음';

  @override
  String get duration7days => '7일';

  @override
  String get duration30days => '30일';

  @override
  String get duration90days => '90일';

  @override
  String get durationKeepForever => '항상 유지';

  @override
  String get menuExportVault => '볼트 내보내기';

  @override
  String get menuImportEntries => '항목 가져오기';

  @override
  String get menuSyncFromFile => '파일에서 동기화';

  @override
  String get menuManageVaults => '볼트 관리';

  @override
  String get menuChangePassphrase => '암호 문구 변경';

  @override
  String get menuManageYubiKeys => 'YubiKey 관리';

  @override
  String get menuAppearance => '외관';

  @override
  String get menuSecurity => '보안';

  @override
  String get menuManageFolders => '폴더 관리';

  @override
  String get menuPasswordGenerator => '비밀번호 생성기';

  @override
  String get menuAbout => '정보';

  @override
  String get tooltipSelectEntries => '항목 선택';

  @override
  String get tooltipLockVault => '볼트 잠금';

  @override
  String get tooltipSelectAll => '모두 선택';

  @override
  String get tooltipDeselectAll => '모두 선택 해제';

  @override
  String get tooltipClearSearch => '검색 지우기';

  @override
  String get tooltipMenu => '메뉴';

  @override
  String get tooltipCopy => '복사';

  @override
  String get tooltipCopied => '복사됨!';

  @override
  String get tooltipShow => '표시';

  @override
  String get tooltipHide => '숨기기';

  @override
  String get tooltipBrowse => '찾아보기';

  @override
  String get tooltipPreviousPage => '이전 페이지';

  @override
  String get tooltipNextPage => '다음 페이지';

  @override
  String get tooltipEditAlias => '별칭 편집';

  @override
  String get tooltipRemoveField => '필드 제거';

  @override
  String get tooltipRename => '이름 변경';

  @override
  String get tooltipDeleteVault => '볼트 삭제';

  @override
  String get tooltipAssignToFolder => '폴더에 할당';

  @override
  String get tooltipShowPin => 'PIN 표시';

  @override
  String get tooltipHidePin => 'PIN 숨기기';

  @override
  String get tooltipShowValue => '값 표시';

  @override
  String get tooltipHideValue => '숨기기';

  @override
  String get tooltipCancel => '취소';

  @override
  String get tooltipOpenInBrowser => '브라우저에서 열기';

  @override
  String get allFolders => '모든 폴더';

  @override
  String get noFolder => '없음';

  @override
  String get selectFolder => '폴더 선택';

  @override
  String get folderName => '폴더 이름';

  @override
  String get noEntriesMatch => '검색과 일치하는 항목이 없습니다.';

  @override
  String get noVaultsRegistered => '등록된 볼트가 없습니다.';

  @override
  String get noYubiKeysRegistered => '등록된 YubiKey가 없습니다';

  @override
  String get selectEntry => '항목 선택';

  @override
  String get newEntryTitle => '새 항목';

  @override
  String createEntryTitle(String type) {
    return '새 $type';
  }

  @override
  String editEntryTitle(String type) {
    return '편집: $type';
  }

  @override
  String get noUrlFallback => '(URL 없음)';

  @override
  String get noNameFallback => '(이름 없음)';

  @override
  String get untitledFallback => '(제목 없음)';

  @override
  String get gabbroTitle => 'Gabbro';

  @override
  String gabbroVaultTitle(String alias) {
    return 'Gabbro — $alias';
  }

  @override
  String selectedCount(int count) {
    return '선택됨: $count';
  }

  @override
  String get searchAllFieldsHint => '모든 필드 검색…';

  @override
  String get searchEntriesHint => '항목 검색…';

  @override
  String get searchAllFieldsTooltip => '모든 필드를 검색합니다';

  @override
  String get searchByTitleTooltip => '제목으로 검색합니다';

  @override
  String get entryTypeAll => '전체';

  @override
  String get entryTypePassword => '비밀번호';

  @override
  String get entryTypeNote => '메모';

  @override
  String get entryTypeCard => '카드';

  @override
  String get entryTypeIdentity => '신원';

  @override
  String get entryTypeFile => '파일';

  @override
  String get entryTypeCustom => '사용자 정의';

  @override
  String errorPrefix(String error) {
    return '오류: $error';
  }

  @override
  String get navVault => '볼트';

  @override
  String get navAppearance => '외관';

  @override
  String get navSecurity => '보안';

  @override
  String get navAbout => '정보';

  @override
  String get deleteEntryTitle => '항목을 삭제하시겠습니까?';

  @override
  String get cannotBeUndone => '이 작업은 취소할 수 없습니다.';

  @override
  String get deleteEntryDialogTitle => '항목을 삭제하시겠습니까?';

  @override
  String deleteEntriesTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count개의 항목을 삭제하시겠습니까?',
    );
    return '$_temp0';
  }

  @override
  String get assignToFolderTitle => '폴더에 할당';

  @override
  String get folderConflictTitle => '폴더 충돌';

  @override
  String get syncFailedTitle => '동기화에 실패했습니다';

  @override
  String get syncFromFileTitle => '파일에서 동기화';

  @override
  String get nothingToSync => '동기화할 것이 없습니다 — 두 볼트 모두 이미 최신 상태입니다.';

  @override
  String importedEntries(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count개의 항목을 가져왔습니다.',
    );
    return '$_temp0';
  }

  @override
  String get exportFileTitle => '파일 내보내기';

  @override
  String get saveDecryptedFileTo => '복호화된 파일 저장 위치:';

  @override
  String get exportPathLabel => '내보내기 경로';

  @override
  String exportedToPath(String path) {
    return '$path에 내보냈습니다';
  }

  @override
  String exportFailed(String error) {
    return '내보내기에 실패했습니다: $error';
  }

  @override
  String get openInBrowserTitle => '브라우저에서 열기?';

  @override
  String couldNotOpen(String url) {
    return '$url을(를) 열 수 없습니다';
  }

  @override
  String get deleteEntryFromHistoryLabel => '이전 항목 삭제';

  @override
  String failedToClearHistory(String error) {
    return '기록 지우기에 실패했습니다: $error';
  }

  @override
  String failedToRevertPassword(String error) {
    return '비밀번호 되돌리기에 실패했습니다: $error';
  }

  @override
  String get renameFolderTitle => '폴더 이름 변경';

  @override
  String get addFolderTitle => '폴더 추가';

  @override
  String get deleteFolderTitle => '폴더 삭제';

  @override
  String deleteFolderConfirm(String folder) {
    return '«$folder»을(를) 삭제하시겠습니까?';
  }

  @override
  String get reassignEntriesTo => '항목 이동 대상:';

  @override
  String get clearToNone => '«없음»으로 이동';

  @override
  String get renameVaultTitle => '볼트 이름 변경';

  @override
  String get deleteVaultTitle => '볼트를 삭제하시겠습니까?';

  @override
  String get deleteVaultConfirmTitle => '확실하십니까?';

  @override
  String deleteVaultUnderstand(String alias) {
    return '이 작업은 \"$alias\"을(를) 영구적으로 삭제하며 되돌릴 수 없음을 이해합니다.';
  }

  @override
  String get noBackupFidoDeviceFound =>
      '백업 FIDO2 장치를 찾을 수 없습니다. 백업 YubiKey를 삽입하세요.';

  @override
  String get yubikeyOperationFailed => 'YubiKey 작업에 실패했습니다.';

  @override
  String get unlockFailed => '잠금 해제에 실패했습니다.';

  @override
  String get csvMapTitleOrUrl => '항목에 이름이 있도록 제목 또는 URL을 하나 이상 매핑하세요.';

  @override
  String get pickAFile => '파일을 선택하세요.';

  @override
  String get touchYourYubiKey => 'YubiKey에 터치하세요';

  @override
  String get noVaultsRegisteredText => '등록된 볼트가 없습니다.';

  @override
  String get addYubiKeyTitle => 'YubiKey 추가';

  @override
  String get enterYubiKeyPinTitle => 'YubiKey PIN 입력';

  @override
  String editAliasForKey(int index) {
    return '키 $index의 별칭 편집';
  }

  @override
  String get lastKeyWarning => '등록된 YubiKey가 하나만 남게 됩니다.';

  @override
  String get removeKeyConfirm => '이 키를 제거하시겠습니까?';

  @override
  String get removeKeyVaultConfirm => '이 YubiKey를 볼트에서 제거하시겠습니까?';

  @override
  String get yubiKeyRemoved => 'YubiKey가 제거됐습니다';

  @override
  String failedToRemoveKey(String error) {
    return '키 제거에 실패했습니다: $error';
  }

  @override
  String get yubiKeyAdded => 'YubiKey가 추가됐습니다';

  @override
  String failedToAddKey(String error) {
    return '키 추가에 실패했습니다: $error';
  }

  @override
  String failedToSaveAlias(String error) {
    return '별칭 저장에 실패했습니다: $error';
  }

  @override
  String get noFidoDeviceFound =>
      'FIDO2 장치를 찾을 수 없습니다. YubiKey를 삽입하고 다시 시도하세요.';

  @override
  String get transportLabel => '전송:';

  @override
  String get transportUsb => 'USB';

  @override
  String get transportNfc => 'NFC';

  @override
  String get passphraseLabel => '암호 문구';

  @override
  String get yubiKeyPinLabel => 'YubiKey PIN';

  @override
  String get pinLabel => 'PIN';

  @override
  String get currentPassphraseLabel => '현재 암호 문구';

  @override
  String get newPassphraseLabel => '새 암호 문구';

  @override
  String get confirmPassphraseLabel => '새 암호 문구 확인';

  @override
  String get vaultPassphraseLabel => '볼트 암호 문구';

  @override
  String get aliasLabel => '별칭';

  @override
  String get aliasHint => '예: 메인, 작업용 키…';

  @override
  String get masterPassphraseLabel => '마스터 암호 문구';

  @override
  String get confirmPassphraseLabelShort => '암호 문구 확인';

  @override
  String get fieldTitle => '제목';

  @override
  String get fieldContent => '내용';

  @override
  String get fieldFirstName => '이름';

  @override
  String get fieldLastName => '성';

  @override
  String get fieldEmail => '이메일 (선택사항)';

  @override
  String get fieldPhone => '전화 (선택사항)';

  @override
  String get fieldAddress => '주소 (선택사항)';

  @override
  String get fieldCardLabel => '카드 이름 (예: «Visa Platinum»)';

  @override
  String get fieldCardholderName => '카드 소지자 이름';

  @override
  String get fieldCardNumber => '카드 번호';

  @override
  String get fieldExpiry => '유효기간 (MM/YY)';

  @override
  String get fieldCvv => 'CVV (선택사항)';

  @override
  String get fieldCardPin => 'PIN (선택사항)';

  @override
  String get fieldCreditLimit => '신용 한도 (선택사항)';

  @override
  String get fieldAccountNumber => '계좌번호 (선택사항)';

  @override
  String get fieldNotes => '메모 (선택사항)';

  @override
  String get fieldUrl => 'URL (선택사항)';

  @override
  String get fieldAndroidAppId => 'Android 앱 ID(선택사항)';

  @override
  String get fieldAndroidAppIdHelper =>
      '이 로그인을 Android 앱에서 자동 입력합니다. 정확히 일치할 때만 작동합니다. 앱의 Play Store 링크에서 id= 뒤에 ID가 있습니다(예: id=com.company.app).';

  @override
  String get recentlyUsedApps => '최근 사용한 앱';

  @override
  String get fieldUsername => '사용자 이름 (선택사항)';

  @override
  String get fieldPassword => '비밀번호';

  @override
  String get fieldSeparator => '구분자';

  @override
  String get fieldFolder => '폴더';

  @override
  String get fieldLabel => '레이블';

  @override
  String get fieldValue => '값';

  @override
  String get fieldCustomFields => '사용자 정의 필드';

  @override
  String fieldLabelOptional(String label) {
    return '$label (선택사항)';
  }

  @override
  String get entryTypeNotSupported => '이 항목 유형은 아직 지원되지 않습니다.';

  @override
  String get csvColumnNone => '(없음)';

  @override
  String get csvPreviewLabel => '미리보기';

  @override
  String get csvImportButton => '가져오기';

  @override
  String get gabbroVaultSection => 'Gabbro 볼트';

  @override
  String get genericCsvSection => '일반 CSV';

  @override
  String get changePassphraseSuccess => '암호 문구가 변경됐습니다';

  @override
  String get changePassphraseBiometricDisabled =>
      'Passphrase changed. Biometric unlock was turned off; re-enable it in Settings.';

  @override
  String get changePassphraseButton => '암호 문구 변경';

  @override
  String get continueLabel => '계속';

  @override
  String get protectWithYubiKey => 'YubiKey로 보호';

  @override
  String get yubiKeySubtitle => '하드웨어 보안 키 (권장)';

  @override
  String get accessibilityButton => '접근성';

  @override
  String get aboutProjectSection => '프로젝트';

  @override
  String get aboutLicenceSection => '라이선스';

  @override
  String get aboutOpenSourceSection => '오픈소스 구성 요소';

  @override
  String get aboutAttributionSection => '크레딧';

  @override
  String get lengthLabel => '길이';

  @override
  String get wordsLabel => '단어 수';

  @override
  String get generateButton => '생성';

  @override
  String get usePasswordButton => '이 비밀번호 사용';

  @override
  String get showHidePassword => '표시';

  @override
  String get deleteVaultPostDeletion => '볼트가 삭제됐습니다. 계속하려면 새 볼트를 만드세요.';

  @override
  String get syncFilePassphraseLabel => '볼트 암호 문구';

  @override
  String get historyWarning => '이전 값은 1개만 유지됩니다. 기록은 보안 설정에 따라 자동으로 삭제됩니다.';

  @override
  String get historyCurrent => '현재';

  @override
  String get historyPrevious => '이전';

  @override
  String historySavedOn(String date) {
    return '$date에 저장됨';
  }

  @override
  String historyExpiresAppend(String saved, String expires) {
    return '$saved · $expires에 만료';
  }

  @override
  String importIssueTitle(int index, int total) {
    return '가져오기 문제 ($index/$total)';
  }

  @override
  String importIssueType(String category) {
    return '유형: $category';
  }

  @override
  String get importIssueHelp => '이 항목을 편집, 수정하고 저장하거나 건너뛰어 거부하세요.';

  @override
  String entriesSkipped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count개의 항목을 건너뛰었습니다',
    );
    return '$_temp0';
  }

  @override
  String get skippedEntriesNote => '다음 항목은 이미 볼트에 존재하며 덮어쓰지 않았습니다:';

  @override
  String syncDeleteEntryContent(String title) {
    return '다른 기기에서 «$title»을(를) 삭제했습니다.\n\n여기서도 삭제하시겠습니까, 아니면 유지하시겠습니까?';
  }

  @override
  String folderConflictContent(String title, String local, String incoming) {
    return '«$title»이(가) 두 기기에서 서로 다른 폴더에 있습니다.\n\n이 기기: $local\n다른 기기: $incoming';
  }

  @override
  String get folderConflictKeepUnfoldered => '폴더 없이 유지';

  @override
  String folderConflictKeepLocal(String folder) {
    return '«$folder» 유지';
  }

  @override
  String get folderConflictMoveUnfoldered => '폴더 없이 이동';

  @override
  String folderConflictMoveIncoming(String folder) {
    return '«$folder»로 이동';
  }

  @override
  String vaultSynced(int added, int updated, int deleted) {
    return '볼트가 동기화됐습니다 — 추가: $added개, 업데이트: $updated개, 삭제: $deleted개.';
  }

  @override
  String get syncPassphraseMismatch =>
      '이 볼트 파일은 다른 암호 문구를 사용합니다. 동기화는 같은 암호 문구를 가진 볼트 간에만 지원됩니다.';

  @override
  String get reviewSensitiveFields => '민감한 필드';

  @override
  String get reviewOtherFields => '기타 필드';

  @override
  String get reviewPasswordChanged => '비밀번호가 변경됐습니다';

  @override
  String get reviewCvvChanged => 'CVV가 변경됐습니다';

  @override
  String get reviewPinChanged => 'PIN이 변경됐습니다';

  @override
  String get reviewTransactionPasswordChanged => '거래 비밀번호가 변경됐습니다';

  @override
  String get tooltipShowValues => '값 표시';

  @override
  String get reviewOld => '이전';

  @override
  String get reviewNew => '새';

  @override
  String get reviewEmpty => '(비어 있음)';

  @override
  String get reviewFieldUrl => 'URL';

  @override
  String get reviewFieldNotes => '메모';

  @override
  String get reviewFieldContent => '내용';

  @override
  String get reviewFieldEmail => '이메일';

  @override
  String get reviewFieldPhone => '전화';

  @override
  String get reviewFieldAddress => '주소';

  @override
  String get reviewFieldCardLabel => '카드 이름';

  @override
  String get reviewFieldStatus => '상태';

  @override
  String get reviewFieldCardholder => '카드 소지자';

  @override
  String get reviewFieldExpiry => '유효기간';

  @override
  String get reviewFieldCreditLimit => '신용 한도';

  @override
  String get reviewFieldAccountNumber => '계좌번호';

  @override
  String get reviewFieldNetwork => '네트워크';

  @override
  String get reviewFieldBank => '은행';

  @override
  String get reviewFieldFilename => '파일 이름';

  @override
  String get reviewFieldSize => '크기';

  @override
  String get reviewFieldCardNumber => '번호';

  @override
  String get reviewFieldCVV => 'CVV';

  @override
  String get reviewFieldTransactionPassword => '거래 비밀번호';

  @override
  String get timestampCreated => '생성됨';

  @override
  String get timestampUpdated => '업데이트됨';

  @override
  String get timestampUnknown => '알 수 없음';

  @override
  String get noTitleFallback => '(제목 없음)';

  @override
  String get tooltipExportFile => '파일 내보내기';

  @override
  String get tooltipEditEntry => '항목 편집';

  @override
  String get tooltipDeleteEntry => '항목 삭제';

  @override
  String get exportLabel => '내보내기';

  @override
  String get customEntryFieldsHeader => '필드';

  @override
  String get copiedNeverClears => '복사됨 — 클립보드는 자동으로 지워지지 않습니다';

  @override
  String get copiedClears30s => '복사됨 — 클립보드는 30초 후 지워집니다';

  @override
  String get copiedClears60s => '복사됨 — 클립보드는 60초 후 지워집니다';

  @override
  String get copiedClears2min => '복사됨 — 클립보드는 2분 후 지워집니다';

  @override
  String get passwordBreakdownTitle => '비밀번호 분석';

  @override
  String get charTypeUppercase => '대문자';

  @override
  String get charTypeLowercase => '소문자';

  @override
  String get charTypeDigit => '숫자';

  @override
  String get charTypeSymbol => '기호';

  @override
  String get charTypeLetter => '글자';

  @override
  String get exportIncludeDate => '파일 이름에 날짜 포함';

  @override
  String get exportChooseFormat => '내보내기 형식을 선택하세요.';

  @override
  String get exportUnencryptedWarning =>
      '완전히 암호화되지 않음 — 모든 비밀이 일반 텍스트로 기록됩니다. 파일을 안전하게 보관하고 사용 후 삭제하세요.';

  @override
  String get exportPassphraseOnlyNote =>
      '암호 문구로만 보호됩니다. 가져오기에 YubiKey가 필요하지 않습니다.';

  @override
  String get exportProtectionKeyProtected =>
      '암호 구문과 YubiKey로 보호됩니다. 내보낸 사본은 이 보호를 유지합니다 — 가져오려면 등록된 YubiKey가 필요합니다.';

  @override
  String get exportWithoutYubikey => 'YubiKey 보호 없이 내보내기(암호 구문만)';

  @override
  String get exportWithoutYubikeyWarning =>
      '내보낸 파일은 암호 구문만으로 열립니다 — YubiKey가 필요하지 않습니다. 암호 구문을 아는 사람은 누구나 읽을 수 있습니다. 원본 보관함은 변경되지 않습니다.';

  @override
  String get exportChooseDestinationJson => '내보낸 JSON 파일의 저장 위치를 선택하세요.';

  @override
  String get exportChooseDestinationVault => '내보낸 볼트 파일의 저장 위치를 선택하세요.';

  @override
  String get exportTwoFilesNote =>
      '두 개의 파일이 만들어집니다: vault.gabbro 및 vault.gabbro.sha256';

  @override
  String get exportSelectDestination => '저장 위치를 선택하세요.';

  @override
  String aboutVersion(String version) {
    return '버전 $version';
  }

  @override
  String get aboutTagline => '포스트 퀀텀 비밀번호 관리자';

  @override
  String get aboutSourceCode => '소스 코드';

  @override
  String get aboutReportIssue => '문제 보고';

  @override
  String get aboutSupportGabbro => 'Gabbro 지원';

  @override
  String get aboutLicenceBody =>
      'Gabbro는 GNU General Public License v3.0 only (GPL-3.0-only) 하에 라이선스된 무료 오픈소스 소프트웨어입니다.\n\n라이선스 조건에 따라 이 애플리케이션을 사용, 연구, 배포할 자유가 있습니다.';

  @override
  String get aboutOwnerRole => '프로젝트 소유자, 아키텍트 및 주요 개발자:';

  @override
  String get aboutAiPartner => 'AI 개발 파트너:';

  @override
  String get aboutNoTelemetry =>
      'Gabbro는 외부 네트워크 연결을 하지 않습니다. 원격 측정, 분석 또는 계정이 없습니다.';

  @override
  String get strengthTierTerrible => '매우 약함';

  @override
  String get strengthTierWeak => '약함';

  @override
  String get strengthTierFair => '보통';

  @override
  String get strengthTierStrong => '강함';

  @override
  String get strengthTierVeryStrong => '매우 강함';

  @override
  String get strengthTierExcellent => '우수';

  @override
  String get yubiKeyProtectedNote => 'YubiKey로 보호된 볼트 — 키 바인딩이 유지됩니다.';

  @override
  String get yubiKeyPinRequired => 'YubiKey PIN이 필요합니다';

  @override
  String get tapYubiKeyNow => '지금 YubiKey에 터치하세요…';

  @override
  String get touchYubiKeyToAuthorize => '이 변경을 승인하기 위해 YubiKey에 터치하세요.';

  @override
  String get currentPassphraseRequired => '현재 암호 문구가 필요합니다';

  @override
  String get newPassphraseRequired => '새 암호 문구가 필요합니다';

  @override
  String get passphraseTooWeak => '암호 문구가 너무 약합니다';

  @override
  String get confirmPassphraseRequired => '새 암호 문구를 확인하세요';

  @override
  String get passphrasesDoNotMatch => '암호 문구가 일치하지 않습니다';

  @override
  String get passphrasesMatch => '✓ 암호 문구가 일치합니다';

  @override
  String get passphrasesNoMatch => '✗ 암호 문구가 일치하지 않습니다';

  @override
  String entropyDisplay(String tier, String bits) {
    return '$tier · $bits비트';
  }

  @override
  String get transportError => '전송 오류.';

  @override
  String get authorizationFailed => '승인에 실패했습니다 — PIN을 확인하고 다시 시도하세요.';

  @override
  String get unlockEnterPassphraseAndPin => '암호 문구와 YubiKey PIN을 입력하여 잠금 해제';

  @override
  String get unlockEnterPassphrase => '암호 문구를 입력하여 잠금 해제';

  @override
  String unlockEntropyDisplay(String tier, String bits) {
    return '$tier · $bits비트 엔트로피';
  }

  @override
  String get insertYubiKeyAndTap => 'YubiKey를 삽입하고 깜박이면 터치하세요';

  @override
  String get unlockErrorPassphrase => '볼트 잠금을 해제할 수 없습니다. 암호 문구를 확인하세요.';

  @override
  String get unlockErrorPassphraseAndPin =>
      '볼트 잠금을 해제할 수 없습니다. 암호 문구와 YubiKey PIN을 확인하세요.';

  @override
  String get importSelectFile => '파일을 선택하세요.';

  @override
  String get importFileNotFound => '파일을 찾을 수 없습니다.';

  @override
  String get importEnterPassphrase => '이 볼트의 암호 문구를 입력하세요.';

  @override
  String get importSourceKeyProtected =>
      '이 보관함은 YubiKey로 보호됩니다. 동기화하려면 등록된 키를 탭해야 합니다.';

  @override
  String get importDuplicateWarning =>
      'UUID가 이미 볼트에 존재하는 항목은 자동으로 건너뜁니다. 요약이 표시됩니다.';

  @override
  String get importGabbroSubtitle => '다른 Gabbro 볼트 (.gabbro)에서 항목 동기화';

  @override
  String get importEnpassSubtitle => 'Enpass에서 JSON 내보내기 (도구 → 내보내기)';

  @override
  String get importBitwardenSubtitle =>
      'Bitwarden에서 암호화되지 않은 JSON 내보내기 (도구 → 볼트 내보내기)';

  @override
  String get importCsvSubtitle => '비밀번호 관리자에서 CSV 내보내기';

  @override
  String get importGooglePmSubtitle =>
      'Google 비밀번호 관리자에서 CSV 내보내기 (passwords.google.com → 다운로드)';

  @override
  String get importDashlaneSubtitle =>
      'Dashlane에서 CSV 내보내기 (설정 → 데이터 내보내기 → 자격 증명)';

  @override
  String vaultNameAlreadyExists(String alias) {
    return '이름이 «$alias»인 볼트가 이미 존재합니다.';
  }

  @override
  String deleteVaultContent(String alias, String path) {
    return '이렇게 하면 «$alias»와 모든 데이터가 영구적으로 삭제됩니다.\n\n파일: $path\n\n이 작업은 취소할 수 없습니다.';
  }

  @override
  String deleteVaultYubikeyContent(String alias, String path) {
    return '이렇게 하면 «$alias»와 YubiKey 바인딩이 영구적으로 삭제됩니다.\n\n파일: $path\n\n이 작업은 취소할 수 없습니다.';
  }

  @override
  String get yubiKeyAuthorizeDeletion =>
      'PIN을 입력하고 삭제를 승인하기 위해 YubiKey에 터치하세요.';

  @override
  String get deleteVaultTooltip => '볼트 삭제';

  @override
  String get backupEmergencyHeading => '백업 및 긴급 삭제';

  @override
  String get backupResponsibilityBody =>
      'Gabbro는 보관함을 백업하지 않습니다. 각 보관함의 사본을 다른 기기에 보관하세요. 삭제되거나 분실된 보관함을 복구하는 유일한 방법은 사용자 본인의 백업입니다.';

  @override
  String get emergencyWipeAndroidBody =>
      '기기의 모든 Gabbro 데이터를 즉시 파기하려면(인증 없음, 되돌릴 수 없음) 기기 설정을 열고 앱 목록에서 Gabbro를 찾아 데이터 지우기를 선택하세요.';

  @override
  String get emergencyWipeLinuxBody =>
      '기기의 모든 Gabbro 데이터를 즉시 파기하려면(인증 없음, 되돌릴 수 없음) 터미널에서 이 폴더들을 삭제하세요. 다른 위치에 저장한 보관함은 이 폴더에 없으므로 별도로 삭제해야 합니다.';

  @override
  String get yubiKeySecurityWarning => '보안 경고';

  @override
  String get removeYubiKeyTitle => 'YubiKey 제거';

  @override
  String get yubiKeyLastKeyRiskWarning =>
      '경고: 남은 키가 분실, 손상 또는 도난된 경우 볼트에 대한 접근이 영구적으로 차단됩니다. 복구 옵션이 없습니다.';

  @override
  String get onlyOneKeyRegisteredWarning =>
      '키가 하나만 등록되어 있습니다. 이 키를 분실하면 볼트에 대한 접근이 영구적으로 차단됩니다.';

  @override
  String get tapRegisterNfc => '등록을 위해 스마트폰에 키를 가져다 대세요';

  @override
  String get tapRegisterUsb => '연결 후 등록을 위해 키에 터치하세요';

  @override
  String get tapActivateNfc => '활성화를 위해 스마트폰에 키를 다시 가져다 대세요';

  @override
  String get tapActivateUsb => '연결 후 활성화를 위해 키에 다시 터치하세요';

  @override
  String failedToRegisterKey(String error) {
    return '키 등록에 실패했습니다: $error';
  }

  @override
  String failedToActivateKey(String error) {
    return '키 활성화에 실패했습니다: $error';
  }

  @override
  String keyDefaultTitle(int index) {
    return '키 $index';
  }

  @override
  String get tapYubiKeyToRegister => '등록을 위해 새 YubiKey에 터치하세요…';

  @override
  String get tapYubiKeyToActivate => '활성화를 위해 새 YubiKey에 다시 터치하세요…';

  @override
  String get editAliasTooltip => '별칭 편집';

  @override
  String get cannotRemoveLastKey => '마지막 키는 제거할 수 없습니다';

  @override
  String get removeKeyTooltip => '키 제거';

  @override
  String manageYubiKeysError(String error) {
    return '오류: $error';
  }

  @override
  String get generatorModeClassic => '클래식';

  @override
  String get generatorModePassphrase => '암호 문구';

  @override
  String get charSetsHeader => '문자 세트';

  @override
  String get languageHeader => '언어';

  @override
  String get separatorLabel => '구분자';

  @override
  String get capitaliseWords => '단어 대문자화';

  @override
  String get appendDigit => '숫자 추가';

  @override
  String entropyBitsDisplay(String bits) {
    return '~$bits비트 엔트로피';
  }

  @override
  String get selectAtLeastOneCharSet => '문자 세트를 하나 이상 선택하세요';

  @override
  String get passwordMinLengthNote =>
      '비밀번호는 최소 12자입니다. 웹사이트에 더 짧은 제한이 있는 경우 필요한 수의 첫 번째 문자를 복사하세요.';

  @override
  String get excludeAmbiguousChars => '모호한 문자 제외 (0, O, l, 1, I)';

  @override
  String get onboardingGetStarted => '볼트를 만들어 시작하세요.';

  @override
  String get onboardingVaultName => '볼트 이름';

  @override
  String get onboardingAliasRequired => '별칭은 필수입니다';

  @override
  String get onboardingNewVaultLocation => '새 볼트 위치 (이전과 동일)';

  @override
  String get onboardingVaultLocation => '볼트 위치';

  @override
  String get onboardingLoadingPath => '로드 중…';

  @override
  String get onboardingPathHint => '볼트 파일 경로';

  @override
  String get onboardingPathRequired => '경로는 필수입니다';

  @override
  String get onboardingReusePassphraseHint =>
      '새 마스터 암호 문구를 선택하거나 이전 것을 재사용하세요.';

  @override
  String get onboardingPassphraseRequired => '암호 문구는 필수입니다';

  @override
  String get onboardingConfirmRequired => '암호 문구를 확인하세요';

  @override
  String get onboardingPrimaryKeyPin => '기본 키 PIN';

  @override
  String get onboardingBackupKeyPin => '백업 키 PIN';

  @override
  String onboardingKeyNPin(int n) {
    return '키 $n PIN';
  }

  @override
  String get onboardingYubikeyTapInstruction =>
      '각 YubiKey에 2번씩 터치합니다 (총 4번). 두 키 사이에 교체하도록 안내됩니다.';

  @override
  String get onboardingYubikeySlowNote =>
      'YubiKey를 사용한 볼트 생성에는 20~30초가 걸립니다. 앱이 반응하지 않는 것처럼 보일 수 있지만 정상입니다.';

  @override
  String get onboardingStep1Label => '기본 키 등록';

  @override
  String get onboardingStep1Hint => '지금 YubiKey에 터치하세요';

  @override
  String get onboardingStep2Label => '기본 키 활성화';

  @override
  String get onboardingStep2Hint => 'YubiKey에 다시 터치하세요';

  @override
  String get onboardingStep3Label => '백업 키로 전환';

  @override
  String get onboardingStep3Hint => '기본 키를 제거하고 백업 YubiKey를 삽입하세요';

  @override
  String get onboardingStep4Label => '백업 키 등록';

  @override
  String get onboardingStep4Hint => '백업 YubiKey에 터치하세요';

  @override
  String get onboardingStep5Label => '백업 키 활성화';

  @override
  String get onboardingStep5Hint => '마지막으로 백업 YubiKey에 터치하세요';

  @override
  String get textSizePreview => '가브로는 Mg와 Fe가 풍부한 조립질 구조를 가진 심성암입니다.';

  @override
  String get fieldCardStatus => '상태';

  @override
  String get fieldPaymentNetwork => '결제 네트워크';

  @override
  String get cardStatusActive => '활성';

  @override
  String get cardStatusLapsed => '만료';

  @override
  String get cardStatusInactive => '비활성';

  @override
  String get validatorTitleRequired => '제목은 필수입니다';

  @override
  String get validatorUsernameRequired => '사용자 이름은 필수입니다';

  @override
  String get validatorPasswordRequired => '비밀번호는 필수입니다';

  @override
  String get validatorContentRequired => '내용은 필수입니다';

  @override
  String get validatorFirstNameRequired => '이름은 필수입니다';

  @override
  String get validatorLastNameRequired => '성은 필수입니다';

  @override
  String get validatorCardLabelRequired => '카드 이름은 필수입니다';

  @override
  String get validatorCardholderRequired => '카드 소지자 이름은 필수입니다';

  @override
  String get validatorCardNumberRequired => '카드 번호는 필수입니다';

  @override
  String get validatorCardNumberLength => '카드 번호는 6~19자리여야 합니다';

  @override
  String get validatorExpiryRequired => '유효기간은 필수입니다';

  @override
  String get validatorExpiryFormat => 'MM/YY 형식을 사용하세요';

  @override
  String get validatorExpiryMonth => '월은 01~12여야 합니다';

  @override
  String get validatorCvvLength => 'CVV는 3자리 또는 4자리여야 합니다';

  @override
  String get validatorLabelRequired => '레이블은 필수입니다';

  @override
  String get validatorStatusRequired => '상태는 필수입니다';

  @override
  String get sectionBiometricUnlock => '생체 인증 잠금 해제';

  @override
  String get biometricUnlockDescription =>
      '암호 문구 입력 대신 지문이나 얼굴을 사용하여 볼트 잠금을 해제합니다.';

  @override
  String get biometricUnlockTitle => '생체 인증 잠금 해제 활성화';

  @override
  String get biometricUnlockNote =>
      '이 기기에 등록된 모든 생체 인증 데이터가 사용 가능합니다 — 등록 시 사용한 것만이 아닙니다.';

  @override
  String get biometricUnavailable =>
      '이 기기에서는 생체 인증 잠금 해제를 사용할 수 없습니다. 생체 인증 센서를 찾을 수 없거나 시스템 설정에 생체 인증 데이터가 등록되지 않았습니다.';

  @override
  String get biometricDialogTitle => '생체 인증 잠금 해제 정보';

  @override
  String get biometricDialogBody =>
      '활성화하면 Gabbro는 마스터 암호 문구를 암호화하여 생체 인증 데이터로 보호된 이 기기에 저장합니다. 문구는 잠금 해제 시에만 복호화됩니다.\n\nGabbro는 지문이나 얼굴 데이터를 저장하지 않습니다 — 스마트폰의 보안 칩에 남아 있습니다.';

  @override
  String get biometricDialogAllBiometrics =>
      '이 기기에 등록된 모든 생체 인증 데이터가 Gabbro의 잠금을 해제할 수 있습니다 — 특정 지문으로 제한할 수 없습니다.';

  @override
  String get biometricDialogInvalidation =>
      '이 스마트폰에 새 생체 인증 데이터(두 번째 지문 포함)가 추가되면 이 설정이 자동으로 비활성화되고 재설정이 필요합니다.';

  @override
  String get biometricDialogRecommendation =>
      '권장: 높은 위협 모델이 있거나 기기를 공유하는 경우 비활성화 상태로 두세요.';

  @override
  String get biometricInvalidated =>
      '이 기기의 생체 인증 데이터가 변경되어 (시스템 설정에서 새 지문 또는 얼굴이 추가됨) 생체 인증 잠금 해제가 비활성화됐습니다. 이는 보안 조치입니다. 암호 문구를 다시 입력하고 생체 인증 잠금 해제를 다시 활성화하세요.';

  @override
  String get useBiometrics => '생체 인증 사용';

  @override
  String get biometricCancelled => '생체 인증이 완료되지 않았습니다. 잠금을 해제하려면 암호 문구를 입력하세요.';

  @override
  String get biometricEnrollTitle => '암호 문구 입력';

  @override
  String get biometricEnrollDescription =>
      '생체 인증 잠금 해제를 활성화하기 위해 마스터 암호 문구를 입력하세요.';

  @override
  String get biometricYubikeyHint =>
      '아래에 YubiKey PIN을 입력하고 «생체 인증 사용»을 클릭한 후 YubiKey에 터치하세요.';

  @override
  String get helpTitle => '도움말';

  @override
  String get menuHelp => '도움말';

  @override
  String get helpCaptionCreate => '볼트 만들기: 이름, 암호 문구를 입력하고 선택적으로 YubiKey로 보호';

  @override
  String get helpCaptionEmpty => '+를 클릭하여 첫 번째 항목 추가';

  @override
  String get helpCaptionDetail => '눈 아이콘을 클릭하여 비밀번호를 표시하고 길게 눌러 자세한 문자 분석 표시';

  @override
  String get helpCaptionTitleSearch => '기본값: 검색창은 항목 제목만 검색합니다';

  @override
  String get helpCaptionFullSearch =>
      '돋보기를 클릭하여 모든 필드 검색으로 전환; 다시 클릭하여 제목 검색으로 돌아가기';

  @override
  String get helpCaptionFilter => '필터 버튼을 사용하여 특정 유형의 항목만 표시';

  @override
  String get helpCaptionFolders => '폴더 선택을 사용하여 폴더별로 항목 필터링';

  @override
  String get helpCaptionSelect =>
      '항목을 길게 눌러 선택 모드로 진입; 더 많은 항목 추가 후 폴더에 할당하거나 삭제. X를 클릭하여 종료.';

  @override
  String get helpCaptionJumpToLetter => '인덱스 바의 문자를 클릭하여 해당 섹션으로 이동';

  @override
  String get helpCaptionBreakdown =>
      '눈 아이콘을 클릭하여 비밀번호를 표시하고 길게 눌러 자세한 문자 분석 표시';

  @override
  String get helpCaptionManageVaults =>
      '«볼트 관리»에서 볼트 이름을 변경하거나 삭제하거나 새 볼트를 추가할 수 있습니다';

  @override
  String get helpCaptionUnlock => '암호 문구를 입력하여 볼트 잠금 해제';

  @override
  String get helpCaptionVaultSync => '암호화된 볼트 동기화 프로세스';

  @override
  String get passphraseNoWordlist => '해당 언어의 단어 목록이 아직 없습니다. 영어를 사용합니다.';

  @override
  String get manageFoldersDefaultNote => '기본 폴더는 이름을 바꾸거나 삭제할 수 있습니다.';

  @override
  String get vaultCorruptBackupAvailable =>
      '이 보관함 파일을 읽을 수 없습니다. 마지막으로 성공한 저장의 자동 안전 사본을 사용할 수 있습니다.';

  @override
  String get restoreBackupButton => '안전 사본에서 복원';

  @override
  String get restoreBackupConfirmTitle => '안전 사본에서 보관함을 복원할까요?';

  @override
  String get restoreBackupConfirmBody =>
      '읽을 수 없는 보관함 파일은 마지막으로 성공한 저장의 안전 사본으로 교체됩니다. 잠금 해제에는 여전히 패스프레이즈(및 등록된 경우 YubiKey)가 필요합니다.';

  @override
  String get restoreBackupConfirmAction => '복원';

  @override
  String get backupRestoredMessage => '안전 사본이 복원되었습니다. 자격 증명으로 잠금을 해제하세요.';

  @override
  String get backupDialogSafetyCopyNote =>
      'Gabbro는 또한 각 보관함의 자동 안전 사본 하나를 기기에 보관하며 저장할 때마다 갱신합니다. 이는 파일 손상만을 대비한 것으로 백업이 아닙니다.';

  @override
  String get vaultUnrecoverableBody =>
      '이 보관함 파일을 읽을 수 없으며, 안전 사본도 읽을 수 없습니다. 이 기기에서는 내용을 복구할 수 없습니다.';

  @override
  String get vaultUnrecoverableBackupHint =>
      '기기 외부에 백업이 있다면 해당 사본에서 보관함을 복원하세요.';

  @override
  String get vaultUnrecoverableNoteLinux =>
      '읽을 수 없는 파일은 디스크에 남아 있으므로 직접 삭제하거나 검사할 수 있습니다.';

  @override
  String get vaultUnrecoverableNoteAndroid =>
      '읽을 수 없는 파일은 앱의 비공개 저장소에 있으며 여기에서만 제거할 수 있습니다.';

  @override
  String get removeVaultFromListButton => '목록에서 제거';

  @override
  String get deleteVaultFileButton => '파일 삭제';

  @override
  String get removeVaultFromListConfirmTitle => '보관함을 목록에서 제거하시겠습니까?';

  @override
  String get removeVaultFromListConfirmBody =>
      '이 보관함을 목록에서 제거하시겠습니까? 파일은 디스크에 남아 있습니다. 복구하면 다시 추가할 수 있습니다.';

  @override
  String get deleteVaultFileConfirmTitle => '손상된 보관함 파일을 영구적으로 삭제하시겠습니까?';

  @override
  String get deleteVaultFileConfirmBody =>
      '이 보관함을 영구적으로 삭제하시겠습니까? 읽을 수 없는 파일과 안전 사본이 이 기기에서 제거됩니다. 이 작업은 되돌릴 수 없습니다.';

  @override
  String get restoreFromFileButton => '백업 파일에서 복원';

  @override
  String get vaultRestoredMessage => '보관함이 복원되었습니다. 자격 증명으로 잠금을 해제하세요.';

  @override
  String get restoreFromFileInvalidError => '이 파일은 사용할 수 있는 Gabbro 보관함이 아닙니다.';
}
