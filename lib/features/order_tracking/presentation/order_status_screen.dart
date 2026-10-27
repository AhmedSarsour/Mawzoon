import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/localization/localized_text.dart';
import '../../../ui_primitives/controls/mawzoon_pill_button.dart';
import '../../../ui_primitives/motion/motion.dart';
import '../../../ui_primitives/text/mawzoon_text.dart';
import '../../../ui_primitives/theme/theme_context.dart';
import '../domain/tracked_order.dart';

/// The guest's order, from "pay at the counter" to "ready".
///
/// One screen, two faces: while unpaid it is the receipt (big code, total,
/// what happens next); after payment it is the tracker. Driven by the order
/// row, never by a client-side timer: every time shown comes from the server.
///
/// Copy rule: before payment it must never say the kitchen has the order.
class OrderStatusScreen extends StatefulWidget {
  /// Creates the screen. [initial] paints at once; [tracker] keeps it live and
  /// enables cancelling. With neither, [orderId] alone shows a loading state.
  const OrderStatusScreen({
    required this.orderId,
    this.initial,
    this.tracker,
    super.key,
  });

  /// The order to show.
  final String orderId;

  /// What the placement answer already told us.
  final TrackedOrder? initial;

  /// Live updates and cancel. Null in previews: the screen stays as given.
  final OrderTracker? tracker;

  @override
  State<OrderStatusScreen> createState() => _OrderStatusScreenState();
}

class _OrderStatusScreenState extends State<OrderStatusScreen> {
  TrackedOrder? _order;
  bool _missing = false;
  bool _cancelling = false;
  String? _notice;
  StreamSubscription<TrackedOrder?>? _sub;

  @override
  void initState() {
    super.initState();
    _order = widget.initial;
    _sub = widget.tracker?.watch(widget.orderId).listen((TrackedOrder? next) {
      if (!mounted) return;
      setState(() {
        if (next == null) {
          _missing = _order == null;
        } else {
          _order = next;
          _missing = false;
        }
      });
    });
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  bool get _ar => context.appLanguage == AppLanguage.arabic;
  String _t(String ar, String en) => _ar ? ar : en;

  Future<void> _confirmCancel() async {
    final bool? yes = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: context.colors.structure,
        title: MawzoonText(
          _t('إلغاء الطلب؟', 'Cancel this order?'),
          style: context.type.sectionTitle,
        ),
        content: MawzoonText(
          _t(
            'لن يُحضَّر شيء ولن تدفع شيئًا.',
            "Nothing is made, nothing to pay.",
          ),
          style: context.type.body,
          color: context.colors.inkSoft,
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(_t('رجوع', 'Back')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(_t('إلغاء الطلب', 'Cancel order')),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    await _cancel();
  }

  Future<void> _cancel() async {
    final OrderTracker? tracker = widget.tracker;
    final TrackedOrder? order = _order;
    if (tracker == null || order == null || _cancelling) return;
    setState(() {
      _cancelling = true;
      _notice = null;
    });
    final CancelResult result = await tracker.cancel(order.id);
    if (!mounted) return;
    setState(() {
      _cancelling = false;
      switch (result) {
        case CancelResult.cancelled:
        case CancelResult.alreadyCancelled:
          _order = order.withStage(
            OrderStage.cancelled,
            reason: order.cancelReason ?? CancelReason.guest,
          );
        case CancelResult.tooLate:
          _notice = _t(
            'تم دفع الطلب للتو — الإلغاء عند الصندوق',
            'It was just paid — ask the counter to cancel',
          );
        case CancelResult.unreachable:
          _notice =
              _t('تعذّر الاتصال — حاول مجددًا', "Couldn't connect — try again");
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final TrackedOrder? order = _order;
    final Widget body;
    if (order == null) {
      body = _missing
          ? _Message(
              title: _t('لم نجد هذا الطلب', "We couldn't find this order"),
              detail: '',
              onBack: () => Navigator.of(context).maybePop(),
              backLabel: _t('العودة للقائمة', 'Back to the menu'),
            )
          : const Center(child: CircularProgressIndicator());
    } else if (order.stage == OrderStage.awaitingPayment) {
      body = _Receipt(
        order: order,
        notice: _notice,
        cancelling: _cancelling,
        onCancel: widget.tracker == null ? null : _confirmCancel,
      );
    } else if (order.stage == OrderStage.cancelled) {
      body = _Message(
        title: switch (order.cancelReason) {
          CancelReason.expired => _t('انتهى وقت الطلب', 'This order expired'),
          CancelReason.staff => _t('أُلغي الطلب', 'The order was cancelled'),
          _ => _t('تم إلغاء الطلب', 'Order cancelled'),
        },
        detail: order.cancelReason == CancelReason.expired
            ? _t(
                'لم يُدفع في الوقت. لم يُحضَّر شيء.',
                'It was not paid in time. Nothing was made.',
              )
            : '',
        onBack: () => Navigator.of(context).maybePop(),
        backLabel: _t('العودة للقائمة', 'Back to the menu'),
      );
    } else {
      body = _Tracker(order: order, notice: _notice);
    }
    return Scaffold(
      backgroundColor: context.colors.canvas,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: IconButton(
                tooltip: _t('رجوع', 'Back'),
                iconSize: 24,
                constraints: BoxConstraints.tightFor(
                  width: context.space.thumbTarget,
                  height: context.space.thumbTarget,
                ),
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const BackButtonIcon(),
              ),
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

/// A figure or code in the Latin face, left-to-right inside RTL text.
Widget _latin(
  BuildContext context,
  String text, {
  required double size,
  Color? color,
}) =>
    Directionality(
      textDirection: TextDirection.ltr,
      child: MawzoonText(
        text,
        style: context.type.macroFigure.copyWith(fontSize: size),
        color: color,
      ),
    );

class _Receipt extends StatelessWidget {
  const _Receipt({
    required this.order,
    required this.notice,
    required this.cancelling,
    required this.onCancel,
  });

  final TrackedOrder order;
  final String? notice;
  final bool cancelling;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final bool ar = context.appLanguage == AppLanguage.arabic;
    String t(String a, String e) => ar ? a : e;
    final DateTime? due = order.dueAt;
    // The expiry time and cancel stay pinned: they must never scroll away.
    return Column(
      children: <Widget>[
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsetsDirectional.symmetric(
              horizontal: context.space.screenGutter,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Center(
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: context.colors.olive,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.check_rounded,
                      color: context.colors.onOlive,
                    ),
                  ),
                ),
                SizedBox(height: context.space.base),
                MawzoonText(
                  t('طلبك محجوز', 'Your order is reserved'),
                  style: context.type.sectionTitle,
                  textAlign: TextAlign.center,
                ),
                MawzoonText(
                  t(
                    'اعرض هذا الرقم عند الصندوق وادفع',
                    'Show this number at the counter and pay',
                  ),
                  style: context.type.body,
                  color: context.colors.inkSoft,
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: context.space.comfortable),
                Container(
                  padding: EdgeInsetsDirectional.all(context.space.section),
                  decoration: BoxDecoration(
                    color: context.colors.structure,
                    borderRadius:
                        BorderRadius.circular(context.space.radiusPlatter),
                    border: Border.all(color: context.colors.hairline),
                  ),
                  child: Column(
                    children: <Widget>[
                      MawzoonText(
                        t('رقم الطلب', 'Order number'),
                        style: context.type.caption,
                        color: context.colors.inkSoft,
                      ),
                      _latin(context, order.code, size: 88),
                      Divider(color: context.colors.hairline, height: 28),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: <Widget>[
                          Expanded(
                            child: MawzoonText(
                              t('المبلغ عند الصندوق', 'Pay at the counter'),
                              style: context.type.body,
                              color: context.colors.inkSoft,
                            ),
                          ),
                          _latin(
                            context,
                            order.total.format(context.appLanguage),
                            size: 24,
                          ),
                        ],
                      ),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: MawzoonText(
                          t('نقدًا أو بالبطاقة', 'Cash or card'),
                          style: context.type.caption,
                          color: context.colors.inkSoft,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: context.space.comfortable),
                _Step(
                  n: 1,
                  active: true,
                  text: t('ادفع عند الصندوق', 'Pay at the counter'),
                ),
                _Step(
                  n: 2,
                  text: t(
                    'نبدأ التحضير بعد الدفع — 12–15 دقيقة',
                    'We start making it after you pay — 12–15 min',
                  ),
                ),
                _Step(n: 3, text: t('نناديك برقمك', 'We call your number')),
              ],
            ),
          ),
        ),
        Padding(
          padding: EdgeInsetsDirectional.symmetric(
            horizontal: context.space.screenGutter,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (due != null)
                Center(
                  child: Text.rich(
                    TextSpan(
                      style: context.type.caption.copyWith(
                        color: context.colors.inkSoft,
                      ),
                      children: <InlineSpan>[
                        TextSpan(
                          text: t('محفوظ لك حتى ', 'Held for you until '),
                        ),
                        TextSpan(
                          text: clockTime(due),
                          style: context.type.caption.copyWith(
                            color: context.colors.ink,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (notice != null)
                Padding(
                  padding: EdgeInsetsDirectional.only(top: context.space.snug),
                  child: MawzoonText(
                    notice!,
                    style: context.type.caption,
                    color: context.colors.ember,
                    textAlign: TextAlign.center,
                  ),
                ),
              if (onCancel != null)
                Center(
                  child: TactileFeedbackWell(
                    onPressed: cancelling ? null : onCancel,
                    enabled: !cancelling,
                    semanticLabel: t('إلغاء الطلب', 'Cancel order'),
                    child: Container(
                      constraints:
                          BoxConstraints(minHeight: context.space.thumbTarget),
                      padding: EdgeInsetsDirectional.symmetric(
                        horizontal: context.space.loose,
                      ),
                      alignment: Alignment.center,
                      child: MawzoonText(
                        t('إلغاء الطلب', 'Cancel order'),
                        style: context.type.buttonLabel,
                        color: context.colors.inkSoft,
                      ),
                    ),
                  ),
                ),
              SizedBox(height: context.space.snug),
            ],
          ),
        ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.n, required this.text, this.active = false});

  final int n;
  final String text;
  final bool active;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsetsDirectional.only(bottom: context.space.snug),
        child: Row(
          children: <Widget>[
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active ? context.colors.ember : null,
                border: active
                    ? null
                    : Border.all(color: context.colors.hairline, width: 2),
              ),
              child: _latin(
                context,
                '$n',
                size: 14,
                color: active ? context.colors.onEmber : context.colors.inkSoft,
              ),
            ),
            SizedBox(width: context.space.snug),
            Expanded(
              child: MawzoonText(
                text,
                style: context.type.body,
                color: active ? context.colors.ink : context.colors.inkSoft,
              ),
            ),
          ],
        ),
      );
}

class _Tracker extends StatelessWidget {
  const _Tracker({required this.order, required this.notice});

  final TrackedOrder order;
  final String? notice;

  @override
  Widget build(BuildContext context) {
    final bool ar = context.appLanguage == AppLanguage.arabic;
    String t(String a, String e) => ar ? a : e;
    final OrderStage stage = order.stage;
    final String headline = switch (stage) {
      OrderStage.paid =>
        t('تم الدفع — طلبك في الطابور', 'Paid — you are in the queue'),
      OrderStage.making => t('نحضّر صحنك الآن', 'We are making your plate'),
      OrderStage.ready => t('صحنك جاهز — تفضّل', 'Your plate is ready'),
      _ => t('بالهناء والعافية', 'Enjoy your meal'),
    };
    // Step 2 is "in the kitchen": current while paid or making.
    final bool inKitchen =
        stage == OrderStage.paid || stage == OrderStage.making;
    final bool atLeastReady =
        stage == OrderStage.ready || stage == OrderStage.done;
    return SingleChildScrollView(
      padding: EdgeInsetsDirectional.symmetric(
        horizontal: context.space.screenGutter,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              MawzoonText(
                t('رقم الطلب', 'Order number'),
                style: context.type.caption,
                color: context.colors.inkSoft,
              ),
              _latin(context, order.code, size: 28),
            ],
          ),
          SizedBox(height: context.space.loose),
          MawzoonText(headline, style: context.type.display),
          SizedBox(height: context.space.chapter),
          _TimelineRow(
            state: _Mark.done,
            title: t('تم الدفع', 'Paid'),
            // LRM keeps the ₪ on its usual side inside RTL text.
            detail: '\u200E${order.total.format(context.appLanguage)}',
          ),
          _TimelineRow(
            state: inKitchen ? _Mark.current : _Mark.done,
            title: t('في المطبخ', 'In the kitchen'),
            detail: stage == OrderStage.paid
                ? t('بانتظار الطباخ', 'Waiting for a cook')
                : t('نحضّر صحنك', 'Making your plate'),
          ),
          _TimelineRow(
            state: atLeastReady ? _Mark.current : _Mark.todo,
            title: t('جاهز للاستلام', 'Ready for pickup'),
            detail: t('نناديك برقمك', 'We call your number'),
            last: true,
          ),
          if (order.title.isNotEmpty) ...<Widget>[
            SizedBox(height: context.space.chapter),
            Container(
              padding: EdgeInsetsDirectional.all(context.space.base),
              decoration: BoxDecoration(
                color: context.colors.structureElevated,
                borderRadius:
                    BorderRadius.circular(context.space.radiusCompartment),
                border: Border.all(color: context.colors.hairline),
              ),
              child: MawzoonText(order.title, style: context.type.body),
            ),
          ],
          if (notice != null) MawzoonText(notice!, style: context.type.caption),
          SizedBox(height: context.space.comfortable),
        ],
      ),
    );
  }
}

enum _Mark { done, current, todo }

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.state,
    required this.title,
    required this.detail,
    this.last = false,
  });

  final _Mark state;
  final String title;
  final String detail;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final Color accent =
        state == _Mark.done ? context.colors.olive : context.colors.ember;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Column(
            children: <Widget>[
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: state == _Mark.todo ? null : accent,
                  border: state == _Mark.todo
                      ? Border.all(color: context.colors.hairline, width: 2)
                      : null,
                ),
                child: state == _Mark.done
                    ? Icon(
                        Icons.check_rounded,
                        size: 18,
                        color: context.colors.onOlive,
                      )
                    : null,
              ),
              if (!last)
                Expanded(
                  child: Container(
                    width: 2,
                    constraints: const BoxConstraints(minHeight: 28),
                    color: state == _Mark.done
                        ? context.colors.olive
                        : context.colors.hairline,
                  ),
                ),
            ],
          ),
          SizedBox(width: context.space.base),
          Expanded(
            child: Padding(
              padding: EdgeInsetsDirectional.only(top: context.space.micro),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  MawzoonText(
                    title,
                    style: context.type.body.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    color: state == _Mark.current
                        ? context.colors.ember
                        : (state == _Mark.todo
                            ? context.colors.inkSoft
                            : context.colors.ink),
                  ),
                  MawzoonText(
                    detail,
                    style: context.type.caption,
                    color: context.colors.inkSoft,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.title,
    required this.detail,
    required this.onBack,
    required this.backLabel,
  });

  final String title;
  final String detail;
  final VoidCallback onBack;
  final String backLabel;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsetsDirectional.all(context.space.screenGutter),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            MawzoonText(
              title,
              style: context.type.display,
              textAlign: TextAlign.center,
            ),
            if (detail.isNotEmpty)
              Padding(
                padding: EdgeInsetsDirectional.only(top: context.space.snug),
                child: MawzoonText(
                  detail,
                  style: context.type.body,
                  color: context.colors.inkSoft,
                  textAlign: TextAlign.center,
                ),
              ),
            SizedBox(height: context.space.section),
            MawzoonPillButton(
              label: backLabel,
              primary: true,
              onPressed: onBack,
            ),
          ],
        ),
      );
}
