import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/import_controller.dart';
import '../responsive/adaptive_scaffold.dart';
import 'recipe_form_screen.dart';

/// Paste a link, get a draft.
///
/// The screen is explicit that the result is a first pass. Captions on
/// Instagram and TikTok are written for humans, not parsers, and a UI
/// that presents the output as finished would be lying about how good
/// the extraction is.
class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key});

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  final TextEditingController _url = TextEditingController();

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(importProvider.notifier).reset();
    });
  }

  @override
  Widget build(BuildContext context) {
    final ImportState state = ref.watch(importProvider);
    final ThemeData theme = Theme.of(context);

    ref.listen<ImportState>(importProvider, (ImportState? _, ImportState next) {
      if (next is ImportReady) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(builder: (_) => const RecipeFormScreen()),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Import a recipe')),
      body: ContentWidth(
        maxWidth: 560,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: <Widget>[
            Text(
              'Paste a link',
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Instagram, TikTok, or any recipe page. The link is read on '
              'the server, not on your device, and the text is stripped '
              'before it is parsed.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              autocorrect: false,
              enabled: state is! ImportRunning,
              decoration: const InputDecoration(
                labelText: 'Recipe URL',
                hintText: 'https://…',
                prefixIcon: Icon(Icons.link),
              ),
              onSubmitted: (String v) =>
                  ref.read(importProvider.notifier).run(v),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: state is ImportRunning
                  ? null
                  : () => ref.read(importProvider.notifier).run(_url.text),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
              icon: state is ImportRunning
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_outlined),
              label: Text(
                state is ImportRunning ? state.message : 'Read this link',
              ),
            ),
            if (state is ImportFailed) ...<Widget>[
              const SizedBox(height: 20),
              Card(
                color: theme.colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(
                        Icons.error_outline,
                        color: theme.colorScheme.onErrorContainer,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          state.message,
                          style: TextStyle(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute<void>(
                    builder: (_) => const RecipeFormScreen(),
                  ),
                ),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Write it out instead'),
              ),
            ],
            const SizedBox(height: 28),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        const Icon(Icons.shield_outlined, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'What happens to the link',
                          style: theme.textTheme.titleSmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'It is fetched by an isolated server function with a '
                      'size limit and a timeout. Private and internal '
                      'addresses are refused. Script and style blocks are '
                      'removed before any parsing happens, and the result '
                      'lands in the editor for you to correct — nothing is '
                      'saved until you press save.',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
