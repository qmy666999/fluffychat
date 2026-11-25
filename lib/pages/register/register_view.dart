// SPDX-FileCopyrightText: 2026 Contributors to the FluffyChat register fork
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/layouts/login_scaffold.dart';
import 'package:material_ui/material_ui.dart';

import 'register.dart';

class RegisterView extends StatelessWidget {
  final RegisterController controller;

  const RegisterView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final homeserver = controller.homeserverName;
    final hasHomeserver = homeserver != null;

    return LoginScaffold(
      appBar: AppBar(
        leading: controller.loading ? null : const Center(child: BackButton()),
        automaticallyImplyLeading: !controller.loading,
        titleSpacing: !controller.loading ? 0 : null,
        title: Text(l10n.createNewAccount),
      ),
      body: AutofillGroup(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          children: <Widget>[
            const SizedBox(height: 8),
            Center(
              child: Hero(
                tag: 'info-logo',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(128),
                  child: Image.asset(
                    './assets/logo/mini/logo_mini.png',
                    width: 96,
                    height: 96,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (!hasHomeserver)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: TextField(
                  readOnly: controller.loading,
                  autocorrect: false,
                  controller: controller.serverController,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.dns_outlined),
                    hintText: 'matrix.org',
                    labelText: l10n.registerServerLabel,
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Row(
                  children: [
                    const Icon(Icons.dns_outlined, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SelectableText(
                        homeserver,
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: TextField(
                readOnly: controller.loading,
                autocorrect: false,
                autofocus: hasHomeserver,
                controller: controller.usernameController,
                textInputAction: TextInputAction.next,
                autofillHints: controller.loading
                    ? null
                    : const [AutofillHints.newUsername],
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.account_box_outlined),
                  errorText: controller.usernameError,
                  errorStyle: const TextStyle(color: Colors.orange),
                  hintText: 'username',
                  helperText: l10n.registerUsernameHint,
                  helperMaxLines: 2,
                  labelText: l10n.registerUsernameLabel,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: TextField(
                readOnly: controller.loading,
                autocorrect: false,
                obscureText: !controller.showPassword,
                controller: controller.passwordController,
                textInputAction: TextInputAction.next,
                autofillHints: controller.loading
                    ? null
                    : const [AutofillHints.newPassword],
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.lock_outlined),
                  suffixIcon: IconButton(
                    onPressed: controller.toggleShowPassword,
                    icon: Icon(
                      controller.showPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                  ),
                  hintText: '********',
                  labelText: l10n.registerPasswordLabel,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: TextField(
                readOnly: controller.loading,
                autocorrect: false,
                obscureText: !controller.showPassword,
                controller: controller.passwordConfirmController,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => controller.register(),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.lock_outline),
                  errorText: controller.passwordError,
                  errorStyle: const TextStyle(color: Colors.orange),
                  hintText: '********',
                  labelText: l10n.registerPasswordConfirmLabel,
                ),
              ),
            ),
            if (controller.error != null) ...[
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Material(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: theme.colorScheme.onErrorContainer,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SelectableText(
                            controller.error!,
                            style: TextStyle(
                              color: theme.colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
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
                    : Text(l10n.registerButton),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: TextButton(
                onPressed: controller.loading ? null : controller.backToLogin,
                child: Text(l10n.registerAlreadyHaveAccount),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
