import 'package:flutter/material.dart';

class TranscriptEditor extends StatefulWidget {
  const TranscriptEditor({
    super.key,
    required this.label,
    required this.text,
    required this.save,
  });
  final String label, text;
  final Future<void> Function(String text) save;
  @override
  State<TranscriptEditor> createState() => _TranscriptEditorState();
}

class _TranscriptEditorState extends State<TranscriptEditor> {
  late final words = TextEditingController(text: widget.text);
  bool busy = false;
  String error = '';
  @override
  void dispose() {
    words.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy || words.text.trim().isEmpty) return;
    setState(() {
      busy = true;
      error = '';
    });
    try {
      await widget.save(words.text.trim());
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error =
              'Could not update the transcript. Your earlier answers are retained. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Edit spoken words')),
      body: ListView(
        padding: const EdgeInsets.all(22),
        children: [
          Text(widget.label, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          const Text(
            'Correct the words below. Saving updates the matching form answers. Your original speech transcript is kept with the draft.',
          ),
          const SizedBox(height: 18),
          TextField(
            key: const ValueKey('edited-transcript'),
            controller: words,
            enabled: !busy,
            minLines: 7,
            maxLines: 18,
            maxLength: 6000,
            decoration: const InputDecoration(
              labelText: 'Your words',
              alignLabelWithHint: true,
            ),
          ),
          if (error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(error),
            ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: busy ? null : save,
            child: Text(busy ? 'Updating…' : 'Save & update form'),
          ),
        ],
      ),
    ),
  );
}
