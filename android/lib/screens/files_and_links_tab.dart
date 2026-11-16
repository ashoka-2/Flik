import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/transfer_item.dart';
import '../providers/flik_state.dart';
import '../theme/tokens.dart';

// Unified Files & Links tab: allows selecting any file from device storage,
// plus entering/pasting web links to send directly to desktop to open in default browser.
class FilesAndLinksTab extends ConsumerStatefulWidget {
  final void Function(List<TransferItem> items) onStageItems;

  const FilesAndLinksTab({super.key, required this.onStageItems});

  @override
  ConsumerState<FilesAndLinksTab> createState() => _FilesAndLinksTabState();
}

class _FilesAndLinksTabState extends ConsumerState<FilesAndLinksTab> {
  final List<PlatformFile> _pickedFiles = [];
  final TextEditingController _urlController = TextEditingController();
  String? _urlError;
  bool _isSendingLink = false;

  @override
  void initState() {
    super.initState();
    _checkClipboard();
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _checkClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text != null && (text.startsWith('http://') || text.startsWith('https://'))) {
      if (mounted) {
        setState(() {
          _urlController.text = text;
        });
      }
    }
  }

  Future<void> _pickFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any,
      );

      if (result != null && result.files.isNotEmpty) {
        setState(() {
          _pickedFiles.addAll(result.files);
        });
      }
    } catch (_) {}
  }

  void _sendPickedFilesDirectly() async {
    if (_pickedFiles.isEmpty) return;
    final notifier = ref.read(flikAppProvider.notifier);
    final items = _pickedFiles.map((f) {
      return TransferItem(
        id: const Uuid().v4(),
        name: f.name,
        size: f.size,
        mime: 'application/octet-stream',
        kind: 'file',
        localPath: f.path,
      );
    }).toList();

    setState(() => _pickedFiles.clear());
    await notifier.sendItemsDirectly(items);
  }

  void _stagePickedFiles() {
    if (_pickedFiles.isEmpty) return;
    final notifier = ref.read(flikAppProvider.notifier);
    final items = _pickedFiles.map((f) {
      return TransferItem(
        id: const Uuid().v4(),
        name: f.name,
        size: f.size,
        mime: 'application/octet-stream',
        kind: 'file',
        localPath: f.path,
      );
    }).toList();

    widget.onStageItems(items);
    setState(() => _pickedFiles.clear());
    notifier.showToast('Staged ${items.length} file(s). Flick to send!');
  }

  void _sendLinkToDesktop() async {
    final text = _urlController.text.trim();
    if (text.isEmpty) {
      setState(() => _urlError = 'Please enter or paste a web URL');
      return;
    }

    String finalUrl = text;
    if (!finalUrl.startsWith('http://') && !finalUrl.startsWith('https://')) {
      finalUrl = 'https://$finalUrl';
    }

    final uri = Uri.tryParse(finalUrl);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      setState(() => _urlError = 'Invalid link format. Must start with http:// or https://');
      return;
    }

    setState(() {
      _urlError = null;
      _isSendingLink = true;
    });

    final notifier = ref.read(flikAppProvider.notifier);
    final state = ref.read(flikAppProvider);

    if (state.peers.isNotEmpty) {
      notifier.showToast('Sending link to ${state.peers.first.deviceName}...');
      final success = await notifier.sendUrl(finalUrl, title: uri.host);
      if (success) {
        _urlController.clear();
        notifier.showToast('Link opened on ${state.peers.first.deviceName}!');
      }
    } else {
      // Stage link if no PC connected right now
      widget.onStageItems([
        TransferItem(
          id: const Uuid().v4(),
          name: uri.host.isNotEmpty ? uri.host : finalUrl,
          size: finalUrl.length,
          mime: 'text/uri-list',
          kind: 'file',
          url: finalUrl,
        ),
      ]);
      notifier.showToast('Link staged. Connect to PC to open.');
    }

    if (mounted) {
      setState(() => _isSendingLink = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // SECTION 1: Select & Send Any Files (PDF, Docs, APK, Archives, etc.)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: FlikTokens.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: FlikTokens.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: FlikTokens.accent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.folder_open, color: FlikTokens.accentSoft, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Send Any File',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: FlikTokens.text),
                        ),
                        Text(
                          'PDFs, APKs, Documents, Audio, Archives',
                          style: TextStyle(fontSize: 11, color: FlikTokens.muted),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _pickFiles,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Pick Files'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: FlikTokens.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),

              if (_pickedFiles.isNotEmpty) ...[
                const SizedBox(height: 14),
                const Divider(height: 1, color: FlikTokens.line),
                const SizedBox(height: 10),
                Text(
                  '${_pickedFiles.length} file(s) ready to send:',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: FlikTokens.accentSoft),
                ),
                const SizedBox(height: 8),
                ...List.generate(_pickedFiles.length, (idx) {
                  final f = _pickedFiles[idx];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.insert_drive_file, size: 16, color: FlikTokens.muted),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            f.name,
                            style: const TextStyle(fontSize: 12, color: FlikTokens.text),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '${(f.size / (1024 * 1024)).toStringAsFixed(1)} MB',
                          style: const TextStyle(fontSize: 11, color: FlikTokens.muted),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 16, color: FlikTokens.muted),
                          onPressed: () => setState(() => _pickedFiles.removeAt(idx)),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 12),
                Row(
                  children: [
                    OutlinedButton(
                      onPressed: _stagePickedFiles,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: FlikTokens.line),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Stage (Flik to Send)', style: TextStyle(color: FlikTokens.text, fontSize: 12)),
                    ),
                    const Spacer(),
                    ElevatedButton.icon(
                      onPressed: _sendPickedFilesDirectly,
                      icon: const Icon(Icons.arrow_upward, size: 16),
                      label: const Text('Send Directly'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: FlikTokens.accent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 18),

        // SECTION 2: Add & Send Web Link to Desktop
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: FlikTokens.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: FlikTokens.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.link, color: Colors.amber, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Send Link to Desktop',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: FlikTokens.text),
                        ),
                        Text(
                          'Instantly opens on PC in default browser',
                          style: TextStyle(fontSize: 11, color: FlikTokens.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Input with Paste button
              Container(
                decoration: BoxDecoration(
                  color: FlikTokens.raised,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _urlError != null ? Colors.redAccent : FlikTokens.line),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    const Icon(Icons.language, size: 18, color: FlikTokens.muted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _urlController,
                        style: const TextStyle(color: FlikTokens.text, fontSize: 13),
                        decoration: const InputDecoration(
                          hintText: 'https://youtube.com or website URL...',
                          hintStyle: TextStyle(color: FlikTokens.muted, fontSize: 13),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 12),
                        ),
                        onSubmitted: (_) => _sendLinkToDesktop(),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        final data = await Clipboard.getData(Clipboard.kTextPlain);
                        if (data?.text != null) {
                          setState(() => _urlController.text = data!.text!.trim());
                        }
                      },
                      icon: const Icon(Icons.content_paste, size: 14),
                      label: const Text('Paste', style: TextStyle(fontSize: 11)),
                      style: TextButton.styleFrom(foregroundColor: FlikTokens.accentSoft),
                    ),
                  ],
                ),
              ),

              if (_urlError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 4),
                  child: Text(
                    _urlError!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 11),
                  ),
                ),

              const SizedBox(height: 14),

              SizedBox(
                width: double.infinity,
                height: 42,
                child: ElevatedButton.icon(
                  onPressed: _isSendingLink ? null : _sendLinkToDesktop,
                  icon: _isSendingLink
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.open_in_browser, size: 18),
                  label: Text(_isSendingLink ? 'Opening on Desktop...' : 'Send Link to Desktop'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: FlikTokens.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
