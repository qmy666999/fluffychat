// SPDX-FileCopyrightText: 2026 Contributors to the QIVchat fork
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:typed_data';

import 'package:matrix/matrix.dart';

/// State event type which marks a room as a moments (朋友圈) feed.
///
/// Any room carrying this state event is treated as one personal moments wall,
/// owned by the room creator.
const String momentsStateType = 'chat.qiv.moments';

/// Marker written into the room topic.
///
/// The stripped state of an invite only contains a small subset of the room
/// state (name, topic, avatar, create, …) but not arbitrary state events, so
/// the topic is used to recognise invited moments rooms before joining them.
const String momentsTopicMarker = 'qivchat.moments';

/// Content key of a room message which holds the image mxc URIs of a post.
const String momentsImagesKey = 'qiv.moments.images';

/// The reaction key used for likes.
const String momentsLikeKey = '❤️';

/// Relation type of a comment (a Matrix thread reply).
const String momentsCommentRelType = 'm.thread';

extension MomentsRoomExtension on Room {
  /// Whether this room is a personal moments feed.
  bool get isMomentsRoom =>
      getState(momentsStateType) != null ||
      getState(EventTypes.RoomTopic)?.content['topic'] == momentsTopicMarker;

  /// The creator of the room, which is the owner of this moments feed.
  String? get momentsOwnerId => getState(EventTypes.RoomCreate)?.senderId;
}

extension MomentsEventExtension on Event {
  /// The reaction key if this event is a reaction.
  String? get momentsReactionKey =>
      type == EventTypes.Reaction
      ? content
            .tryGetMap<String, Object?>('m.relates_to')
            ?.tryGet<String>('key')
      : null;

  bool get isMomentsComment =>
      type == EventTypes.Message &&
      relationshipType == momentsCommentRelType &&
      relationshipEventId != null;

  /// Whether this event is a post on the given feed.
  bool isMomentsPostOf(String? ownerId) =>
      type == EventTypes.Message &&
      relationshipType == null &&
      senderId == ownerId;
}

/// One post of a moments feed together with its likes and comments.
class MomentEntry {
  const MomentEntry({
    required this.room,
    required this.post,
    required this.ownerId,
    required this.reactions,
    required this.comments,
  });

  final Room room;
  final Event post;
  final String? ownerId;
  final List<Event> reactions;
  final List<Event> comments;

  String get body => post.body;

  List<String> get images =>
      (post.content[momentsImagesKey] as List?)?.whereType<String>().toList() ??
      const [];

  DateTime get timestamp => post.originServerTs;

  bool likedBy(String? userId) =>
      userId != null && reactions.any((reaction) => reaction.senderId == userId);

  int get likeCount => reactions.map((reaction) => reaction.senderId).toSet().length;
}

/// Aggregates the timelines of all moments rooms into one feed, newest first.
List<MomentEntry> buildMomentsFeed(Iterable<Timeline> timelines) {
  final entries = <MomentEntry>[];
  for (final timeline in timelines) {
    final room = timeline.room;
    final ownerId = room.momentsOwnerId;
    final reactions = <String, List<Event>>{};
    final comments = <String, List<Event>>{};

    for (final event in timeline.events) {
      if (event.type == EventTypes.Reaction) {
        if (event.momentsReactionKey != momentsLikeKey) continue;
        final target = event.relationshipEventId;
        if (target == null) continue;
        (reactions[target] ??= []).add(event);
        continue;
      }
      if (event.isMomentsComment) {
        (comments[event.relationshipEventId!] ??= []).add(event);
      }
    }

    for (final event in timeline.events) {
      if (!event.isMomentsPostOf(ownerId)) continue;
      final eventId = event.eventId;
      final eventComments = List<Event>.of(comments[eventId] ?? const [])
        ..sort((a, b) => a.originServerTs.compareTo(b.originServerTs));
      entries.add(
        MomentEntry(
          room: room,
          post: event,
          ownerId: ownerId,
          reactions: List<Event>.of(reactions[eventId] ?? const []),
          comments: eventComments,
        ),
      );
    }
  }
  entries.sort((a, b) => b.timestamp.compareTo(a.timestamp));
  return entries;
}

/// Reads and writes the moments data of the current account.
class MomentsService {
  final Client client;

  const MomentsService(this.client);

  /// All moments feeds this account has joined.
  List<Room> get joinedRooms => client.rooms
      .where((room) => room.isMomentsRoom && room.membership == Membership.join)
      .toList();

  /// Moments feeds this account has been invited to but not joined yet.
  List<Room> get pendingInvites => client.rooms
      .where(
        (room) => room.isMomentsRoom && room.membership == Membership.invite,
      )
      .toList();

  /// The own moments feed, if it already exists.
  Room? get ownRoom {
    final userId = client.userID;
    if (userId == null) return null;
    for (final room in joinedRooms) {
      if (room.momentsOwnerId == userId) return room;
    }
    return null;
  }

  /// Returns the own moments room, creating it on first use.
  ///
  /// The room is private, has no members besides the owner and carries
  /// [momentsStateType] so the app can recognise it later. Friends are invited
  /// manually (`room.invite(userId)`), which is what makes them able to see this
  /// feed.
  Future<Room> ensureOwnRoom() async {
    final existing = ownRoom;
    if (existing != null) return existing;
    final userId = client.userID;
    if (userId == null) throw StateError('Not logged in');
    final displayName = await _ownDisplayName(userId);
    final roomId = await client.createRoom(
      name: '朋友圈 · $displayName',
      topic: momentsTopicMarker,
      preset: CreateRoomPreset.privateChat,
      visibility: Visibility.private,
      invite: const <String>[],
      initialState: [
        StateEvent(
          type: momentsStateType,
          stateKey: '',
          content: const {'version': 1},
        ),
      ],
    );
    final room = client.getRoomById(roomId);
    if (room == null) throw StateError('Unable to open the new moments room');
    return room;
  }

  Future<String> _ownDisplayName(String userId) async {
    try {
      final profile = await client.getUserProfile(userId);
      return profile.displayname ?? userId.localpart ?? userId;
    } catch (_) {
      return userId.localpart ?? userId;
    }
  }

  Future<Uri> uploadImage(Uint8List bytes, String filename) =>
      client.uploadContent(bytes, filename: filename);

  /// Publishes a post into [room].
  Future<void> publish({
    required Room room,
    required String body,
    required List<Uri> images,
  }) async {
    await room.sendEvent(<String, dynamic>{
      'msgtype': MessageTypes.Text,
      'body': body,
      if (images.isNotEmpty)
        momentsImagesKey: images.map((uri) => uri.toString()).toList(),
    });
  }

  /// Likes or unlikes [post].
  Future<void> setLiked({
    required Room room,
    required Event post,
    required List<Event> currentReactions,
    required bool liked,
  }) async {
    final userId = client.userID;
    if (userId == null) return;

    final ownReactions = currentReactions
        .where(
          (reaction) =>
              reaction.senderId == userId &&
              reaction.momentsReactionKey == momentsLikeKey,
        )
        .toList();

    if (liked) {
      for (final reaction in ownReactions) {
        await room.redactEvent(reaction.eventId);
      }
      return;
    }
    if (ownReactions.isNotEmpty) return;
    await room.sendReaction(post.eventId, momentsLikeKey);
  }

  /// Adds a comment to [post] as a thread reply.
  Future<void> comment({
    required Room room,
    required Event post,
    required String body,
  }) async {
    await room.sendEvent(
      <String, dynamic>{
        'msgtype': MessageTypes.Text,
        'body': body,
      },
      threadRootEventId: post.eventId,
    );
  }

  /// Deletes a post (or comment) of the own account.
  Future<void> delete({required Room room, required Event event}) async {
    await room.redactEvent(event.eventId);
  }

  /// Loads the timelines of all joined moments rooms.
  Future<List<Timeline>> loadTimelines({
    void Function()? onUpdate,
    int limit = 80,
  }) async {
    final timelines = <Timeline>[];
    for (final room in joinedRooms) {
      try {
        timelines.add(
          await room.getTimeline(
            limit: limit,
            onUpdate: onUpdate,
            onNewEvent: onUpdate,
          ),
        );
      } catch (exception, stackTrace) {
        Logs().w('Unable to load the timeline of ${room.id}', exception, stackTrace);
      }
    }
    return timelines;
  }
}
