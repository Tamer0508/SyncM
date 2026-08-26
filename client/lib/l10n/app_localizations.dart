import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ru.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of L
/// returned by `L.of(context)`.
///
/// Applications need to include `L.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: L.localizationsDelegates,
///   supportedLocales: L.supportedLocales,
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
/// be consistent with the languages listed in the L.supportedLocales
/// property.
abstract class L {
  L(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static L of(BuildContext context) {
    return Localizations.of<L>(context, L)!;
  }

  static const LocalizationsDelegate<L> delegate = _LDelegate();

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
    Locale('en'),
    Locale('ru'),
  ];

  /// No description provided for @aboutDataPrivacy.
  ///
  /// In ru, this message translates to:
  /// **'Данные и приватность'**
  String get aboutDataPrivacy;

  /// No description provided for @aboutDataPrivacyHint.
  ///
  /// In ru, this message translates to:
  /// **'Что приложение хранит и как это удалить'**
  String get aboutDataPrivacyHint;

  /// No description provided for @aboutLegalGroup.
  ///
  /// In ru, this message translates to:
  /// **'Данные и правила'**
  String get aboutLegalGroup;

  /// No description provided for @aboutPrivacyPolicy.
  ///
  /// In ru, this message translates to:
  /// **'Политика конфиденциальности'**
  String get aboutPrivacyPolicy;

  /// No description provided for @aboutTerms.
  ///
  /// In ru, this message translates to:
  /// **'Условия использования'**
  String get aboutTerms;

  /// No description provided for @aboutTermsHint.
  ///
  /// In ru, this message translates to:
  /// **'Правила пользования приложением'**
  String get aboutTermsHint;

  /// No description provided for @aboutVersion.
  ///
  /// In ru, this message translates to:
  /// **'Версия {version}'**
  String aboutVersion(String version);

  /// No description provided for @accentAmber.
  ///
  /// In ru, this message translates to:
  /// **'Янтарь'**
  String get accentAmber;

  /// No description provided for @accentClay.
  ///
  /// In ru, this message translates to:
  /// **'Глина'**
  String get accentClay;

  /// No description provided for @accentIndigo.
  ///
  /// In ru, this message translates to:
  /// **'Индиго'**
  String get accentIndigo;

  /// No description provided for @accentOlive.
  ///
  /// In ru, this message translates to:
  /// **'Оливковый'**
  String get accentOlive;

  /// No description provided for @accentPlum.
  ///
  /// In ru, this message translates to:
  /// **'Слива'**
  String get accentPlum;

  /// No description provided for @accountConnectedServices.
  ///
  /// In ru, this message translates to:
  /// **'Подключённые сервисы'**
  String get accountConnectedServices;

  /// No description provided for @accountEmail.
  ///
  /// In ru, this message translates to:
  /// **'Почта'**
  String get accountEmail;

  /// No description provided for @accountNameUnset.
  ///
  /// In ru, this message translates to:
  /// **'Не задано'**
  String get accountNameUnset;

  /// No description provided for @accountProfile.
  ///
  /// In ru, this message translates to:
  /// **'Профиль'**
  String get accountProfile;

  /// No description provided for @accountPublicId.
  ///
  /// In ru, this message translates to:
  /// **'Ваш код'**
  String get accountPublicId;

  /// No description provided for @accountPublicIdCopied.
  ///
  /// In ru, this message translates to:
  /// **'Код скопирован'**
  String get accountPublicIdCopied;

  /// No description provided for @addedToPlaylist.
  ///
  /// In ru, this message translates to:
  /// **'Добавлено в «{name}»'**
  String addedToPlaylist(String name);

  /// No description provided for @addToPlaylistCreate.
  ///
  /// In ru, this message translates to:
  /// **'Создать новый'**
  String get addToPlaylistCreate;

  /// No description provided for @addToPlaylistEmpty.
  ///
  /// In ru, this message translates to:
  /// **'Своих плейлистов пока нет. Создайте первый — трек попадёт в него сразу.'**
  String get addToPlaylistEmpty;

  /// No description provided for @addToPlaylistTitle.
  ///
  /// In ru, this message translates to:
  /// **'Добавить в плейлист'**
  String get addToPlaylistTitle;

  /// No description provided for @addTracksAddCount.
  ///
  /// In ru, this message translates to:
  /// **'Добавить ({count})'**
  String addTracksAddCount(int count);

  /// No description provided for @addTracksAdded.
  ///
  /// In ru, this message translates to:
  /// **'Добавлено {count, plural, one{{count} трек} few{{count} трека} many{{count} треков} other{{count} трека}}'**
  String addTracksAdded(int count);

  /// No description provided for @addTracksAddedWithSkipped.
  ///
  /// In ru, this message translates to:
  /// **'{base}, {skipped} уже было'**
  String addTracksAddedWithSkipped(String base, int skipped);

  /// No description provided for @addTracksAllPresent.
  ///
  /// In ru, this message translates to:
  /// **'Все выбранные треки уже в плейлисте'**
  String get addTracksAllPresent;

  /// No description provided for @addTracksAlreadyIn.
  ///
  /// In ru, this message translates to:
  /// **'Уже в плейлисте'**
  String get addTracksAlreadyIn;

  /// No description provided for @addTracksBackToPlaylists.
  ///
  /// In ru, this message translates to:
  /// **'К списку плейлистов'**
  String get addTracksBackToPlaylists;

  /// No description provided for @addTracksDeselect.
  ///
  /// In ru, this message translates to:
  /// **'Снять'**
  String get addTracksDeselect;

  /// No description provided for @addTracksEmptyPlaylist.
  ///
  /// In ru, this message translates to:
  /// **'В этом плейлисте нет треков.'**
  String get addTracksEmptyPlaylist;

  /// No description provided for @addTracksForeignPlaylist.
  ///
  /// In ru, this message translates to:
  /// **'Spotify не отдаёт содержимое этого плейлиста — доступны только ваши собственные и совместные.'**
  String get addTracksForeignPlaylist;

  /// No description provided for @addTracksFromPlaylist.
  ///
  /// In ru, this message translates to:
  /// **'Из плейлиста'**
  String get addTracksFromPlaylist;

  /// No description provided for @addTracksNoOtherPlaylists.
  ///
  /// In ru, this message translates to:
  /// **'Других плейлистов пока нет — брать треки не из чего.'**
  String get addTracksNoOtherPlaylists;

  /// No description provided for @addTracksNothingFound.
  ///
  /// In ru, this message translates to:
  /// **'Ничего не нашлось. Попробуйте другой запрос.'**
  String get addTracksNothingFound;

  /// No description provided for @addTracksSearch.
  ///
  /// In ru, this message translates to:
  /// **'Поиск'**
  String get addTracksSearch;

  /// No description provided for @addTracksSearchEmpty.
  ///
  /// In ru, this message translates to:
  /// **'Найдите трек в Spotify и добавьте его в плейлист.'**
  String get addTracksSearchEmpty;

  /// No description provided for @addTracksSearchHint.
  ///
  /// In ru, this message translates to:
  /// **'Название трека или исполнитель'**
  String get addTracksSearchHint;

  /// No description provided for @addTracksSelectAll.
  ///
  /// In ru, this message translates to:
  /// **'Выбрать всё'**
  String get addTracksSelectAll;

  /// No description provided for @addTracksToPlaylist.
  ///
  /// In ru, this message translates to:
  /// **'Добавить в «{name}»'**
  String addTracksToPlaylist(String name);

  /// No description provided for @addTracksYourPlaylist.
  ///
  /// In ru, this message translates to:
  /// **'Ваш плейлист'**
  String get addTracksYourPlaylist;

  /// No description provided for @alreadyInPlaylist.
  ///
  /// In ru, this message translates to:
  /// **'Уже в «{name}»'**
  String alreadyInPlaylist(String name);

  /// No description provided for @appearanceAccent.
  ///
  /// In ru, this message translates to:
  /// **'Цвет акцента'**
  String get appearanceAccent;

  /// No description provided for @appearanceArtworkBackground.
  ///
  /// In ru, this message translates to:
  /// **'Фон по обложке'**
  String get appearanceArtworkBackground;

  /// No description provided for @appearanceArtworkBackgroundHint.
  ///
  /// In ru, this message translates to:
  /// **'Свечение в цвет обложки на экране плеера'**
  String get appearanceArtworkBackgroundHint;

  /// No description provided for @appearanceCompact.
  ///
  /// In ru, this message translates to:
  /// **'Компактный режим'**
  String get appearanceCompact;

  /// No description provided for @appearanceCompactHint.
  ///
  /// In ru, this message translates to:
  /// **'Плотнее списки — на экран помещается больше'**
  String get appearanceCompactHint;

  /// No description provided for @appearanceDensityGroup.
  ///
  /// In ru, this message translates to:
  /// **'Плотность и движение'**
  String get appearanceDensityGroup;

  /// No description provided for @appearanceLanguage.
  ///
  /// In ru, this message translates to:
  /// **'Язык'**
  String get appearanceLanguage;

  /// No description provided for @appearanceLanguageHint.
  ///
  /// In ru, this message translates to:
  /// **'Язык интерфейса на всех ваших устройствах'**
  String get appearanceLanguageHint;

  /// No description provided for @appearanceReduceMotion.
  ///
  /// In ru, this message translates to:
  /// **'Меньше анимации'**
  String get appearanceReduceMotion;

  /// No description provided for @appearanceReduceMotionHint.
  ///
  /// In ru, this message translates to:
  /// **'Переходы без движения — если оно мешает или укачивает'**
  String get appearanceReduceMotionHint;

  /// No description provided for @appearanceReset.
  ///
  /// In ru, this message translates to:
  /// **'Сбросить оформление'**
  String get appearanceReset;

  /// No description provided for @appearanceResetDone.
  ///
  /// In ru, this message translates to:
  /// **'Оформление сброшено'**
  String get appearanceResetDone;

  /// No description provided for @appearanceResetHint.
  ///
  /// In ru, this message translates to:
  /// **'Вернуть тему, цвет, текст, плотность и стартовую вкладку'**
  String get appearanceResetHint;

  /// No description provided for @appearanceStartTab.
  ///
  /// In ru, this message translates to:
  /// **'С чего начинать'**
  String get appearanceStartTab;

  /// No description provided for @appearanceStartTabHint.
  ///
  /// In ru, this message translates to:
  /// **'Вкладка, которая открывается при запуске'**
  String get appearanceStartTabHint;

  /// No description provided for @appearanceTextSize.
  ///
  /// In ru, this message translates to:
  /// **'Размер текста'**
  String get appearanceTextSize;

  /// No description provided for @appearanceTheme.
  ///
  /// In ru, this message translates to:
  /// **'Тема'**
  String get appearanceTheme;

  /// No description provided for @appTitle.
  ///
  /// In ru, this message translates to:
  /// **'SyncM'**
  String get appTitle;

  /// No description provided for @avatarBadFormat.
  ///
  /// In ru, this message translates to:
  /// **'Неподдерживаемый формат. Разрешены: PNG, JPG, JPEG, GIF, WEBP'**
  String get avatarBadFormat;

  /// No description provided for @avatarReadFailed.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось прочитать файл'**
  String get avatarReadFailed;

  /// No description provided for @avatarUpdated.
  ///
  /// In ru, this message translates to:
  /// **'Аватарка обновлена'**
  String get avatarUpdated;

  /// No description provided for @blockedEmptyMessage.
  ///
  /// In ru, this message translates to:
  /// **'Заблокировать можно из профиля человека или из списка друзей.'**
  String get blockedEmptyMessage;

  /// No description provided for @blockedEmptyTitle.
  ///
  /// In ru, this message translates to:
  /// **'Никто не заблокирован'**
  String get blockedEmptyTitle;

  /// No description provided for @blockedHint.
  ///
  /// In ru, this message translates to:
  /// **'Эти люди не найдут вас в поиске и не смогут отправить заявку или позвать в сессию. Они об этом не узнают.'**
  String get blockedHint;

  /// No description provided for @blockedPeopleCount.
  ///
  /// In ru, this message translates to:
  /// **'{count, plural, one{{count} человек} few{{count} человека} many{{count} человек} other{{count} человека}}'**
  String blockedPeopleCount(int count);

  /// No description provided for @blockedUnblock.
  ///
  /// In ru, this message translates to:
  /// **'Разблокировать'**
  String get blockedUnblock;

  /// No description provided for @blockedUnblocked.
  ///
  /// In ru, this message translates to:
  /// **'{name} разблокирован'**
  String blockedUnblocked(String name);

  /// No description provided for @blockedUnblockFailed.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось разблокировать'**
  String get blockedUnblockFailed;

  /// No description provided for @cacheFriendsCount.
  ///
  /// In ru, this message translates to:
  /// **'друзей: {count}'**
  String cacheFriendsCount(int count);

  /// No description provided for @cacheInMemory.
  ///
  /// In ru, this message translates to:
  /// **'В памяти: {size}'**
  String cacheInMemory(String size);

  /// No description provided for @cacheOnDisk.
  ///
  /// In ru, this message translates to:
  /// **'На диске: {disk} · в памяти: {memory}'**
  String cacheOnDisk(String disk, String memory);

  /// No description provided for @cacheSessionsCount.
  ///
  /// In ru, this message translates to:
  /// **'сессий: {count}'**
  String cacheSessionsCount(int count);

  /// No description provided for @clockSummary.
  ///
  /// In ru, this message translates to:
  /// **'Часы: {offset} мс · пинг: {ping} мс'**
  String clockSummary(String offset, int ping);

  /// No description provided for @commonBack.
  ///
  /// In ru, this message translates to:
  /// **'Назад'**
  String get commonBack;

  /// No description provided for @commonCancel.
  ///
  /// In ru, this message translates to:
  /// **'Отмена'**
  String get commonCancel;

  /// No description provided for @commonClear.
  ///
  /// In ru, this message translates to:
  /// **'Очистить'**
  String get commonClear;

  /// No description provided for @commonClose.
  ///
  /// In ru, this message translates to:
  /// **'Закрыть'**
  String get commonClose;

  /// No description provided for @commonCollapse.
  ///
  /// In ru, this message translates to:
  /// **'Свернуть'**
  String get commonCollapse;

  /// No description provided for @commonCreate.
  ///
  /// In ru, this message translates to:
  /// **'Создать'**
  String get commonCreate;

  /// No description provided for @commonDelete.
  ///
  /// In ru, this message translates to:
  /// **'Удалить'**
  String get commonDelete;

  /// No description provided for @commonEmpty.
  ///
  /// In ru, this message translates to:
  /// **'Пусто'**
  String get commonEmpty;

  /// No description provided for @commonFinish.
  ///
  /// In ru, this message translates to:
  /// **'Завершить'**
  String get commonFinish;

  /// No description provided for @commonFriends.
  ///
  /// In ru, this message translates to:
  /// **'Друзья'**
  String get commonFriends;

  /// No description provided for @commonJustNow.
  ///
  /// In ru, this message translates to:
  /// **'только что'**
  String get commonJustNow;

  /// No description provided for @commonLoadMore.
  ///
  /// In ru, this message translates to:
  /// **'Загрузить ещё'**
  String get commonLoadMore;

  /// No description provided for @commonLongAgo.
  ///
  /// In ru, this message translates to:
  /// **'давно'**
  String get commonLongAgo;

  /// No description provided for @commonMore.
  ///
  /// In ru, this message translates to:
  /// **'Ещё'**
  String get commonMore;

  /// No description provided for @commonMoreCount.
  ///
  /// In ru, this message translates to:
  /// **'Ещё {count}'**
  String commonMoreCount(int count);

  /// No description provided for @commonName.
  ///
  /// In ru, this message translates to:
  /// **'Имя'**
  String get commonName;

  /// No description provided for @commonNobody.
  ///
  /// In ru, this message translates to:
  /// **'Никто'**
  String get commonNobody;

  /// No description provided for @commonNoName.
  ///
  /// In ru, this message translates to:
  /// **'Без имени'**
  String get commonNoName;

  /// No description provided for @commonOpen.
  ///
  /// In ru, this message translates to:
  /// **'Открыть'**
  String get commonOpen;

  /// No description provided for @commonOr.
  ///
  /// In ru, this message translates to:
  /// **' или '**
  String get commonOr;

  /// No description provided for @commonRefresh.
  ///
  /// In ru, this message translates to:
  /// **'Обновить'**
  String get commonRefresh;

  /// No description provided for @commonReset.
  ///
  /// In ru, this message translates to:
  /// **'Сбросить'**
  String get commonReset;

  /// No description provided for @commonSave.
  ///
  /// In ru, this message translates to:
  /// **'Сохранить'**
  String get commonSave;

  /// No description provided for @commonSignOut.
  ///
  /// In ru, this message translates to:
  /// **'Выйти'**
  String get commonSignOut;

  /// No description provided for @commonSystem.
  ///
  /// In ru, this message translates to:
  /// **'Система'**
  String get commonSystem;

  /// No description provided for @commonUser.
  ///
  /// In ru, this message translates to:
  /// **'Пользователь'**
  String get commonUser;

  /// No description provided for @createSessionFailed.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось создать сессию'**
  String get createSessionFailed;

  /// No description provided for @createSessionFriendsOnly.
  ///
  /// In ru, this message translates to:
  /// **'Сессию можно создать только с другом'**
  String get createSessionFriendsOnly;

  /// No description provided for @createSessionFriendsOnlyHint.
  ///
  /// In ru, this message translates to:
  /// **'Добавьте кого-нибудь в друзья, и он появится в этом списке.'**
  String get createSessionFriendsOnlyHint;

  /// No description provided for @createSessionHint.
  ///
  /// In ru, this message translates to:
  /// **'Пригласите друга и слушайте музыку одновременно.'**
  String get createSessionHint;

  /// No description provided for @createSessionName.
  ///
  /// In ru, this message translates to:
  /// **'Название сессии'**
  String get createSessionName;

  /// No description provided for @createSessionNobodyFound.
  ///
  /// In ru, this message translates to:
  /// **'Никого с таким именем'**
  String get createSessionNobodyFound;

  /// No description provided for @createSessionPickFriend.
  ///
  /// In ru, this message translates to:
  /// **'Выберите друга, чтобы продолжить'**
  String get createSessionPickFriend;

  /// No description provided for @createSessionSearchFriends.
  ///
  /// In ru, this message translates to:
  /// **'Поиск среди друзей'**
  String get createSessionSearchFriends;

  /// No description provided for @createSessionWithWhom.
  ///
  /// In ru, this message translates to:
  /// **'С кем слушаем'**
  String get createSessionWithWhom;

  /// No description provided for @cropDone.
  ///
  /// In ru, this message translates to:
  /// **'Готово'**
  String get cropDone;

  /// No description provided for @cropFailed.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось обработать изображение'**
  String get cropFailed;

  /// No description provided for @cropHint.
  ///
  /// In ru, this message translates to:
  /// **'Область всегда квадратная — так аватар выглядит одинаково везде.'**
  String get cropHint;

  /// No description provided for @cropNoImageData.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось получить данные изображения'**
  String get cropNoImageData;

  /// No description provided for @cropRotateLeft.
  ///
  /// In ru, this message translates to:
  /// **'Влево'**
  String get cropRotateLeft;

  /// No description provided for @cropRotateRight.
  ///
  /// In ru, this message translates to:
  /// **'Вправо'**
  String get cropRotateRight;

  /// No description provided for @cropTitle.
  ///
  /// In ru, this message translates to:
  /// **'Кадрирование'**
  String get cropTitle;

  /// No description provided for @dataExport.
  ///
  /// In ru, this message translates to:
  /// **'Выгрузить мои данные'**
  String get dataExport;

  /// No description provided for @dataExportHint.
  ///
  /// In ru, this message translates to:
  /// **'Профиль, друзья, плейлисты и история одним файлом'**
  String get dataExportHint;

  /// No description provided for @dataHistoryHint.
  ///
  /// In ru, this message translates to:
  /// **'Посмотреть и очистить'**
  String get dataHistoryHint;

  /// No description provided for @dataImageCache.
  ///
  /// In ru, this message translates to:
  /// **'Кэш изображений'**
  String get dataImageCache;

  /// No description provided for @dataImageCacheCleared.
  ///
  /// In ru, this message translates to:
  /// **'Кэш изображений очищен'**
  String get dataImageCacheCleared;

  /// No description provided for @dataNothingSaved.
  ///
  /// In ru, this message translates to:
  /// **'Пока ничего не сохранено'**
  String get dataNothingSaved;

  /// No description provided for @dataOnServer.
  ///
  /// In ru, this message translates to:
  /// **'На сервере'**
  String get dataOnServer;

  /// No description provided for @dataOnThisDevice.
  ///
  /// In ru, this message translates to:
  /// **'На этом устройстве'**
  String get dataOnThisDevice;

  /// No description provided for @dataPrefetch.
  ///
  /// In ru, this message translates to:
  /// **'Загружать данные при запуске'**
  String get dataPrefetch;

  /// No description provided for @dataPrefetchHint.
  ///
  /// In ru, this message translates to:
  /// **'Списки друзей и сессий готовы к моменту открытия вкладки'**
  String get dataPrefetchHint;

  /// No description provided for @dataSavedLists.
  ///
  /// In ru, this message translates to:
  /// **'Сохранённые списки'**
  String get dataSavedLists;

  /// No description provided for @dataSavedListsCleared.
  ///
  /// In ru, this message translates to:
  /// **'Списки очищены'**
  String get dataSavedListsCleared;

  /// No description provided for @dataUpdatedJustNow.
  ///
  /// In ru, this message translates to:
  /// **'обновлено только что'**
  String get dataUpdatedJustNow;

  /// No description provided for @dataWhatIsStored.
  ///
  /// In ru, this message translates to:
  /// **'Что хранится о вас'**
  String get dataWhatIsStored;

  /// No description provided for @dataWhatIsStoredHint.
  ///
  /// In ru, this message translates to:
  /// **'Список данных и как их удалить'**
  String get dataWhatIsStoredHint;

  /// No description provided for @daysAgoShort.
  ///
  /// In ru, this message translates to:
  /// **'{count} дн. назад'**
  String daysAgoShort(int count);

  /// No description provided for @deleteAccountMessage.
  ///
  /// In ru, this message translates to:
  /// **'Профиль, друзья и история сессий будут удалены безвозвратно. Это действие нельзя отменить.'**
  String get deleteAccountMessage;

  /// No description provided for @devicesApp.
  ///
  /// In ru, this message translates to:
  /// **'Приложение SyncM'**
  String get devicesApp;

  /// No description provided for @devicesBrowser.
  ///
  /// In ru, this message translates to:
  /// **'Браузер'**
  String get devicesBrowser;

  /// No description provided for @devicesCurrent.
  ///
  /// In ru, this message translates to:
  /// **'Это устройство'**
  String get devicesCurrent;

  /// No description provided for @devicesEmptyMessage.
  ///
  /// In ru, this message translates to:
  /// **'Список пуст — похоже, связь с сервером потерялась. Попробуйте открыть экран заново.'**
  String get devicesEmptyMessage;

  /// No description provided for @devicesEmptyTitle.
  ///
  /// In ru, this message translates to:
  /// **'Активных сеансов нет'**
  String get devicesEmptyTitle;

  /// No description provided for @devicesEndAgainMessage.
  ///
  /// In ru, this message translates to:
  /// **'На «{device}» придётся входить заново.'**
  String devicesEndAgainMessage(String device);

  /// No description provided for @devicesEndSessionTitle.
  ///
  /// In ru, this message translates to:
  /// **'Завершить сеанс?'**
  String get devicesEndSessionTitle;

  /// No description provided for @devicesHint.
  ///
  /// In ru, this message translates to:
  /// **'Здесь показаны приложения и браузеры, где выполнен вход. Если видите незнакомое устройство — завершите его сеанс.'**
  String get devicesHint;

  /// No description provided for @devicesSessionEnded.
  ///
  /// In ru, this message translates to:
  /// **'Сеанс завершён'**
  String get devicesSessionEnded;

  /// No description provided for @devicesSignOutThisDeviceTitle.
  ///
  /// In ru, this message translates to:
  /// **'Выйти на этом устройстве?'**
  String get devicesSignOutThisDeviceTitle;

  /// No description provided for @devicesTimeUnknown.
  ///
  /// In ru, this message translates to:
  /// **'Время неизвестно'**
  String get devicesTimeUnknown;

  /// No description provided for @devicesTitle.
  ///
  /// In ru, this message translates to:
  /// **'Устройства'**
  String get devicesTitle;

  /// No description provided for @devicesYesterday.
  ///
  /// In ru, this message translates to:
  /// **'Вчера'**
  String get devicesYesterday;

  /// No description provided for @durationHours.
  ///
  /// In ru, this message translates to:
  /// **'{count} ч'**
  String durationHours(int count);

  /// No description provided for @durationMinutes.
  ///
  /// In ru, this message translates to:
  /// **'{count} мин'**
  String durationMinutes(int count);

  /// No description provided for @errorBadResponse.
  ///
  /// In ru, this message translates to:
  /// **'Сервер вернул неожиданный ответ. Попробуйте обновить.'**
  String get errorBadResponse;

  /// No description provided for @errorConflict.
  ///
  /// In ru, this message translates to:
  /// **'Действие уже выполняется или невозможно сейчас.'**
  String get errorConflict;

  /// No description provided for @errorConnectionDropped.
  ///
  /// In ru, this message translates to:
  /// **'Соединение прервалось. Попробуйте ещё раз.'**
  String get errorConnectionDropped;

  /// No description provided for @errorForbidden.
  ///
  /// In ru, this message translates to:
  /// **'Недостаточно прав для этого действия.'**
  String get errorForbidden;

  /// No description provided for @errorGeneric.
  ///
  /// In ru, this message translates to:
  /// **'Что-то пошло не так.'**
  String get errorGeneric;

  /// No description provided for @errorGenericRetry.
  ///
  /// In ru, this message translates to:
  /// **'Что-то пошло не так. Попробуйте снова.'**
  String get errorGenericRetry;

  /// No description provided for @errorGoogleFailed.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось войти через Google. Попробуйте ещё раз.'**
  String get errorGoogleFailed;

  /// No description provided for @errorGoogleMisconfigured.
  ///
  /// In ru, this message translates to:
  /// **'Вход через Google настроен неверно. Сообщите разработчику.'**
  String get errorGoogleMisconfigured;

  /// No description provided for @errorGoogleUnreachable.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось связаться с Google. Проверьте соединение.'**
  String get errorGoogleUnreachable;

  /// No description provided for @errorHandshake.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось установить защищённое соединение.'**
  String get errorHandshake;

  /// No description provided for @errorNetwork.
  ///
  /// In ru, this message translates to:
  /// **'Ошибка сети. Проверьте соединение.'**
  String get errorNetwork;

  /// No description provided for @errorNoInternet.
  ///
  /// In ru, this message translates to:
  /// **'Нет подключения к интернету. Проверьте сеть.'**
  String get errorNoInternet;

  /// No description provided for @errorNotFound.
  ///
  /// In ru, this message translates to:
  /// **'Не найдено.'**
  String get errorNotFound;

  /// No description provided for @errorServerFailure.
  ///
  /// In ru, this message translates to:
  /// **'Ошибка на сервере. Мы уже знаем о проблеме.'**
  String get errorServerFailure;

  /// No description provided for @errorServerSlow.
  ///
  /// In ru, this message translates to:
  /// **'Сервер долго не отвечает. Попробуйте позже.'**
  String get errorServerSlow;

  /// No description provided for @errorServerUnavailable.
  ///
  /// In ru, this message translates to:
  /// **'Сервер временно недоступен. Попробуйте через минуту.'**
  String get errorServerUnavailable;

  /// No description provided for @errorServerUnreachable.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось связаться с сервером. Проверьте соединение.'**
  String get errorServerUnreachable;

  /// No description provided for @errorSessionExpired.
  ///
  /// In ru, this message translates to:
  /// **'Сессия истекла. Войдите заново.'**
  String get errorSessionExpired;

  /// No description provided for @errorSignInCancelled.
  ///
  /// In ru, this message translates to:
  /// **'Вход отменён'**
  String get errorSignInCancelled;

  /// No description provided for @errorTooManyRequests.
  ///
  /// In ru, this message translates to:
  /// **'Слишком много запросов. Немного подождите.'**
  String get errorTooManyRequests;

  /// No description provided for @exportSaved.
  ///
  /// In ru, this message translates to:
  /// **'Файл сохранён: {path}'**
  String exportSaved(String path);

  /// No description provided for @foregroundChannelDescription.
  ///
  /// In ru, this message translates to:
  /// **'Показывается, пока идёт совместное прослушивание, чтобы синхронизация не прерывалась.'**
  String get foregroundChannelDescription;

  /// No description provided for @foregroundChannelName.
  ///
  /// In ru, this message translates to:
  /// **'Активная сессия SyncM'**
  String get foregroundChannelName;

  /// No description provided for @foregroundText.
  ///
  /// In ru, this message translates to:
  /// **'Слушаете вместе с друзьями'**
  String get foregroundText;

  /// No description provided for @foregroundTitle.
  ///
  /// In ru, this message translates to:
  /// **'Сессия SyncM активна'**
  String get foregroundTitle;

  /// No description provided for @friendActions.
  ///
  /// In ru, this message translates to:
  /// **'Действия'**
  String get friendActions;

  /// No description provided for @friendBlock.
  ///
  /// In ru, this message translates to:
  /// **'Заблокировать'**
  String get friendBlock;

  /// No description provided for @friendLastSeen.
  ///
  /// In ru, this message translates to:
  /// **'Был(а) в сети {when}'**
  String friendLastSeen(String when);

  /// No description provided for @friendOffline.
  ///
  /// In ru, this message translates to:
  /// **'Не в сети'**
  String get friendOffline;

  /// No description provided for @friendOnline.
  ///
  /// In ru, this message translates to:
  /// **'В сети'**
  String get friendOnline;

  /// No description provided for @friendOpenProfile.
  ///
  /// In ru, this message translates to:
  /// **'Открыть профиль'**
  String get friendOpenProfile;

  /// No description provided for @friendRemove.
  ///
  /// In ru, this message translates to:
  /// **'Удалить из друзей'**
  String get friendRemove;

  /// No description provided for @friendsBlocked.
  ///
  /// In ru, this message translates to:
  /// **'{name} заблокирован'**
  String friendsBlocked(String name);

  /// No description provided for @friendsBlockFailed.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось заблокировать'**
  String get friendsBlockFailed;

  /// No description provided for @friendsBlockMessage.
  ///
  /// In ru, this message translates to:
  /// **'Он не найдёт вас в поиске, не сможет отправить заявку или позвать в сессию. Дружба будет удалена. Уведомления он не получит.'**
  String get friendsBlockMessage;

  /// No description provided for @friendsBlockTitle.
  ///
  /// In ru, this message translates to:
  /// **'Заблокировать {name}?'**
  String friendsBlockTitle(String name);

  /// No description provided for @friendsEmptyMessage.
  ///
  /// In ru, this message translates to:
  /// **'С другом можно слушать музыку одновременно — где бы вы ни были.'**
  String get friendsEmptyMessage;

  /// No description provided for @friendsEmptyTitle.
  ///
  /// In ru, this message translates to:
  /// **'Добавьте друзей'**
  String get friendsEmptyTitle;

  /// No description provided for @friendsRemoved.
  ///
  /// In ru, this message translates to:
  /// **'{name} удалён из друзей'**
  String friendsRemoved(String name);

  /// No description provided for @friendsRemoveFailed.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось удалить друга'**
  String get friendsRemoveFailed;

  /// No description provided for @friendsRemoveMessage.
  ///
  /// In ru, this message translates to:
  /// **'{name} пропадёт из вашего списка друзей.'**
  String friendsRemoveMessage(String name);

  /// No description provided for @friendsRemoveTitle.
  ///
  /// In ru, this message translates to:
  /// **'Удалить из друзей?'**
  String get friendsRemoveTitle;

  /// No description provided for @hiddenList.
  ///
  /// In ru, this message translates to:
  /// **'Скрыто: {items}'**
  String hiddenList(String items);

  /// No description provided for @historyClear.
  ///
  /// In ru, this message translates to:
  /// **'Очистить'**
  String get historyClear;

  /// No description provided for @historyCleared.
  ///
  /// In ru, this message translates to:
  /// **'История очищена'**
  String get historyCleared;

  /// No description provided for @historyClearFailed.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось очистить историю'**
  String get historyClearFailed;

  /// No description provided for @historyClearMessage.
  ///
  /// In ru, this message translates to:
  /// **'Записи о прослушанных треках будут удалены.'**
  String get historyClearMessage;

  /// No description provided for @historyClearTitle.
  ///
  /// In ru, this message translates to:
  /// **'Очистить историю?'**
  String get historyClearTitle;

  /// No description provided for @historyEmptyMessage.
  ///
  /// In ru, this message translates to:
  /// **'Здесь появятся треки, которые вы включали в SyncM.'**
  String get historyEmptyMessage;

  /// No description provided for @historyEmptyTitle.
  ///
  /// In ru, this message translates to:
  /// **'История пуста'**
  String get historyEmptyTitle;

  /// No description provided for @historyJustNow.
  ///
  /// In ru, this message translates to:
  /// **'только что'**
  String get historyJustNow;

  /// No description provided for @historyTitle.
  ///
  /// In ru, this message translates to:
  /// **'История'**
  String get historyTitle;

  /// No description provided for @historyUntitled.
  ///
  /// In ru, this message translates to:
  /// **'Без названия'**
  String get historyUntitled;

  /// No description provided for @historyYesterday.
  ///
  /// In ru, this message translates to:
  /// **'вчера'**
  String get historyYesterday;

  /// No description provided for @homeAnotherSession.
  ///
  /// In ru, this message translates to:
  /// **'Ещё одна сессия'**
  String get homeAnotherSession;

  /// No description provided for @homeConnectSpotify.
  ///
  /// In ru, this message translates to:
  /// **'Подключить Spotify'**
  String get homeConnectSpotify;

  /// No description provided for @homeCreatePlaylist.
  ///
  /// In ru, this message translates to:
  /// **'Создать плейлист'**
  String get homeCreatePlaylist;

  /// No description provided for @homeDarkTheme.
  ///
  /// In ru, this message translates to:
  /// **'Тёмная тема'**
  String get homeDarkTheme;

  /// No description provided for @homeFilterAll.
  ///
  /// In ru, this message translates to:
  /// **'Все'**
  String get homeFilterAll;

  /// No description provided for @homeFilterFriend.
  ///
  /// In ru, this message translates to:
  /// **'Друг'**
  String get homeFilterFriend;

  /// No description provided for @homeFilterMine.
  ///
  /// In ru, this message translates to:
  /// **'Мои'**
  String get homeFilterMine;

  /// No description provided for @homeFriendRequests.
  ///
  /// In ru, this message translates to:
  /// **'Заявки в друзья'**
  String get homeFriendRequests;

  /// No description provided for @homeInvitedYou.
  ///
  /// In ru, this message translates to:
  /// **'Вас зовут'**
  String get homeInvitedYou;

  /// No description provided for @homeInviteFrom.
  ///
  /// In ru, this message translates to:
  /// **'От {name}'**
  String homeInviteFrom(String name);

  /// No description provided for @homeLightTheme.
  ///
  /// In ru, this message translates to:
  /// **'Светлая тема'**
  String get homeLightTheme;

  /// No description provided for @homeListenTogether.
  ///
  /// In ru, this message translates to:
  /// **'Слушайте вместе'**
  String get homeListenTogether;

  /// No description provided for @homeListenTogetherHint.
  ///
  /// In ru, this message translates to:
  /// **'Позовите друга — музыка пойдёт у вас одновременно, где бы вы ни были.'**
  String get homeListenTogetherHint;

  /// No description provided for @homeNoOwnPlaylists.
  ///
  /// In ru, this message translates to:
  /// **'Своих плейлистов пока нет'**
  String get homeNoOwnPlaylists;

  /// No description provided for @homeNoOwnPlaylistsHint.
  ///
  /// In ru, this message translates to:
  /// **'Соберите первый — и его можно будет включить в сессии.'**
  String get homeNoOwnPlaylistsHint;

  /// No description provided for @homeNoSpotifyPlaylists.
  ///
  /// In ru, this message translates to:
  /// **'Нет доступных плейлистов'**
  String get homeNoSpotifyPlaylists;

  /// No description provided for @homeNoSpotifyPlaylistsHint.
  ///
  /// In ru, this message translates to:
  /// **'В Spotify не нашлось плейлистов, которые SyncM может открыть.'**
  String get homeNoSpotifyPlaylistsHint;

  /// No description provided for @homeNothingPlaying.
  ///
  /// In ru, this message translates to:
  /// **'Ничего не играет'**
  String get homeNothingPlaying;

  /// No description provided for @homeNothingPlayingHint.
  ///
  /// In ru, this message translates to:
  /// **'Выберите трек из плейлиста — управление появится здесь.'**
  String get homeNothingPlayingHint;

  /// No description provided for @homeNowListening.
  ///
  /// In ru, this message translates to:
  /// **'Сейчас слушаете'**
  String get homeNowListening;

  /// No description provided for @homePlaylist.
  ///
  /// In ru, this message translates to:
  /// **'Плейлист'**
  String get homePlaylist;

  /// No description provided for @homeSearchFriends.
  ///
  /// In ru, this message translates to:
  /// **'Поиск друзей'**
  String get homeSearchFriends;

  /// No description provided for @homeSession.
  ///
  /// In ru, this message translates to:
  /// **'Сессия'**
  String get homeSession;

  /// No description provided for @homeSpotifyUnavailable.
  ///
  /// In ru, this message translates to:
  /// **'Плейлисты Spotify недоступны'**
  String get homeSpotifyUnavailable;

  /// No description provided for @homeSpotifyUnavailableHint.
  ///
  /// In ru, this message translates to:
  /// **'Подключите аккаунт Spotify, чтобы видеть здесь свою библиотеку.'**
  String get homeSpotifyUnavailableHint;

  /// No description provided for @homeStartSession.
  ///
  /// In ru, this message translates to:
  /// **'Начать сессию'**
  String get homeStartSession;

  /// No description provided for @homeTapToOpen.
  ///
  /// In ru, this message translates to:
  /// **'Нажмите, чтобы открыть'**
  String get homeTapToOpen;

  /// No description provided for @hoursAgoShort.
  ///
  /// In ru, this message translates to:
  /// **'{count} ч. назад'**
  String hoursAgoShort(int count);

  /// No description provided for @invitesAccepted.
  ///
  /// In ru, this message translates to:
  /// **'Приглашение принято'**
  String get invitesAccepted;

  /// No description provided for @inviteScopeFriendsHint.
  ///
  /// In ru, this message translates to:
  /// **'Позвать может только тот, кто у вас в друзьях'**
  String get inviteScopeFriendsHint;

  /// No description provided for @inviteScopeNobodyHint.
  ///
  /// In ru, this message translates to:
  /// **'Никто не сможет позвать вас в сессию'**
  String get inviteScopeNobodyHint;

  /// No description provided for @invitesCount.
  ///
  /// In ru, this message translates to:
  /// **'Приглашения · {count}'**
  String invitesCount(int count);

  /// No description provided for @invitesDeclined.
  ///
  /// In ru, this message translates to:
  /// **'Приглашение отклонено'**
  String get invitesDeclined;

  /// No description provided for @invitesEmptyMessage.
  ///
  /// In ru, this message translates to:
  /// **'Друг позовёт, приглашение появится здесь. Можно и не ждать: начните сессию сами.'**
  String get invitesEmptyMessage;

  /// No description provided for @invitesEmptyTitle.
  ///
  /// In ru, this message translates to:
  /// **'Приглашений пока нет'**
  String get invitesEmptyTitle;

  /// No description provided for @invitesNotification.
  ///
  /// In ru, this message translates to:
  /// **'Приглашение в сессию «{name}»'**
  String invitesNotification(String name);

  /// No description provided for @invitesReplyFailed.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось ответить на приглашение'**
  String get invitesReplyFailed;

  /// No description provided for @invitesTitle.
  ///
  /// In ru, this message translates to:
  /// **'Приглашения'**
  String get invitesTitle;

  /// No description provided for @invitesWaiting.
  ///
  /// In ru, this message translates to:
  /// **'{count, plural, one{Одно приглашение ждёт ответа} few{{count} приглашения ждут ответа} many{{count} приглашений ждут ответа} other{{count} приглашения ждут ответа}}'**
  String invitesWaiting(int count);

  /// No description provided for @latencyMilliseconds.
  ///
  /// In ru, this message translates to:
  /// **'{value} мс'**
  String latencyMilliseconds(int value);

  /// No description provided for @latencySpeaker.
  ///
  /// In ru, this message translates to:
  /// **'Колонка'**
  String get latencySpeaker;

  /// No description provided for @latencyTitle.
  ///
  /// In ru, this message translates to:
  /// **'Задержка звука'**
  String get latencyTitle;

  /// No description provided for @latencyWired.
  ///
  /// In ru, this message translates to:
  /// **'Провод'**
  String get latencyWired;

  /// No description provided for @legalCopyText.
  ///
  /// In ru, this message translates to:
  /// **'Скопировать текст'**
  String get legalCopyText;

  /// No description provided for @legalOpenFailed.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось открыть документ.'**
  String get legalOpenFailed;

  /// No description provided for @legalOpenFailedDetails.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось открыть документ в браузере: {error}'**
  String legalOpenFailedDetails(String error);

  /// No description provided for @legalTextCopied.
  ///
  /// In ru, this message translates to:
  /// **'Текст скопирован'**
  String get legalTextCopied;

  /// No description provided for @loginBrowser.
  ///
  /// In ru, this message translates to:
  /// **'Войти через браузер'**
  String get loginBrowser;

  /// No description provided for @loginDoneCloseTab.
  ///
  /// In ru, this message translates to:
  /// **'Вход выполнен! Вкладку можно закрыть.'**
  String get loginDoneCloseTab;

  /// No description provided for @loginGoogle.
  ///
  /// In ru, this message translates to:
  /// **'Войти через Google'**
  String get loginGoogle;

  /// No description provided for @loginGoogleNoToken.
  ///
  /// In ru, this message translates to:
  /// **'Ошибка: не удалось получить ID токен от Google'**
  String get loginGoogleNoToken;

  /// No description provided for @loginHint.
  ///
  /// In ru, this message translates to:
  /// **'Войдите через Google, чтобы создавать сессии и слушать музыку вместе.'**
  String get loginHint;

  /// No description provided for @loginSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'Музыка для друзей'**
  String get loginSubtitle;

  /// No description provided for @loginTagline.
  ///
  /// In ru, this message translates to:
  /// **'Слушайте одну музыку одновременно — где бы вы ни были.'**
  String get loginTagline;

  /// No description provided for @loginTitle.
  ///
  /// In ru, this message translates to:
  /// **'Вход'**
  String get loginTitle;

  /// No description provided for @minutesAgoShort.
  ///
  /// In ru, this message translates to:
  /// **'{count} мин. назад'**
  String minutesAgoShort(int count);

  /// No description provided for @nameDialogCharset.
  ///
  /// In ru, this message translates to:
  /// **'Только буквы, цифры, пробел и знаки . _ -'**
  String get nameDialogCharset;

  /// No description provided for @nameDialogEmpty.
  ///
  /// In ru, this message translates to:
  /// **'Введите имя'**
  String get nameDialogEmpty;

  /// No description provided for @nameDialogHint.
  ///
  /// In ru, this message translates to:
  /// **'Это имя видят друзья — в списке, в сессиях и в приглашениях.'**
  String get nameDialogHint;

  /// No description provided for @nameDialogTitle.
  ///
  /// In ru, this message translates to:
  /// **'Как вас зовут?'**
  String get nameDialogTitle;

  /// No description provided for @nameDialogTooLong.
  ///
  /// In ru, this message translates to:
  /// **'Не более {count, plural, one{{count} символа} few{{count} символов} many{{count} символов} other{{count} символов}}'**
  String nameDialogTooLong(int count);

  /// No description provided for @nameDialogTooShort.
  ///
  /// In ru, this message translates to:
  /// **'Минимум {count, plural, one{{count} символ} few{{count} символа} many{{count} символов} other{{count} символа}}'**
  String nameDialogTooShort(int count);

  /// No description provided for @nameUpdated.
  ///
  /// In ru, this message translates to:
  /// **'Имя обновлено'**
  String get nameUpdated;

  /// No description provided for @navFindFriends.
  ///
  /// In ru, this message translates to:
  /// **'Найти друзей'**
  String get navFindFriends;

  /// No description provided for @navLibrary.
  ///
  /// In ru, this message translates to:
  /// **'Библиотека'**
  String get navLibrary;

  /// No description provided for @navLikedTracks.
  ///
  /// In ru, this message translates to:
  /// **'Любимые треки'**
  String get navLikedTracks;

  /// No description provided for @navNewSession.
  ///
  /// In ru, this message translates to:
  /// **'Новая сессия'**
  String get navNewSession;

  /// No description provided for @navQuick.
  ///
  /// In ru, this message translates to:
  /// **'Быстро'**
  String get navQuick;

  /// No description provided for @notificationsAllOff.
  ///
  /// In ru, this message translates to:
  /// **'Карточки выключены'**
  String get notificationsAllOff;

  /// No description provided for @notificationsAllOn.
  ///
  /// In ru, this message translates to:
  /// **'Все карточки включены'**
  String get notificationsAllOn;

  /// No description provided for @notificationsFriendRequests.
  ///
  /// In ru, this message translates to:
  /// **'Заявки в друзья'**
  String get notificationsFriendRequests;

  /// No description provided for @notificationsFriendRequestsHint.
  ///
  /// In ru, this message translates to:
  /// **'Карточка, когда вас добавляют'**
  String get notificationsFriendRequestsHint;

  /// No description provided for @notificationsGroup.
  ///
  /// In ru, this message translates to:
  /// **'Всплывающие карточки'**
  String get notificationsGroup;

  /// No description provided for @notificationsHint.
  ///
  /// In ru, this message translates to:
  /// **'Настройки общие для всех ваших устройств. Сами заявки и приглашения продолжают приходить — выключается только карточка поверх экрана.'**
  String get notificationsHint;

  /// No description provided for @notificationsOffInvites.
  ///
  /// In ru, this message translates to:
  /// **'приглашения'**
  String get notificationsOffInvites;

  /// No description provided for @notificationsOffOne.
  ///
  /// In ru, this message translates to:
  /// **'Выключено: {what}'**
  String notificationsOffOne(String what);

  /// No description provided for @notificationsOffRequests.
  ///
  /// In ru, this message translates to:
  /// **'заявки'**
  String get notificationsOffRequests;

  /// No description provided for @notificationsSessionInvites.
  ///
  /// In ru, this message translates to:
  /// **'Приглашения в сессию'**
  String get notificationsSessionInvites;

  /// No description provided for @notificationsSessionInvitesHint.
  ///
  /// In ru, this message translates to:
  /// **'Карточка, когда друг зовёт слушать вместе'**
  String get notificationsSessionInvitesHint;

  /// No description provided for @pickPlaylistAddAll.
  ///
  /// In ru, this message translates to:
  /// **'Добавить все ({count})'**
  String pickPlaylistAddAll(int count);

  /// No description provided for @pickPlaylistAddSelected.
  ///
  /// In ru, this message translates to:
  /// **'Добавить выбранные ({count})'**
  String pickPlaylistAddSelected(int count);

  /// No description provided for @pickPlaylistDeselectCount.
  ///
  /// In ru, this message translates to:
  /// **'Снять ({count})'**
  String pickPlaylistDeselectCount(int count);

  /// No description provided for @pickPlaylistEmptyPlaylist.
  ///
  /// In ru, this message translates to:
  /// **'В плейлисте нет треков'**
  String get pickPlaylistEmptyPlaylist;

  /// No description provided for @pickPlaylistInPlaylist.
  ///
  /// In ru, this message translates to:
  /// **'{count} в плейлисте'**
  String pickPlaylistInPlaylist(int count);

  /// No description provided for @pickPlaylistNoPlaylists.
  ///
  /// In ru, this message translates to:
  /// **'Плейлистов нет'**
  String get pickPlaylistNoPlaylists;

  /// No description provided for @pickPlaylistNoPlaylistsHint.
  ///
  /// In ru, this message translates to:
  /// **'Подключите Spotify или создайте свой плейлист, чтобы добавлять треки в сессии.'**
  String get pickPlaylistNoPlaylistsHint;

  /// No description provided for @pickPlaylistNoSession.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось определить сессию'**
  String get pickPlaylistNoSession;

  /// No description provided for @pickPlaylistNoTracks.
  ///
  /// In ru, this message translates to:
  /// **'Треков нет'**
  String get pickPlaylistNoTracks;

  /// No description provided for @pickPlaylistNoTracksHint.
  ///
  /// In ru, this message translates to:
  /// **'Этот плейлист пуст либо его содержимое недоступно: Spotify отдаёт треки только для ваших собственных плейлистов.'**
  String get pickPlaylistNoTracksHint;

  /// No description provided for @pickPlaylistTitle.
  ///
  /// In ru, this message translates to:
  /// **'Выберите плейлист'**
  String get pickPlaylistTitle;

  /// No description provided for @playbackAllowBackground.
  ///
  /// In ru, this message translates to:
  /// **'Разрешить работу в фоне'**
  String get playbackAllowBackground;

  /// No description provided for @playbackAllowBackgroundHint.
  ///
  /// In ru, this message translates to:
  /// **'Чтобы синхронизация не прерывалась при погашенном экране'**
  String get playbackAllowBackgroundHint;

  /// No description provided for @playbackAutostart.
  ///
  /// In ru, this message translates to:
  /// **'Настроить автозапуск'**
  String get playbackAutostart;

  /// No description provided for @playbackAutostartHint.
  ///
  /// In ru, this message translates to:
  /// **'На Xiaomi и Redmi без этого система закрывает приложение'**
  String get playbackAutostartHint;

  /// No description provided for @playbackAutostartHint2.
  ///
  /// In ru, this message translates to:
  /// **'Откройте настройки приложения и включите автозапуск вручную'**
  String get playbackAutostartHint2;

  /// No description provided for @playbackBackgroundGroup.
  ///
  /// In ru, this message translates to:
  /// **'Фоновый режим'**
  String get playbackBackgroundGroup;

  /// No description provided for @playbackClockSync.
  ///
  /// In ru, this message translates to:
  /// **'Сверить часы с сервером'**
  String get playbackClockSync;

  /// No description provided for @playbackClockSyncStarted.
  ///
  /// In ru, this message translates to:
  /// **'Часы синхронизируются заново'**
  String get playbackClockSyncStarted;

  /// No description provided for @playbackClockUnknown.
  ///
  /// In ru, this message translates to:
  /// **'Ещё не измерено — нажмите, чтобы обновить'**
  String get playbackClockUnknown;

  /// No description provided for @playbackConnections.
  ///
  /// In ru, this message translates to:
  /// **'Подключения'**
  String get playbackConnections;

  /// No description provided for @playbackOpenSpotifyHint.
  ///
  /// In ru, this message translates to:
  /// **'Откройте Spotify и запустите любой трек, затем повторите.'**
  String get playbackOpenSpotifyHint;

  /// No description provided for @playbackPermissionsHint.
  ///
  /// In ru, this message translates to:
  /// **'Проверьте разрешения в системном окне'**
  String get playbackPermissionsHint;

  /// No description provided for @playbackQualityGroup.
  ///
  /// In ru, this message translates to:
  /// **'Качество звука'**
  String get playbackQualityGroup;

  /// No description provided for @playbackServerLink.
  ///
  /// In ru, this message translates to:
  /// **'Связь с сервером'**
  String get playbackServerLink;

  /// No description provided for @playbackServerOffline.
  ///
  /// In ru, this message translates to:
  /// **'Нет связи. Проверьте интернет'**
  String get playbackServerOffline;

  /// No description provided for @playbackServerOnline.
  ///
  /// In ru, this message translates to:
  /// **'На связи — события сессии приходят сразу'**
  String get playbackServerOnline;

  /// No description provided for @playbackSpotifyConnected.
  ///
  /// In ru, this message translates to:
  /// **'Подключён — можно запускать треки'**
  String get playbackSpotifyConnected;

  /// No description provided for @playbackSpotifyConnectFailed.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось подключиться к Spotify'**
  String get playbackSpotifyConnectFailed;

  /// No description provided for @playbackSpotifyDevice.
  ///
  /// In ru, this message translates to:
  /// **'Spotify на устройстве'**
  String get playbackSpotifyDevice;

  /// No description provided for @playbackSpotifyDisconnected.
  ///
  /// In ru, this message translates to:
  /// **'Не подключён. Нажмите, чтобы связаться с приложением Spotify'**
  String get playbackSpotifyDisconnected;

  /// No description provided for @playbackSpotifySettings.
  ///
  /// In ru, this message translates to:
  /// **'Настройки Spotify'**
  String get playbackSpotifySettings;

  /// No description provided for @playbackSpotifySettingsHint.
  ///
  /// In ru, this message translates to:
  /// **'Качество, кроссфейд и громкость задаются в приложении Spotify'**
  String get playbackSpotifySettingsHint;

  /// No description provided for @playbackSpotifySettingsPath.
  ///
  /// In ru, this message translates to:
  /// **'Откройте Spotify → Настройки → Качество звука'**
  String get playbackSpotifySettingsPath;

  /// No description provided for @playbackSyncGroup.
  ///
  /// In ru, this message translates to:
  /// **'Синхронизация'**
  String get playbackSyncGroup;

  /// No description provided for @playerNext.
  ///
  /// In ru, this message translates to:
  /// **'Следующий трек'**
  String get playerNext;

  /// No description provided for @playerNowPlayingLabel.
  ///
  /// In ru, this message translates to:
  /// **'СЕЙЧАС ИГРАЕТ'**
  String get playerNowPlayingLabel;

  /// No description provided for @playerPause.
  ///
  /// In ru, this message translates to:
  /// **'Пауза'**
  String get playerPause;

  /// No description provided for @playerPlay.
  ///
  /// In ru, this message translates to:
  /// **'Воспроизвести'**
  String get playerPlay;

  /// No description provided for @playerPrevious.
  ///
  /// In ru, this message translates to:
  /// **'Предыдущий трек'**
  String get playerPrevious;

  /// No description provided for @playerRepeatAll.
  ///
  /// In ru, this message translates to:
  /// **'Повтор списка'**
  String get playerRepeatAll;

  /// No description provided for @playerRepeatOff.
  ///
  /// In ru, this message translates to:
  /// **'Повтор выключен'**
  String get playerRepeatOff;

  /// No description provided for @playerRepeatOne.
  ///
  /// In ru, this message translates to:
  /// **'Повтор одного трека'**
  String get playerRepeatOne;

  /// No description provided for @playerShuffle.
  ///
  /// In ru, this message translates to:
  /// **'Перемешать'**
  String get playerShuffle;

  /// No description provided for @playerShuffleOn.
  ///
  /// In ru, this message translates to:
  /// **'Перемешивание включено'**
  String get playerShuffleOn;

  /// No description provided for @playerUnknownTrack.
  ///
  /// In ru, this message translates to:
  /// **'Неизвестный трек'**
  String get playerUnknownTrack;

  /// No description provided for @playlistActionsTitle.
  ///
  /// In ru, this message translates to:
  /// **'Действия с плейлистом'**
  String get playlistActionsTitle;

  /// No description provided for @playlistAddMusic.
  ///
  /// In ru, this message translates to:
  /// **'Добавить музыку'**
  String get playlistAddMusic;

  /// No description provided for @playlistChangeCover.
  ///
  /// In ru, this message translates to:
  /// **'Изменить обложку'**
  String get playlistChangeCover;

  /// No description provided for @playlistClear.
  ///
  /// In ru, this message translates to:
  /// **'Очистить плейлист'**
  String get playlistClear;

  /// No description provided for @playlistCleared.
  ///
  /// In ru, this message translates to:
  /// **'Плейлист очищен'**
  String get playlistCleared;

  /// No description provided for @playlistClearMessage.
  ///
  /// In ru, this message translates to:
  /// **'Из «{name}» будут удалены все треки. Сам плейлист останется.'**
  String playlistClearMessage(String name);

  /// No description provided for @playlistClearTitle.
  ///
  /// In ru, this message translates to:
  /// **'Очистить плейлист?'**
  String get playlistClearTitle;

  /// No description provided for @playlistConnectSpotifyHint.
  ///
  /// In ru, this message translates to:
  /// **'Подключите Spotify аккаунт в профиле'**
  String get playlistConnectSpotifyHint;

  /// No description provided for @playlistCopyCreated.
  ///
  /// In ru, this message translates to:
  /// **'Создана копия «{name}»'**
  String playlistCopyCreated(String name);

  /// No description provided for @playlistCoverHint.
  ///
  /// In ru, this message translates to:
  /// **'Обложка квадратная — так плейлисты выглядят ровно в списке.'**
  String get playlistCoverHint;

  /// No description provided for @playlistCoverRemoved.
  ///
  /// In ru, this message translates to:
  /// **'Обложка убрана'**
  String get playlistCoverRemoved;

  /// No description provided for @playlistCoverTitle.
  ///
  /// In ru, this message translates to:
  /// **'Обложка плейлиста'**
  String get playlistCoverTitle;

  /// No description provided for @playlistCoverUpdated.
  ///
  /// In ru, this message translates to:
  /// **'Обложка обновлена'**
  String get playlistCoverUpdated;

  /// No description provided for @playlistDelete.
  ///
  /// In ru, this message translates to:
  /// **'Удалить плейлист'**
  String get playlistDelete;

  /// No description provided for @playlistDeleted.
  ///
  /// In ru, this message translates to:
  /// **'Плейлист удалён'**
  String get playlistDeleted;

  /// No description provided for @playlistDeleteMessage.
  ///
  /// In ru, this message translates to:
  /// **'«{name}» и его список треков будут удалены. Сами треки останутся в Spotify.'**
  String playlistDeleteMessage(String name);

  /// No description provided for @playlistDeleteTitle.
  ///
  /// In ru, this message translates to:
  /// **'Удалить плейлист?'**
  String get playlistDeleteTitle;

  /// No description provided for @playlistDuplicate.
  ///
  /// In ru, this message translates to:
  /// **'Дублировать'**
  String get playlistDuplicate;

  /// No description provided for @playlistEdit.
  ///
  /// In ru, this message translates to:
  /// **'Изменить плейлист'**
  String get playlistEdit;

  /// No description provided for @playlistEditNameDescription.
  ///
  /// In ru, this message translates to:
  /// **'Изменить название и описание'**
  String get playlistEditNameDescription;

  /// No description provided for @playlistEmptyMessage.
  ///
  /// In ru, this message translates to:
  /// **'Найдите музыку в Spotify или возьмите её из другого плейлиста.'**
  String get playlistEmptyMessage;

  /// No description provided for @playlistEmptyShort.
  ///
  /// In ru, this message translates to:
  /// **'В этом плейлисте пока пусто.'**
  String get playlistEmptyShort;

  /// No description provided for @playlistEmptyTitle.
  ///
  /// In ru, this message translates to:
  /// **'Нет треков'**
  String get playlistEmptyTitle;

  /// No description provided for @playlistFieldDescription.
  ///
  /// In ru, this message translates to:
  /// **'Описание'**
  String get playlistFieldDescription;

  /// No description provided for @playlistFieldName.
  ///
  /// In ru, this message translates to:
  /// **'Название'**
  String get playlistFieldName;

  /// No description provided for @playlistFieldOptional.
  ///
  /// In ru, this message translates to:
  /// **'Необязательно'**
  String get playlistFieldOptional;

  /// No description provided for @playlistForeign.
  ///
  /// In ru, this message translates to:
  /// **'Spotify не отдаёт содержимое чужих плейлистов — доступны только ваши собственные и совместные.'**
  String get playlistForeign;

  /// No description provided for @playlistLinkCopied.
  ///
  /// In ru, this message translates to:
  /// **'Плейлист скопирован в буфер обмена'**
  String get playlistLinkCopied;

  /// No description provided for @playlistNameCharset.
  ///
  /// In ru, this message translates to:
  /// **'Только буквы, цифры, пробелы и ._-()'**
  String get playlistNameCharset;

  /// No description provided for @playlistNameEmpty.
  ///
  /// In ru, this message translates to:
  /// **'Название не может быть пустым'**
  String get playlistNameEmpty;

  /// No description provided for @playlistNameEmptyGeneric.
  ///
  /// In ru, this message translates to:
  /// **'Введите название'**
  String get playlistNameEmptyGeneric;

  /// No description provided for @playlistNameTooShort.
  ///
  /// In ru, this message translates to:
  /// **'Минимум 2 символа'**
  String get playlistNameTooShort;

  /// No description provided for @playlistNew.
  ///
  /// In ru, this message translates to:
  /// **'Новый плейлист'**
  String get playlistNew;

  /// No description provided for @playlistOpen.
  ///
  /// In ru, this message translates to:
  /// **'Открыть'**
  String get playlistOpen;

  /// No description provided for @playlistPlay.
  ///
  /// In ru, this message translates to:
  /// **'Слушать'**
  String get playlistPlay;

  /// No description provided for @playlistRemoveCover.
  ///
  /// In ru, this message translates to:
  /// **'Убрать обложку'**
  String get playlistRemoveCover;

  /// No description provided for @playlistRemoveTrack.
  ///
  /// In ru, this message translates to:
  /// **'Удалить из плейлиста'**
  String get playlistRemoveTrack;

  /// No description provided for @playlistShare.
  ///
  /// In ru, this message translates to:
  /// **'Поделиться'**
  String get playlistShare;

  /// No description provided for @playlistTrackActions.
  ///
  /// In ru, this message translates to:
  /// **'Действия с треком'**
  String get playlistTrackActions;

  /// No description provided for @playlistTrackRemoved.
  ///
  /// In ru, this message translates to:
  /// **'Трек удалён из плейлиста'**
  String get playlistTrackRemoved;

  /// No description provided for @previewArtistName.
  ///
  /// In ru, this message translates to:
  /// **'Исполнитель'**
  String get previewArtistName;

  /// No description provided for @previewTrackName.
  ///
  /// In ru, this message translates to:
  /// **'Название трека'**
  String get previewTrackName;

  /// No description provided for @privacyAlwaysVisible.
  ///
  /// In ru, this message translates to:
  /// **'Видно всегда'**
  String get privacyAlwaysVisible;

  /// No description provided for @privacyBitActivity.
  ///
  /// In ru, this message translates to:
  /// **'активность'**
  String get privacyBitActivity;

  /// No description provided for @privacyBitFriends.
  ///
  /// In ru, this message translates to:
  /// **'друзья'**
  String get privacyBitFriends;

  /// No description provided for @privacyBitSearch.
  ///
  /// In ru, this message translates to:
  /// **'поиск'**
  String get privacyBitSearch;

  /// No description provided for @privacyBitStatus.
  ///
  /// In ru, this message translates to:
  /// **'статус'**
  String get privacyBitStatus;

  /// No description provided for @privacyBlocked.
  ///
  /// In ru, this message translates to:
  /// **'Заблокированные'**
  String get privacyBlocked;

  /// No description provided for @privacyBlockedHint.
  ///
  /// In ru, this message translates to:
  /// **'Не смогут найти вас, писать и звать в сессии'**
  String get privacyBlockedHint;

  /// No description provided for @privacyBlockedNobody.
  ///
  /// In ru, this message translates to:
  /// **'Никого нет'**
  String get privacyBlockedNobody;

  /// No description provided for @privacyBlockList.
  ///
  /// In ru, this message translates to:
  /// **'Чёрный список'**
  String get privacyBlockList;

  /// No description provided for @privacyDetailed.
  ///
  /// In ru, this message translates to:
  /// **'Подробно'**
  String get privacyDetailed;

  /// No description provided for @privacyDocFriends.
  ///
  /// In ru, this message translates to:
  /// **'Друзья и заявки'**
  String get privacyDocFriends;

  /// No description provided for @privacyDocFriendsText.
  ///
  /// In ru, this message translates to:
  /// **'С кем вы дружите и кому отправляли заявки. Заблокированные хранятся отдельно и никому не показываются.'**
  String get privacyDocFriendsText;

  /// No description provided for @privacyDocFullHint.
  ///
  /// In ru, this message translates to:
  /// **'Всё написанное выше — краткий пересказ. Полная политика конфиденциальности с формулировками и сроками хранения открывается ниже.'**
  String get privacyDocFullHint;

  /// No description provided for @privacyDocFullTitle.
  ///
  /// In ru, this message translates to:
  /// **'Полный текст'**
  String get privacyDocFullTitle;

  /// No description provided for @privacyDocHistoryText.
  ///
  /// In ru, this message translates to:
  /// **'Треки, которые вы включали в приложении, и время. Её можно очистить в разделе «Данные».'**
  String get privacyDocHistoryText;

  /// No description provided for @privacyDocHowToDeleteText.
  ///
  /// In ru, this message translates to:
  /// **'История прослушанного очищается в разделе «Данные». Там же удаляется аккаунт целиком — вместе с профилем, друзьями, сессиями и подключением Spotify. Это необратимо.'**
  String get privacyDocHowToDeleteText;

  /// No description provided for @privacyDocHowToDeleteTitle.
  ///
  /// In ru, this message translates to:
  /// **'Как удалить'**
  String get privacyDocHowToDeleteTitle;

  /// No description provided for @privacyDocNoOutsideListening.
  ///
  /// In ru, this message translates to:
  /// **'Содержимое прослушивания вне приложения: что вы слушаете сами, без сессии, никуда не отправляется.'**
  String get privacyDocNoOutsideListening;

  /// No description provided for @privacyDocNoPassword.
  ///
  /// In ru, this message translates to:
  /// **'Пароль от Spotify — авторизация проходит на стороне Spotify.'**
  String get privacyDocNoPassword;

  /// No description provided for @privacyDocNoPayments.
  ///
  /// In ru, this message translates to:
  /// **'Платёжные данные — приложение бесплатное и ничего не принимает.'**
  String get privacyDocNoPayments;

  /// No description provided for @privacyDocNotStoredTitle.
  ///
  /// In ru, this message translates to:
  /// **'Чего нет'**
  String get privacyDocNotStoredTitle;

  /// No description provided for @privacyDocProfile.
  ///
  /// In ru, this message translates to:
  /// **'Имя, адрес почты и аватар. Почта нужна для входа, имя и аватар видят друзья.'**
  String get privacyDocProfile;

  /// No description provided for @privacyDocSessionsText.
  ///
  /// In ru, this message translates to:
  /// **'Названия совместных прослушиваний, их участники, добавленные треки и оценки — чтобы показать совпадения в конце.'**
  String get privacyDocSessionsText;

  /// No description provided for @privacyDocSpotify.
  ///
  /// In ru, this message translates to:
  /// **'Подключение Spotify'**
  String get privacyDocSpotify;

  /// No description provided for @privacyDocSpotifyText.
  ///
  /// In ru, this message translates to:
  /// **'Идентификатор аккаунта и токены доступа — в зашифрованном виде. Пароль от Spotify приложение не видит и не получает.'**
  String get privacyDocSpotifyText;

  /// No description provided for @privacyDocStoredHint.
  ///
  /// In ru, this message translates to:
  /// **'Список собран по тому, что приложение действительно записывает в базу.'**
  String get privacyDocStoredHint;

  /// No description provided for @privacyDocStoredTitle.
  ///
  /// In ru, this message translates to:
  /// **'Что хранится'**
  String get privacyDocStoredTitle;

  /// No description provided for @privacyHiddenWarning.
  ///
  /// In ru, this message translates to:
  /// **'При полностью скрытом профиле друзьям сложнее понять, когда вас звать слушать вместе.'**
  String get privacyHiddenWarning;

  /// No description provided for @privacyHideActivity.
  ///
  /// In ru, this message translates to:
  /// **'Скрыть активность'**
  String get privacyHideActivity;

  /// No description provided for @privacyHideActivityHint.
  ///
  /// In ru, this message translates to:
  /// **'Что вы слушаете в сессии, не будет видно в профиле'**
  String get privacyHideActivityHint;

  /// No description provided for @privacyHideFriends.
  ///
  /// In ru, this message translates to:
  /// **'Скрыть друзей'**
  String get privacyHideFriends;

  /// No description provided for @privacyHideFriendsHint.
  ///
  /// In ru, this message translates to:
  /// **'Никто не увидит, сколько у вас друзей и кто из них общий'**
  String get privacyHideFriendsHint;

  /// No description provided for @privacyHideOnline.
  ///
  /// In ru, this message translates to:
  /// **'Скрыть статус в сети'**
  String get privacyHideOnline;

  /// No description provided for @privacyHideOnlineHint.
  ///
  /// In ru, this message translates to:
  /// **'Друзья не увидят, когда вы онлайн и когда были в последний раз'**
  String get privacyHideOnlineHint;

  /// No description provided for @privacyHideSearch.
  ///
  /// In ru, this message translates to:
  /// **'Скрыть из поиска'**
  String get privacyHideSearch;

  /// No description provided for @privacyHideSearchHint.
  ///
  /// In ru, this message translates to:
  /// **'Новые люди не найдут вас по имени. Друзья — увидят'**
  String get privacyHideSearchHint;

  /// No description provided for @privacyHistory.
  ///
  /// In ru, this message translates to:
  /// **'История прослушанного'**
  String get privacyHistory;

  /// No description provided for @privacyHistoryHint.
  ///
  /// In ru, this message translates to:
  /// **'Видна только вам, даже друзьям — нет'**
  String get privacyHistoryHint;

  /// No description provided for @privacyNameAndAvatar.
  ///
  /// In ru, this message translates to:
  /// **'Имя и аватар'**
  String get privacyNameAndAvatar;

  /// No description provided for @privacyNameAndAvatarHint.
  ///
  /// In ru, this message translates to:
  /// **'По ним друзья узнают вас в списке и в сессии'**
  String get privacyNameAndAvatarHint;

  /// No description provided for @privacyNothingHidden.
  ///
  /// In ru, this message translates to:
  /// **'Ничего не скрыто'**
  String get privacyNothingHidden;

  /// No description provided for @privacyPresetFriends.
  ///
  /// In ru, this message translates to:
  /// **'Только свои'**
  String get privacyPresetFriends;

  /// No description provided for @privacyPresetFriendsSummary.
  ///
  /// In ru, this message translates to:
  /// **'Только свои — вас не найдут в поиске'**
  String get privacyPresetFriendsSummary;

  /// No description provided for @privacyPresetHidden.
  ///
  /// In ru, this message translates to:
  /// **'Скрытый'**
  String get privacyPresetHidden;

  /// No description provided for @privacyPresetHiddenSummary.
  ///
  /// In ru, this message translates to:
  /// **'Скрытый профиль'**
  String get privacyPresetHiddenSummary;

  /// No description provided for @privacyPresetOpen.
  ///
  /// In ru, this message translates to:
  /// **'Открытый'**
  String get privacyPresetOpen;

  /// No description provided for @privacyPresetOpenSummary.
  ///
  /// In ru, this message translates to:
  /// **'Открытый профиль'**
  String get privacyPresetOpenSummary;

  /// No description provided for @privacyQuickMode.
  ///
  /// In ru, this message translates to:
  /// **'Быстрый режим'**
  String get privacyQuickMode;

  /// No description provided for @privacySessionParticipation.
  ///
  /// In ru, this message translates to:
  /// **'Участие в общей сессии'**
  String get privacySessionParticipation;

  /// No description provided for @privacySessionParticipationHint.
  ///
  /// In ru, this message translates to:
  /// **'Тот, с кем вы слушаете, видит вас и очередь треков'**
  String get privacySessionParticipationHint;

  /// No description provided for @privacySummaryFriendCount.
  ///
  /// In ru, this message translates to:
  /// **'сколько у вас друзей'**
  String get privacySummaryFriendCount;

  /// No description provided for @privacySummaryFriendsSee.
  ///
  /// In ru, this message translates to:
  /// **'Друзья видят'**
  String get privacySummaryFriendsSee;

  /// No description provided for @privacySummaryListening.
  ///
  /// In ru, this message translates to:
  /// **'что вы слушаете'**
  String get privacySummaryListening;

  /// No description provided for @privacySummaryNameAvatar.
  ///
  /// In ru, this message translates to:
  /// **'имя и аватар'**
  String get privacySummaryNameAvatar;

  /// No description provided for @privacySummaryNotSearchable.
  ///
  /// In ru, this message translates to:
  /// **'Не найдут вас в поиске'**
  String get privacySummaryNotSearchable;

  /// No description provided for @privacySummaryOnline.
  ///
  /// In ru, this message translates to:
  /// **'когда вы в сети'**
  String get privacySummaryOnline;

  /// No description provided for @privacySummaryOthers.
  ///
  /// In ru, this message translates to:
  /// **'Остальные'**
  String get privacySummaryOthers;

  /// No description provided for @privacySummarySearchable.
  ///
  /// In ru, this message translates to:
  /// **'Могут найти вас по имени и отправить заявку'**
  String get privacySummarySearchable;

  /// No description provided for @privacyWhatIsVisible.
  ///
  /// In ru, this message translates to:
  /// **'Что о вас видно'**
  String get privacyWhatIsVisible;

  /// No description provided for @profileConnectSpotify.
  ///
  /// In ru, this message translates to:
  /// **'Подключить Spotify'**
  String get profileConnectSpotify;

  /// No description provided for @profileDisconnectSpotify.
  ///
  /// In ru, this message translates to:
  /// **'Отключить Spotify'**
  String get profileDisconnectSpotify;

  /// No description provided for @profileEmpty.
  ///
  /// In ru, this message translates to:
  /// **'Пока пусто'**
  String get profileEmpty;

  /// No description provided for @profileFriendsCount.
  ///
  /// In ru, this message translates to:
  /// **'{count, plural, one{{count} друг} few{{count} друга} many{{count} друзей} other{{count} друга}}'**
  String profileFriendsCount(int count);

  /// No description provided for @profileInCommonEmpty.
  ///
  /// In ru, this message translates to:
  /// **'Пока ничего общего не нашлось'**
  String get profileInCommonEmpty;

  /// No description provided for @profileInCommonHint.
  ///
  /// In ru, this message translates to:
  /// **'Из ваших любимых'**
  String get profileInCommonHint;

  /// No description provided for @profileInCommonTitle.
  ///
  /// In ru, this message translates to:
  /// **'Общая музыка'**
  String get profileInCommonTitle;

  /// No description provided for @profileInCommonTracks.
  ///
  /// In ru, this message translates to:
  /// **'{count, plural, one{{count} общий трек} few{{count} общих трека} many{{count} общих треков} other{{count} общих трека}}'**
  String profileInCommonTracks(int count);

  /// No description provided for @profileInSelection.
  ///
  /// In ru, this message translates to:
  /// **'{count} в подборке'**
  String profileInSelection(int count);

  /// No description provided for @profileLast.
  ///
  /// In ru, this message translates to:
  /// **'Последнее'**
  String get profileLast;

  /// No description provided for @profileLikedCount.
  ///
  /// In ru, this message translates to:
  /// **'{count} любимых'**
  String profileLikedCount(int count);

  /// No description provided for @profileLikedEmpty.
  ///
  /// In ru, this message translates to:
  /// **'Отмечайте треки сердечком — они соберутся здесь'**
  String get profileLikedEmpty;

  /// No description provided for @profileLikedTracks.
  ///
  /// In ru, this message translates to:
  /// **'Любимые треки'**
  String get profileLikedTracks;

  /// No description provided for @profileMutualCount.
  ///
  /// In ru, this message translates to:
  /// **'{count} общих'**
  String profileMutualCount(int count);

  /// No description provided for @profileNothingShown.
  ///
  /// In ru, this message translates to:
  /// **'Ничего не показывается'**
  String get profileNothingShown;

  /// No description provided for @profilePlaylistsHint.
  ///
  /// In ru, this message translates to:
  /// **'Ваши подборки'**
  String get profilePlaylistsHint;

  /// No description provided for @profilePlaylistsTitle.
  ///
  /// In ru, this message translates to:
  /// **'Плейлисты'**
  String get profilePlaylistsTitle;

  /// No description provided for @profileRecentlyPlayed.
  ///
  /// In ru, this message translates to:
  /// **'Недавно слушали'**
  String get profileRecentlyPlayed;

  /// No description provided for @profileRecentlyPlayedEmpty.
  ///
  /// In ru, this message translates to:
  /// **'Здесь появятся треки, которые вы включали'**
  String get profileRecentlyPlayedEmpty;

  /// No description provided for @profileSessionsCount.
  ///
  /// In ru, this message translates to:
  /// **'{count, plural, one{{count} сессия} few{{count} сессии} many{{count} сессий} other{{count} сессии}}'**
  String profileSessionsCount(int count);

  /// No description provided for @profileTopArtists.
  ///
  /// In ru, this message translates to:
  /// **'Чаще всего звучит'**
  String get profileTopArtists;

  /// No description provided for @profileTopArtistsHint.
  ///
  /// In ru, this message translates to:
  /// **'По прослушанному и любимому'**
  String get profileTopArtistsHint;

  /// No description provided for @profileVisibleToYouOnly.
  ///
  /// In ru, this message translates to:
  /// **'Видно только вам'**
  String get profileVisibleToYouOnly;

  /// No description provided for @requestsAccept.
  ///
  /// In ru, this message translates to:
  /// **'Принять'**
  String get requestsAccept;

  /// No description provided for @requestsAccepted.
  ///
  /// In ru, this message translates to:
  /// **'Заявка принята'**
  String get requestsAccepted;

  /// No description provided for @requestsDecline.
  ///
  /// In ru, this message translates to:
  /// **'Отклонить'**
  String get requestsDecline;

  /// No description provided for @requestsDeclineMessage.
  ///
  /// In ru, this message translates to:
  /// **'{name} не увидит, что вы отклонили заявку.'**
  String requestsDeclineMessage(String name);

  /// No description provided for @requestsDeclineTitle.
  ///
  /// In ru, this message translates to:
  /// **'Отклонить заявку?'**
  String get requestsDeclineTitle;

  /// No description provided for @requestsEmptyMessage.
  ///
  /// In ru, this message translates to:
  /// **'Здесь появятся приглашения в друзья. Отправить свою — быстрее, чем ждать.'**
  String get requestsEmptyMessage;

  /// No description provided for @requestsEmptyTitle.
  ///
  /// In ru, this message translates to:
  /// **'Заявок пока нет'**
  String get requestsEmptyTitle;

  /// No description provided for @requestsNotification.
  ///
  /// In ru, this message translates to:
  /// **'Заявка в друзья от {name}'**
  String requestsNotification(String name);

  /// No description provided for @requestsWantsToAdd.
  ///
  /// In ru, this message translates to:
  /// **'Хочет добавить вас в друзья'**
  String get requestsWantsToAdd;

  /// No description provided for @resultsBackHome.
  ///
  /// In ru, this message translates to:
  /// **'На главную'**
  String get resultsBackHome;

  /// No description provided for @resultsMatches.
  ///
  /// In ru, this message translates to:
  /// **'Совпадения'**
  String get resultsMatches;

  /// No description provided for @resultsMatchesHint.
  ///
  /// In ru, this message translates to:
  /// **'Эти треки понравились обоим.'**
  String get resultsMatchesHint;

  /// No description provided for @resultsNoMatches.
  ///
  /// In ru, this message translates to:
  /// **'Совпадений нет'**
  String get resultsNoMatches;

  /// No description provided for @resultsNoMatchesHint.
  ///
  /// In ru, this message translates to:
  /// **'В этот раз вкусы разошлись. Попробуйте ещё одну сессию — с другой подборкой результат может быть иным.'**
  String get resultsNoMatchesHint;

  /// No description provided for @resultsTitle.
  ///
  /// In ru, this message translates to:
  /// **'Итоги сессии'**
  String get resultsTitle;

  /// No description provided for @searchEmptyMessage.
  ///
  /// In ru, this message translates to:
  /// **'Введите имя или код из восьми символов. Свой код можно посмотреть в настройках, в разделе «Аккаунт».'**
  String get searchEmptyMessage;

  /// No description provided for @searchEmptyTitle.
  ///
  /// In ru, this message translates to:
  /// **'Найдите друзей'**
  String get searchEmptyTitle;

  /// No description provided for @searchFieldHint.
  ///
  /// In ru, this message translates to:
  /// **'Имя или код'**
  String get searchFieldHint;

  /// No description provided for @searchNothingFound.
  ///
  /// In ru, this message translates to:
  /// **'Никого не нашлось'**
  String get searchNothingFound;

  /// No description provided for @searchNothingFoundHint.
  ///
  /// In ru, this message translates to:
  /// **'Проверьте написание. По коду человек находится, даже если скрыл себя из поиска.'**
  String get searchNothingFoundHint;

  /// No description provided for @searchRequestSent.
  ///
  /// In ru, this message translates to:
  /// **'Заявка отправлена'**
  String get searchRequestSent;

  /// No description provided for @searchSendRequest.
  ///
  /// In ru, this message translates to:
  /// **'Отправить заявку'**
  String get searchSendRequest;

  /// No description provided for @searchStatusFriends.
  ///
  /// In ru, this message translates to:
  /// **'В друзьях'**
  String get searchStatusFriends;

  /// No description provided for @searchStatusSent.
  ///
  /// In ru, this message translates to:
  /// **'Отправлено'**
  String get searchStatusSent;

  /// No description provided for @searchStatusWaiting.
  ///
  /// In ru, this message translates to:
  /// **'Ждёт ответа'**
  String get searchStatusWaiting;

  /// No description provided for @sectionAbout.
  ///
  /// In ru, this message translates to:
  /// **'О приложении'**
  String get sectionAbout;

  /// No description provided for @sectionAccount.
  ///
  /// In ru, this message translates to:
  /// **'Аккаунт'**
  String get sectionAccount;

  /// No description provided for @sectionAppearance.
  ///
  /// In ru, this message translates to:
  /// **'Оформление'**
  String get sectionAppearance;

  /// No description provided for @sectionData.
  ///
  /// In ru, this message translates to:
  /// **'Данные'**
  String get sectionData;

  /// No description provided for @sectionNotifications.
  ///
  /// In ru, this message translates to:
  /// **'Уведомления'**
  String get sectionNotifications;

  /// No description provided for @sectionPlayback.
  ///
  /// In ru, this message translates to:
  /// **'Воспроизведение'**
  String get sectionPlayback;

  /// No description provided for @sectionPrivacy.
  ///
  /// In ru, this message translates to:
  /// **'Приватность'**
  String get sectionPrivacy;

  /// No description provided for @sectionSecurity.
  ///
  /// In ru, this message translates to:
  /// **'Безопасность'**
  String get sectionSecurity;

  /// No description provided for @sectionSessions.
  ///
  /// In ru, this message translates to:
  /// **'Сессии'**
  String get sectionSessions;

  /// No description provided for @securityDangerZone.
  ///
  /// In ru, this message translates to:
  /// **'Опасная зона'**
  String get securityDangerZone;

  /// No description provided for @securityDeleteAccount.
  ///
  /// In ru, this message translates to:
  /// **'Удалить аккаунт'**
  String get securityDeleteAccount;

  /// No description provided for @securityDeleteAccountHint.
  ///
  /// In ru, this message translates to:
  /// **'Безвозвратно удалит профиль, друзей и историю сессий'**
  String get securityDeleteAccountHint;

  /// No description provided for @securityDeleteAccountTitle.
  ///
  /// In ru, this message translates to:
  /// **'Удалить аккаунт?'**
  String get securityDeleteAccountTitle;

  /// No description provided for @securityDevices.
  ///
  /// In ru, this message translates to:
  /// **'Устройства'**
  String get securityDevices;

  /// No description provided for @securityDevicesHint.
  ///
  /// In ru, this message translates to:
  /// **'Где выполнен вход, и как завершить лишнее'**
  String get securityDevicesHint;

  /// No description provided for @securitySessionsGroup.
  ///
  /// In ru, this message translates to:
  /// **'Сеансы'**
  String get securitySessionsGroup;

  /// No description provided for @securitySignInGoogle.
  ///
  /// In ru, this message translates to:
  /// **'Через Google'**
  String get securitySignInGoogle;

  /// No description provided for @securitySignInMethod.
  ///
  /// In ru, this message translates to:
  /// **'Способ входа'**
  String get securitySignInMethod;

  /// No description provided for @securitySignInSpotifyGoogle.
  ///
  /// In ru, this message translates to:
  /// **'Через Spotify или Google'**
  String get securitySignInSpotifyGoogle;

  /// No description provided for @securitySignOutEverywhere.
  ///
  /// In ru, this message translates to:
  /// **'Выйти со всех устройств'**
  String get securitySignOutEverywhere;

  /// No description provided for @securitySignOutEverywhereConfirm.
  ///
  /// In ru, this message translates to:
  /// **'Выйти везде'**
  String get securitySignOutEverywhereConfirm;

  /// No description provided for @securitySignOutEverywhereHint.
  ///
  /// In ru, this message translates to:
  /// **'Завершит все сеансы, включая этот'**
  String get securitySignOutEverywhereHint;

  /// No description provided for @securitySignOutEverywhereMessage.
  ///
  /// In ru, this message translates to:
  /// **'Все сеансы завершатся, включая этот. Так стоит поступить, если в списке есть чужое устройство.'**
  String get securitySignOutEverywhereMessage;

  /// No description provided for @securitySignOutEverywhereTitle.
  ///
  /// In ru, this message translates to:
  /// **'Выйти со всех устройств?'**
  String get securitySignOutEverywhereTitle;

  /// No description provided for @securitySignOutMessage.
  ///
  /// In ru, this message translates to:
  /// **'Придётся войти заново, чтобы вернуться.'**
  String get securitySignOutMessage;

  /// No description provided for @securitySignOutThisDevice.
  ///
  /// In ru, this message translates to:
  /// **'Только на этом устройстве'**
  String get securitySignOutThisDevice;

  /// No description provided for @securitySignOutTitle.
  ///
  /// In ru, this message translates to:
  /// **'Выйти из аккаунта?'**
  String get securitySignOutTitle;

  /// No description provided for @sessionAddTracks.
  ///
  /// In ru, this message translates to:
  /// **'Добавить треки'**
  String get sessionAddTracks;

  /// No description provided for @sessionAdjusting.
  ///
  /// In ru, this message translates to:
  /// **'Подстраиваемся'**
  String get sessionAdjusting;

  /// No description provided for @sessionAlreadyRated.
  ///
  /// In ru, this message translates to:
  /// **'Второй участник уже оценил'**
  String get sessionAlreadyRated;

  /// No description provided for @sessionDislike.
  ///
  /// In ru, this message translates to:
  /// **'Не нравится'**
  String get sessionDislike;

  /// No description provided for @sessionEndAction.
  ///
  /// In ru, this message translates to:
  /// **'Завершить сессию'**
  String get sessionEndAction;

  /// No description provided for @sessionEndMessage.
  ///
  /// In ru, this message translates to:
  /// **'«{name}» закроется у всех участников.'**
  String sessionEndMessage(String name);

  /// No description provided for @sessionEndMessagePlain.
  ///
  /// In ru, this message translates to:
  /// **'Сессия будет закрыта для всех участников.'**
  String get sessionEndMessagePlain;

  /// No description provided for @sessionHostChanged.
  ///
  /// In ru, this message translates to:
  /// **'Ведущий сессии сменился'**
  String get sessionHostChanged;

  /// No description provided for @sessionInQueue.
  ///
  /// In ru, this message translates to:
  /// **'{count} в очереди'**
  String sessionInQueue(int count);

  /// No description provided for @sessionInSync.
  ///
  /// In ru, this message translates to:
  /// **'Звучит одновременно'**
  String get sessionInSync;

  /// No description provided for @sessionLike.
  ///
  /// In ru, this message translates to:
  /// **'Нравится'**
  String get sessionLike;

  /// No description provided for @sessionNoTracksYet.
  ///
  /// In ru, this message translates to:
  /// **'Пока без треков'**
  String get sessionNoTracksYet;

  /// No description provided for @sessionNotStarted.
  ///
  /// In ru, this message translates to:
  /// **'Сессия не запущена'**
  String get sessionNotStarted;

  /// No description provided for @sessionParticipant.
  ///
  /// In ru, this message translates to:
  /// **'Участник'**
  String get sessionParticipant;

  /// No description provided for @sessionQueueEmpty.
  ///
  /// In ru, this message translates to:
  /// **'Очередь пуста'**
  String get sessionQueueEmpty;

  /// No description provided for @sessionQueueEmptyHint.
  ///
  /// In ru, this message translates to:
  /// **'Добавьте треки из своих плейлистов — их услышат все участники.'**
  String get sessionQueueEmptyHint;

  /// No description provided for @sessionsActive.
  ///
  /// In ru, this message translates to:
  /// **'Активные сессии'**
  String get sessionsActive;

  /// No description provided for @sessionsActiveCount.
  ///
  /// In ru, this message translates to:
  /// **'Активные сессии · {count}'**
  String sessionsActiveCount(int count);

  /// No description provided for @sessionsAutoOpenPlayer.
  ///
  /// In ru, this message translates to:
  /// **'Открывать плеер при запуске'**
  String get sessionsAutoOpenPlayer;

  /// No description provided for @sessionsAutoOpenPlayerHint.
  ///
  /// In ru, this message translates to:
  /// **'Полноэкранный плеер, когда трек пошёл'**
  String get sessionsAutoOpenPlayerHint;

  /// No description provided for @sessionsBlockedHint.
  ///
  /// In ru, this message translates to:
  /// **'Они не смогут позвать вас в сессию'**
  String get sessionsBlockedHint;

  /// No description provided for @sessionsConfirmEnd.
  ///
  /// In ru, this message translates to:
  /// **'Спрашивать перед завершением'**
  String get sessionsConfirmEnd;

  /// No description provided for @sessionsConfirmEndHint.
  ///
  /// In ru, this message translates to:
  /// **'Подтверждение, чтобы не закрыть сессию случайно'**
  String get sessionsConfirmEndHint;

  /// No description provided for @sessionsDuringGroup.
  ///
  /// In ru, this message translates to:
  /// **'Во время сессии'**
  String get sessionsDuringGroup;

  /// No description provided for @sessionsEnded.
  ///
  /// In ru, this message translates to:
  /// **'Сессия завершена'**
  String get sessionsEnded;

  /// No description provided for @sessionsEndTitle.
  ///
  /// In ru, this message translates to:
  /// **'Завершить сессию?'**
  String get sessionsEndTitle;

  /// No description provided for @sessionsKeepScreenOn.
  ///
  /// In ru, this message translates to:
  /// **'Не гасить экран'**
  String get sessionsKeepScreenOn;

  /// No description provided for @sessionsKeepScreenOnHint.
  ///
  /// In ru, this message translates to:
  /// **'Экран остаётся включённым, пока идёт сессия'**
  String get sessionsKeepScreenOnHint;

  /// No description provided for @sessionsNothingPlaying.
  ///
  /// In ru, this message translates to:
  /// **'Сейчас ничего не идёт'**
  String get sessionsNothingPlaying;

  /// No description provided for @sessionsNothingPlayingHint.
  ///
  /// In ru, this message translates to:
  /// **'Начатые сессии появятся здесь'**
  String get sessionsNothingPlayingHint;

  /// No description provided for @sessionsOneInvite.
  ///
  /// In ru, this message translates to:
  /// **'Одно приглашение ждёт ответа'**
  String get sessionsOneInvite;

  /// No description provided for @sessionsOpenList.
  ///
  /// In ru, this message translates to:
  /// **'Открыть список'**
  String get sessionsOpenList;

  /// No description provided for @sessionsRunningNow.
  ///
  /// In ru, this message translates to:
  /// **'Идёт сейчас'**
  String get sessionsRunningNow;

  /// No description provided for @sessionsWhoCanInvite.
  ///
  /// In ru, this message translates to:
  /// **'Кто может звать'**
  String get sessionsWhoCanInvite;

  /// No description provided for @sessionWaitingForSecond.
  ///
  /// In ru, this message translates to:
  /// **'Ждём второго'**
  String get sessionWaitingForSecond;

  /// No description provided for @sessionYouAreHost.
  ///
  /// In ru, this message translates to:
  /// **'Вы теперь ведущий сессии'**
  String get sessionYouAreHost;

  /// No description provided for @settingsTitle.
  ///
  /// In ru, this message translates to:
  /// **'Настройки'**
  String get settingsTitle;

  /// No description provided for @sizeBytes.
  ///
  /// In ru, this message translates to:
  /// **'{value} Б'**
  String sizeBytes(int value);

  /// No description provided for @sizeKilobytes.
  ///
  /// In ru, this message translates to:
  /// **'{value} КБ'**
  String sizeKilobytes(int value);

  /// No description provided for @sizeMegabytes.
  ///
  /// In ru, this message translates to:
  /// **'{value} МБ'**
  String sizeMegabytes(String value);

  /// No description provided for @spotifyCheck.
  ///
  /// In ru, this message translates to:
  /// **'Проверить'**
  String get spotifyCheck;

  /// No description provided for @spotifyCheckFailed.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось проверить подключение'**
  String get spotifyCheckFailed;

  /// No description provided for @spotifyChecking.
  ///
  /// In ru, this message translates to:
  /// **'Проверяем подключение…'**
  String get spotifyChecking;

  /// No description provided for @spotifyConnect.
  ///
  /// In ru, this message translates to:
  /// **'Подключить'**
  String get spotifyConnect;

  /// No description provided for @spotifyConnected.
  ///
  /// In ru, this message translates to:
  /// **'Подключён'**
  String get spotifyConnected;

  /// No description provided for @spotifyConnectedAs.
  ///
  /// In ru, this message translates to:
  /// **'Подключён · {name}'**
  String spotifyConnectedAs(String name);

  /// No description provided for @spotifyConnectedShort.
  ///
  /// In ru, this message translates to:
  /// **'Spotify подключён'**
  String get spotifyConnectedShort;

  /// No description provided for @spotifyDisconnect.
  ///
  /// In ru, this message translates to:
  /// **'Отключить'**
  String get spotifyDisconnect;

  /// No description provided for @spotifyDisconnectMessage.
  ///
  /// In ru, this message translates to:
  /// **'Плейлисты и совместное прослушивание перестанут работать, пока вы не подключите его снова.'**
  String get spotifyDisconnectMessage;

  /// No description provided for @spotifyDisconnectTitle.
  ///
  /// In ru, this message translates to:
  /// **'Отключить Spotify?'**
  String get spotifyDisconnectTitle;

  /// No description provided for @spotifyLikedEmpty.
  ///
  /// In ru, this message translates to:
  /// **'Здесь появятся треки, которые вы сохраните в Spotify.'**
  String get spotifyLikedEmpty;

  /// No description provided for @spotifyLikedSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'Сохранённые в Spotify'**
  String get spotifyLikedSubtitle;

  /// No description provided for @spotifyLikedTitle.
  ///
  /// In ru, this message translates to:
  /// **'Любимые треки'**
  String get spotifyLikedTitle;

  /// No description provided for @spotifyLinkBusy.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось начать подключение: предыдущая попытка ещё не завершилась. Подождите несколько секунд и попробуйте снова.'**
  String get spotifyLinkBusy;

  /// No description provided for @spotifyLinked.
  ///
  /// In ru, this message translates to:
  /// **'Spotify подключён'**
  String get spotifyLinked;

  /// No description provided for @spotifyNeedsReauth.
  ///
  /// In ru, this message translates to:
  /// **'Доступ отозван или истёк — подключите заново'**
  String get spotifyNeedsReauth;

  /// No description provided for @spotifyNotConnected.
  ///
  /// In ru, this message translates to:
  /// **'Не подключён'**
  String get spotifyNotConnected;

  /// No description provided for @spotifyNotConnectedShort.
  ///
  /// In ru, this message translates to:
  /// **'Spotify не подключён'**
  String get spotifyNotConnectedShort;

  /// No description provided for @spotifyReconnect.
  ///
  /// In ru, this message translates to:
  /// **'Переподключить'**
  String get spotifyReconnect;

  /// No description provided for @spotifyUnlinked.
  ///
  /// In ru, this message translates to:
  /// **'Spotify отключён'**
  String get spotifyUnlinked;

  /// No description provided for @spotifyWebviewTitle.
  ///
  /// In ru, this message translates to:
  /// **'Подключение Spotify'**
  String get spotifyWebviewTitle;

  /// No description provided for @summaryAbout.
  ///
  /// In ru, this message translates to:
  /// **'Версия • Приватность • Условия'**
  String get summaryAbout;

  /// No description provided for @summaryData.
  ///
  /// In ru, this message translates to:
  /// **'Кэш • История • Выгрузка'**
  String get summaryData;

  /// No description provided for @summaryPlayback.
  ///
  /// In ru, this message translates to:
  /// **'Подключения • Задержка звука • Фон'**
  String get summaryPlayback;

  /// No description provided for @summarySecurity.
  ///
  /// In ru, this message translates to:
  /// **'Устройства • Выход • Удаление аккаунта'**
  String get summarySecurity;

  /// No description provided for @summarySessions.
  ///
  /// In ru, this message translates to:
  /// **'Активные • Приглашения • Кто может звать'**
  String get summarySessions;

  /// No description provided for @tabMusic.
  ///
  /// In ru, this message translates to:
  /// **'Музыка'**
  String get tabMusic;

  /// No description provided for @tabNow.
  ///
  /// In ru, this message translates to:
  /// **'Сейчас'**
  String get tabNow;

  /// No description provided for @themeDark.
  ///
  /// In ru, this message translates to:
  /// **'Тёмная'**
  String get themeDark;

  /// No description provided for @themeLight.
  ///
  /// In ru, this message translates to:
  /// **'Светлая'**
  String get themeLight;

  /// No description provided for @themeSystem.
  ///
  /// In ru, this message translates to:
  /// **'Как в системе'**
  String get themeSystem;

  /// No description provided for @trackCount.
  ///
  /// In ru, this message translates to:
  /// **'{count, plural, one{{count} трек} few{{count} трека} many{{count} треков} other{{count} трека}}'**
  String trackCount(int count);

  /// No description provided for @trackLike.
  ///
  /// In ru, this message translates to:
  /// **'В любимые'**
  String get trackLike;

  /// No description provided for @trackUnlike.
  ///
  /// In ru, this message translates to:
  /// **'Убрать из любимых'**
  String get trackUnlike;

  /// No description provided for @updatedDaysAgo.
  ///
  /// In ru, this message translates to:
  /// **'обновлено {count, plural, one{{count} день} few{{count} дня} many{{count} дней} other{{count} дня}} назад'**
  String updatedDaysAgo(int count);

  /// No description provided for @updatedHoursAgo.
  ///
  /// In ru, this message translates to:
  /// **'обновлено {count, plural, one{{count} час} few{{count} часа} many{{count} часов} other{{count} часа}} назад'**
  String updatedHoursAgo(int count);

  /// No description provided for @updatedMinutesAgo.
  ///
  /// In ru, this message translates to:
  /// **'обновлено {count, plural, one{{count} минуту} few{{count} минуты} many{{count} минут} other{{count} минуты}} назад'**
  String updatedMinutesAgo(int count);
}

class _LDelegate extends LocalizationsDelegate<L> {
  const _LDelegate();

  @override
  Future<L> load(Locale locale) {
    return SynchronousFuture<L>(lookupL(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ru'].contains(locale.languageCode);

  @override
  bool shouldReload(_LDelegate old) => false;
}

L lookupL(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return LEn();
    case 'ru':
      return LRu();
  }

  throw FlutterError(
    'L.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
