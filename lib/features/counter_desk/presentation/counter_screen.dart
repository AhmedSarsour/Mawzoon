import 'package:flutter/material.dart';

import '../../../core/localization/localized_text.dart';
import '../../../ui_primitives/motion/motion.dart';
import '../../../ui_primitives/text/mawzoon_text.dart';
import '../../../ui_primitives/theme/theme_context.dart';
import '../../order_tracking/domain/tracked_order.dart';
import '../application/counter_controller.dart';
import '../domain/counter_payment.dart';
import '../domain/unpaid_order.dart';

/// The cashier's screen: orders waiting for money, big enough to read across
/// a counter. Nothing here reaches the kitchen until "paid" is confirmed.
class CounterScreen extends StatelessWidget {
  /// Creates the screen.
  const CounterScreen({required this.controller, super.key});

  /// Owns the list and the taps.
  final CounterController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (BuildContext context, _) {
          final bool ar = context.appLanguage == AppLanguage.arabic;
          String t(String a, String e) => ar ? a : e;
          final List<UnpaidOrder> orders = controller.orders;
          return Scaffold(
            backgroundColor: context.colors.canvas,
            body: SafeArea(
              child: Padding(
                padding: EdgeInsetsDirectional.symmetric(
                  horizontal: context.space.section,
                  vertical: context.space.comfortable,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              MawzoonText(
                                t('الصندوق', 'Counter'),
                                style: context.type.display,
                              ),
                              MawzoonText(
                                t(
                                  'طلبات تنتظر الدفع · لا تصل المطبخ قبل الدفع',
                                  'Orders waiting for payment · the kitchen sees them only after',
                                ),
                                style: context.type.body,
                                color: context.colors.inkSoft,
                              ),
                            ],
                          ),
                        ),
                        SizedBox(
                          width: 320,
                          child: _Search(controller: controller),
                        ),
                      ],
                    ),
                    if (controller.notice != null)
                      _NoticeBar(notice: controller.notice!),
                    SizedBox(height: context.space.base),
                    Expanded(
                      child: !controller.loaded
                          ? const Center(child: CircularProgressIndicator())
                          : orders.isEmpty
                              ? Center(
                                  child: MawzoonText(
                                    controller.query.isEmpty
                                        ? t(
                                            'لا طلبات تنتظر الدفع',
                                            'No orders waiting for payment',
                                          )
                                        : t(
                                            'لا طلب بهذا الرقم',
                                            'No order with that number',
                                          ),
                                    style: context.type.sectionTitle,
                                    color: context.colors.inkSoft,
                                  ),
                                )
                              : GridView.builder(
                                  gridDelegate:
                                      const SliverGridDelegateWithMaxCrossAxisExtent(
                                    maxCrossAxisExtent: 300,
                                    mainAxisExtent: 270,
                                    crossAxisSpacing: 18,
                                    mainAxisSpacing: 18,
                                  ),
                                  itemCount: orders.length,
                                  itemBuilder: (BuildContext context, int i) =>
                                      _OrderCard(
                                    order: orders[i],
                                    controller: controller,
                                  ),
                                ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
}

class _Search extends StatelessWidget {
  const _Search({required this.controller});

  final CounterController controller;

  @override
  Widget build(BuildContext context) {
    final bool ar = context.appLanguage == AppLanguage.arabic;
    return TextField(
      keyboardType: TextInputType.number,
      onChanged: controller.setQuery,
      style: context.type.body.copyWith(fontSize: 17),
      decoration: InputDecoration(
        hintText: ar ? 'رقم الطلب، مثلًا 12' : 'Order number, e.g. 12',
        prefixIcon: const Icon(Icons.search_rounded),
        filled: true,
        fillColor: context.colors.structure,
        contentPadding: EdgeInsetsDirectional.symmetric(
          horizontal: context.space.base,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
          borderSide: BorderSide(color: context.colors.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
          borderSide: BorderSide(color: context.colors.ink),
        ),
      ),
    );
  }
}

class _NoticeBar extends StatelessWidget {
  const _NoticeBar({required this.notice});

  final CounterNotice notice;

  @override
  Widget build(BuildContext context) {
    final bool ar = context.appLanguage == AppLanguage.arabic;
    final String code = notice.code;
    final (String text, bool good) = switch (notice.result) {
      CounterPayResult.paid => (
          ar
              ? 'تم الدفع $code — ذهب للمطبخ'
              : '$code paid — sent to the kitchen',
          true,
        ),
      CounterPayResult.alreadyPaid => (
          ar ? '$code مدفوع مسبقًا' : '$code was already paid',
          true,
        ),
      CounterPayResult.expired => (
          ar
              ? '$code انتهى — اطلب من الزبون طلبًا جديدًا'
              : '$code expired — ask for a new order',
          false,
        ),
      CounterPayResult.cancelled => (
          ar ? '$code أُلغي' : '$code was cancelled',
          false,
        ),
      CounterPayResult.cardRequired => (
          ar ? '$code بالبطاقة فقط' : '$code is card only',
          false,
        ),
      CounterPayResult.notFound => (
          ar ? '$code غير موجود' : '$code not found',
          false,
        ),
      CounterPayResult.unreachable => (
          ar
              ? 'لا اتصال — اضغط «نعم» مرة أخرى'
              : 'No connection — tap Yes again',
          false,
        ),
    };
    return Container(
      margin: EdgeInsetsDirectional.only(top: context.space.snug),
      padding: EdgeInsetsDirectional.all(context.space.snug),
      decoration: BoxDecoration(
        color: good ? context.colors.olive : context.colors.ember,
        borderRadius: BorderRadius.circular(context.space.radiusControl),
      ),
      child: MawzoonText(
        text,
        style: context.type.buttonLabel,
        color: good ? context.colors.onOlive : context.colors.onEmber,
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, required this.controller});

  final UnpaidOrder order;
  final CounterController controller;

  @override
  Widget build(BuildContext context) {
    final bool ar = context.appLanguage == AppLanguage.arabic;
    String t(String a, String e) => ar ? a : e;
    final DateTime now = controller.now;
    final bool expired = order.isExpiredAt(now);
    final bool asking = controller.confirmingId == order.id;
    final bool busy = controller.busyId == order.id;
    final DateTime? created = order.createdAt;
    final DateTime? due = order.dueAt;
    final String? soon =
        due == null ? null : expiresInLabel(due.difference(now), arabic: ar);
    final bool urgent = due != null && due.difference(now).inMinutes < 10;
    final String age =
        created == null ? '' : ageLabel(now.difference(created), arabic: ar);

    return Container(
      padding: EdgeInsetsDirectional.all(context.space.base),
      decoration: BoxDecoration(
        color: expired ? context.colors.canvas : context.colors.structure,
        borderRadius: BorderRadius.circular(context.space.radiusSurface),
        border: Border.all(
          color: asking ? context.colors.olive : context.colors.hairline,
          width: asking ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Directionality(
                    textDirection: TextDirection.ltr,
                    child: MawzoonText(
                      order.code,
                      style: context.type.macroFigure.copyWith(
                        fontSize: 44,
                        decoration: expired ? TextDecoration.lineThrough : null,
                      ),
                      color: expired ? context.colors.inkSoft : null,
                    ),
                  ),
                ),
              ),
              SizedBox(width: context.space.snug),
              MawzoonText(
                expired
                    ? t('انتهى', 'Expired')
                    : (urgent && soon != null ? soon : age),
                style: context.type.caption,
                color: urgent && !expired
                    ? context.colors.ember
                    : context.colors.inkSoft,
              ),
            ],
          ),
          if (expired) ...<Widget>[
            MawzoonText(
              t(
                'لم يُدفع في الوقت. لم يُحضَّر شيء.',
                'Not paid in time. Nothing was made.',
              ),
              style: context.type.caption,
              color: context.colors.inkSoft,
            ),
            const Spacer(),
            MawzoonText(
              t('اطلب من الزبون طلبًا جديدًا', 'Ask the guest to order again'),
              style: context.type.caption,
              color: context.colors.inkSoft,
            ),
          ] else ...<Widget>[
            if (order.title.isNotEmpty)
              MawzoonText(
                order.title,
                style: context.type.caption,
                color: context.colors.inkSoft,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            SizedBox(height: context.space.snug),
            Directionality(
              textDirection: TextDirection.ltr,
              child: MawzoonText(
                order.total.format(context.appLanguage),
                style: context.type.macroFigure.copyWith(fontSize: 30),
              ),
            ),
            const Spacer(),
            if (asking) ...<Widget>[
              MawzoonText(
                t(
                  'استلمت ${order.total.format(context.appLanguage)}؟',
                  'Did you take ${order.total.format(context.appLanguage)}?',
                ),
                style: context.type.body.copyWith(fontWeight: FontWeight.w700),
              ),
              SizedBox(height: context.space.snug),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _CardButton(
                      label: t('نعم', 'Yes'),
                      color: context.colors.olive,
                      textColor: context.colors.onOlive,
                      onPressed: busy ? null : () => controller.confirm(order),
                    ),
                  ),
                  SizedBox(width: context.space.snug),
                  Expanded(
                    child: _CardButton(
                      label: t('رجوع', 'Back'),
                      color: context.colors.structureElevated,
                      textColor: context.colors.ink,
                      onPressed: busy ? null : controller.back,
                    ),
                  ),
                ],
              ),
            ] else
              _CardButton(
                label: t('تم الدفع', 'Paid'),
                color: context.colors.ember,
                textColor: context.colors.onEmber,
                onPressed: () => controller.ask(order.id),
              ),
          ],
        ],
      ),
    );
  }
}

class _CardButton extends StatelessWidget {
  const _CardButton({
    required this.label,
    required this.color,
    required this.textColor,
    required this.onPressed,
  });

  final String label;
  final Color color;
  final Color textColor;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => TactileFeedbackWell(
        onPressed: onPressed,
        enabled: onPressed != null,
        semanticLabel: label,
        child: Container(
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: onPressed == null ? context.colors.track : color,
            borderRadius: BorderRadius.circular(12),
          ),
          child: MawzoonText(
            label,
            style: context.type.buttonLabel.copyWith(fontSize: 17),
            color: textColor,
          ),
        ),
      );
}
