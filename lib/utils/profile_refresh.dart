// SPDX-FileCopyrightText: 2026 Contributors to the QIVchat fork
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';

/// Profile helpers which work around a stale cache in the Matrix SDK.
extension OwnProfileRefresh on Client {
  /// Re-reads the own profile from the server and refreshes the local cache.
  ///
  /// `getUserProfile()` answers from a cache which is considered valid for a
  /// day, and it is only invalidated when an `m.room.member` event for that user
  /// arrives through /sync. Changing your own display name or avatar does **not**
  /// produce such an event, so without this call every screen keeps showing the
  /// old values until the next login.
  ///
  /// Passing `maxCacheAge: Duration.zero` makes the SDK skip the cache and go to
  /// the server; the result is stored back into the database so subsequent
  /// `fetchOwnProfile()` / `getProfileFromUserId()` calls see the new values.
  /// [onUserProfileUpdate] is pinged so widgets listening for profile changes can
  /// rebuild.
  Future<CachedProfileInformation?> refreshOwnProfile() async {
    final userId = userID;
    if (userId == null) return null;
    try {
      final profile = await getUserProfile(userId, maxCacheAge: Duration.zero);
      onUserProfileUpdate.add(userId);
      return profile;
    } catch (exception, stackTrace) {
      Logs().w('Unable to refresh the own profile', exception, stackTrace);
      return null;
    }
  }
}
