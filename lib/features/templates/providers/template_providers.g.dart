// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'template_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$templateServiceHash() => r'36d13a14783ac315bb1669b2f28b9692090cb896';

/// See also [TemplateService].
@ProviderFor(TemplateService)
final templateServiceProvider = AutoDisposeAsyncNotifierProvider<
    TemplateService, template_service_lib.TemplateService>.internal(
  TemplateService.new,
  name: r'templateServiceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$templateServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$TemplateService
    = AutoDisposeAsyncNotifier<template_service_lib.TemplateService>;
String _$folderNavigationStackHash() =>
    r'0400154adae7575bbc48f03bb909dd07480ac5cf';

/// See also [FolderNavigationStack].
@ProviderFor(FolderNavigationStack)
final folderNavigationStackProvider =
    AsyncNotifierProvider<FolderNavigationStack, List<String?>>.internal(
  FolderNavigationStack.new,
  name: r'folderNavigationStackProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$folderNavigationStackHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$FolderNavigationStack = AsyncNotifier<List<String?>>;
String _$currentFolderIdHash() => r'aef559d6b1f01cbef186a6afc2239201f215a044';

/// See also [CurrentFolderId].
@ProviderFor(CurrentFolderId)
final currentFolderIdProvider =
    AutoDisposeNotifierProvider<CurrentFolderId, String?>.internal(
  CurrentFolderId.new,
  name: r'currentFolderIdProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$currentFolderIdHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$CurrentFolderId = AutoDisposeNotifier<String?>;
String _$folderContentsHash() => r'f00fce0a1c20a4af0bc90ee520e608d6173f913f';

/// Copied from Dart SDK
class _SystemHash {
  _SystemHash._();

  static int combine(int hash, int value) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + value);
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
    return hash ^ (hash >> 6);
  }

  static int finish(int hash) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    // ignore: parameter_assignments
    hash = hash ^ (hash >> 11);
    return 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
  }
}

abstract class _$FolderContents
    extends BuildlessAutoDisposeAsyncNotifier<List<dynamic>> {
  late final String? folderId;

  FutureOr<List<dynamic>> build(
    String? folderId,
  );
}

/// See also [FolderContents].
@ProviderFor(FolderContents)
const folderContentsProvider = FolderContentsFamily();

/// See also [FolderContents].
class FolderContentsFamily extends Family<AsyncValue<List<dynamic>>> {
  /// See also [FolderContents].
  const FolderContentsFamily();

  /// See also [FolderContents].
  FolderContentsProvider call(
    String? folderId,
  ) {
    return FolderContentsProvider(
      folderId,
    );
  }

  @override
  FolderContentsProvider getProviderOverride(
    covariant FolderContentsProvider provider,
  ) {
    return call(
      provider.folderId,
    );
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'folderContentsProvider';
}

/// See also [FolderContents].
class FolderContentsProvider extends AutoDisposeAsyncNotifierProviderImpl<
    FolderContents, List<dynamic>> {
  /// See also [FolderContents].
  FolderContentsProvider(
    String? folderId,
  ) : this._internal(
          () => FolderContents()..folderId = folderId,
          from: folderContentsProvider,
          name: r'folderContentsProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$folderContentsHash,
          dependencies: FolderContentsFamily._dependencies,
          allTransitiveDependencies:
              FolderContentsFamily._allTransitiveDependencies,
          folderId: folderId,
        );

  FolderContentsProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.folderId,
  }) : super.internal();

  final String? folderId;

  @override
  FutureOr<List<dynamic>> runNotifierBuild(
    covariant FolderContents notifier,
  ) {
    return notifier.build(
      folderId,
    );
  }

  @override
  Override overrideWith(FolderContents Function() create) {
    return ProviderOverride(
      origin: this,
      override: FolderContentsProvider._internal(
        () => create()..folderId = folderId,
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        folderId: folderId,
      ),
    );
  }

  @override
  AutoDisposeAsyncNotifierProviderElement<FolderContents, List<dynamic>>
      createElement() {
    return _FolderContentsProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is FolderContentsProvider && other.folderId == folderId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, folderId.hashCode);

    return _SystemHash.finish(hash);
  }
}

mixin FolderContentsRef on AutoDisposeAsyncNotifierProviderRef<List<dynamic>> {
  /// The parameter `folderId` of this provider.
  String? get folderId;
}

class _FolderContentsProviderElement
    extends AutoDisposeAsyncNotifierProviderElement<FolderContents,
        List<dynamic>> with FolderContentsRef {
  _FolderContentsProviderElement(super.provider);

  @override
  String? get folderId => (origin as FolderContentsProvider).folderId;
}

String _$folderPathHash() => r'22736ebe6fce56cf9691c091712899bae4114dbe';

/// See also [FolderPath].
@ProviderFor(FolderPath)
final folderPathProvider =
    AutoDisposeAsyncNotifierProvider<FolderPath, List<Folder?>>.internal(
  FolderPath.new,
  name: r'folderPathProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$folderPathHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$FolderPath = AutoDisposeAsyncNotifier<List<Folder?>>;
String _$templateCreationHash() => r'667a801d2bf48ef9aa629914abf8e03e54b993ab';

/// See also [TemplateCreation].
@ProviderFor(TemplateCreation)
final templateCreationProvider =
    AutoDisposeNotifierProvider<TemplateCreation, Template>.internal(
  TemplateCreation.new,
  name: r'templateCreationProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$templateCreationHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$TemplateCreation = AutoDisposeNotifier<Template>;
String _$templateByIdHash() => r'920681502666279f6b4d2bdb7dec83f7ce10fbc0';

abstract class _$TemplateById
    extends BuildlessAutoDisposeAsyncNotifier<Template> {
  late final String id;

  FutureOr<Template> build(
    String id,
  );
}

/// See also [TemplateById].
@ProviderFor(TemplateById)
const templateByIdProvider = TemplateByIdFamily();

/// See also [TemplateById].
class TemplateByIdFamily extends Family<AsyncValue<Template>> {
  /// See also [TemplateById].
  const TemplateByIdFamily();

  /// See also [TemplateById].
  TemplateByIdProvider call(
    String id,
  ) {
    return TemplateByIdProvider(
      id,
    );
  }

  @override
  TemplateByIdProvider getProviderOverride(
    covariant TemplateByIdProvider provider,
  ) {
    return call(
      provider.id,
    );
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'templateByIdProvider';
}

/// See also [TemplateById].
class TemplateByIdProvider
    extends AutoDisposeAsyncNotifierProviderImpl<TemplateById, Template> {
  /// See also [TemplateById].
  TemplateByIdProvider(
    String id,
  ) : this._internal(
          () => TemplateById()..id = id,
          from: templateByIdProvider,
          name: r'templateByIdProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$templateByIdHash,
          dependencies: TemplateByIdFamily._dependencies,
          allTransitiveDependencies:
              TemplateByIdFamily._allTransitiveDependencies,
          id: id,
        );

  TemplateByIdProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.id,
  }) : super.internal();

  final String id;

  @override
  FutureOr<Template> runNotifierBuild(
    covariant TemplateById notifier,
  ) {
    return notifier.build(
      id,
    );
  }

  @override
  Override overrideWith(TemplateById Function() create) {
    return ProviderOverride(
      origin: this,
      override: TemplateByIdProvider._internal(
        () => create()..id = id,
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        id: id,
      ),
    );
  }

  @override
  AutoDisposeAsyncNotifierProviderElement<TemplateById, Template>
      createElement() {
    return _TemplateByIdProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is TemplateByIdProvider && other.id == id;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, id.hashCode);

    return _SystemHash.finish(hash);
  }
}

mixin TemplateByIdRef on AutoDisposeAsyncNotifierProviderRef<Template> {
  /// The parameter `id` of this provider.
  String get id;
}

class _TemplateByIdProviderElement
    extends AutoDisposeAsyncNotifierProviderElement<TemplateById, Template>
    with TemplateByIdRef {
  _TemplateByIdProviderElement(super.provider);

  @override
  String get id => (origin as TemplateByIdProvider).id;
}

String _$allTemplatesHash() => r'cee18972b700e590262d6c84be9582c4448c271f';

/// See also [AllTemplates].
@ProviderFor(AllTemplates)
final allTemplatesProvider =
    AutoDisposeAsyncNotifierProvider<AllTemplates, List<Template>>.internal(
  AllTemplates.new,
  name: r'allTemplatesProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$allTemplatesHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$AllTemplates = AutoDisposeAsyncNotifier<List<Template>>;
String _$templatesAndFoldersActionsHash() =>
    r'bbe1e3d922f64858dc3e1a441ba2468b05dc3b4d';

/// See also [TemplatesAndFoldersActions].
@ProviderFor(TemplatesAndFoldersActions)
final templatesAndFoldersActionsProvider = AutoDisposeNotifierProvider<
    TemplatesAndFoldersActions, TemplatesAndFoldersActionsLogic>.internal(
  TemplatesAndFoldersActions.new,
  name: r'templatesAndFoldersActionsProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$templatesAndFoldersActionsHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$TemplatesAndFoldersActions
    = AutoDisposeNotifier<TemplatesAndFoldersActionsLogic>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member
