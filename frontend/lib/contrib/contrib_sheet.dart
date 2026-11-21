import 'dart:async';
import 'package:flutter/material.dart';
import 'contrib_models.dart';
import 'contrib_podium.dart';
import 'contrib_widgets.dart';

Future<void> showContribSheet(
  BuildContext context, {
  required Future<ContribData> Function(ContribPeriod period) loader,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withOpacity(.58),
    builder: (_) => ContribSheet(loader: loader),
  );
}

class ContribSheet extends StatefulWidget {
  const ContribSheet({super.key, required this.loader});
  final Future<ContribData> Function(ContribPeriod period) loader;

  @override
  State<ContribSheet> createState() => _ContribSheetState();
}

class _ContribSheetState extends State<ContribSheet> {
  static const _periods = <ContribPeriod>[
    ContribPeriod.daily,
    ContribPeriod.weekly,
    ContribPeriod.monthly,
  ];
  static const _labels = <String>['اليومي', 'الأسبوعي', 'الشهري'];

  ContribPeriod _period = ContribPeriod.daily;
  ContribData? _data;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.loader(_period);
      if (!mounted) return;
      setState(() {
        _data = result;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  void _select(ContribPeriod period) {
    if (_period == period) return;
    setState(() => _period = period);
    unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    final data = _data;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        height: MediaQuery.sizeOf(context).height * .78,
        decoration: const BoxDecoration(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0.0, 0.32, 0.68, 1.0],
            colors: [
              Color(0xFF0F7A44),
              Color(0xFF0B5E35),
              Color(0xFF063E2A),
              Color(0xFF011A16),
            ],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(.42),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 12),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'تصنيف المساهمين في الغرفة',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(height: 13),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: List.generate(_periods.length, (index) {
                    final selected = _period == _periods[index];
                    return Expanded(
                      child: Padding(
                        padding: EdgeInsetsDirectional.only(
                          end: index == 0 ? 0 : 6,
                        ),
                        child: InkWell(
                          onTap: () => _select(_periods[index]),
                          borderRadius: BorderRadius.circular(30),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            decoration: BoxDecoration(
                              color: selected
                                  ? Colors.white
                                  : Colors.white.withOpacity(.10),
                              borderRadius: BorderRadius.circular(30),
                              border: Border.all(
                                color: Colors.white.withOpacity(
                                  selected ? .9 : .18,
                                ),
                              ),
                            ),
                            child: Text(
                              _labels[index],
                              style: TextStyle(
                                color: selected
                                    ? const Color(0xFF07512F)
                                    : Colors.white.withOpacity(.9),
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 5),
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFFFFE4A1),
                          strokeWidth: 2.5,
                        ),
                      )
                    : _error != null
                        ? _ErrorState(onRetry: _load)
                        : data == null
                            ? _ErrorState(onRetry: _load)
                            : _ContribContent(data: data),
              ),
              if (data?.me != null)
                _MeBar(
                  entry: data!.me!,
                  rank: data.myRank,
                ),
              SizedBox(height: bottom > 0 ? 4 : 10),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContribContent extends StatelessWidget {
  const _ContribContent({required this.data});
  final ContribData data;

  @override
  Widget build(BuildContext context) {
    final entries = data.entries;
    final rest = entries.length > 3 ? entries.skip(3).toList() : <ContribEntry>[];
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      children: [
        ContribPodium(top: entries.take(3).toList()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: Divider(color: Colors.white.withOpacity(.16), height: 15),
        ),
        if (rest.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 22),
            child: Text(
              entries.isEmpty ? 'لا توجد مساهمات في هذه الفترة بعد' : 'لا توجد مراكز إضافية',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          )
        else
          ...List.generate(rest.length, (index) {
            final entry = rest[index];
            return _ContributorRow(rank: index + 4, entry: entry);
          }),
      ],
    );
  }
}

class _ContributorRow extends StatelessWidget {
  const _ContributorRow({required this.rank, required this.entry});
  final int rank;
  final ContribEntry entry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 7),
      child: Row(
        children: [
          SizedBox(
            width: 27,
            child: Text(
              '$rank',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 9),
          ContribAvatar(url: entry.avatarUrl, size: 39),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              entry.name.isEmpty ? 'مستخدم' : entry.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const ContribCoin(size: 16),
          const SizedBox(width: 5),
          Text(
            contribFmt(entry.amount),
            style: const TextStyle(
              color: Color(0xFFFFE3A0),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _MeBar extends StatelessWidget {
  const _MeBar({required this.entry, required this.rank});
  final ContribEntry entry;
  final int? rank;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(.18)),
        ),
      ),
      child: Row(
        children: [
          const Text(
            'مساهمتك',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(width: 9),
          Text(
            rank == null ? '—' : '#$rank',
            style: const TextStyle(
              color: Color(0xFFFFE4A1),
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 10),
          ContribAvatar(url: entry.avatarUrl, size: 34),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              entry.name.isEmpty ? 'أنا' : entry.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const ContribCoin(size: 16),
          const SizedBox(width: 4),
          Text(
            contribFmt(entry.amount),
            style: const TextStyle(
              color: Color(0xFFFFE4A1),
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off_rounded, color: Colors.white70, size: 28),
          const SizedBox(height: 9),
          const Text(
            'تعذر تحميل التصنيف',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFFFFE4A1)),
            label: const Text('إعادة المحاولة',
                style: TextStyle(color: Color(0xFFFFE4A1))),
          ),
        ],
      ),
    );
  }
}
