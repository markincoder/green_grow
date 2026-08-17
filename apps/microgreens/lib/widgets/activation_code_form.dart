import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../state/access_store.dart';
import '../theme/app_theme.dart';

String formatRuAccessDate(DateTime utc) {
  final local = utc.toLocal();
  const months = [
    'января',
    'февраля',
    'марта',
    'апреля',
    'мая',
    'июня',
    'июля',
    'августа',
    'сентября',
    'октября',
    'ноября',
    'декабря',
  ];
  return '${local.day} ${months[local.month - 1]} ${local.year}';
}

Future<void> showActivationSheet(BuildContext context, AccessStore access) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: _ActivationSheet(access: access),
      );
    },
  );
}

class _ActivationSheet extends StatelessWidget {
  const _ActivationSheet({required this.access});

  final AccessStore access;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.mist,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Активировать доступ',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              Text(
                'Введите почту, на которую оформляли код, и сам код.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 18),
              ActivationCodeForm(
                access: access,
                onSuccess: () {
                  if (context.mounted) Navigator.of(context).pop();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ActivationCodeForm extends StatefulWidget {
  const ActivationCodeForm({
    super.key,
    required this.access,
    this.onSuccess,
  });

  final AccessStore access;
  final VoidCallback? onSuccess;

  @override
  State<ActivationCodeForm> createState() => _ActivationCodeFormState();
}

class _ActivationCodeFormState extends State<ActivationCodeForm> {
  late final TextEditingController _email;
  final _code = TextEditingController();
  final _emailFocus = FocusNode();
  final _codeFocus = FocusNode();
  late final TapGestureRecognizer _buyTap;
  String? _error;
  bool _busy = false;

  static final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void initState() {
    super.initState();
    _email = TextEditingController(text: widget.access.email);
    _buyTap = TapGestureRecognizer()..onTap = _openBuy;
  }

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _emailFocus.dispose();
    _codeFocus.dispose();
    _buyTap.dispose();
    super.dispose();
  }

  Future<void> _openBuy() async {
    final uri = widget.access.buyUri;
    final ok = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
      webOnlyWindowName: '_blank',
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось открыть $uri')),
      );
    }
  }

  Future<void> _pasteCode() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final digits = (data?.text ?? '').replaceAll(RegExp(r'\D'), '');
    if (!mounted) return;
    if (digits.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('В буфере нет кода')),
      );
      return;
    }
    final code = digits.length > 6 ? digits.substring(0, 6) : digits;
    _code.value = TextEditingValue(
      text: code,
      selection: TextSelection.collapsed(offset: code.length),
    );
    if (_error != null) setState(() => _error = null);
  }

  Future<void> _submit() async {
    if (_busy) return;
    final email = _email.text.trim();
    final code = _code.text.replaceAll(RegExp(r'\D'), '');
    if (!_emailRe.hasMatch(email)) {
      setState(() => _error = 'Укажите почту, на которую оформляли доступ');
      _emailFocus.requestFocus();
      return;
    }
    if (code.length != 6) {
      setState(() => _error = 'Введите 6 цифр кода доступа');
      _codeFocus.requestFocus();
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final err = await widget.access.activate(code, email);
      if (!mounted) return;
      if (err == 'expired') {
        setState(() => _error = 'Срок этого кода истёк. Оформите доступ на сайте.');
      } else if (err == 'mismatch') {
        setState(() => _error = 'Этот код не привязан к указанной почте.');
      } else if (err == 'invalid') {
        setState(() => _error = 'Неверный код или почта. Проверьте данные.');
      } else {
        _emailFocus.unfocus();
        _codeFocus.unfocus();
        widget.onSuccess?.call();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Не удалось связаться с сервером. Проверьте интернет.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _decoration({
    required String hint,
    Widget? prefix,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: prefix,
      suffixIcon: suffix,
      filled: true,
      fillColor: Colors.white,
      counterText: '',
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.mist),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.mist),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.meadow, width: 1.6),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _email,
          focusNode: _emailFocus,
          enabled: !_busy,
          autofocus: widget.access.email.isEmpty,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autocorrect: false,
          autofillHints: const [AutofillHints.email],
          style: theme.textTheme.titleMedium,
          decoration: _decoration(
            hint: 'email@example.com',
            prefix: const Icon(Icons.mail_outline_rounded, color: AppColors.meadow),
          ),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _code,
          focusNode: _codeFocus,
          enabled: !_busy,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: theme.textTheme.titleLarge?.copyWith(
            letterSpacing: 6,
            fontWeight: FontWeight.w800,
            color: AppColors.forest,
          ),
          textAlign: TextAlign.center,
          decoration: _decoration(
            hint: 'Код активации',
            prefix: const SizedBox(width: 48),
            suffix: IconButton(
              tooltip: 'Вставить из буфера',
              onPressed: _busy ? null : _pasteCode,
              icon: const Icon(
                Icons.content_paste_rounded,
                color: AppColors.meadow,
              ),
            ),
          ),
          onSubmitted: (_) => _submit(),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF9B2226),
            ),
          ),
        ],
        const SizedBox(height: 14),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: Colors.white,
                  ),
                )
              : const Text('Активировать'),
        ),
        const SizedBox(height: 14),
        Text.rich(
          TextSpan(
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
            children: [
              const TextSpan(
                text: 'Код активации вы можете оформить на сайте ',
              ),
              TextSpan(
                text: 'https://${widget.access.siteHost}',
                style: const TextStyle(
                  color: AppColors.leaf,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.underline,
                  decorationColor: AppColors.leaf,
                ),
                recognizer: _buyTap,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
