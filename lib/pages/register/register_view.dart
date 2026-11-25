// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/layouts/login_scaffold.dart';
import 'package:material_ui/material_ui.dart';

import 'register.dart';

class RegisterView extends StatelessWidget {
  final RegisterPageController controller;

  const RegisterView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);

    return LoginScaffold(
      appBar: AppBar(
        leading: controller.loading ? null : const Center(child: BackButton()),
        automaticallyImplyLeading: !controller.loading,
        titleSpacing: !controller.loading ? 0 : null,
        centerTitle: true,
        title: Text(l10n.registerAccountTitle),
      ),
      body: AutofillGroup(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          children: [
            Center(
              child: Hero(
                tag: 'info-logo',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(128),
                  child: Image.asset(
                    './assets/logo/mini/logo_mini.png',
                    width: 128,
                    height: 128,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Text(
                l10n.registerAccountSubtitle(controller.homeserver),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: TextField(
                readOnly: controller.loading,
                autocorrect: false,
                autofocus: true,
                controller: controller.usernameController,
                textInputAction: TextInputAction.next,
                autofillHints: controller.loading
                    ? null
                    : [AutofillHints.newUsername],
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.account_box_outlined),
                  errorText: controller.usernameError,
                  errorStyle: const TextStyle(color: Colors.orange),
                  hintText: l10n.registerUsernameHint,
                  labelText: l10n.registerUsername,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: TextField(
                readOnly: controller.loading,
                autocorrect: false,
                autofillHints: controller.loading
                    ? null
                    : [AutofillHints.newPassword],
                controller: controller.passwordController,
                textInputAction: TextInputAction.next,
                obscureText: !controller.showPassword,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.lock_outlined),
                  errorText: controller.passwordError,
                  errorStyle: const TextStyle(color: Colors.orange),
                  suffixIcon: IconButton(
                    onPressed: controller.toggleShowPassword,
                    icon: Icon(
                      controller.showPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                  ),
                  hintText: '********',
                  labelText: l10n.password,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: TextField(
                readOnly: controller.loading,
                autocorrect: false,
                controller: controller.confirmPasswordController,
                textInputAction: TextInputAction.go,
                obscureText: !controller.showPassword,
                onSubmitted: (_) => controller.register(),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.lock_outlined),
                  errorText: controller.confirmPasswordError,
                  errorStyle: const TextStyle(color: Colors.orange),
                  hintText: '********',
                  labelText: l10n.confirmPassword,
                ),
              ),
            ),
            if (controller.formError != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SelectableText(
                    controller.formError!,
                    style: TextStyle(
                      color: theme.colorScheme.onErrorContainer,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                ),
                onPressed: controller.loading ? null : controller.register,
                child: controller.loading
                    ? const LinearProgressIndicator()
                    : Text(l10n.register),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: TextButton(
                onPressed: controller.loading
                    ? null
                    : controller.changeHomeserver,
                child: Text(l10n.changeServer),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
