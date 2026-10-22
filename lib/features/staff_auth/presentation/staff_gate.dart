import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/localization/localized_text.dart';
import '../../../ui_primitives/controls/mawzoon_input_decoration.dart';
import '../../../ui_primitives/controls/mawzoon_pill_button.dart';
import '../../../ui_primitives/text/mawzoon_text.dart';
import '../../../ui_primitives/theme/theme_context.dart';
import '../domain/staff_auth.dart';

/// Shows [signedIn] only to a signed-in staff member; everyone else gets the
/// sign-in card. Used by both staff apps (kitchen and back office).
class StaffGate extends StatefulWidget {
  /// Creates the gate.
  const StaffGate({
    required this.auth,
    required this.subtitle,
    required this.note,
    required this.signedIn,
    super.key,
  });

  /// Who decides.
  final StaffAuth auth;

  /// Which app this is, under the wordmark.
  final LocalizedText subtitle;

  /// The quiet line under the button.
  final LocalizedText note;

  /// The app itself, built only once access is confirmed.
  final WidgetBuilder signedIn;

  @override
  State<StaffGate> createState() => _StaffGateState();
}

class _StaffGateState extends State<StaffGate> {
  StaffAccess? _access;

  @override
  void initState() {
    super.initState();
    unawaited(_check());
  }

  Future<void> _check() async {
    final StaffAccess access = await widget.auth.current();
    if (mounted) setState(() => _access = access);
  }

  Future<void> _signOut() async {
    await widget.auth.signOut();
    if (mounted) setState(() => _access = const StaffSignedOut());
  }

  @override
  Widget build(BuildContext context) => switch (_access) {
        // Checking a stored session takes a moment; a blank canvas beats a
        // sign-in form that flashes up and vanishes.
        null => ColoredBox(color: context.colors.canvas),
        StaffSignedIn() => widget.signedIn(context),
        StaffSignedOut() => _Card(
            subtitle: widget.subtitle,
            child: _SignInForm(
              auth: widget.auth,
              note: widget.note,
              onAccess: (StaffAccess a) => setState(() => _access = a),
            ),
          ),
        StaffNotOnTeam(:final String? email) => _Card(
            subtitle: widget.subtitle,
            child: _NotOnTeam(email: email, onOtherAccount: _signOut),
          ),
      };
}

class _Card extends StatelessWidget {
  const _Card({required this.subtitle, required this.child});

  final LocalizedText subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: context.colors.canvas,
        body: Center(
          child: SingleChildScrollView(
            padding: EdgeInsetsDirectional.all(context.space.comfortable),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Container(
                padding: EdgeInsetsDirectional.all(context.space.section),
                decoration: BoxDecoration(
                  color: context.colors.structure,
                  borderRadius: BorderRadius.circular(
                    context.space.radiusPlatter,
                  ),
                  border: Border.all(color: context.colors.hairline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    MawzoonText(
                      context.appLanguage == AppLanguage.arabic
                          ? 'موزون'
                          : 'Mawzoon',
                      style: context.type.wordmark,
                    ),
                    SizedBox(height: context.space.tight),
                    MawzoonText(
                      subtitle.resolve(context.appLanguage),
                      style: context.type.body,
                      color: context.colors.inkSoft,
                    ),
                    SizedBox(height: context.space.comfortable),
                    child,
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

class _SignInForm extends StatefulWidget {
  const _SignInForm({
    required this.auth,
    required this.note,
    required this.onAccess,
  });

  final StaffAuth auth;
  final LocalizedText note;
  final ValueChanged<StaffAccess> onAccess;

  @override
  State<_SignInForm> createState() => _SignInFormState();
}

class _SignInFormState extends State<_SignInForm> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  bool _busy = false;
  StaffSignInFailure? _failure;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _ready =>
      !_busy && _email.text.trim().contains('@') && _password.text.isNotEmpty;

  Future<void> _submit() async {
    if (!_ready) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    final (StaffAccess? access, StaffSignInFailure? failure) =
        await widget.auth.signIn(email: _email.text, password: _password.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failure = failure;
    });
    if (access != null) widget.onAccess(access);
  }

  @override
  Widget build(BuildContext context) {
    final bool ar = context.appLanguage == AppLanguage.arabic;
    final String? failure = switch (_failure) {
      null => null,
      StaffSignInFailure.wrongCredentials =>
        ar ? 'البريد أو كلمة المرور غير صحيحة' : 'Wrong email or password',
      StaffSignInFailure.unreachable =>
        ar ? 'تعذّر الاتصال — حاول مجددًا' : "Couldn't connect — try again",
    };

    Widget field({
      required String label,
      required TextEditingController controller,
      required bool secret,
    }) =>
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            MawzoonText(label, style: context.type.capsuleLabel),
            SizedBox(height: context.space.tight),
            Directionality(
              // An email address and a password are Latin strings.
              textDirection: TextDirection.ltr,
              child: TextField(
                controller: controller,
                obscureText: secret,
                autocorrect: false,
                enableSuggestions: !secret,
                keyboardType: secret
                    ? TextInputType.visiblePassword
                    : TextInputType.emailAddress,
                autofillHints: <String>[
                  if (secret) AutofillHints.password else AutofillHints.email,
                ],
                textInputAction:
                    secret ? TextInputAction.done : TextInputAction.next,
                onChanged: (_) => setState(() => _failure = null),
                onSubmitted: secret ? (_) => unawaited(_submit()) : null,
                cursorColor: context.colors.ember,
                style: context.type.body.copyWith(color: context.colors.ink),
                decoration: mawzoonInputDecoration(context),
              ),
            ),
          ],
        );

    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          field(
            label: ar ? 'البريد الإلكتروني' : 'Email',
            controller: _email,
            secret: false,
          ),
          SizedBox(height: context.space.comfortable),
          field(
            label: ar ? 'كلمة المرور' : 'Password',
            controller: _password,
            secret: true,
          ),
          if (failure != null) ...<Widget>[
            SizedBox(height: context.space.base),
            Semantics(
              liveRegion: true,
              child: MawzoonText(
                failure,
                style: context.type.capsuleLabel,
                color: context.colors.protein,
              ),
            ),
          ],
          SizedBox(height: context.space.loose),
          MawzoonPillButton(
            label: ar ? 'دخول' : 'Sign in',
            primary: true,
            onPressed: _ready ? () => unawaited(_submit()) : null,
          ),
          SizedBox(height: context.space.comfortable),
          MawzoonText(
            widget.note.resolve(context.appLanguage),
            style: context.type.caption,
            color: context.colors.inkFaint,
          ),
        ],
      ),
    );
  }
}

class _NotOnTeam extends StatelessWidget {
  const _NotOnTeam({required this.email, required this.onOtherAccount});

  final String? email;
  final VoidCallback onOtherAccount;

  @override
  Widget build(BuildContext context) {
    final bool ar = context.appLanguage == AppLanguage.arabic;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Semantics(
          liveRegion: true,
          child: Container(
            padding: EdgeInsetsDirectional.all(context.space.comfortable),
            decoration: BoxDecoration(
              color: context.colors.structureElevated,
              borderRadius: context.space.surfaceRadius,
              border: Border.all(color: context.colors.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                MawzoonText(
                  ar
                      ? 'هذا الحساب ليس من فريق العمل'
                      : "This account isn't on the team",
                  style: context.type.sectionTitle,
                ),
                if (email != null) ...<Widget>[
                  SizedBox(height: context.space.tight),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(
                      email!,
                      style: context.type.caption
                          .copyWith(color: context.colors.inkSoft),
                    ),
                  ),
                ],
                SizedBox(height: context.space.snug),
                MawzoonText(
                  ar
                      ? 'اطلب من المدير إضافته إلى الفريق، ثم ادخل مرة أخرى.'
                      : 'Ask the manager to add it to the team, then sign in again.',
                  style: context.type.capsuleLabel,
                  color: context.colors.inkSoft,
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: context.space.comfortable),
        MawzoonPillButton(
          label: ar ? 'الدخول بحساب آخر' : 'Use another account',
          primary: false,
          onPressed: onOtherAccount,
        ),
      ],
    );
  }
}
