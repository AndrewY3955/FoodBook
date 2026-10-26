import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/failure.dart';
import '../../core/security/password_policy.dart';
import '../../state/providers.dart';
import '../responsive/breakpoints.dart';

enum _Mode { signIn, signUp, reset }

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _name = TextEditingController();

  _Mode _mode = _Mode.signIn;
  bool _busy = false;
  bool _obscure = true;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _error = null;
      _notice = null;
    });
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _busy = true);
    try {
      final auth = ref.read(authRepositoryProvider);
      switch (_mode) {
        case _Mode.signIn:
          await auth.signIn(
            email: _email.text,
            password: _password.text,
          );
        case _Mode.signUp:
          await auth.signUp(
            email: _email.text,
            password: _password.text,
            displayName: _name.text,
          );
          if (mounted) {
            setState(() {
              _notice = 'Check your email to confirm the account.';
              _mode = _Mode.signIn;
            });
          }
        case _Mode.reset:
          await auth.sendPasswordReset(_email.text);
          if (mounted) {
            setState(() {
              // Same message whether or not the address exists.
              _notice =
                  'If that address has an account, a reset link is on its way.';
              _mode = _Mode.signIn;
            });
          }
      }
    } catch (error) {
      if (mounted) setState(() => _error = Failure.from(error).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      body: ResponsiveBuilder(
        builder: (BuildContext context, LayoutScope scope) {
          final Widget form = Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: _buildForm(theme),
              ),
            ),
          );

          // Desktop and tablet get a two-pane sign-in; a 420 px form
          // alone on a 27-inch display looks broken.
          if (scope.isPhone) return SafeArea(child: form);

          return Row(
            children: <Widget>[
              Expanded(
                flex: scope.isDesktop ? 5 : 4,
                child: Container(
                  color: theme.colorScheme.primaryContainer,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(48),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Icon(
                            Icons.soup_kitchen_outlined,
                            size: 56,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'Your recipes, your pantry,\nyour week.',
                            style: theme.textTheme.displaySmall?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Shared with the people you cook for, and nobody else.',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(flex: 6, child: SafeArea(child: form)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildForm(ThemeData theme) {
    final bool isSignUp = _mode == _Mode.signUp;
    final bool isReset = _mode == _Mode.reset;

    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            switch (_mode) {
              _Mode.signIn => 'Welcome back',
              _Mode.signUp => 'Create your library',
              _Mode.reset => 'Reset your password',
            },
            style: theme.textTheme.headlineMedium,
          ),
          const SizedBox(height: 24),

          if (isSignUp) ...<Widget>[
            TextFormField(
              controller: _name,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'What should we call you?',
                prefixIcon: Icon(Icons.person_outline),
              ),
              validator: (String? v) =>
                  (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
            ),
            const SizedBox(height: 12),
          ],

          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const <String>[AutofillHints.email],
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.alternate_email),
            ),
            validator: (String? v) =>
                (v == null || !v.contains('@')) ? 'Enter your email' : null,
          ),

          if (!isReset) ...<Widget>[
            const SizedBox(height: 12),
            TextFormField(
              controller: _password,
              obscureText: _obscure,
              autofillHints: <String>[
                isSignUp ? AutofillHints.newPassword : AutofillHints.password,
              ],
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _busy ? null : _submit(),
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              onChanged: (_) => setState(() {}),
              validator: (String? v) {
                if (v == null || v.isEmpty) return 'Enter your password';
                if (!isSignUp) return null;
                final List<String> problems = PasswordPolicy.violations(v);
                return problems.isEmpty
                    ? null
                    : 'Needs: ${problems.join(', ').toLowerCase()}';
              },
            ),
            if (isSignUp) ...<Widget>[
              const SizedBox(height: 8),
              _StrengthBar(password: _password.text),
            ],
          ],

          if (_error != null) ...<Widget>[
            const SizedBox(height: 16),
            _Banner(text: _error!, tone: _BannerTone.error),
          ],
          if (_notice != null) ...<Widget>[
            const SizedBox(height: 16),
            _Banner(text: _notice!, tone: _BannerTone.info),
          ],

          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _submit,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            child: _busy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(switch (_mode) {
                    _Mode.signIn => 'Sign in',
                    _Mode.signUp => 'Create account',
                    _Mode.reset => 'Send reset link',
                  }),
          ),

          const SizedBox(height: 12),
          if (_mode == _Mode.signIn)
            TextButton(
              onPressed:
                  _busy ? null : () => setState(() => _mode = _Mode.reset),
              child: const Text('Forgot your password?'),
            ),

          TextButton(
            onPressed: _busy
                ? null
                : () => setState(
                      () => _mode =
                          _mode == _Mode.signUp ? _Mode.signIn : _Mode.signUp,
                    ),
            child: Text(
              _mode == _Mode.signUp
                  ? 'I already have an account'
                  : 'Create an account',
            ),
          ),

          // Apple and Google are wired in AuthRepository. The buttons
          // appear once the providers are enabled in the Supabase
          // dashboard; showing them before that would produce a dead
          // button, which is worse than no button.
        ],
      ),
    );
  }
}

class _StrengthBar extends StatelessWidget {
  const _StrengthBar({required this.password});

  final String password;

  @override
  Widget build(BuildContext context) {
    final double value = PasswordPolicy.strength(password);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color color = value < 0.4
        ? scheme.error
        : (value < 0.75 ? Colors.orange : Colors.green);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 6,
            backgroundColor: scheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'At least ${PasswordPolicy.minLength} characters, with letters '
          'and numbers. Longer is stronger.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

enum _BannerTone { error, info }

class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.tone});

  final String text;
  final _BannerTone tone;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool isError = tone == _BannerTone.error;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isError ? scheme.errorContainer : scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            isError ? Icons.error_outline : Icons.info_outline,
            size: 20,
            color:
                isError ? scheme.onErrorContainer : scheme.onSecondaryContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: isError
                    ? scheme.onErrorContainer
                    : scheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
