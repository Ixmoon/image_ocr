import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_ocr/features/templates/models/folder.dart';
import 'package:image_ocr/features/templates/models/template.dart';
import 'package:image_ocr/features/templates/providers/template_providers.dart';

// --- State Provider for Overlay ---
// Manages the currently selected template within the overlay window.
final overlaySelectedTemplateProvider = StateProvider<Template?>((ref) => null);

class TemplateSelector extends ConsumerStatefulWidget {
  const TemplateSelector({super.key});

  @override
  ConsumerState<TemplateSelector> createState() => _TemplateSelectorState();
}

class _TemplateSelectorState extends ConsumerState<TemplateSelector> {
  late final List<String?> _navigationStack;

  @override
  void initState() {
    super.initState();
    // Initialize navigation stack with the root folder.
    _navigationStack = [ref.read(currentFolderIdProvider)];
  }

  @override
  Widget build(BuildContext context) {
    final currentFolderId = _navigationStack.last;
    final contentsAsync = ref.watch(folderContentsProvider(currentFolderId));
    final pathAsync = ref.watch(folderPathProvider);
    final selectedTemplate = ref.watch(overlaySelectedTemplateProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // --- Breadcrumb Navigation ---
        SizedBox(
          height: 24,
          child: pathAsync.when(
            data: (path) => ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              scrollDirection: Axis.horizontal,
              itemCount: path.length,
              separatorBuilder: (context, index) => const Icon(Icons.chevron_right, color: Colors.grey, size: 12),
              itemBuilder: (context, index) {
                final folder = path[index];
                return InkWell(
                  onTap: () => setState(() => _navigationStack.removeRange(index + 1, _navigationStack.length)),
                  child: Center(
                    child: Text(
                      folder?.name ?? '根目录',
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
                );
              },
            ),
            loading: () => const SizedBox.shrink(),
            error: (e, s) => const SizedBox.shrink(),
          ),
        ),
        const Divider(height: 1),
        // --- File/Folder List ---
        Expanded(
          child: contentsAsync.when(
            loading: () => const Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
            error: (err, stack) => Center(
              child: Text(
                '加载失败',
                style: const TextStyle(fontSize: 10),
              ),
            ),
            data: (contents) {
              if (contents.isEmpty) {
                return const Center(
                  child: Text(
                    '此文件夹为空',
                    style: TextStyle(fontSize: 10),
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.all(4.0),
                itemCount: contents.length,
                itemBuilder: (context, index) {
                  final item = contents[index];
                  if (item is Folder) {
                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 1.0),
                      child: InkWell(
                        onTap: () => setState(() => _navigationStack.add(item.id)),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 3.0),
                          child: Row(
                            children: [
                              const Icon(Icons.folder_outlined, size: 14, color: Colors.orange),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  item.name,
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  } else if (item is Template) {
                    final template = item;
                    final isSelected = selectedTemplate?.id == template.id;
                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 1.0),
                      child: InkWell(
                        onTap: () {
                          ref.read(overlaySelectedTemplateProvider.notifier).state = template;
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 3.0),
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.blue.shade100 : Colors.transparent,
                            borderRadius: BorderRadius.circular(3),
                            border: isSelected ? Border.all(color: Colors.blue, width: 1) : null,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                                size: 14,
                                color: isSelected ? Colors.blue : Colors.grey,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  template.name,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                                    color: isSelected ? Colors.blue.shade700 : Colors.black87,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              );
            },
          ),
        ),
      ],
    );
  }
}