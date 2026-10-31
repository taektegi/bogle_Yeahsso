import 'package:flutter/material.dart';
import '../../theme/bogle_theme.dart';
import '../../widgets/bogle_dialog.dart';

class ManagementPage extends StatelessWidget {
  const ManagementPage({
    super.key,
    required this.title,
    required this.addLabel,
    required this.onAdd,
    required this.children,
    this.busy = false,
    this.error,
    this.onRetry,
  });
  final String title, addLabel;
  final VoidCallback? onAdd, onRetry;
  final bool busy;
  final String? error;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: BogleColors.cream,
    appBar: AppBar(title: Text(title), backgroundColor: BogleColors.cream),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: busy ? null : onAdd,
                  icon: const Icon(Icons.add_rounded),
                  label: Text(addLabel),
                ),
              ),
              const SizedBox(height: 20),
              if (busy) const LinearProgressIndicator(),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Column(
                    children: [
                      Text(error!, textAlign: TextAlign.center),
                      if (onRetry != null)
                        TextButton(
                          onPressed: onRetry,
                          child: const Text('다시 불러오기'),
                        ),
                    ],
                  ),
                ),
              ...children,
            ],
          ),
        ),
      ),
    ),
  );
}

class ManagementCard extends StatelessWidget {
  const ManagementCard({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 16),
    color: Colors.white,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(22),
      side: const BorderSide(color: BogleColors.line),
    ),
    child: Padding(padding: const EdgeInsets.all(20), child: child),
  );
}

class DefaultLabel extends StatelessWidget {
  const DefaultLabel({super.key, required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: BogleColors.blueSoft,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      text,
      style: const TextStyle(fontSize: 12, color: BogleColors.blueStrong),
    ),
  );
}

Future<bool> confirmRemoval(
  BuildContext context,
  String title,
  String body,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => BogleDialog(
        title: title,
        icon: Icons.delete_outline_rounded,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제'),
          ),
        ],
        child: BogleDialogCard(child: Text(body)),
      ),
    ) ??
    false;
