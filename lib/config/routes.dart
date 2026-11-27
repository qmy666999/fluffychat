// SPDX-FileCopyrightText: 2019-Present Christian Ku鑴給wski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:animations/animations.dart';
import 'package:fluffychat/config/m3_motion.dart';
import 'package:fluffychat/config/motion_settings.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/pages/archive/archive.dart';
import 'package:fluffychat/pages/bootstrap/bootstrap_page.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pages/chat/chat_info_page.dart';
import 'package:fluffychat/pages/chat_access_settings/chat_access_settings_controller.dart';
import 'package:fluffychat/pages/chat_details/chat_details.dart';
import 'package:fluffychat/pages/chat_encryption_settings/chat_encryption_settings.dart';
import 'package:fluffychat/pages/chat_list/chat_list.dart';
import 'package:fluffychat/pages/chat_members/chat_members.dart';
import 'package:fluffychat/pages/chat_permissions_settings/chat_permissions_settings.dart';
import 'package:fluffychat/pages/chat_search/chat_search_page.dart';
import 'package:fluffychat/pages/contacts/add_friend_page.dart';
import 'package:fluffychat/pages/contacts/contacts_page.dart';
import 'package:fluffychat/pages/contacts/friend_profile_page.dart';
import 'package:fluffychat/pages/contacts/groups_page.dart';
import 'package:fluffychat/pages/contacts/new_friends_page.dart';
import 'package:fluffychat/pages/contacts/tags_page.dart';
import 'package:fluffychat/pages/device_settings/device_settings.dart';
import 'package:fluffychat/pages/discover/discover_page.dart';
import 'package:fluffychat/pages/intro/intro_page_presenter.dart';
import 'package:fluffychat/pages/invitation_selection/invitation_selection.dart';
import 'package:fluffychat/pages/login/login.dart';
import 'package:fluffychat/pages/me/favorites_page.dart';
import 'package:fluffychat/pages/me/me_page.dart';
import 'package:fluffychat/pages/moments/friend_moments_page.dart';
import 'package:fluffychat/pages/moments/moment_composer_page.dart';
import 'package:fluffychat/pages/moments/moments_page.dart';
import 'package:fluffychat/pages/new_group/new_group.dart';
import 'package:fluffychat/pages/new_private_chat/new_private_chat.dart';
import 'package:fluffychat/pages/register/register.dart';
import 'package:fluffychat/pages/settings/discover_manage_page.dart';
import 'package:fluffychat/pages/settings/settings.dart';
import 'package:fluffychat/pages/settings/wechat_settings_pages.dart';
import 'package:fluffychat/pages/settings_3pid/settings_3pid.dart';
import 'package:fluffychat/pages/settings_chat/settings_chat.dart';
import 'package:fluffychat/pages/settings_emotes/settings_emotes.dart';
import 'package:fluffychat/pages/settings_homeserver/settings_homeserver.dart';
import 'package:fluffychat/pages/settings_ignore_list/settings_ignore_list.dart';
import 'package:fluffychat/pages/settings_notifications/settings_notifications.dart';
import 'package:fluffychat/pages/settings_password/settings_password.dart';
import 'package:fluffychat/pages/settings_security/settings_security.dart';
import 'package:fluffychat/pages/settings_style/settings_style.dart';
import 'package:fluffychat/pages/sign_in/sign_in_page.dart';
import 'package:fluffychat/pages/voip/voip_call_page.dart';
import 'package:fluffychat/widgets/config_viewer.dart';
import 'package:fluffychat/widgets/layouts/empty_page.dart';
import 'package:fluffychat/widgets/layouts/two_column_layout.dart';
import 'package:fluffychat/widgets/log_view.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/share_scaffold_dialog.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

abstract class AppRoutes {
  static FutureOr<String?> loggedInRedirect(
    BuildContext context,
    GoRouterState state,
  ) => Matrix.of(context).widget.clients.any((client) => client.isLogged())
      ? '/rooms'
      : null;

  static FutureOr<String?> loggedOutRedirect(
    BuildContext context,
    GoRouterState state,
  ) => Matrix.of(context).widget.clients.any((client) => client.isLogged())
      ? null
      : '/home';

  AppRoutes();

  static final List<RouteBase> routes = [
    GoRoute(
      path: '/',
      redirect: (context, state) =>
          Matrix.of(context).widget.clients.any((client) => client.isLogged())
          ? '/rooms'
          : '/home',
    ),
    GoRoute(
      path: '/home',
      pageBuilder: (context, state) =>
          defaultPageBuilder(context, state, const IntroPagePresenter()),
      redirect: loggedInRedirect,
      routes: [
        GoRoute(
          path: 'sign_in',
          pageBuilder: (context, state) =>
              defaultPageBuilder(context, state, SignInPage(signUp: false)),
          redirect: loggedInRedirect,
        ),
        GoRoute(
          path: 'sign_up',
          pageBuilder: (context, state) =>
              defaultPageBuilder(context, state, SignInPage(signUp: true)),
          redirect: loggedInRedirect,
        ),
        GoRoute(
          path: 'register',
          pageBuilder: (context, state) =>
              defaultPageBuilder(context, state, const RegisterPage()),
          redirect: loggedInRedirect,
        ),
        GoRoute(
          path: 'login',
          pageBuilder: (context, state) => defaultPageBuilder(
            context,
            state,
            Login(client: state.extra as Client),
          ),
          redirect: loggedInRedirect,
        ),
      ],
    ),
    GoRoute(
      path: '/contacts',
      pageBuilder: (context, state) =>
          defaultPageBuilder(context, state, const ContactsPage()),
      routes: [
        GoRoute(
          path: 'add',
          pageBuilder: (context, state) => defaultPageBuilder(
            context,
            state,
            AddFriendPage(initialQuery: state.uri.queryParameters['q']),
          ),
        ),
        GoRoute(
          path: 'new',
          pageBuilder: (context, state) =>
              defaultPageBuilder(context, state, const NewFriendsPage()),
        ),
        GoRoute(
          path: 'friend',
          pageBuilder: (context, state) => defaultPageBuilder(
            context,
            state,
            FriendProfilePage(
              userId: state.uri.queryParameters['userId'] ?? '',
            ),
          ),
        ),
        GoRoute(
          path: 'groups',
          pageBuilder: (context, state) =>
              defaultPageBuilder(context, state, const GroupsPage()),
        ),
        GoRoute(
          path: 'tags',
          pageBuilder: (context, state) =>
              defaultPageBuilder(context, state, const TagsPage()),
        ),
      ],
    ),
    GoRoute(
      path: '/discover',
      pageBuilder: (context, state) =>
          defaultPageBuilder(context, state, const DiscoverPage()),
    ),
    GoRoute(
      path: '/me',
      pageBuilder: (context, state) =>
          defaultPageBuilder(context, state, const MePage()),
      routes: [
        GoRoute(
          path: 'favorites',
          pageBuilder: (context, state) =>
              defaultPageBuilder(context, state, const FavoritesPage()),
        ),
      ],
    ),
    // 1 对 1 语音/视频通话：全屏独立路由。
    GoRoute(
      path: '/call',
      pageBuilder: (context, state) =>
          defaultPageBuilder(context, state, const VoipCallPage()),
    ),
    // 朋友圈：全屏页面，故意不放底部导航（它是从发现页点进来的子页面）。
    GoRoute(
      path: '/moments',
      pageBuilder: (context, state) =>
          defaultPageBuilder(context, state, const MomentsPage()),
      routes: [
        GoRoute(
          path: 'compose',
          pageBuilder: (context, state) =>
              defaultPageBuilder(context, state, const MomentComposerPage()),
        ),
        GoRoute(
          path: 'friend',
          pageBuilder: (context, state) => defaultPageBuilder(
            context,
            state,
            FriendMomentsPage(
              userId: state.uri.queryParameters['userId'] ?? '',
            ),
          ),
        ),
      ],
    ),
    GoRoute(
      path: '/logs',
      pageBuilder: (context, state) =>
          defaultPageBuilder(context, state, const LogViewer()),
    ),
    GoRoute(
      path: '/configs',
      pageBuilder: (context, state) =>
          defaultPageBuilder(context, state, const ConfigViewer()),
    ),
    GoRoute(
      path: '/backup',
      redirect: loggedOutRedirect,
      pageBuilder: (context, state) => defaultPageBuilder(
        context,
        state,
        BootstrapPage(reset: state.uri.queryParameters['reset'] == 'true'),
      ),
    ),
    ShellRoute(
      // Never use a transition on the shell route. Changing the PageBuilder
      // here based on a MediaQuery causes the child to briefly be rendered
      // twice with the same GlobalKey, blowing up the rendering.
      pageBuilder: (context, state, child) => noTransitionPageBuilder(
        context,
        state,
        FluffyThemes.isColumnMode(context) &&
                state.fullPath?.startsWith('/rooms/settings') == false
            ? TwoColumnLayout(
                mainView: ChatList(
                  activeChat: state.pathParameters['roomid'],
                  activeSpace: state.uri.queryParameters['spaceId'],
                  displayNavigationRail:
                      state.path?.startsWith('/rooms/settings') != true,
                ),
                sideView: child,
              )
            : child,
      ),
      routes: [
        GoRoute(
          path: '/rooms',
          redirect: loggedOutRedirect,
          pageBuilder: (context, state) => defaultPageBuilder(
            context,
            state,
            FluffyThemes.isColumnMode(context)
                ? const EmptyPage()
                : ChatList(
                    activeChat: state.pathParameters['roomid'],
                    activeSpace: state.uri.queryParameters['spaceId'],
                  ),
          ),
          routes: [
            // 微信式聊天信息页：右上「…」进来的整页设置。
            GoRoute(
              path: 'info',
              pageBuilder: (context, state) => defaultPageBuilder(
                context,
                state,
                ChatInfoPage(roomId: state.uri.queryParameters['roomId'] ?? ''),
              ),
              redirect: loggedOutRedirect,
            ),
            GoRoute(
              path: 'archive',
              pageBuilder: (context, state) =>
                  defaultPageBuilder(context, state, const Archive()),
              routes: [
                GoRoute(
                  path: ':roomid',
                  pageBuilder: (context, state) => defaultPageBuilder(
                    context,
                    state,
                    ChatPage(
                      key: ValueKey(state.uri),
                      roomId: state.pathParameters['roomid']!,
                      eventId: state.uri.queryParameters['event'],
                      timeline: state.extra as Timeline?,
                      action: state.uri.queryParameters['action'],
                    ),
                  ),
                  redirect: loggedOutRedirect,
                ),
              ],
              redirect: loggedOutRedirect,
            ),
            GoRoute(
              path: 'newprivatechat',
              pageBuilder: (context, state) => defaultPageBuilder(
                context,
                state,
                NewPrivateChat(
                  key: ValueKey('new_chat_${state.uri.fragment}'),
                  deeplink: state.uri.fragment,
                ),
              ),
              redirect: loggedOutRedirect,
            ),
            GoRoute(
              path: 'newgroup',
              pageBuilder: (context, state) => defaultPageBuilder(
                context,
                state,
                NewGroup(spaceId: state.uri.queryParameters['space_id']),
              ),
              redirect: loggedOutRedirect,
            ),
            GoRoute(
              path: 'newspace',
              pageBuilder: (context, state) => defaultPageBuilder(
                context,
                state,
                NewGroup(
                  createGroupType: CreateGroupType.space,
                  spaceId: state.uri.queryParameters['space_id'],
                ),
              ),
              redirect: loggedOutRedirect,
            ),
            ShellRoute(
              pageBuilder: (context, state, child) => defaultPageBuilder(
                context,
                state,
                FluffyThemes.isColumnMode(context)
                    ? TwoColumnLayout(
                        mainView: Settings(key: state.pageKey),
                        sideView: child,
                        hasNavigationRail: false,
                      )
                    : child,
              ),
              routes: [
                GoRoute(
                  path: 'settings',
                  pageBuilder: (context, state) => defaultPageBuilder(
                    context,
                    state,
                    FluffyThemes.isColumnMode(context)
                        ? const EmptyPage()
                        : const Settings(),
                  ),
                  routes: [
                    GoRoute(
                      path: 'notifications',
                      pageBuilder: (context, state) => defaultPageBuilder(
                        context,
                        state,
                        const SettingsNotifications(),
                      ),
                      redirect: loggedOutRedirect,
                    ),
                    GoRoute(
                      path: 'style',
                      pageBuilder: (context, state) => defaultPageBuilder(
                        context,
                        state,
                        const SettingsStyle(),
                      ),
                      redirect: loggedOutRedirect,
                    ),
                    // 微信式二级设置页
                    GoRoute(
                      path: 'wechat-account',
                      pageBuilder: (context, state) => defaultPageBuilder(
                        context,
                        state,
                        const SettingsAccountPage(),
                      ),
                      redirect: loggedOutRedirect,
                    ),
                    GoRoute(
                      path: 'wechat-notifications',
                      pageBuilder: (context, state) => defaultPageBuilder(
                        context,
                        state,
                        const SettingsNotificationsPage(),
                      ),
                      redirect: loggedOutRedirect,
                    ),
                    GoRoute(
                      path: 'wechat-chat',
                      pageBuilder: (context, state) => defaultPageBuilder(
                        context,
                        state,
                        const SettingsChatPage(),
                      ),
                      redirect: loggedOutRedirect,
                    ),
                    GoRoute(
                      path: 'wechat-general',
                      pageBuilder: (context, state) => defaultPageBuilder(
                        context,
                        state,
                        const SettingsGeneralPage(),
                      ),
                      redirect: loggedOutRedirect,
                    ),
                    GoRoute(
                      path: 'wechat-privacy',
                      pageBuilder: (context, state) => defaultPageBuilder(
                        context,
                        state,
                        const SettingsPrivacyPage(),
                      ),
                      redirect: loggedOutRedirect,
                    ),
                    GoRoute(
                      path: 'wechat-friend-permission',
                      pageBuilder: (context, state) => defaultPageBuilder(
                        context,
                        state,
                        const SettingsFriendPermissionPage(),
                      ),
                      redirect: loggedOutRedirect,
                    ),
                    GoRoute(
                      path: 'wechat-personal-info',
                      pageBuilder: (context, state) => defaultPageBuilder(
                        context,
                        state,
                        const SettingsPersonalInfoPage(),
                      ),
                      redirect: loggedOutRedirect,
                    ),
                    GoRoute(
                      path: 'wechat-about',
                      pageBuilder: (context, state) => defaultPageBuilder(
                        context,
                        state,
                        const SettingsAboutPage(),
                      ),
                      redirect: loggedOutRedirect,
                    ),
                    GoRoute(
                      path: 'wechat-help',
                      pageBuilder: (context, state) => defaultPageBuilder(
                        context,
                        state,
                        const SettingsHelpPage(),
                      ),
                      redirect: loggedOutRedirect,
                    ),
                    GoRoute(
                      path: 'discover-manage',
                      pageBuilder: (context, state) => defaultPageBuilder(
                        context,
                        state,
                        const DiscoverManagePage(),
                      ),
                      redirect: loggedOutRedirect,
                    ),
                    GoRoute(
                      path: 'storage',
                      pageBuilder: (context, state) => defaultPageBuilder(
                        context,
                        state,
                        const StorageSpacePage(),
                      ),
                      redirect: loggedOutRedirect,
                    ),
                    GoRoute(
                      path: 'devices',
                      pageBuilder: (context, state) => defaultPageBuilder(
                        context,
                        state,
                        const DevicesSettings(),
                      ),
                      redirect: loggedOutRedirect,
                    ),
                    GoRoute(
                      path: 'chat',
                      pageBuilder: (context, state) => defaultPageBuilder(
                        context,
                        state,
                        const SettingsChat(),
                      ),
                      routes: [
                        GoRoute(
                          path: 'emotes',
                          pageBuilder: (context, state) => defaultPageBuilder(
                            context,
                            state,
                            EmotesSettings(
                              roomId: state.pathParameters['roomid'],
                            ),
                          ),
                        ),
                      ],
                      redirect: loggedOutRedirect,
                    ),
                    GoRoute(
                      path: 'addaccount',
                      redirect: loggedOutRedirect,
                      pageBuilder: (context, state) => defaultPageBuilder(
                        context,
                        state,
                        const IntroPagePresenter(),
                      ),
                      routes: [
                        GoRoute(
                          path: 'sign_in',
                          pageBuilder: (context, state) => defaultPageBuilder(
                            context,
                            state,
                            SignInPage(signUp: false),
                          ),
                          redirect: loggedOutRedirect,
                        ),
                        GoRoute(
                          path: 'sign_up',
                          pageBuilder: (context, state) => defaultPageBuilder(
                            context,
                            state,
                            SignInPage(signUp: true),
                          ),
                          redirect: loggedOutRedirect,
                        ),
                        // 「添加账户」这条入口也要能进应用内注册页，
                        // 否则和 /rooms/settings/login 是同一类缺路由的错误。
                        GoRoute(
                          path: 'register',
                          pageBuilder: (context, state) => defaultPageBuilder(
                            context,
                            state,
                            const RegisterPage(),
                          ),
                          redirect: loggedOutRedirect,
                        ),
                        GoRoute(
                          path: 'login',
                          pageBuilder: (context, state) => defaultPageBuilder(
                            context,
                            state,
                            Login(client: state.extra as Client),
                          ),
                          redirect: loggedOutRedirect,
                        ),
                      ],
                    ),
                    GoRoute(
                      path: 'homeserver',
                      pageBuilder: (context, state) {
                        return defaultPageBuilder(
                          context,
                          state,
                          const SettingsHomeserver(),
                        );
                      },
                      redirect: loggedOutRedirect,
                    ),
                    GoRoute(
                      path: 'security',
                      redirect: loggedOutRedirect,
                      pageBuilder: (context, state) => defaultPageBuilder(
                        context,
                        state,
                        const SettingsSecurity(),
                      ),
                      routes: [
                        GoRoute(
                          path: 'password',
                          pageBuilder: (context, state) {
                            return defaultPageBuilder(
                              context,
                              state,
                              const SettingsPassword(),
                            );
                          },
                          redirect: loggedOutRedirect,
                        ),
                        GoRoute(
                          path: 'ignorelist',
                          pageBuilder: (context, state) {
                            return defaultPageBuilder(
                              context,
                              state,
                              SettingsIgnoreList(
                                initialUserId: state.extra?.toString(),
                              ),
                            );
                          },
                          redirect: loggedOutRedirect,
                        ),
                        GoRoute(
                          path: '3pid',
                          pageBuilder: (context, state) => defaultPageBuilder(
                            context,
                            state,
                            const Settings3Pid(),
                          ),
                          redirect: loggedOutRedirect,
                        ),
                      ],
                    ),
                  ],
                  redirect: loggedOutRedirect,
                ),
              ],
            ),
            GoRoute(
              path: ':roomid',
              pageBuilder: (context, state) {
                final body = state.uri.queryParameters['body'];
                var shareItems = state.extra is List<ShareItem>
                    ? state.extra as List<ShareItem>
                    : null;
                if (body != null && body.isNotEmpty) {
                  shareItems ??= [];
                  shareItems.add(TextShareItem(body));
                }
                return defaultPageBuilder(
                  context,
                  state,
                  ChatPage(
                    key: ValueKey(state.uri),
                    roomId: state.pathParameters['roomid']!,
                    shareItems: shareItems,
                    eventId: state.uri.queryParameters['event'],
                    action: state.uri.queryParameters['action'],
                  ),
                );
              },
              redirect: loggedOutRedirect,
              routes: [
                GoRoute(
                  path: 'search',
                  pageBuilder: (context, state) => defaultPageBuilder(
                    context,
                    state,
                    ChatSearchPage(roomId: state.pathParameters['roomid']!),
                  ),
                  redirect: loggedOutRedirect,
                ),
                GoRoute(
                  path: 'encryption',
                  pageBuilder: (context, state) => defaultPageBuilder(
                    context,
                    state,
                    const ChatEncryptionSettings(),
                  ),
                  redirect: loggedOutRedirect,
                ),
                GoRoute(
                  path: 'invite',
                  pageBuilder: (context, state) => defaultPageBuilder(
                    context,
                    state,
                    InvitationSelection(
                      roomId: state.pathParameters['roomid']!,
                    ),
                  ),
                  redirect: loggedOutRedirect,
                ),
                GoRoute(
                  path: 'details',
                  pageBuilder: (context, state) => defaultPageBuilder(
                    context,
                    state,
                    ChatDetails(roomId: state.pathParameters['roomid']!),
                  ),
                  routes: [
                    GoRoute(
                      path: 'access',
                      pageBuilder: (context, state) => defaultPageBuilder(
                        context,
                        state,
                        ChatAccessSettings(
                          roomId: state.pathParameters['roomid']!,
                        ),
                      ),
                      redirect: loggedOutRedirect,
                    ),
                    GoRoute(
                      path: 'members',
                      pageBuilder: (context, state) => defaultPageBuilder(
                        context,
                        state,
                        ChatMembersPage(
                          roomId: state.pathParameters['roomid']!,
                        ),
                      ),
                      redirect: loggedOutRedirect,
                    ),
                    GoRoute(
                      path: 'permissions',
                      pageBuilder: (context, state) => defaultPageBuilder(
                        context,
                        state,
                        const ChatPermissionsSettings(),
                      ),
                      redirect: loggedOutRedirect,
                    ),
                    GoRoute(
                      path: 'invite',
                      pageBuilder: (context, state) => defaultPageBuilder(
                        context,
                        state,
                        InvitationSelection(
                          roomId: state.pathParameters['roomid']!,
                        ),
                      ),
                      redirect: loggedOutRedirect,
                    ),
                    GoRoute(
                      path: 'emotes',
                      pageBuilder: (context, state) => defaultPageBuilder(
                        context,
                        state,
                        EmotesSettings(roomId: state.pathParameters['roomid']),
                      ),
                      redirect: loggedOutRedirect,
                    ),
                  ],
                  redirect: loggedOutRedirect,
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  ];

  static Page noTransitionPageBuilder(
    BuildContext context,
    GoRouterState state,
    Widget child,
  ) => NoTransitionPage(
    key: state.pageKey,
    restorationId: state.pageKey.value,
    child: child,
  );

  /// 四个平级 tab 的路径。判断用：tab 之间切换不用纵向共享轴。
  static const _tabPaths = {'/rooms', '/contacts', '/discover', '/me'};

  /// 按用户在设置里选的动效风格生成页面转场。
  ///
  /// 桌面端的 column 模式不参与（没有整页切换感，动起来反而乱）。
  static Page motionPageBuilder(GoRouterState state, Widget child) {
    final isTab = _tabPaths.contains(state.uri.path);
    final style = MotionSettings.effectiveStyle(isTab: isTab);

    if (style == MotionStyle.none) {
      return CustomTransitionPage(
        key: state.pageKey,
        restorationId: state.pageKey.value,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        transitionsBuilder: (_, _, _, child) => child,
        child: child,
      );
    }

    final duration = MotionSettings.scaled(MotionSettings.baseDuration);

    // 四个平级 tab 之间用横向共享轴：新页从右边 8dp 滑入 + 淡入，
    // 旧页同时往左退 8dp，位移很小，看起来像「同一层左右推一下」而不是压栈。
    //
    // 只在用户选的是「系统默认 / 淡入淡出 / 共享轴」时接管：选 zoom、
    // 容器变换这类风格的，说明他想要别的观感，tab 也尊重他的选择。
    if (isTab &&
        (style == MotionStyle.system ||
            style == MotionStyle.fadeThrough ||
            style == MotionStyle.sharedAxisX ||
            style == MotionStyle.sharedAxisY)) {
      return CustomTransitionPage(
        key: state.pageKey,
        restorationId: state.pageKey.value,
        transitionDuration: duration,
        reverseTransitionDuration: duration,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final incoming = animation.drive(
            Tween<Offset>(
              begin: const Offset(0.02, 0),
              end: Offset.zero,
            ).chain(CurveTween(curve: M3Motion.emphasizedDecel)),
          );
          final outgoing = secondaryAnimation.drive(
            Tween<Offset>(
              begin: Offset.zero,
              end: const Offset(-0.02, 0),
            ).chain(CurveTween(curve: M3Motion.emphasized)),
          );
          return SlideTransition(
            position: outgoing,
            child: SlideTransition(
              position: incoming,
              child: FadeTransition(
                opacity: animation.drive(CurveTween(curve: Curves.easeIn)),
                child: child,
              ),
            ),
          );
        },
        child: child,
      );
    }
    return CustomTransitionPage(
      key: state.pageKey,
      restorationId: state.pageKey.value,
      transitionDuration: duration,
      reverseTransitionDuration: duration,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final fillColor = Theme.of(context).colorScheme.surface;
        switch (style) {
          case MotionStyle.fadeThrough:
            return FadeThroughTransition(
              animation: animation,
              secondaryAnimation: secondaryAnimation,
              fillColor: fillColor,
              child: child,
            );
          case MotionStyle.sharedAxisX:
            return SharedAxisTransition(
              animation: animation,
              secondaryAnimation: secondaryAnimation,
              transitionType: SharedAxisTransitionType.horizontal,
              fillColor: fillColor,
              child: child,
            );
          case MotionStyle.sharedAxisY:
            return SharedAxisTransition(
              animation: animation,
              secondaryAnimation: secondaryAnimation,
              transitionType: SharedAxisTransitionType.vertical,
              fillColor: fillColor,
              child: child,
            );
          case MotionStyle.containerTransform:
            return SharedAxisTransition(
              animation: animation,
              secondaryAnimation: secondaryAnimation,
              transitionType: SharedAxisTransitionType.scaled,
              fillColor: fillColor,
              child: child,
            );
          case MotionStyle.zoom:
          case MotionStyle.system:
            // 交回给当前平台自己的转场实现（Android 是 Zoom，iOS 是 Cupertino）。
            final route = ModalRoute.of(context);
            final theme = Theme.of(context);
            final builder =
                theme.pageTransitionsTheme.builders[theme.platform] ??
                const ZoomPageTransitionsBuilder();
            if (route is PageRoute) {
              return builder.buildTransitions(
                route,
                context,
                animation,
                secondaryAnimation,
                child,
              );
            }
            return child;
          case MotionStyle.none:
            return child;
        }
      },
      child: child,
    );
  }

  static Page defaultPageBuilder(
    BuildContext context,
    GoRouterState state,
    Widget child,
  ) {
    final clientName = state.uri.queryParameters['client'];
    if (clientName != null) {
      final matrix = Matrix.of(context);
      final client = matrix.getClientByName(clientName);
      if (client != null) matrix.setActiveClient(client);
    }
    return FluffyThemes.isColumnMode(context)
        ? noTransitionPageBuilder(context, state, child)
        : motionPageBuilder(state, child);
  }
}
