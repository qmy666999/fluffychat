// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/pages/call/call_page.dart';
import 'package:fluffychat/pages/voip/voip_call_page.dart';
import 'package:fluffychat/utils/voip/matrix_voip.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class CallOverlay extends StatelessWidget {
  final Widget child;
  const CallOverlay({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    final voip = MatrixVoip.ensure(Matrix.of(context).client);
    return ValueListenableBuilder<CallSession?>(
      valueListenable: voip.activeCall,
      builder: (context, call, _) {
        final base = _elementCallOverlay(context);
        if (call == null) return base;
        // 1 对 1 mesh 通话优先，全屏盖住当前页面（来电时也在这里接）。
        return Stack(
          children: [
            base,
            Positioned.fill(
              child: VoipCallPage(key: ValueKey(call.callId), voip: voip),
            ),
          ],
        );
      },
    );
  }

  /// 上游的 MatrixRTC / Element Call 浮层，保持原样。
  Widget _elementCallOverlay(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: Matrix.of(context).activeCallRoomId,
      builder: (context, value, _) {
        final roomId = value;
        if (roomId == null) return child;
        return ValueListenableBuilder(
          valueListenable: Matrix.of(context).callPosition,
          builder: (context, value, _) {
            final callPosition = value;
            final callFullScreen = callPosition == .fullScreen;
            return Stack(
              children: [
                child,
                AnimatedPositioned(
                  duration: FluffyThemes.animationDuration,
                  curve: FluffyThemes.animationCurve,
                  top: callFullScreen
                      ? 0
                      : callPosition == .top
                      ? 86
                      : null,
                  left: callFullScreen ? 0 : null,
                  right: callFullScreen ? 0 : 8,
                  bottom: callFullScreen ? 0 : null,
                  height: callFullScreen ? null : 256,
                  width: callFullScreen ? null : 256,
                  child: Material(
                    elevation: callFullScreen ? 0 : 4,
                    clipBehavior: .hardEdge,
                    shape: callFullScreen
                        ? null
                        : RoundedRectangleBorder(
                            side: BorderSide(color: Colors.grey),
                            borderRadius: BorderRadius.circular(
                              AppConfig.borderRadius,
                            ),
                          ),
                    child: Navigator(
                      onDidRemovePage: (_) {
                        Matrix.of(context).activeCallRoomId.value = null;
                      },
                      pages: [MaterialPage(child: CallPage(roomId: roomId))],
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
