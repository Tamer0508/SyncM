// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class LRu extends L {
  LRu([String locale = 'ru']) : super(locale);

  @override
  String get aboutDataPrivacy => 'Данные и приватность';

  @override
  String get aboutDataPrivacyHint => 'Что приложение хранит и как это удалить';

  @override
  String get aboutLegalGroup => 'Данные и правила';

  @override
  String get aboutPrivacyPolicy => 'Политика конфиденциальности';

  @override
  String get aboutTerms => 'Условия использования';

  @override
  String get aboutTermsHint => 'Правила пользования приложением';

  @override
  String aboutVersion(String version) {
    return 'Версия $version';
  }

  @override
  String get accentAmber => 'Янтарь';

  @override
  String get accentClay => 'Глина';

  @override
  String get accentIndigo => 'Индиго';

  @override
  String get accentOlive => 'Оливковый';

  @override
  String get accentPlum => 'Слива';

  @override
  String get accountConnectedServices => 'Подключённые сервисы';

  @override
  String get accountEmail => 'Почта';

  @override
  String get accountNameUnset => 'Не задано';

  @override
  String get accountProfile => 'Профиль';

  @override
  String get accountPublicId => 'Ваш код';

  @override
  String get accountPublicIdCopied => 'Код скопирован';

  @override
  String addedToPlaylist(String name) {
    return 'Добавлено в «$name»';
  }

  @override
  String get addToPlaylistCreate => 'Создать новый';

  @override
  String get addToPlaylistEmpty =>
      'Своих плейлистов пока нет. Создайте первый — трек попадёт в него сразу.';

  @override
  String get addToPlaylistTitle => 'Добавить в плейлист';

  @override
  String addTracksAddCount(int count) {
    return 'Добавить ($count)';
  }

  @override
  String addTracksAdded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count трека',
      many: '$count треков',
      few: '$count трека',
      one: '$count трек',
    );
    return 'Добавлено $_temp0';
  }

  @override
  String addTracksAddedWithSkipped(String base, int skipped) {
    return '$base, $skipped уже было';
  }

  @override
  String get addTracksAllPresent => 'Все выбранные треки уже в плейлисте';

  @override
  String get addTracksAlreadyIn => 'Уже в плейлисте';

  @override
  String get addTracksBackToPlaylists => 'К списку плейлистов';

  @override
  String get addTracksDeselect => 'Снять';

  @override
  String get addTracksEmptyPlaylist => 'В этом плейлисте нет треков.';

  @override
  String get addTracksForeignPlaylist =>
      'Spotify не отдаёт содержимое этого плейлиста — доступны только ваши собственные и совместные.';

  @override
  String get addTracksFromPlaylist => 'Из плейлиста';

  @override
  String get addTracksNoOtherPlaylists =>
      'Других плейлистов пока нет — брать треки не из чего.';

  @override
  String get addTracksNothingFound =>
      'Ничего не нашлось. Попробуйте другой запрос.';

  @override
  String get addTracksSearch => 'Поиск';

  @override
  String get addTracksSearchEmpty =>
      'Найдите трек в Spotify и добавьте его в плейлист.';

  @override
  String get addTracksSearchHint => 'Название трека или исполнитель';

  @override
  String get addTracksSelectAll => 'Выбрать всё';

  @override
  String addTracksToPlaylist(String name) {
    return 'Добавить в «$name»';
  }

  @override
  String get addTracksYourPlaylist => 'Ваш плейлист';

  @override
  String alreadyInPlaylist(String name) {
    return 'Уже в «$name»';
  }

  @override
  String get appearanceAccent => 'Цвет акцента';

  @override
  String get appearanceArtworkBackground => 'Фон по обложке';

  @override
  String get appearanceArtworkBackgroundHint =>
      'Свечение в цвет обложки на экране плеера';

  @override
  String get appearanceCompact => 'Компактный режим';

  @override
  String get appearanceCompactHint =>
      'Плотнее списки — на экран помещается больше';

  @override
  String get appearanceDensityGroup => 'Плотность и движение';

  @override
  String get appearanceLanguage => 'Язык';

  @override
  String get appearanceLanguageHint =>
      'Язык интерфейса на всех ваших устройствах';

  @override
  String get appearanceReduceMotion => 'Меньше анимации';

  @override
  String get appearanceReduceMotionHint =>
      'Переходы без движения — если оно мешает или укачивает';

  @override
  String get appearanceReset => 'Сбросить оформление';

  @override
  String get appearanceResetDone => 'Оформление сброшено';

  @override
  String get appearanceResetHint =>
      'Вернуть тему, цвет, текст, плотность и стартовую вкладку';

  @override
  String get appearanceStartTab => 'С чего начинать';

  @override
  String get appearanceStartTabHint =>
      'Вкладка, которая открывается при запуске';

  @override
  String get appearanceTextSize => 'Размер текста';

  @override
  String get appearanceTheme => 'Тема';

  @override
  String get appTitle => 'SyncM';

  @override
  String get avatarBadFormat =>
      'Неподдерживаемый формат. Разрешены: PNG, JPG, JPEG, GIF, WEBP';

  @override
  String get avatarReadFailed => 'Не удалось прочитать файл';

  @override
  String get avatarUpdated => 'Аватарка обновлена';

  @override
  String get blockedEmptyMessage =>
      'Заблокировать можно из профиля человека или из списка друзей.';

  @override
  String get blockedEmptyTitle => 'Никто не заблокирован';

  @override
  String get blockedHint =>
      'Эти люди не найдут вас в поиске и не смогут отправить заявку или позвать в сессию. Они об этом не узнают.';

  @override
  String blockedPeopleCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count человека',
      many: '$count человек',
      few: '$count человека',
      one: '$count человек',
    );
    return '$_temp0';
  }

  @override
  String get blockedUnblock => 'Разблокировать';

  @override
  String blockedUnblocked(String name) {
    return '$name разблокирован';
  }

  @override
  String get blockedUnblockFailed => 'Не удалось разблокировать';

  @override
  String cacheFriendsCount(int count) {
    return 'друзей: $count';
  }

  @override
  String cacheInMemory(String size) {
    return 'В памяти: $size';
  }

  @override
  String cacheOnDisk(String disk, String memory) {
    return 'На диске: $disk · в памяти: $memory';
  }

  @override
  String cacheSessionsCount(int count) {
    return 'сессий: $count';
  }

  @override
  String clockSummary(String offset, int ping) {
    return 'Часы: $offset мс · пинг: $ping мс';
  }

  @override
  String get commonBack => 'Назад';

  @override
  String get commonCancel => 'Отмена';

  @override
  String get commonClear => 'Очистить';

  @override
  String get commonClose => 'Закрыть';

  @override
  String get commonCollapse => 'Свернуть';

  @override
  String get commonCreate => 'Создать';

  @override
  String get commonDelete => 'Удалить';

  @override
  String get commonEmpty => 'Пусто';

  @override
  String get commonFinish => 'Завершить';

  @override
  String get commonFriends => 'Друзья';

  @override
  String get commonJustNow => 'только что';

  @override
  String get commonLoadMore => 'Загрузить ещё';

  @override
  String get commonLongAgo => 'давно';

  @override
  String get commonMore => 'Ещё';

  @override
  String commonMoreCount(int count) {
    return 'Ещё $count';
  }

  @override
  String get commonName => 'Имя';

  @override
  String get commonNobody => 'Никто';

  @override
  String get commonNoName => 'Без имени';

  @override
  String get commonOpen => 'Открыть';

  @override
  String get commonOr => ' или ';

  @override
  String get commonRefresh => 'Обновить';

  @override
  String get commonReset => 'Сбросить';

  @override
  String get commonSave => 'Сохранить';

  @override
  String get commonSignOut => 'Выйти';

  @override
  String get commonSystem => 'Система';

  @override
  String get commonUser => 'Пользователь';

  @override
  String get createSessionFailed => 'Не удалось создать сессию';

  @override
  String get createSessionFriendsOnly => 'Сессию можно создать только с другом';

  @override
  String get createSessionFriendsOnlyHint =>
      'Добавьте кого-нибудь в друзья, и он появится в этом списке.';

  @override
  String get createSessionHint =>
      'Пригласите друга и слушайте музыку одновременно.';

  @override
  String get createSessionName => 'Название сессии';

  @override
  String get createSessionNobodyFound => 'Никого с таким именем';

  @override
  String get createSessionPickFriend => 'Выберите друга, чтобы продолжить';

  @override
  String get createSessionSearchFriends => 'Поиск среди друзей';

  @override
  String get createSessionWithWhom => 'С кем слушаем';

  @override
  String get cropDone => 'Готово';

  @override
  String get cropFailed => 'Не удалось обработать изображение';

  @override
  String get cropHint =>
      'Область всегда квадратная — так аватар выглядит одинаково везде.';

  @override
  String get cropNoImageData => 'Не удалось получить данные изображения';

  @override
  String get cropRotateLeft => 'Влево';

  @override
  String get cropRotateRight => 'Вправо';

  @override
  String get cropTitle => 'Кадрирование';

  @override
  String get dataExport => 'Выгрузить мои данные';

  @override
  String get dataExportHint =>
      'Профиль, друзья, плейлисты и история одним файлом';

  @override
  String get dataHistoryHint => 'Посмотреть и очистить';

  @override
  String get dataImageCache => 'Кэш изображений';

  @override
  String get dataImageCacheCleared => 'Кэш изображений очищен';

  @override
  String get dataNothingSaved => 'Пока ничего не сохранено';

  @override
  String get dataOnServer => 'На сервере';

  @override
  String get dataOnThisDevice => 'На этом устройстве';

  @override
  String get dataPrefetch => 'Загружать данные при запуске';

  @override
  String get dataPrefetchHint =>
      'Списки друзей и сессий готовы к моменту открытия вкладки';

  @override
  String get dataSavedLists => 'Сохранённые списки';

  @override
  String get dataSavedListsCleared => 'Списки очищены';

  @override
  String get dataUpdatedJustNow => 'обновлено только что';

  @override
  String get dataWhatIsStored => 'Что хранится о вас';

  @override
  String get dataWhatIsStoredHint => 'Список данных и как их удалить';

  @override
  String daysAgoShort(int count) {
    return '$count дн. назад';
  }

  @override
  String get deleteAccountMessage =>
      'Профиль, друзья и история сессий будут удалены безвозвратно. Это действие нельзя отменить.';

  @override
  String get devicesApp => 'Приложение SyncM';

  @override
  String get devicesBrowser => 'Браузер';

  @override
  String get devicesCurrent => 'Это устройство';

  @override
  String get devicesEmptyMessage =>
      'Список пуст — похоже, связь с сервером потерялась. Попробуйте открыть экран заново.';

  @override
  String get devicesEmptyTitle => 'Активных сеансов нет';

  @override
  String devicesEndAgainMessage(String device) {
    return 'На «$device» придётся входить заново.';
  }

  @override
  String get devicesEndSessionTitle => 'Завершить сеанс?';

  @override
  String get devicesHint =>
      'Здесь показаны приложения и браузеры, где выполнен вход. Если видите незнакомое устройство — завершите его сеанс.';

  @override
  String get devicesSessionEnded => 'Сеанс завершён';

  @override
  String get devicesSignOutThisDeviceTitle => 'Выйти на этом устройстве?';

  @override
  String get devicesTimeUnknown => 'Время неизвестно';

  @override
  String get devicesTitle => 'Устройства';

  @override
  String get devicesYesterday => 'Вчера';

  @override
  String durationHours(int count) {
    return '$count ч';
  }

  @override
  String durationMinutes(int count) {
    return '$count мин';
  }

  @override
  String get errorBadResponse =>
      'Сервер вернул неожиданный ответ. Попробуйте обновить.';

  @override
  String get errorConflict => 'Действие уже выполняется или невозможно сейчас.';

  @override
  String get errorConnectionDropped =>
      'Соединение прервалось. Попробуйте ещё раз.';

  @override
  String get errorForbidden => 'Недостаточно прав для этого действия.';

  @override
  String get errorGeneric => 'Что-то пошло не так.';

  @override
  String get errorGenericRetry => 'Что-то пошло не так. Попробуйте снова.';

  @override
  String get errorGoogleFailed =>
      'Не удалось войти через Google. Попробуйте ещё раз.';

  @override
  String get errorGoogleMisconfigured =>
      'Вход через Google настроен неверно. Сообщите разработчику.';

  @override
  String get errorGoogleUnreachable =>
      'Не удалось связаться с Google. Проверьте соединение.';

  @override
  String get errorHandshake => 'Не удалось установить защищённое соединение.';

  @override
  String get errorNetwork => 'Ошибка сети. Проверьте соединение.';

  @override
  String get errorNoInternet => 'Нет подключения к интернету. Проверьте сеть.';

  @override
  String get errorNotFound => 'Не найдено.';

  @override
  String get errorServerFailure =>
      'Ошибка на сервере. Мы уже знаем о проблеме.';

  @override
  String get errorServerSlow => 'Сервер долго не отвечает. Попробуйте позже.';

  @override
  String get errorServerUnavailable =>
      'Сервер временно недоступен. Попробуйте через минуту.';

  @override
  String get errorServerUnreachable =>
      'Не удалось связаться с сервером. Проверьте соединение.';

  @override
  String get errorSessionExpired => 'Сессия истекла. Войдите заново.';

  @override
  String get errorSignInCancelled => 'Вход отменён';

  @override
  String get errorTooManyRequests =>
      'Слишком много запросов. Немного подождите.';

  @override
  String exportSaved(String path) {
    return 'Файл сохранён: $path';
  }

  @override
  String get foregroundChannelDescription =>
      'Показывается, пока идёт совместное прослушивание, чтобы синхронизация не прерывалась.';

  @override
  String get foregroundChannelName => 'Активная сессия SyncM';

  @override
  String get foregroundText => 'Слушаете вместе с друзьями';

  @override
  String get foregroundTitle => 'Сессия SyncM активна';

  @override
  String get friendActions => 'Действия';

  @override
  String get friendBlock => 'Заблокировать';

  @override
  String friendLastSeen(String when) {
    return 'Был(а) в сети $when';
  }

  @override
  String get friendOffline => 'Не в сети';

  @override
  String get friendOnline => 'В сети';

  @override
  String get friendOpenProfile => 'Открыть профиль';

  @override
  String get friendRemove => 'Удалить из друзей';

  @override
  String friendsBlocked(String name) {
    return '$name заблокирован';
  }

  @override
  String get friendsBlockFailed => 'Не удалось заблокировать';

  @override
  String get friendsBlockMessage =>
      'Он не найдёт вас в поиске, не сможет отправить заявку или позвать в сессию. Дружба будет удалена. Уведомления он не получит.';

  @override
  String friendsBlockTitle(String name) {
    return 'Заблокировать $name?';
  }

  @override
  String get friendsEmptyMessage =>
      'С другом можно слушать музыку одновременно — где бы вы ни были.';

  @override
  String get friendsEmptyTitle => 'Добавьте друзей';

  @override
  String friendsRemoved(String name) {
    return '$name удалён из друзей';
  }

  @override
  String get friendsRemoveFailed => 'Не удалось удалить друга';

  @override
  String friendsRemoveMessage(String name) {
    return '$name пропадёт из вашего списка друзей.';
  }

  @override
  String get friendsRemoveTitle => 'Удалить из друзей?';

  @override
  String hiddenList(String items) {
    return 'Скрыто: $items';
  }

  @override
  String get historyClear => 'Очистить';

  @override
  String get historyCleared => 'История очищена';

  @override
  String get historyClearFailed => 'Не удалось очистить историю';

  @override
  String get historyClearMessage =>
      'Записи о прослушанных треках будут удалены.';

  @override
  String get historyClearTitle => 'Очистить историю?';

  @override
  String get historyEmptyMessage =>
      'Здесь появятся треки, которые вы включали в SyncM.';

  @override
  String get historyEmptyTitle => 'История пуста';

  @override
  String get historyJustNow => 'только что';

  @override
  String get historyTitle => 'История';

  @override
  String get historyUntitled => 'Без названия';

  @override
  String get historyYesterday => 'вчера';

  @override
  String get homeAnotherSession => 'Ещё одна сессия';

  @override
  String get homeConnectSpotify => 'Подключить Spotify';

  @override
  String get homeCreatePlaylist => 'Создать плейлист';

  @override
  String get homeDarkTheme => 'Тёмная тема';

  @override
  String get homeFilterAll => 'Все';

  @override
  String get homeFilterFriend => 'Друг';

  @override
  String get homeFilterMine => 'Мои';

  @override
  String get homeFriendRequests => 'Заявки в друзья';

  @override
  String get homeInvitedYou => 'Вас зовут';

  @override
  String homeInviteFrom(String name) {
    return 'От $name';
  }

  @override
  String get homeLightTheme => 'Светлая тема';

  @override
  String get homeListenTogether => 'Слушайте вместе';

  @override
  String get homeListenTogetherHint =>
      'Позовите друга — музыка пойдёт у вас одновременно, где бы вы ни были.';

  @override
  String get homeNoOwnPlaylists => 'Своих плейлистов пока нет';

  @override
  String get homeNoOwnPlaylistsHint =>
      'Соберите первый — и его можно будет включить в сессии.';

  @override
  String get homeNoSpotifyPlaylists => 'Нет доступных плейлистов';

  @override
  String get homeNoSpotifyPlaylistsHint =>
      'В Spotify не нашлось плейлистов, которые SyncM может открыть.';

  @override
  String get homeNothingPlaying => 'Ничего не играет';

  @override
  String get homeNothingPlayingHint =>
      'Выберите трек из плейлиста — управление появится здесь.';

  @override
  String get homeNowListening => 'Сейчас слушаете';

  @override
  String get homePlaylist => 'Плейлист';

  @override
  String get homeSearchFriends => 'Поиск друзей';

  @override
  String get homeSession => 'Сессия';

  @override
  String get homeSpotifyUnavailable => 'Плейлисты Spotify недоступны';

  @override
  String get homeSpotifyUnavailableHint =>
      'Подключите аккаунт Spotify, чтобы видеть здесь свою библиотеку.';

  @override
  String get homeStartSession => 'Начать сессию';

  @override
  String get homeTapToOpen => 'Нажмите, чтобы открыть';

  @override
  String hoursAgoShort(int count) {
    return '$count ч. назад';
  }

  @override
  String get invitesAccepted => 'Приглашение принято';

  @override
  String get inviteScopeFriendsHint =>
      'Позвать может только тот, кто у вас в друзьях';

  @override
  String get inviteScopeNobodyHint => 'Никто не сможет позвать вас в сессию';

  @override
  String invitesCount(int count) {
    return 'Приглашения · $count';
  }

  @override
  String get invitesDeclined => 'Приглашение отклонено';

  @override
  String get invitesEmptyMessage =>
      'Друг позовёт, приглашение появится здесь. Можно и не ждать: начните сессию сами.';

  @override
  String get invitesEmptyTitle => 'Приглашений пока нет';

  @override
  String invitesNotification(String name) {
    return 'Приглашение в сессию «$name»';
  }

  @override
  String get invitesReplyFailed => 'Не удалось ответить на приглашение';

  @override
  String get invitesTitle => 'Приглашения';

  @override
  String invitesWaiting(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count приглашения ждут ответа',
      many: '$count приглашений ждут ответа',
      few: '$count приглашения ждут ответа',
      one: 'Одно приглашение ждёт ответа',
    );
    return '$_temp0';
  }

  @override
  String latencyMilliseconds(int value) {
    return '$value мс';
  }

  @override
  String get latencySpeaker => 'Колонка';

  @override
  String get latencyTitle => 'Задержка звука';

  @override
  String get latencyWired => 'Провод';

  @override
  String get legalCopyText => 'Скопировать текст';

  @override
  String get legalOpenFailed => 'Не удалось открыть документ.';

  @override
  String legalOpenFailedDetails(String error) {
    return 'Не удалось открыть документ в браузере: $error';
  }

  @override
  String get legalTextCopied => 'Текст скопирован';

  @override
  String get loginBrowser => 'Войти через браузер';

  @override
  String get loginDoneCloseTab => 'Вход выполнен! Вкладку можно закрыть.';

  @override
  String get loginGoogle => 'Войти через Google';

  @override
  String get loginGoogleNoToken =>
      'Ошибка: не удалось получить ID токен от Google';

  @override
  String get loginHint =>
      'Войдите через Google, чтобы создавать сессии и слушать музыку вместе.';

  @override
  String get loginSubtitle => 'Музыка для друзей';

  @override
  String get loginTagline =>
      'Слушайте одну музыку одновременно — где бы вы ни были.';

  @override
  String get loginTitle => 'Вход';

  @override
  String minutesAgoShort(int count) {
    return '$count мин. назад';
  }

  @override
  String get nameDialogCharset => 'Только буквы, цифры, пробел и знаки . _ -';

  @override
  String get nameDialogEmpty => 'Введите имя';

  @override
  String get nameDialogHint =>
      'Это имя видят друзья — в списке, в сессиях и в приглашениях.';

  @override
  String get nameDialogTitle => 'Как вас зовут?';

  @override
  String nameDialogTooLong(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count символов',
      many: '$count символов',
      few: '$count символов',
      one: '$count символа',
    );
    return 'Не более $_temp0';
  }

  @override
  String nameDialogTooShort(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count символа',
      many: '$count символов',
      few: '$count символа',
      one: '$count символ',
    );
    return 'Минимум $_temp0';
  }

  @override
  String get nameUpdated => 'Имя обновлено';

  @override
  String get navFindFriends => 'Найти друзей';

  @override
  String get navLibrary => 'Библиотека';

  @override
  String get navLikedTracks => 'Любимые треки';

  @override
  String get navNewSession => 'Новая сессия';

  @override
  String get navQuick => 'Быстро';

  @override
  String get notificationsAllOff => 'Карточки выключены';

  @override
  String get notificationsAllOn => 'Все карточки включены';

  @override
  String get notificationsFriendRequests => 'Заявки в друзья';

  @override
  String get notificationsFriendRequestsHint => 'Карточка, когда вас добавляют';

  @override
  String get notificationsGroup => 'Всплывающие карточки';

  @override
  String get notificationsHint =>
      'Настройки общие для всех ваших устройств. Сами заявки и приглашения продолжают приходить — выключается только карточка поверх экрана.';

  @override
  String get notificationsOffInvites => 'приглашения';

  @override
  String notificationsOffOne(String what) {
    return 'Выключено: $what';
  }

  @override
  String get notificationsOffRequests => 'заявки';

  @override
  String get notificationsSessionInvites => 'Приглашения в сессию';

  @override
  String get notificationsSessionInvitesHint =>
      'Карточка, когда друг зовёт слушать вместе';

  @override
  String pickPlaylistAddAll(int count) {
    return 'Добавить все ($count)';
  }

  @override
  String pickPlaylistAddSelected(int count) {
    return 'Добавить выбранные ($count)';
  }

  @override
  String pickPlaylistDeselectCount(int count) {
    return 'Снять ($count)';
  }

  @override
  String get pickPlaylistEmptyPlaylist => 'В плейлисте нет треков';

  @override
  String pickPlaylistInPlaylist(int count) {
    return '$count в плейлисте';
  }

  @override
  String get pickPlaylistNoPlaylists => 'Плейлистов нет';

  @override
  String get pickPlaylistNoPlaylistsHint =>
      'Подключите Spotify или создайте свой плейлист, чтобы добавлять треки в сессии.';

  @override
  String get pickPlaylistNoSession => 'Не удалось определить сессию';

  @override
  String get pickPlaylistNoTracks => 'Треков нет';

  @override
  String get pickPlaylistNoTracksHint =>
      'Этот плейлист пуст либо его содержимое недоступно: Spotify отдаёт треки только для ваших собственных плейлистов.';

  @override
  String get pickPlaylistTitle => 'Выберите плейлист';

  @override
  String get playbackAllowBackground => 'Разрешить работу в фоне';

  @override
  String get playbackAllowBackgroundHint =>
      'Чтобы синхронизация не прерывалась при погашенном экране';

  @override
  String get playbackAutostart => 'Настроить автозапуск';

  @override
  String get playbackAutostartHint =>
      'На Xiaomi и Redmi без этого система закрывает приложение';

  @override
  String get playbackAutostartHint2 =>
      'Откройте настройки приложения и включите автозапуск вручную';

  @override
  String get playbackBackgroundGroup => 'Фоновый режим';

  @override
  String get playbackClockSync => 'Сверить часы с сервером';

  @override
  String get playbackClockSyncStarted => 'Часы синхронизируются заново';

  @override
  String get playbackClockUnknown =>
      'Ещё не измерено — нажмите, чтобы обновить';

  @override
  String get playbackConnections => 'Подключения';

  @override
  String get playbackOpenSpotifyHint =>
      'Откройте Spotify и запустите любой трек, затем повторите.';

  @override
  String get playbackPermissionsHint => 'Проверьте разрешения в системном окне';

  @override
  String get playbackQualityGroup => 'Качество звука';

  @override
  String get playbackServerLink => 'Связь с сервером';

  @override
  String get playbackServerOffline => 'Нет связи. Проверьте интернет';

  @override
  String get playbackServerOnline => 'На связи — события сессии приходят сразу';

  @override
  String get playbackSpotifyConnected => 'Подключён — можно запускать треки';

  @override
  String get playbackSpotifyConnectFailed =>
      'Не удалось подключиться к Spotify';

  @override
  String get playbackSpotifyDevice => 'Spotify на устройстве';

  @override
  String get playbackSpotifyDisconnected =>
      'Не подключён. Нажмите, чтобы связаться с приложением Spotify';

  @override
  String get playbackSpotifySettings => 'Настройки Spotify';

  @override
  String get playbackSpotifySettingsHint =>
      'Качество, кроссфейд и громкость задаются в приложении Spotify';

  @override
  String get playbackSpotifySettingsPath =>
      'Откройте Spotify → Настройки → Качество звука';

  @override
  String get playbackSyncGroup => 'Синхронизация';

  @override
  String get playerNext => 'Следующий трек';

  @override
  String get playerNowPlayingLabel => 'СЕЙЧАС ИГРАЕТ';

  @override
  String get playerPause => 'Пауза';

  @override
  String get playerPlay => 'Воспроизвести';

  @override
  String get playerPrevious => 'Предыдущий трек';

  @override
  String get playerRepeatAll => 'Повтор списка';

  @override
  String get playerRepeatOff => 'Повтор выключен';

  @override
  String get playerRepeatOne => 'Повтор одного трека';

  @override
  String get playerShuffle => 'Перемешать';

  @override
  String get playerShuffleOn => 'Перемешивание включено';

  @override
  String get playerUnknownTrack => 'Неизвестный трек';

  @override
  String get playlistActionsTitle => 'Действия с плейлистом';

  @override
  String get playlistAddMusic => 'Добавить музыку';

  @override
  String get playlistChangeCover => 'Изменить обложку';

  @override
  String get playlistClear => 'Очистить плейлист';

  @override
  String get playlistCleared => 'Плейлист очищен';

  @override
  String playlistClearMessage(String name) {
    return 'Из «$name» будут удалены все треки. Сам плейлист останется.';
  }

  @override
  String get playlistClearTitle => 'Очистить плейлист?';

  @override
  String get playlistConnectSpotifyHint =>
      'Подключите Spotify аккаунт в профиле';

  @override
  String playlistCopyCreated(String name) {
    return 'Создана копия «$name»';
  }

  @override
  String get playlistCoverHint =>
      'Обложка квадратная — так плейлисты выглядят ровно в списке.';

  @override
  String get playlistCoverRemoved => 'Обложка убрана';

  @override
  String get playlistCoverTitle => 'Обложка плейлиста';

  @override
  String get playlistCoverUpdated => 'Обложка обновлена';

  @override
  String get playlistDelete => 'Удалить плейлист';

  @override
  String get playlistDeleted => 'Плейлист удалён';

  @override
  String playlistDeleteMessage(String name) {
    return '«$name» и его список треков будут удалены. Сами треки останутся в Spotify.';
  }

  @override
  String get playlistDeleteTitle => 'Удалить плейлист?';

  @override
  String get playlistDuplicate => 'Дублировать';

  @override
  String get playlistEdit => 'Изменить плейлист';

  @override
  String get playlistEditNameDescription => 'Изменить название и описание';

  @override
  String get playlistEmptyMessage =>
      'Найдите музыку в Spotify или возьмите её из другого плейлиста.';

  @override
  String get playlistEmptyShort => 'В этом плейлисте пока пусто.';

  @override
  String get playlistEmptyTitle => 'Нет треков';

  @override
  String get playlistFieldDescription => 'Описание';

  @override
  String get playlistFieldName => 'Название';

  @override
  String get playlistFieldOptional => 'Необязательно';

  @override
  String get playlistForeign =>
      'Spotify не отдаёт содержимое чужих плейлистов — доступны только ваши собственные и совместные.';

  @override
  String get playlistLinkCopied => 'Плейлист скопирован в буфер обмена';

  @override
  String get playlistNameCharset => 'Только буквы, цифры, пробелы и ._-()';

  @override
  String get playlistNameEmpty => 'Название не может быть пустым';

  @override
  String get playlistNameEmptyGeneric => 'Введите название';

  @override
  String get playlistNameTooShort => 'Минимум 2 символа';

  @override
  String get playlistNew => 'Новый плейлист';

  @override
  String get playlistOpen => 'Открыть';

  @override
  String get playlistPlay => 'Слушать';

  @override
  String get playlistRemoveCover => 'Убрать обложку';

  @override
  String get playlistRemoveTrack => 'Удалить из плейлиста';

  @override
  String get playlistShare => 'Поделиться';

  @override
  String get playlistTrackActions => 'Действия с треком';

  @override
  String get playlistTrackRemoved => 'Трек удалён из плейлиста';

  @override
  String get previewArtistName => 'Исполнитель';

  @override
  String get previewTrackName => 'Название трека';

  @override
  String get privacyAlwaysVisible => 'Видно всегда';

  @override
  String get privacyBitActivity => 'активность';

  @override
  String get privacyBitFriends => 'друзья';

  @override
  String get privacyBitSearch => 'поиск';

  @override
  String get privacyBitStatus => 'статус';

  @override
  String get privacyBlocked => 'Заблокированные';

  @override
  String get privacyBlockedHint =>
      'Не смогут найти вас, писать и звать в сессии';

  @override
  String get privacyBlockedNobody => 'Никого нет';

  @override
  String get privacyBlockList => 'Чёрный список';

  @override
  String get privacyDetailed => 'Подробно';

  @override
  String get privacyDocFriends => 'Друзья и заявки';

  @override
  String get privacyDocFriendsText =>
      'С кем вы дружите и кому отправляли заявки. Заблокированные хранятся отдельно и никому не показываются.';

  @override
  String get privacyDocFullHint =>
      'Всё написанное выше — краткий пересказ. Полная политика конфиденциальности с формулировками и сроками хранения открывается ниже.';

  @override
  String get privacyDocFullTitle => 'Полный текст';

  @override
  String get privacyDocHistoryText =>
      'Треки, которые вы включали в приложении, и время. Её можно очистить в разделе «Данные».';

  @override
  String get privacyDocHowToDeleteText =>
      'История прослушанного очищается в разделе «Данные». Там же удаляется аккаунт целиком — вместе с профилем, друзьями, сессиями и подключением Spotify. Это необратимо.';

  @override
  String get privacyDocHowToDeleteTitle => 'Как удалить';

  @override
  String get privacyDocNoOutsideListening =>
      'Содержимое прослушивания вне приложения: что вы слушаете сами, без сессии, никуда не отправляется.';

  @override
  String get privacyDocNoPassword =>
      'Пароль от Spotify — авторизация проходит на стороне Spotify.';

  @override
  String get privacyDocNoPayments =>
      'Платёжные данные — приложение бесплатное и ничего не принимает.';

  @override
  String get privacyDocNotStoredTitle => 'Чего нет';

  @override
  String get privacyDocProfile =>
      'Имя, адрес почты и аватар. Почта нужна для входа, имя и аватар видят друзья.';

  @override
  String get privacyDocSessionsText =>
      'Названия совместных прослушиваний, их участники, добавленные треки и оценки — чтобы показать совпадения в конце.';

  @override
  String get privacyDocSpotify => 'Подключение Spotify';

  @override
  String get privacyDocSpotifyText =>
      'Идентификатор аккаунта и токены доступа — в зашифрованном виде. Пароль от Spotify приложение не видит и не получает.';

  @override
  String get privacyDocStoredHint =>
      'Список собран по тому, что приложение действительно записывает в базу.';

  @override
  String get privacyDocStoredTitle => 'Что хранится';

  @override
  String get privacyHiddenWarning =>
      'При полностью скрытом профиле друзьям сложнее понять, когда вас звать слушать вместе.';

  @override
  String get privacyHideActivity => 'Скрыть активность';

  @override
  String get privacyHideActivityHint =>
      'Что вы слушаете в сессии, не будет видно в профиле';

  @override
  String get privacyHideFriends => 'Скрыть друзей';

  @override
  String get privacyHideFriendsHint =>
      'Никто не увидит, сколько у вас друзей и кто из них общий';

  @override
  String get privacyHideOnline => 'Скрыть статус в сети';

  @override
  String get privacyHideOnlineHint =>
      'Друзья не увидят, когда вы онлайн и когда были в последний раз';

  @override
  String get privacyHideSearch => 'Скрыть из поиска';

  @override
  String get privacyHideSearchHint =>
      'Новые люди не найдут вас по имени. Друзья — увидят';

  @override
  String get privacyHistory => 'История прослушанного';

  @override
  String get privacyHistoryHint => 'Видна только вам, даже друзьям — нет';

  @override
  String get privacyNameAndAvatar => 'Имя и аватар';

  @override
  String get privacyNameAndAvatarHint =>
      'По ним друзья узнают вас в списке и в сессии';

  @override
  String get privacyNothingHidden => 'Ничего не скрыто';

  @override
  String get privacyPresetFriends => 'Только свои';

  @override
  String get privacyPresetFriendsSummary =>
      'Только свои — вас не найдут в поиске';

  @override
  String get privacyPresetHidden => 'Скрытый';

  @override
  String get privacyPresetHiddenSummary => 'Скрытый профиль';

  @override
  String get privacyPresetOpen => 'Открытый';

  @override
  String get privacyPresetOpenSummary => 'Открытый профиль';

  @override
  String get privacyQuickMode => 'Быстрый режим';

  @override
  String get privacySessionParticipation => 'Участие в общей сессии';

  @override
  String get privacySessionParticipationHint =>
      'Тот, с кем вы слушаете, видит вас и очередь треков';

  @override
  String get privacySummaryFriendCount => 'сколько у вас друзей';

  @override
  String get privacySummaryFriendsSee => 'Друзья видят';

  @override
  String get privacySummaryListening => 'что вы слушаете';

  @override
  String get privacySummaryNameAvatar => 'имя и аватар';

  @override
  String get privacySummaryNotSearchable => 'Не найдут вас в поиске';

  @override
  String get privacySummaryOnline => 'когда вы в сети';

  @override
  String get privacySummaryOthers => 'Остальные';

  @override
  String get privacySummarySearchable =>
      'Могут найти вас по имени и отправить заявку';

  @override
  String get privacyWhatIsVisible => 'Что о вас видно';

  @override
  String get profileConnectSpotify => 'Подключить Spotify';

  @override
  String get profileDisconnectSpotify => 'Отключить Spotify';

  @override
  String get profileEmpty => 'Пока пусто';

  @override
  String profileFriendsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count друга',
      many: '$count друзей',
      few: '$count друга',
      one: '$count друг',
    );
    return '$_temp0';
  }

  @override
  String get profileInCommonEmpty => 'Пока ничего общего не нашлось';

  @override
  String get profileInCommonHint => 'Из ваших любимых';

  @override
  String get profileInCommonTitle => 'Общая музыка';

  @override
  String profileInCommonTracks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count общих трека',
      many: '$count общих треков',
      few: '$count общих трека',
      one: '$count общий трек',
    );
    return '$_temp0';
  }

  @override
  String profileInSelection(int count) {
    return '$count в подборке';
  }

  @override
  String get profileLast => 'Последнее';

  @override
  String profileLikedCount(int count) {
    return '$count любимых';
  }

  @override
  String get profileLikedEmpty =>
      'Отмечайте треки сердечком — они соберутся здесь';

  @override
  String get profileLikedTracks => 'Любимые треки';

  @override
  String profileMutualCount(int count) {
    return '$count общих';
  }

  @override
  String get profileNothingShown => 'Ничего не показывается';

  @override
  String get profilePlaylistsHint => 'Ваши подборки';

  @override
  String get profilePlaylistsTitle => 'Плейлисты';

  @override
  String get profileRecentlyPlayed => 'Недавно слушали';

  @override
  String get profileRecentlyPlayedEmpty =>
      'Здесь появятся треки, которые вы включали';

  @override
  String profileSessionsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count сессии',
      many: '$count сессий',
      few: '$count сессии',
      one: '$count сессия',
    );
    return '$_temp0';
  }

  @override
  String get profileTopArtists => 'Чаще всего звучит';

  @override
  String get profileTopArtistsHint => 'По прослушанному и любимому';

  @override
  String get profileVisibleToYouOnly => 'Видно только вам';

  @override
  String get requestsAccept => 'Принять';

  @override
  String get requestsAccepted => 'Заявка принята';

  @override
  String get requestsDecline => 'Отклонить';

  @override
  String requestsDeclineMessage(String name) {
    return '$name не увидит, что вы отклонили заявку.';
  }

  @override
  String get requestsDeclineTitle => 'Отклонить заявку?';

  @override
  String get requestsEmptyMessage =>
      'Здесь появятся приглашения в друзья. Отправить свою — быстрее, чем ждать.';

  @override
  String get requestsEmptyTitle => 'Заявок пока нет';

  @override
  String requestsNotification(String name) {
    return 'Заявка в друзья от $name';
  }

  @override
  String get requestsWantsToAdd => 'Хочет добавить вас в друзья';

  @override
  String get resultsBackHome => 'На главную';

  @override
  String get resultsMatches => 'Совпадения';

  @override
  String get resultsMatchesHint => 'Эти треки понравились обоим.';

  @override
  String get resultsNoMatches => 'Совпадений нет';

  @override
  String get resultsNoMatchesHint =>
      'В этот раз вкусы разошлись. Попробуйте ещё одну сессию — с другой подборкой результат может быть иным.';

  @override
  String get resultsTitle => 'Итоги сессии';

  @override
  String get searchEmptyMessage =>
      'Введите имя или код из восьми символов. Свой код можно посмотреть в настройках, в разделе «Аккаунт».';

  @override
  String get searchEmptyTitle => 'Найдите друзей';

  @override
  String get searchFieldHint => 'Имя или код';

  @override
  String get searchNothingFound => 'Никого не нашлось';

  @override
  String get searchNothingFoundHint =>
      'Проверьте написание. По коду человек находится, даже если скрыл себя из поиска.';

  @override
  String get searchRequestSent => 'Заявка отправлена';

  @override
  String get searchSendRequest => 'Отправить заявку';

  @override
  String get searchStatusFriends => 'В друзьях';

  @override
  String get searchStatusSent => 'Отправлено';

  @override
  String get searchStatusWaiting => 'Ждёт ответа';

  @override
  String get sectionAbout => 'О приложении';

  @override
  String get sectionAccount => 'Аккаунт';

  @override
  String get sectionAppearance => 'Оформление';

  @override
  String get sectionData => 'Данные';

  @override
  String get sectionNotifications => 'Уведомления';

  @override
  String get sectionPlayback => 'Воспроизведение';

  @override
  String get sectionPrivacy => 'Приватность';

  @override
  String get sectionSecurity => 'Безопасность';

  @override
  String get sectionSessions => 'Сессии';

  @override
  String get securityDangerZone => 'Опасная зона';

  @override
  String get securityDeleteAccount => 'Удалить аккаунт';

  @override
  String get securityDeleteAccountHint =>
      'Безвозвратно удалит профиль, друзей и историю сессий';

  @override
  String get securityDeleteAccountTitle => 'Удалить аккаунт?';

  @override
  String get securityDevices => 'Устройства';

  @override
  String get securityDevicesHint => 'Где выполнен вход, и как завершить лишнее';

  @override
  String get securitySessionsGroup => 'Сеансы';

  @override
  String get securitySignInGoogle => 'Через Google';

  @override
  String get securitySignInMethod => 'Способ входа';

  @override
  String get securitySignInSpotifyGoogle => 'Через Spotify или Google';

  @override
  String get securitySignOutEverywhere => 'Выйти со всех устройств';

  @override
  String get securitySignOutEverywhereConfirm => 'Выйти везде';

  @override
  String get securitySignOutEverywhereHint =>
      'Завершит все сеансы, включая этот';

  @override
  String get securitySignOutEverywhereMessage =>
      'Все сеансы завершатся, включая этот. Так стоит поступить, если в списке есть чужое устройство.';

  @override
  String get securitySignOutEverywhereTitle => 'Выйти со всех устройств?';

  @override
  String get securitySignOutMessage =>
      'Придётся войти заново, чтобы вернуться.';

  @override
  String get securitySignOutThisDevice => 'Только на этом устройстве';

  @override
  String get securitySignOutTitle => 'Выйти из аккаунта?';

  @override
  String get sessionAddTracks => 'Добавить треки';

  @override
  String get sessionAdjusting => 'Подстраиваемся';

  @override
  String get sessionAlreadyRated => 'Второй участник уже оценил';

  @override
  String get sessionDislike => 'Не нравится';

  @override
  String get sessionEndAction => 'Завершить сессию';

  @override
  String sessionEndMessage(String name) {
    return '«$name» закроется у всех участников.';
  }

  @override
  String get sessionEndMessagePlain =>
      'Сессия будет закрыта для всех участников.';

  @override
  String get sessionHostChanged => 'Ведущий сессии сменился';

  @override
  String sessionInQueue(int count) {
    return '$count в очереди';
  }

  @override
  String get sessionInSync => 'Звучит одновременно';

  @override
  String get sessionLike => 'Нравится';

  @override
  String get sessionNoTracksYet => 'Пока без треков';

  @override
  String get sessionNotStarted => 'Сессия не запущена';

  @override
  String get sessionParticipant => 'Участник';

  @override
  String get sessionQueueEmpty => 'Очередь пуста';

  @override
  String get sessionQueueEmptyHint =>
      'Добавьте треки из своих плейлистов — их услышат все участники.';

  @override
  String get sessionsActive => 'Активные сессии';

  @override
  String sessionsActiveCount(int count) {
    return 'Активные сессии · $count';
  }

  @override
  String get sessionsAutoOpenPlayer => 'Открывать плеер при запуске';

  @override
  String get sessionsAutoOpenPlayerHint =>
      'Полноэкранный плеер, когда трек пошёл';

  @override
  String get sessionsBlockedHint => 'Они не смогут позвать вас в сессию';

  @override
  String get sessionsConfirmEnd => 'Спрашивать перед завершением';

  @override
  String get sessionsConfirmEndHint =>
      'Подтверждение, чтобы не закрыть сессию случайно';

  @override
  String get sessionsDuringGroup => 'Во время сессии';

  @override
  String get sessionsEnded => 'Сессия завершена';

  @override
  String get sessionsEndTitle => 'Завершить сессию?';

  @override
  String get sessionsKeepScreenOn => 'Не гасить экран';

  @override
  String get sessionsKeepScreenOnHint =>
      'Экран остаётся включённым, пока идёт сессия';

  @override
  String get sessionsNothingPlaying => 'Сейчас ничего не идёт';

  @override
  String get sessionsNothingPlayingHint => 'Начатые сессии появятся здесь';

  @override
  String get sessionsOneInvite => 'Одно приглашение ждёт ответа';

  @override
  String get sessionsOpenList => 'Открыть список';

  @override
  String get sessionsRunningNow => 'Идёт сейчас';

  @override
  String get sessionsWhoCanInvite => 'Кто может звать';

  @override
  String get sessionWaitingForSecond => 'Ждём второго';

  @override
  String get sessionYouAreHost => 'Вы теперь ведущий сессии';

  @override
  String get settingsGroupApp => 'Приложение';

  @override
  String get settingsGroupData => 'Данные и приватность';

  @override
  String get settingsGroupProfile => 'Профиль и доступ';

  @override
  String get settingsTitle => 'Настройки';

  @override
  String sizeBytes(int value) {
    return '$value Б';
  }

  @override
  String sizeKilobytes(int value) {
    return '$value КБ';
  }

  @override
  String sizeMegabytes(String value) {
    return '$value МБ';
  }

  @override
  String get spotifyCheck => 'Проверить';

  @override
  String get spotifyCheckFailed => 'Не удалось проверить подключение';

  @override
  String get spotifyChecking => 'Проверяем подключение…';

  @override
  String get spotifyConnect => 'Подключить';

  @override
  String get spotifyConnected => 'Подключён';

  @override
  String spotifyConnectedAs(String name) {
    return 'Подключён · $name';
  }

  @override
  String get spotifyConnectedShort => 'Spotify подключён';

  @override
  String get spotifyDisconnect => 'Отключить';

  @override
  String get spotifyDisconnectMessage =>
      'Плейлисты и совместное прослушивание перестанут работать, пока вы не подключите его снова.';

  @override
  String get spotifyDisconnectTitle => 'Отключить Spotify?';

  @override
  String get spotifyLikedEmpty =>
      'Здесь появятся треки, которые вы сохраните в Spotify.';

  @override
  String get spotifyLikedSubtitle => 'Сохранённые в Spotify';

  @override
  String get spotifyLikedTitle => 'Любимые треки';

  @override
  String get spotifyLinkBusy =>
      'Не удалось начать подключение: предыдущая попытка ещё не завершилась. Подождите несколько секунд и попробуйте снова.';

  @override
  String get spotifyLinked => 'Spotify подключён';

  @override
  String get spotifyNeedsReauth =>
      'Доступ отозван или истёк — подключите заново';

  @override
  String get spotifyNotConnected => 'Не подключён';

  @override
  String get spotifyNotConnectedShort => 'Spotify не подключён';

  @override
  String get spotifyReconnect => 'Переподключить';

  @override
  String get spotifyUnlinked => 'Spotify отключён';

  @override
  String get spotifyWebviewTitle => 'Подключение Spotify';

  @override
  String get summaryAbout => 'Версия • Приватность • Условия';

  @override
  String get summaryData => 'Кэш • История • Выгрузка';

  @override
  String get summaryPlayback => 'Подключения • Задержка звука • Фон';

  @override
  String get summarySecurity => 'Устройства • Выход • Удаление аккаунта';

  @override
  String get summarySessions => 'Активные • Приглашения • Кто может звать';

  @override
  String get tabMusic => 'Музыка';

  @override
  String get tabNow => 'Сейчас';

  @override
  String get themeDark => 'Тёмная';

  @override
  String get themeLight => 'Светлая';

  @override
  String get themeSystem => 'Как в системе';

  @override
  String trackCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count трека',
      many: '$count треков',
      few: '$count трека',
      one: '$count трек',
    );
    return '$_temp0';
  }

  @override
  String get trackLike => 'В любимые';

  @override
  String get trackUnlike => 'Убрать из любимых';

  @override
  String updatedDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count дня',
      many: '$count дней',
      few: '$count дня',
      one: '$count день',
    );
    return 'обновлено $_temp0 назад';
  }

  @override
  String updatedHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count часа',
      many: '$count часов',
      few: '$count часа',
      one: '$count час',
    );
    return 'обновлено $_temp0 назад';
  }

  @override
  String updatedMinutesAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count минуты',
      many: '$count минут',
      few: '$count минуты',
      one: '$count минуту',
    );
    return 'обновлено $_temp0 назад';
  }
}
