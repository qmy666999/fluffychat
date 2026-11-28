// SPDX-FileCopyrightText: 2026 FluffyChatX contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:material_ui/material_ui.dart';

/// 启动失败时的兜底界面。
///
/// 之前启动路径上一旦抛异常，`runZonedGuarded` 只记日志，用户看到的就是
/// 一片灰屏——既不知道出了什么事，也没法把信息发出来。这里保证**任何**
/// 启动异常都能变成一段可读、可复制的文字。
class StartupFailureApp extends StatelessWidget {
  const StartupFailureApp({super.key, required this.error, this.theme});

  final String error;

  /// 只在测试里用：让 golden 能指定字体。
  final ThemeData? theme;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: Scaffold(
        backgroundColor: const Color(0xFF1B1B1F),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '启动失败',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'App 在启动过程中出错了。把下面的文字发给我，就能定位。',
                  style: TextStyle(color: Colors.white70, height: 1.5),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: SingleChildScrollView(
                    child: SelectableText(
                      error,
                      style: const TextStyle(
                        color: Color(0xFFFFB4AB),
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 替换默认的 `ErrorWidget`：release 包里默认是纯灰/纯红方块，什么都读不到。
///
/// 光有异常文字往往不够——`Null check operator used on a null value` 这类
/// 消息没有位置信息，必须把堆栈前几帧一起显示出来才能定位。
class StartupErrorPanel extends StatelessWidget {
  const StartupErrorPanel({super.key, required this.message, this.stack});

  final String message;

  /// 堆栈的前若干帧（由调用方裁剪好）。
  final String? stack;

  @override
  Widget build(BuildContext context) {
    final stack = this.stack?.trim();
    final text = StringBuffer('界面出错了\n\n$message');
    if (stack != null && stack.isNotEmpty) {
      text
        ..write('\n\n')
        ..write(stack);
    }
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        color: const Color(0xFF1B1B1F),
        padding: const EdgeInsets.all(16),
        alignment: Alignment.center,
        child: SingleChildScrollView(
          child: SelectableText(
            text.toString(),
            style: const TextStyle(
              color: Color(0xFFFFB4AB),
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ),
      ),
    );
  }
}
