// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class LEn extends L {
  LEn([String locale = 'en']) : super(locale);

  @override
  String get aboutDataPrivacy => 'Data and privacy';

  @override
  String get aboutDataPrivacyHint => 'What the app stores and how to delete it';

  @override
  String get aboutLegalGroup => 'Data and rules';

  @override
  String get aboutPrivacyPolicy => 'Privacy policy';

  @override
  String get aboutTerms => 'Terms of use';

  @override
  String get aboutTermsHint => 'The rules for using the app';

  @override
  String aboutVersion(String version) {
    return 'Version $version';
  }

  @override
  String get accentAmber => 'Amber';

  @override
  String get accentClay => 'Clay';

  @override
  String get accentIndigo => 'Indigo';

  @override
  String get accentOlive => 'Olive';

  @override
  String get accentPlum => 'Plum';

  @override
  String get accountConnectedServices => 'Connected services';

  @override
  String get accountEmail => 'Email';

  @override
  String get accountNameUnset => 'Not set';

  @override
  String get accountProfile => 'Profile';

  @override
  String get accountPublicId => 'Your code';

  @override
  String get accountPublicIdCopied => 'Code copied';

  @override
  String addedToPlaylist(String name) {
    return 'Added to “$name”';
  }

  @override
  String get addToPlaylistCreate => 'Create a new one';

  @override
  String get addToPlaylistEmpty =>
      'You don\'t have playlists yet. Create one and the track goes straight in.';

  @override
  String get addToPlaylistTitle => 'Add to a playlist';

  @override
  String addTracksAddCount(int count) {
    return 'Add ($count)';
  }

  @override
  String addTracksAdded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tracks',
      one: '$count track',
    );
    return 'Added $_temp0';
  }

  @override
  String addTracksAddedWithSkipped(String base, int skipped) {
    return '$base, $skipped already there';
  }

  @override
  String get addTracksAllPresent =>
      'All the selected tracks are already in the playlist';

  @override
  String get addTracksAlreadyIn => 'Already in the playlist';

  @override
  String get addTracksBackToPlaylists => 'Back to the playlists';

  @override
  String get addTracksDeselect => 'Deselect';

  @override
  String get addTracksEmptyPlaylist => 'This playlist has no tracks.';

  @override
  String get addTracksForeignPlaylist =>
      'Spotify doesn\'t share this playlist\'s contents — only your own and collaborative ones are available.';

  @override
  String get addTracksFromPlaylist => 'From a playlist';

  @override
  String get addTracksNoOtherPlaylists =>
      'There are no other playlists yet — nowhere to take tracks from.';

  @override
  String get addTracksNothingFound => 'Nothing found. Try a different search.';

  @override
  String get addTracksSearch => 'Search';

  @override
  String get addTracksSearchEmpty =>
      'Find a track on Spotify and add it to the playlist.';

  @override
  String get addTracksSearchHint => 'Track name or artist';

  @override
  String get addTracksSelectAll => 'Select all';

  @override
  String addTracksToPlaylist(String name) {
    return 'Add to “$name”';
  }

  @override
  String get addTracksYourPlaylist => 'Your playlist';

  @override
  String alreadyInPlaylist(String name) {
    return 'Already in “$name”';
  }

  @override
  String get appearanceAccent => 'Accent colour';

  @override
  String get appearanceArtworkBackground => 'Artwork background';

  @override
  String get appearanceArtworkBackgroundHint =>
      'A glow in the artwork\'s colour on the player screen';

  @override
  String get appearanceCompact => 'Compact mode';

  @override
  String get appearanceCompactHint => 'Tighter lists — more fits on screen';

  @override
  String get appearanceDensityGroup => 'Density and motion';

  @override
  String get appearanceLanguage => 'Language';

  @override
  String get appearanceLanguageHint =>
      'Interface language across all your devices';

  @override
  String get appearanceReduceMotion => 'Reduce motion';

  @override
  String get appearanceReduceMotionHint =>
      'Transitions without movement — if motion distracts or makes you queasy';

  @override
  String get appearanceReset => 'Reset appearance';

  @override
  String get appearanceResetDone => 'Appearance reset';

  @override
  String get appearanceResetHint =>
      'Restore theme, colour, text, density and the starting tab';

  @override
  String get appearanceStartTab => 'Where to start';

  @override
  String get appearanceStartTabHint => 'The tab that opens on launch';

  @override
  String get appearanceTextSize => 'Text size';

  @override
  String get appearanceTheme => 'Theme';

  @override
  String get appTitle => 'SyncM';

  @override
  String get avatarBadFormat =>
      'Unsupported format. Allowed: PNG, JPG, JPEG, GIF, WEBP';

  @override
  String get avatarReadFailed => 'Could not read the file';

  @override
  String get avatarUpdated => 'Avatar updated';

  @override
  String get blockedEmptyMessage =>
      'You can block someone from their profile or from your friends list.';

  @override
  String get blockedEmptyTitle => 'Nobody is blocked';

  @override
  String get blockedHint =>
      'These people won\'t find you in search and can\'t send you a request or an invitation. They won\'t be told about it.';

  @override
  String blockedPeopleCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count people',
      one: '$count person',
    );
    return '$_temp0';
  }

  @override
  String get blockedUnblock => 'Unblock';

  @override
  String blockedUnblocked(String name) {
    return '$name unblocked';
  }

  @override
  String get blockedUnblockFailed => 'Could not unblock';

  @override
  String cacheFriendsCount(int count) {
    return 'friends: $count';
  }

  @override
  String cacheInMemory(String size) {
    return 'In memory: $size';
  }

  @override
  String cacheOnDisk(String disk, String memory) {
    return 'On disk: $disk · in memory: $memory';
  }

  @override
  String cacheSessionsCount(int count) {
    return 'sessions: $count';
  }

  @override
  String clockSummary(String offset, int ping) {
    return 'Clock: $offset ms · ping: $ping ms';
  }

  @override
  String get commonBack => 'Back';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonClear => 'Clear';

  @override
  String get commonClose => 'Close';

  @override
  String get commonCollapse => 'Collapse';

  @override
  String get commonCreate => 'Create';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonEmpty => 'Empty';

  @override
  String get commonFinish => 'End';

  @override
  String get commonFriends => 'Friends';

  @override
  String get commonJustNow => 'just now';

  @override
  String get commonLoadMore => 'Load more';

  @override
  String get commonLongAgo => 'a while ago';

  @override
  String get commonMore => 'More';

  @override
  String commonMoreCount(int count) {
    return '$count more';
  }

  @override
  String get commonName => 'Name';

  @override
  String get commonNobody => 'Nobody';

  @override
  String get commonNoName => 'No name';

  @override
  String get commonOpen => 'Open';

  @override
  String get commonOr => ' or ';

  @override
  String get commonRefresh => 'Refresh';

  @override
  String get commonReset => 'Reset';

  @override
  String get commonSave => 'Save';

  @override
  String get commonSignOut => 'Sign out';

  @override
  String get commonSystem => 'System';

  @override
  String get commonUser => 'User';

  @override
  String get createSessionFailed => 'Could not create the session';

  @override
  String get createSessionFriendsOnly =>
      'A session can only be created with a friend';

  @override
  String get createSessionFriendsOnlyHint =>
      'Add someone as a friend and they\'ll show up in this list.';

  @override
  String get createSessionHint =>
      'Invite a friend and listen at the same time.';

  @override
  String get createSessionName => 'Session name';

  @override
  String get createSessionNobodyFound => 'Nobody by that name';

  @override
  String get createSessionPickFriend => 'Pick a friend to continue';

  @override
  String get createSessionSearchFriends => 'Search your friends';

  @override
  String get createSessionWithWhom => 'Who you\'re listening with';

  @override
  String get cropDone => 'Done';

  @override
  String get cropFailed => 'Could not process the image';

  @override
  String get cropHint =>
      'The area is always square, so the avatar looks the same everywhere.';

  @override
  String get cropNoImageData => 'Could not read the image data';

  @override
  String get cropRotateLeft => 'Left';

  @override
  String get cropRotateRight => 'Right';

  @override
  String get cropTitle => 'Crop';

  @override
  String get dataExport => 'Export my data';

  @override
  String get dataExportHint =>
      'Profile, friends, playlists and history in a single file';

  @override
  String get dataHistoryHint => 'View and clear';

  @override
  String get dataImageCache => 'Image cache';

  @override
  String get dataImageCacheCleared => 'Image cache cleared';

  @override
  String get dataNothingSaved => 'Nothing saved yet';

  @override
  String get dataOnServer => 'On the server';

  @override
  String get dataOnThisDevice => 'On this device';

  @override
  String get dataPrefetch => 'Preload data on launch';

  @override
  String get dataPrefetchHint =>
      'Friends and sessions are ready by the time you open the tab';

  @override
  String get dataSavedLists => 'Saved lists';

  @override
  String get dataSavedListsCleared => 'Lists cleared';

  @override
  String get dataUpdatedJustNow => 'updated just now';

  @override
  String get dataWhatIsStored => 'What we store about you';

  @override
  String get dataWhatIsStoredHint => 'A list of the data and how to delete it';

  @override
  String daysAgoShort(int count) {
    return '$count d ago';
  }

  @override
  String get deleteAccountMessage =>
      'Your profile, friends and session history will be deleted for good. This cannot be undone.';

  @override
  String get devicesApp => 'SyncM app';

  @override
  String get devicesBrowser => 'Browser';

  @override
  String get devicesCurrent => 'This device';

  @override
  String get devicesEmptyMessage =>
      'The list is empty — the server connection seems to be lost. Try opening this screen again.';

  @override
  String get devicesEmptyTitle => 'No active sessions';

  @override
  String devicesEndAgainMessage(String device) {
    return 'You\'ll have to sign in again on “$device”.';
  }

  @override
  String get devicesEndSessionTitle => 'End this session?';

  @override
  String get devicesHint =>
      'These are the apps and browsers where you\'re signed in. If you see a device you don\'t recognise, end its session.';

  @override
  String get devicesSessionEnded => 'Session ended';

  @override
  String get devicesSignOutThisDeviceTitle => 'Sign out on this device?';

  @override
  String get devicesTimeUnknown => 'Time unknown';

  @override
  String get devicesTitle => 'Devices';

  @override
  String get devicesYesterday => 'Yesterday';

  @override
  String durationHours(int count) {
    return '$count h';
  }

  @override
  String durationMinutes(int count) {
    return '$count min';
  }

  @override
  String get errorBadResponse =>
      'The server returned an unexpected response. Try refreshing.';

  @override
  String get errorConflict =>
      'That action is already running or isn\'t possible right now.';

  @override
  String get errorConnectionDropped => 'The connection dropped. Try again.';

  @override
  String get errorForbidden => 'You don\'t have permission for this.';

  @override
  String get errorGeneric => 'Something went wrong.';

  @override
  String get errorGenericRetry => 'Something went wrong. Try again.';

  @override
  String get errorGoogleFailed => 'Could not sign in with Google. Try again.';

  @override
  String get errorGoogleMisconfigured =>
      'Google sign-in is misconfigured. Let the developer know.';

  @override
  String get errorGoogleUnreachable =>
      'Could not reach Google. Check your connection.';

  @override
  String get errorHandshake => 'Could not establish a secure connection.';

  @override
  String get errorNetwork => 'Network error. Check your connection.';

  @override
  String get errorNoInternet => 'No internet connection. Check your network.';

  @override
  String get errorNotFound => 'Not found.';

  @override
  String get errorServerFailure => 'Server error. We already know about it.';

  @override
  String get errorServerSlow =>
      'The server is taking too long. Try again later.';

  @override
  String get errorServerUnavailable =>
      'The server is temporarily unavailable. Try again in a minute.';

  @override
  String get errorServerUnreachable =>
      'Could not reach the server. Check your connection.';

  @override
  String get errorSessionExpired => 'Your session expired. Sign in again.';

  @override
  String get errorSignInCancelled => 'Sign-in cancelled';

  @override
  String get errorTooManyRequests => 'Too many requests. Wait a moment.';

  @override
  String exportSaved(String path) {
    return 'File saved: $path';
  }

  @override
  String get foregroundChannelDescription =>
      'Shown while a shared listening session runs, so syncing is not interrupted.';

  @override
  String get foregroundChannelName => 'Active SyncM session';

  @override
  String get foregroundText => 'Listening together with friends';

  @override
  String get foregroundTitle => 'SyncM session is active';

  @override
  String get friendActions => 'Actions';

  @override
  String get friendBlock => 'Block';

  @override
  String friendLastSeen(String when) {
    return 'Last seen $when';
  }

  @override
  String get friendOffline => 'Offline';

  @override
  String get friendOnline => 'Online';

  @override
  String get friendOpenProfile => 'Open profile';

  @override
  String get friendRemove => 'Remove from friends';

  @override
  String friendsBlocked(String name) {
    return '$name blocked';
  }

  @override
  String get friendsBlockFailed => 'Could not block';

  @override
  String get friendsBlockMessage =>
      'They won\'t find you in search, send you a request or invite you to a session. The friendship will be removed, and they won\'t be notified.';

  @override
  String friendsBlockTitle(String name) {
    return 'Block $name?';
  }

  @override
  String get friendsEmptyMessage =>
      'With a friend you can listen at the same time, wherever you both are.';

  @override
  String get friendsEmptyTitle => 'Add friends';

  @override
  String friendsRemoved(String name) {
    return '$name removed from friends';
  }

  @override
  String get friendsRemoveFailed => 'Could not remove the friend';

  @override
  String friendsRemoveMessage(String name) {
    return '$name will disappear from your friends list.';
  }

  @override
  String get friendsRemoveTitle => 'Remove from friends?';

  @override
  String hiddenList(String items) {
    return 'Hidden: $items';
  }

  @override
  String get historyClear => 'Clear';

  @override
  String get historyCleared => 'History cleared';

  @override
  String get historyClearFailed => 'Could not clear the history';

  @override
  String get historyClearMessage =>
      'The records of tracks you played will be deleted.';

  @override
  String get historyClearTitle => 'Clear the history?';

  @override
  String get historyEmptyMessage =>
      'Tracks you play in SyncM will show up here.';

  @override
  String get historyEmptyTitle => 'The history is empty';

  @override
  String get historyJustNow => 'just now';

  @override
  String get historyTitle => 'History';

  @override
  String get historyUntitled => 'Untitled';

  @override
  String get historyYesterday => 'yesterday';

  @override
  String get homeAnotherSession => 'Another session';

  @override
  String get homeConnectSpotify => 'Connect Spotify';

  @override
  String get homeCreatePlaylist => 'Create a playlist';

  @override
  String get homeDarkTheme => 'Dark theme';

  @override
  String get homeFilterAll => 'All';

  @override
  String get homeFilterFriend => 'Friend';

  @override
  String get homeFilterMine => 'Mine';

  @override
  String get homeFriendRequests => 'Friend requests';

  @override
  String get homeInvitedYou => 'You\'re invited';

  @override
  String homeInviteFrom(String name) {
    return 'From $name';
  }

  @override
  String get homeLightTheme => 'Light theme';

  @override
  String get homeListenTogether => 'Listen together';

  @override
  String get homeListenTogetherHint =>
      'Invite a friend — the music plays for both of you at once, wherever you are.';

  @override
  String get homeNoOwnPlaylists => 'No playlists of your own yet';

  @override
  String get homeNoOwnPlaylistsHint =>
      'Put one together and you\'ll be able to play it in a session.';

  @override
  String get homeNoSpotifyPlaylists => 'No playlists available';

  @override
  String get homeNoSpotifyPlaylistsHint =>
      'Spotify has no playlists SyncM can open.';

  @override
  String get homeNothingPlaying => 'Nothing is playing';

  @override
  String get homeNothingPlayingHint =>
      'Pick a track from a playlist and the controls will show up here.';

  @override
  String get homeNowListening => 'Listening now';

  @override
  String get homePlaylist => 'Playlist';

  @override
  String get homeSearchFriends => 'Friend search';

  @override
  String get homeSession => 'Session';

  @override
  String get homeSpotifyUnavailable => 'Spotify playlists are unavailable';

  @override
  String get homeSpotifyUnavailableHint =>
      'Connect your Spotify account to see your library here.';

  @override
  String get homeStartSession => 'Start a session';

  @override
  String get homeTapToOpen => 'Tap to open';

  @override
  String hoursAgoShort(int count) {
    return '$count h ago';
  }

  @override
  String get invitesAccepted => 'Invitation accepted';

  @override
  String get inviteScopeFriendsHint =>
      'Only people on your friends list can invite you';

  @override
  String get inviteScopeNobodyHint =>
      'Nobody will be able to invite you to a session';

  @override
  String invitesCount(int count) {
    return 'Invitations · $count';
  }

  @override
  String get invitesDeclined => 'Invitation declined';

  @override
  String get invitesEmptyMessage =>
      'When a friend invites you it shows up here. You don\'t have to wait — start a session yourself.';

  @override
  String get invitesEmptyTitle => 'No invitations yet';

  @override
  String invitesNotification(String name) {
    return 'Invitation to the session “$name”';
  }

  @override
  String get invitesReplyFailed => 'Could not reply to the invitation';

  @override
  String get invitesTitle => 'Invitations';

  @override
  String invitesWaiting(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count invitations are waiting',
      one: 'One invitation is waiting',
    );
    return '$_temp0';
  }

  @override
  String latencyMilliseconds(int value) {
    return '$value ms';
  }

  @override
  String get latencySpeaker => 'Speaker';

  @override
  String get latencyTitle => 'Audio delay';

  @override
  String get latencyWired => 'Wired';

  @override
  String get legalCopyText => 'Copy the text';

  @override
  String get legalOpenFailed => 'Could not open the document.';

  @override
  String legalOpenFailedDetails(String error) {
    return 'Could not open the document in the browser: $error';
  }

  @override
  String get legalTextCopied => 'Text copied';

  @override
  String get loginBrowser => 'Sign in through the browser';

  @override
  String get loginDoneCloseTab => 'Signed in! You can close this tab.';

  @override
  String get loginGoogle => 'Sign in with Google';

  @override
  String get loginGoogleNoToken =>
      'Error: could not get the ID token from Google';

  @override
  String get loginHint =>
      'Sign in with Google to create sessions and listen together.';

  @override
  String get loginSubtitle => 'Music for friends';

  @override
  String get loginTagline =>
      'Listen to the same music at the same time, wherever you are.';

  @override
  String get loginTitle => 'Sign in';

  @override
  String minutesAgoShort(int count) {
    return '$count min ago';
  }

  @override
  String get nameDialogCharset => 'Only letters, digits, spaces and . _ -';

  @override
  String get nameDialogEmpty => 'Enter a name';

  @override
  String get nameDialogHint =>
      'Friends see this name — in lists, in sessions and in invitations.';

  @override
  String get nameDialogTitle => 'What\'s your name?';

  @override
  String nameDialogTooLong(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count characters',
      one: '$count character',
    );
    return 'No more than $_temp0';
  }

  @override
  String nameDialogTooShort(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count characters',
      one: '$count character',
    );
    return 'At least $_temp0';
  }

  @override
  String get nameUpdated => 'Name updated';

  @override
  String get navFindFriends => 'Find friends';

  @override
  String get navLibrary => 'Library';

  @override
  String get navLikedTracks => 'Liked tracks';

  @override
  String get navNewSession => 'New session';

  @override
  String get navQuick => 'Quick';

  @override
  String get notificationsAllOff => 'Cards disabled';

  @override
  String get notificationsAllOn => 'All cards enabled';

  @override
  String get notificationsFriendRequests => 'Friend requests';

  @override
  String get notificationsFriendRequestsHint => 'A card when someone adds you';

  @override
  String get notificationsGroup => 'Pop-up cards';

  @override
  String get notificationsHint =>
      'These settings apply to all your devices. Requests and invitations still arrive — only the card on top of the screen goes away.';

  @override
  String get notificationsOffInvites => 'invitations';

  @override
  String notificationsOffOne(String what) {
    return 'Disabled: $what';
  }

  @override
  String get notificationsOffRequests => 'requests';

  @override
  String get notificationsSessionInvites => 'Session invitations';

  @override
  String get notificationsSessionInvitesHint =>
      'A card when a friend invites you to listen together';

  @override
  String pickPlaylistAddAll(int count) {
    return 'Add all ($count)';
  }

  @override
  String pickPlaylistAddSelected(int count) {
    return 'Add selected ($count)';
  }

  @override
  String pickPlaylistDeselectCount(int count) {
    return 'Deselect ($count)';
  }

  @override
  String get pickPlaylistEmptyPlaylist => 'The playlist has no tracks';

  @override
  String pickPlaylistInPlaylist(int count) {
    return '$count in the playlist';
  }

  @override
  String get pickPlaylistNoPlaylists => 'No playlists';

  @override
  String get pickPlaylistNoPlaylistsHint =>
      'Connect Spotify or create your own playlist to add tracks to sessions.';

  @override
  String get pickPlaylistNoSession => 'Could not identify the session';

  @override
  String get pickPlaylistNoTracks => 'No tracks';

  @override
  String get pickPlaylistNoTracksHint =>
      'This playlist is empty or its contents aren\'t available: Spotify only shares tracks for your own playlists.';

  @override
  String get pickPlaylistTitle => 'Pick a playlist';

  @override
  String get playbackAllowBackground => 'Allow background work';

  @override
  String get playbackAllowBackgroundHint =>
      'So syncing survives a locked screen';

  @override
  String get playbackAutostart => 'Set up autostart';

  @override
  String get playbackAutostartHint =>
      'On Xiaomi and Redmi the system closes the app without it';

  @override
  String get playbackAutostartHint2 =>
      'Open the app settings and enable autostart manually';

  @override
  String get playbackBackgroundGroup => 'Background mode';

  @override
  String get playbackClockSync => 'Sync the clock with the server';

  @override
  String get playbackClockSyncStarted => 'Re-syncing the clock';

  @override
  String get playbackClockUnknown => 'Not measured yet — tap to refresh';

  @override
  String get playbackConnections => 'Connections';

  @override
  String get playbackOpenSpotifyHint =>
      'Open Spotify, start any track, then try again.';

  @override
  String get playbackPermissionsHint =>
      'Check the permissions in the system dialog';

  @override
  String get playbackQualityGroup => 'Audio quality';

  @override
  String get playbackServerLink => 'Server connection';

  @override
  String get playbackServerOffline => 'No connection. Check your internet';

  @override
  String get playbackServerOnline => 'Online — session events arrive instantly';

  @override
  String get playbackSpotifyConnected => 'Connected — you can start playing';

  @override
  String get playbackSpotifyConnectFailed => 'Could not connect to Spotify';

  @override
  String get playbackSpotifyDevice => 'Spotify on this device';

  @override
  String get playbackSpotifyDisconnected =>
      'Not connected. Tap to link the Spotify app';

  @override
  String get playbackSpotifySettings => 'Spotify settings';

  @override
  String get playbackSpotifySettingsHint =>
      'Quality, crossfade and volume live in the Spotify app';

  @override
  String get playbackSpotifySettingsPath =>
      'Open Spotify → Settings → Audio quality';

  @override
  String get playbackSyncGroup => 'Synchronisation';

  @override
  String get playerNext => 'Next track';

  @override
  String get playerNowPlayingLabel => 'NOW PLAYING';

  @override
  String get playerPause => 'Pause';

  @override
  String get playerPlay => 'Play';

  @override
  String get playerPrevious => 'Previous track';

  @override
  String get playerRepeatAll => 'Repeat the list';

  @override
  String get playerRepeatOff => 'Repeat is off';

  @override
  String get playerRepeatOne => 'Repeat one track';

  @override
  String get playerShuffle => 'Shuffle';

  @override
  String get playerShuffleOn => 'Shuffle is on';

  @override
  String get playerUnknownTrack => 'Unknown track';

  @override
  String get playlistActionsTitle => 'Playlist actions';

  @override
  String get playlistAddMusic => 'Add music';

  @override
  String get playlistChangeCover => 'Change the cover';

  @override
  String get playlistClear => 'Clear the playlist';

  @override
  String get playlistCleared => 'Playlist cleared';

  @override
  String playlistClearMessage(String name) {
    return 'All tracks will be removed from “$name”. The playlist itself stays.';
  }

  @override
  String get playlistClearTitle => 'Clear the playlist?';

  @override
  String get playlistConnectSpotifyHint =>
      'Connect your Spotify account in the profile';

  @override
  String playlistCopyCreated(String name) {
    return 'Copy “$name” created';
  }

  @override
  String get playlistCoverHint =>
      'The cover is square, so playlists line up neatly in the list.';

  @override
  String get playlistCoverRemoved => 'Cover removed';

  @override
  String get playlistCoverTitle => 'Playlist cover';

  @override
  String get playlistCoverUpdated => 'Cover updated';

  @override
  String get playlistDelete => 'Delete the playlist';

  @override
  String get playlistDeleted => 'Playlist deleted';

  @override
  String playlistDeleteMessage(String name) {
    return '“$name” and its track list will be deleted. The tracks themselves stay in Spotify.';
  }

  @override
  String get playlistDeleteTitle => 'Delete the playlist?';

  @override
  String get playlistDuplicate => 'Duplicate';

  @override
  String get playlistEdit => 'Edit the playlist';

  @override
  String get playlistEditNameDescription => 'Edit name and description';

  @override
  String get playlistEmptyMessage =>
      'Find music on Spotify or take it from another playlist.';

  @override
  String get playlistEmptyShort => 'This playlist is empty for now.';

  @override
  String get playlistEmptyTitle => 'No tracks';

  @override
  String get playlistFieldDescription => 'Description';

  @override
  String get playlistFieldName => 'Name';

  @override
  String get playlistFieldOptional => 'Optional';

  @override
  String get playlistForeign =>
      'Spotify doesn\'t share other people\'s playlists — only your own and collaborative ones are available.';

  @override
  String get playlistLinkCopied => 'Playlist link copied to the clipboard';

  @override
  String get playlistNameCharset => 'Only letters, digits, spaces and ._-()';

  @override
  String get playlistNameEmpty => 'The name can\'t be empty';

  @override
  String get playlistNameEmptyGeneric => 'Enter a name';

  @override
  String get playlistNameTooShort => 'At least 2 characters';

  @override
  String get playlistNew => 'New playlist';

  @override
  String get playlistOpen => 'Open';

  @override
  String get playlistPlay => 'Play';

  @override
  String get playlistRemoveCover => 'Remove the cover';

  @override
  String get playlistRemoveTrack => 'Remove from the playlist';

  @override
  String get playlistShare => 'Share';

  @override
  String get playlistTrackActions => 'Track actions';

  @override
  String get playlistTrackRemoved => 'Track removed from the playlist';

  @override
  String get previewArtistName => 'Artist';

  @override
  String get previewTrackName => 'Track name';

  @override
  String get privacyAlwaysVisible => 'Always visible';

  @override
  String get privacyBitActivity => 'activity';

  @override
  String get privacyBitFriends => 'friends';

  @override
  String get privacyBitSearch => 'search';

  @override
  String get privacyBitStatus => 'status';

  @override
  String get privacyBlocked => 'Blocked';

  @override
  String get privacyBlockedHint =>
      'They can\'t find you, message you or invite you';

  @override
  String get privacyBlockedNobody => 'Nobody yet';

  @override
  String get privacyBlockList => 'Block list';

  @override
  String get privacyDetailed => 'In detail';

  @override
  String get privacyDocFriends => 'Friends and requests';

  @override
  String get privacyDocFriendsText =>
      'Who you\'re friends with and who you\'ve sent requests to. Blocked people are stored separately and shown to nobody.';

  @override
  String get privacyDocFullHint =>
      'Everything above is a summary. The full privacy policy, with the exact wording and retention periods, opens below.';

  @override
  String get privacyDocFullTitle => 'Full text';

  @override
  String get privacyDocHistoryText =>
      'The tracks you played in the app and when. You can clear it in the Data section.';

  @override
  String get privacyDocHowToDeleteText =>
      'Listening history is cleared in the Data section. The same place deletes the whole account — profile, friends, sessions and the Spotify connection. This cannot be undone.';

  @override
  String get privacyDocHowToDeleteTitle => 'How to delete it';

  @override
  String get privacyDocNoOutsideListening =>
      'What you listen to outside the app: anything played without a session goes nowhere.';

  @override
  String get privacyDocNoPassword =>
      'Your Spotify password — authorisation happens on Spotify\'s side.';

  @override
  String get privacyDocNoPayments =>
      'Payment details — the app is free and takes no payments.';

  @override
  String get privacyDocNotStoredTitle => 'What is not stored';

  @override
  String get privacyDocProfile =>
      'Your name, email address and avatar. The email is for signing in; friends see your name and avatar.';

  @override
  String get privacyDocSessionsText =>
      'The names of shared listening sessions, who took part, which tracks were added and how they were rated — so the matches can be shown at the end.';

  @override
  String get privacyDocSpotify => 'Spotify connection';

  @override
  String get privacyDocSpotifyText =>
      'Your account id and access tokens, encrypted. The app never sees or receives your Spotify password.';

  @override
  String get privacyDocStoredHint =>
      'The list follows what the app actually writes to the database.';

  @override
  String get privacyDocStoredTitle => 'What is stored';

  @override
  String get privacyHiddenWarning =>
      'With a fully hidden profile it’s harder for friends to tell when to invite you to listen together.';

  @override
  String get privacyHideActivity => 'Hide activity';

  @override
  String get privacyHideActivityHint =>
      'What you listen to in a session won\'t show on your profile';

  @override
  String get privacyHideFriends => 'Hide friends';

  @override
  String get privacyHideFriendsHint =>
      'Nobody will see how many friends you have or which ones you share';

  @override
  String get privacyHideOnline => 'Hide online status';

  @override
  String get privacyHideOnlineHint =>
      'Friends won\'t see when you\'re online or last seen';

  @override
  String get privacyHideSearch => 'Hide from search';

  @override
  String get privacyHideSearchHint =>
      'New people won\'t find you by name. Friends still will';

  @override
  String get privacyHistory => 'Listening history';

  @override
  String get privacyHistoryHint => 'Visible only to you — not even to friends';

  @override
  String get privacyNameAndAvatar => 'Name and avatar';

  @override
  String get privacyNameAndAvatarHint =>
      'That\'s how friends recognise you in lists and sessions';

  @override
  String get privacyNothingHidden => 'Nothing is hidden';

  @override
  String get privacyPresetFriends => 'Friends only';

  @override
  String get privacyPresetFriendsSummary =>
      'Friends only — you won\'t show up in search';

  @override
  String get privacyPresetHidden => 'Hidden';

  @override
  String get privacyPresetHiddenSummary => 'Hidden profile';

  @override
  String get privacyPresetOpen => 'Open';

  @override
  String get privacyPresetOpenSummary => 'Open profile';

  @override
  String get privacyQuickMode => 'Quick mode';

  @override
  String get privacySessionParticipation => 'Taking part in a shared session';

  @override
  String get privacySessionParticipationHint =>
      'Whoever listens with you sees you and the queue';

  @override
  String get privacySummaryFriendCount => 'how many friends you have';

  @override
  String get privacySummaryFriendsSee => 'Friends see';

  @override
  String get privacySummaryListening => 'what you\'re listening to';

  @override
  String get privacySummaryNameAvatar => 'name and avatar';

  @override
  String get privacySummaryNotSearchable => 'You won\'t be found in search';

  @override
  String get privacySummaryOnline => 'when you\'re online';

  @override
  String get privacySummaryOthers => 'Everyone else';

  @override
  String get privacySummarySearchable =>
      'People can find you by name and send a request';

  @override
  String get privacyWhatIsVisible => 'What others see';

  @override
  String get profileConnectSpotify => 'Connect Spotify';

  @override
  String get profileDisconnectSpotify => 'Disconnect Spotify';

  @override
  String get profileEmpty => 'Empty for now';

  @override
  String profileFriendsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count friends',
      one: '$count friend',
    );
    return '$_temp0';
  }

  @override
  String get profileInCommonEmpty => 'Nothing in common yet';

  @override
  String get profileInCommonHint => 'From your liked tracks';

  @override
  String get profileInCommonTitle => 'Music in common';

  @override
  String profileInCommonTracks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tracks in common',
      one: '$count track in common',
    );
    return '$_temp0';
  }

  @override
  String profileInSelection(int count) {
    return '$count in the selection';
  }

  @override
  String get profileLast => 'Latest';

  @override
  String profileLikedCount(int count) {
    return '$count liked';
  }

  @override
  String get profileLikedEmpty =>
      'Tap the heart on tracks and they\'ll gather here';

  @override
  String get profileLikedTracks => 'Liked tracks';

  @override
  String profileMutualCount(int count) {
    return '$count mutual';
  }

  @override
  String get profileNothingShown => 'Nothing is shown';

  @override
  String get profilePlaylistsHint => 'Your collections';

  @override
  String get profilePlaylistsTitle => 'Playlists';

  @override
  String get profileRecentlyPlayed => 'Recently played';

  @override
  String get profileRecentlyPlayedEmpty => 'Tracks you play will show up here';

  @override
  String profileSessionsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sessions',
      one: '$count session',
    );
    return '$_temp0';
  }

  @override
  String get profileTopArtists => 'On repeat';

  @override
  String get profileTopArtistsHint => 'From plays and liked tracks';

  @override
  String get profileVisibleToYouOnly => 'Visible only to you';

  @override
  String get requestsAccept => 'Accept';

  @override
  String get requestsAccepted => 'Request accepted';

  @override
  String get requestsDecline => 'Decline';

  @override
  String requestsDeclineMessage(String name) {
    return '$name won\'t see that you declined.';
  }

  @override
  String get requestsDeclineTitle => 'Decline the request?';

  @override
  String get requestsEmptyMessage =>
      'Friend requests will show up here. Sending one is faster than waiting.';

  @override
  String get requestsEmptyTitle => 'No requests yet';

  @override
  String requestsNotification(String name) {
    return 'Friend request from $name';
  }

  @override
  String get requestsWantsToAdd => 'Wants to add you as a friend';

  @override
  String get resultsBackHome => 'Back home';

  @override
  String get resultsMatches => 'Matches';

  @override
  String get resultsMatchesHint => 'You both liked these tracks.';

  @override
  String get resultsNoMatches => 'No matches';

  @override
  String get resultsNoMatchesHint =>
      'Your tastes differed this time. Try another session — a different selection may go better.';

  @override
  String get resultsTitle => 'Session results';

  @override
  String get searchEmptyMessage =>
      'Enter a name or an eight-character code. Your own code is in Settings, under Account.';

  @override
  String get searchEmptyTitle => 'Find friends';

  @override
  String get searchFieldHint => 'Name or code';

  @override
  String get searchNothingFound => 'Nobody found';

  @override
  String get searchNothingFoundHint =>
      'Check the spelling. A code finds people even when they\'ve hidden themselves from search.';

  @override
  String get searchRequestSent => 'Request sent';

  @override
  String get searchSendRequest => 'Send a request';

  @override
  String get searchStatusFriends => 'Friends';

  @override
  String get searchStatusSent => 'Sent';

  @override
  String get searchStatusWaiting => 'Awaiting reply';

  @override
  String get sectionAbout => 'About';

  @override
  String get sectionAccount => 'Account';

  @override
  String get sectionAppearance => 'Appearance';

  @override
  String get sectionData => 'Data';

  @override
  String get sectionNotifications => 'Notifications';

  @override
  String get sectionPlayback => 'Playback';

  @override
  String get sectionPrivacy => 'Privacy';

  @override
  String get sectionSecurity => 'Security';

  @override
  String get sectionSessions => 'Sessions';

  @override
  String get securityDangerZone => 'Danger zone';

  @override
  String get securityDeleteAccount => 'Delete account';

  @override
  String get securityDeleteAccountHint =>
      'Permanently deletes your profile, friends and session history';

  @override
  String get securityDeleteAccountTitle => 'Delete account?';

  @override
  String get securityDevices => 'Devices';

  @override
  String get securityDevicesHint =>
      'Where you\'re signed in, and how to end what you don\'t need';

  @override
  String get securitySessionsGroup => 'Sessions';

  @override
  String get securitySignInGoogle => 'Via Google';

  @override
  String get securitySignInMethod => 'Sign-in method';

  @override
  String get securitySignInSpotifyGoogle => 'Via Spotify or Google';

  @override
  String get securitySignOutEverywhere => 'Sign out everywhere';

  @override
  String get securitySignOutEverywhereConfirm => 'Sign out everywhere';

  @override
  String get securitySignOutEverywhereHint =>
      'Ends every session, including this one';

  @override
  String get securitySignOutEverywhereMessage =>
      'Every session will end, including this one. Do this if you see a device that isn’t yours.';

  @override
  String get securitySignOutEverywhereTitle => 'Sign out everywhere?';

  @override
  String get securitySignOutMessage =>
      'You\'ll need to sign in again to come back.';

  @override
  String get securitySignOutThisDevice => 'This device only';

  @override
  String get securitySignOutTitle => 'Sign out?';

  @override
  String get sessionAddTracks => 'Add tracks';

  @override
  String get sessionAdjusting => 'Adjusting';

  @override
  String get sessionAlreadyRated => 'The other person has already rated it';

  @override
  String get sessionDislike => 'Dislike';

  @override
  String get sessionEndAction => 'End the session';

  @override
  String sessionEndMessage(String name) {
    return '“$name” will close for everyone.';
  }

  @override
  String get sessionEndMessagePlain => 'The session will close for everyone.';

  @override
  String get sessionHostChanged => 'The session host has changed';

  @override
  String sessionInQueue(int count) {
    return '$count in the queue';
  }

  @override
  String get sessionInSync => 'Playing in sync';

  @override
  String get sessionLike => 'Like';

  @override
  String get sessionNoTracksYet => 'No tracks yet';

  @override
  String get sessionNotStarted => 'The session hasn\'t started';

  @override
  String get sessionParticipant => 'Participant';

  @override
  String get sessionQueueEmpty => 'The queue is empty';

  @override
  String get sessionQueueEmptyHint =>
      'Add tracks from your playlists — everyone in the session will hear them.';

  @override
  String get sessionsActive => 'Active sessions';

  @override
  String sessionsActiveCount(int count) {
    return 'Active sessions · $count';
  }

  @override
  String get sessionsAutoOpenPlayer => 'Open the player on start';

  @override
  String get sessionsAutoOpenPlayerHint =>
      'Full-screen player once a track starts';

  @override
  String get sessionsBlockedHint =>
      'They won\'t be able to invite you to a session';

  @override
  String get sessionsConfirmEnd => 'Ask before ending';

  @override
  String get sessionsConfirmEndHint =>
      'A confirmation so you don\'t end a session by accident';

  @override
  String get sessionsDuringGroup => 'During a session';

  @override
  String get sessionsEnded => 'Session ended';

  @override
  String get sessionsEndTitle => 'End the session?';

  @override
  String get sessionsKeepScreenOn => 'Keep the screen on';

  @override
  String get sessionsKeepScreenOnHint =>
      'The screen stays on while a session runs';

  @override
  String get sessionsNothingPlaying => 'Nothing is playing';

  @override
  String get sessionsNothingPlayingHint =>
      'Sessions you start will show up here';

  @override
  String get sessionsOneInvite => 'One invitation is waiting';

  @override
  String get sessionsOpenList => 'Open the list';

  @override
  String get sessionsRunningNow => 'Playing now';

  @override
  String get sessionsWhoCanInvite => 'Who can invite you';

  @override
  String get sessionWaitingForSecond => 'Waiting for the other person';

  @override
  String get sessionYouAreHost => 'You\'re the session host now';

  @override
  String get settingsGroupApp => 'App';

  @override
  String get settingsGroupData => 'Data & privacy';

  @override
  String get settingsGroupProfile => 'Profile & access';

  @override
  String get settingsTitle => 'Settings';

  @override
  String sizeBytes(int value) {
    return '$value B';
  }

  @override
  String sizeKilobytes(int value) {
    return '$value KB';
  }

  @override
  String sizeMegabytes(String value) {
    return '$value MB';
  }

  @override
  String get spotifyCheck => 'Check';

  @override
  String get spotifyCheckFailed => 'Could not check the connection';

  @override
  String get spotifyChecking => 'Checking the connection…';

  @override
  String get spotifyConnect => 'Connect';

  @override
  String get spotifyConnected => 'Connected';

  @override
  String spotifyConnectedAs(String name) {
    return 'Connected · $name';
  }

  @override
  String get spotifyConnectedShort => 'Spotify connected';

  @override
  String get spotifyDisconnect => 'Disconnect';

  @override
  String get spotifyDisconnectMessage =>
      'Playlists and shared listening will stop working until you connect it again.';

  @override
  String get spotifyDisconnectTitle => 'Disconnect Spotify?';

  @override
  String get spotifyLikedEmpty =>
      'Tracks you save in Spotify will show up here.';

  @override
  String get spotifyLikedSubtitle => 'Saved in Spotify';

  @override
  String get spotifyLikedTitle => 'Liked tracks';

  @override
  String get spotifyLinkBusy =>
      'Could not start connecting: the previous attempt hasn\'t finished. Wait a few seconds and try again.';

  @override
  String get spotifyLinked => 'Spotify connected';

  @override
  String get spotifyNeedsReauth =>
      'Access was revoked or expired — connect again';

  @override
  String get spotifyNotConnected => 'Not connected';

  @override
  String get spotifyNotConnectedShort => 'Spotify not connected';

  @override
  String get spotifyReconnect => 'Reconnect';

  @override
  String get spotifyUnlinked => 'Spotify disconnected';

  @override
  String get spotifyWebviewTitle => 'Connecting Spotify';

  @override
  String get summaryAbout => 'Version • Privacy • Terms';

  @override
  String get summaryData => 'Cache • History • Export';

  @override
  String get summaryPlayback => 'Connections • Audio delay • Background';

  @override
  String get summarySecurity => 'Devices • Sign out • Delete account';

  @override
  String get summarySessions => 'Active • Invitations • Who can invite';

  @override
  String get tabMusic => 'Music';

  @override
  String get tabNow => 'Now';

  @override
  String get themeDark => 'Dark';

  @override
  String get themeLight => 'Light';

  @override
  String get themeSystem => 'Match system';

  @override
  String trackCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tracks',
      one: '$count track',
    );
    return '$_temp0';
  }

  @override
  String get trackLike => 'Add to liked';

  @override
  String get trackUnlike => 'Remove from liked';

  @override
  String updatedDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days',
      one: '$count day',
    );
    return 'updated $_temp0 ago';
  }

  @override
  String updatedHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hours',
      one: '$count hour',
    );
    return 'updated $_temp0 ago';
  }

  @override
  String updatedMinutesAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count minutes',
      one: '$count minute',
    );
    return 'updated $_temp0 ago';
  }
}
