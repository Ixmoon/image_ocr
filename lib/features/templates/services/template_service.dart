import 'package:hive_flutter/hive_flutter.dart';
import 'package:image_ocr/features/templates/models/folder.dart';
import 'package:image_ocr/features/templates/models/template.dart';

/// A service class for handling all local storage operations for templates and folders using Hive.
class TemplateService {
  final Box<Template> _templatesBox;
  final Box<Folder> _foldersBox;
  final Box<List<String>> _orderBox;

  TemplateService._(this._templatesBox, this._foldersBox, this._orderBox);

  /// Factory for creating an instance of [TemplateService] with initialized Hive boxes.
  static Future<TemplateService> create() async {
    final templatesBox = await Hive.openBox<Template>('templates');
    final foldersBox = await Hive.openBox<Folder>('folders');
    final orderBox = await Hive.openBox<List<String>>('item_order');
    return TemplateService._(templatesBox, foldersBox, orderBox);
  }

  // --- Read Operations ---

  /// Gets the sorted list of item IDs for the root directory.
  List<String> getRootOrder() {
    return _orderBox.get('root', defaultValue: [])?.cast<String>() ?? [];
  }

  /// Gets all templates from the box.
  List<Template> getTemplates() {
    return _templatesBox.values.toList();
  }

  /// Gets all folders from the box.
  List<Folder> getFolders() {
    return _foldersBox.values.toList();
  }

  // --- Write Operations ---

  /// Saves a template. If it's new, adds it to the correct parent's children list.
  Future<void> saveTemplate(Template template) async {
    final isNew = !_templatesBox.containsKey(template.id);
    await _templatesBox.put(template.id, template);

    if (isNew) {
      await _addItemToParent(template.id, template.folderId);
    }
  }

  /// Deletes a template and removes it from its parent's children list.
  Future<void> deleteTemplate(String id) async {
    final template = _templatesBox.get(id);
    if (template == null) return;

    await _removeItemFromParent(id, template.folderId);
    await _templatesBox.delete(id);
  }

  /// Creates a new folder and adds it to the parent's children list.
  Future<void> createFolder(String name, {String? parentId}) async {
    final newFolder = Folder(name: name, parentId: parentId);
    await _foldersBox.put(newFolder.id, newFolder);
    await _addItemToParent(newFolder.id, parentId);
  }

  /// Updates a folder's name.
  Future<void> updateFolder(String folderId, String newName) async {
    final folder = _foldersBox.get(folderId);
    if (folder != null) {
      folder.name = newName;
      await folder.save();
    }
  }

  /// Deletes a folder if it's empty and removes it from its parent's list.
  Future<void> deleteFolder(String folderId) async {
    final folder = _foldersBox.get(folderId);
    if (folder == null) return;

    if (folder.childrenIds.isNotEmpty) {
      throw Exception('文件夹不为空，无法删除。');
    }

    await _removeItemFromParent(folderId, folder.parentId);
    await _foldersBox.delete(folderId);
  }

  /// Reorders the children within a specific parent (or root).
  Future<void> reorderChildren(String? parentId, int oldIndex, int newIndex) async {
    if (oldIndex == newIndex) return;

    List<String> orderList;
    if (parentId == null) {
      orderList = getRootOrder();
    } else {
      final parentFolder = _foldersBox.get(parentId);
      if (parentFolder == null) return;
      orderList = parentFolder.childrenIds;
    }

    if (oldIndex < 0 || oldIndex >= orderList.length) return;
    
    final item = orderList.removeAt(oldIndex);
    orderList.insert(newIndex, item);

    if (parentId == null) {
      await _orderBox.put('root', orderList);
    } else {
      // The list is a reference to parentFolder.childrenIds, so saving the parent persists the change.
      await _foldersBox.get(parentId)?.save();
    }
  }

  /// Moves a template to a different folder.
  Future<void> moveTemplateToFolder(String templateId, String? newFolderId) async {
    final template = _templatesBox.get(templateId);
    if (template == null) return;

    final oldFolderId = template.folderId;
    if (oldFolderId == newFolderId) return;

    await _removeItemFromParent(templateId, oldFolderId);
    
    template.folderId = newFolderId;
    await template.save(); // Use template's own save method

    await _addItemToParent(templateId, newFolderId);
  }

  /// Moves a folder to a different parent folder, with cycle detection.
  Future<void> moveFolderToFolder(String folderId, String? newParentId) async {
    final folder = _foldersBox.get(folderId);
    if (folder == null) return;

    final oldParentId = folder.parentId;
    if (oldParentId == newParentId) return;

    // Cycle detection: cannot move a folder into itself or one of its descendants.
    if (folderId == newParentId) throw Exception('不能将文件夹移动到自身。');
    var currentId = newParentId;
    while (currentId != null) {
      if (currentId == folderId) {
        throw Exception('不能将文件夹移动到其子文件夹中。');
      }
      final parent = _foldersBox.get(currentId);
      currentId = parent?.parentId;
    }

    await _removeItemFromParent(folderId, oldParentId);

    folder.parentId = newParentId;
    await folder.save(); // Use folder's own save method
    
    await _addItemToParent(folderId, newParentId);
  }

  // --- Private Helper Methods ---

  /// Removes an item's ID from its parent's children list.
  Future<void> _removeItemFromParent(String itemId, String? parentId) async {
    if (parentId == null) {
      final rootOrder = getRootOrder()..remove(itemId);
      await _orderBox.put('root', rootOrder);
    } else {
      final parentFolder = _foldersBox.get(parentId);
      if (parentFolder != null) {
        parentFolder.childrenIds.remove(itemId);
        await parentFolder.save();
      }
    }
  }

  /// Adds an item's ID to its new parent's children list.
  Future<void> _addItemToParent(String itemId, String? parentId) async {
    if (parentId == null) {
      final rootOrder = getRootOrder();
      if (!rootOrder.contains(itemId)) {
        rootOrder.add(itemId);
        await _orderBox.put('root', rootOrder);
      }
    } else {
      final parentFolder = _foldersBox.get(parentId);
      if (parentFolder != null) {
        if (!parentFolder.childrenIds.contains(itemId)) {
          parentFolder.childrenIds.add(itemId);
          await parentFolder.save();
        }
      }
    }
  }
}