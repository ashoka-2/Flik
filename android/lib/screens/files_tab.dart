import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/transfer_item.dart';
import '../theme/tokens.dart';

// Files tab allowing multi-file selection via native file picker and staging.
class FilesTab extends StatefulWidget {
  final void Function(List<TransferItem> items) onStageItems;

  const FilesTab({super.key, required this.onStageItems});

  @override
  State<FilesTab> createState() => _FilesTabState();
}

class _FilesTabState extends State<FilesTab> {
  final List<PlatformFile> _pickedFiles = [];

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

  void _stagePicked() {
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
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(FlikTokens.screenMargin),
      child: Column(
        children: [
          // Pick files header card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: FlikTokens.surface,
              borderRadius: BorderRadius.circular(FlikTokens.radiusGroup),
              border: Border.all(color: FlikTokens.line),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: FlikTokens.raised,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.folder_open, color: FlikTokens.accentSoft),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Select Files',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: FlikTokens.text),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'PDFs, ZIPs, docs, audio, and more',
                        style: TextStyle(fontSize: 12, color: FlikTokens.muted),
                      ),
                    ],
                  ),
                ),
                ElevatedButton(
                  onPressed: _pickFiles,
                  child: const Text('Browse'),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Picked files list
          Expanded(
            child: _pickedFiles.isEmpty
                ? Center(
                    child: Text(
                      'No files selected yet',
                      style: TextStyle(color: FlikTokens.muted.withOpacity(0.6), fontSize: 13),
                    ),
                  )
                : ListView.separated(
                    itemCount: _pickedFiles.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final f = _pickedFiles[index];
                      final sizeMb = (f.size / (1024 * 1024)).toStringAsFixed(1);

                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: FlikTokens.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: FlikTokens.line),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.insert_drive_file, color: FlikTokens.muted, size: 22),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    f.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                                  ),
                                  Text(
                                    '$sizeMb MB',
                                    style: const TextStyle(fontSize: 12, color: FlikTokens.muted),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 18, color: FlikTokens.muted),
                              onPressed: () {
                                setState(() => _pickedFiles.removeAt(index));
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),

          if (_pickedFiles.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: ElevatedButton.icon(
                onPressed: _stagePicked,
                icon: const Icon(Icons.arrow_upward, size: 18),
                label: Text('Stage ${_pickedFiles.length} File(s) to Flick'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(FlikTokens.buttonHeightLarge),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
