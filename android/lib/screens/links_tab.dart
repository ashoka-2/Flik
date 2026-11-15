import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../models/transfer_item.dart';
import '../theme/tokens.dart';

// Links tab with clipboard auto-detection, URL allowlist check, and staging.
class LinksTab extends StatefulWidget {
  final void Function(TransferItem item) onStageItem;

  const LinksTab({super.key, required this.onStageItem});

  @override
  State<LinksTab> createState() => _LinksTabState();
}

class _LinksTabState extends State<LinksTab> {
  final TextEditingController _urlController = TextEditingController();
  String? _validationError;

  @override
  void initState() {
    super.initState();
    _checkClipboard();
  }

  Future<void> _checkClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text != null && (text.startsWith('http://') || text.startsWith('https://'))) {
      if (mounted) {
        setState(() {
          _urlController.text = text;
          _validate(text);
        });
      }
    }
  }

  bool _validate(String input) {
    if (input.isEmpty) {
      setState(() => _validationError = null);
      return false;
    }

    if (!input.startsWith(RegExp(r'^https?://', caseSensitive: false))) {
      setState(() => _validationError = 'Please enter a valid web link starting with http:// or https://.');
      return false;
    }

    if (input.length > 2048) {
      setState(() => _validationError = 'Link exceeds maximum permitted length of 2048 characters.');
      return false;
    }

    setState(() => _validationError = null);
    return true;
  }

  void _stageLink() {
    final raw = _urlController.text.trim();
    if (!_validate(raw)) return;

    final uri = Uri.parse(raw);
    final host = uri.host.isNotEmpty ? uri.host : 'Web Link';

    final item = TransferItem(
      id: const Uuid().v4(),
      name: host,
      size: raw.length,
      mime: 'text/uri-list',
      kind: 'file',
      url: raw,
    );

    widget.onStageItem(item);
    _urlController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(_urlController.text.trim());
    final host = uri?.host ?? '';

    return Padding(
      padding: const EdgeInsets.all(FlikTokens.screenMargin),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // URL Input pill container
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: FlikTokens.surface,
              borderRadius: BorderRadius.circular(FlikTokens.radiusPill),
              border: Border.all(
                color: _validationError != null ? FlikTokens.danger : FlikTokens.line,
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.link, color: FlikTokens.muted, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _urlController,
                    decoration: const InputDecoration(
                      hintText: 'Paste web address (http:// or https://)',
                      hintStyle: TextStyle(color: FlikTokens.muted, fontSize: 14),
                      border: InputBorder.none,
                    ),
                    style: const TextStyle(color: FlikTokens.text, fontSize: 14),
                    keyboardType: TextInputType.url,
                    onChanged: _validate,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.content_paste, size: 20, color: FlikTokens.accentSoft),
                  onPressed: _checkClipboard,
                ),
              ],
            ),
          ),

          if (_validationError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 16),
              child: Text(
                _validationError!,
                style: const TextStyle(color: FlikTokens.danger, fontSize: 12),
              ),
            ),

          const SizedBox(height: 24),

          // Domain Card Preview
          if (host.isNotEmpty && _validationError == null)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: FlikTokens.surface,
                borderRadius: BorderRadius.circular(FlikTokens.radiusGroup),
                border: Border.all(color: FlikTokens.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: FlikTokens.raised,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.language, color: FlikTokens.accentSoft),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              host,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _urlController.text.trim(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, color: FlikTokens.muted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _stageLink,
                    icon: const Icon(Icons.arrow_upward, size: 18),
                    label: const Text('Stage Link to Flick'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(FlikTokens.buttonHeight),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
