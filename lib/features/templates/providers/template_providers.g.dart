// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'template_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$templateServiceHash() => r'a250ac08f3040ee51c322c9934b865cb01e940cc';

/// See also [templateService].
@ProviderFor(templateService)
final templateServiceProvider = FutureProvider<TemplateService>.internal(
  templateService,
  name: r'templateServiceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$templateServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef TemplateServiceRef = FutureProviderRef<TemplateService>;
String _$currentFolderIdHash() => r'1e8b881406488a3504d72ee85510baedd67ef5f8';

/// See also [currentFolderId].
@ProviderFor(currentFolderId)
final currentFolderIdProvider = AutoDisposeProvider<String?>.internal(
  currentFolderId,
  name: r'currentFolderIdProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$currentFolderIdHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef CurrentFolderIdRef = AutoDisposeProviderRef<String?>;
String _$folderContentsHash() => r'd7bc99fa8ca5bb40ba58d36061dadf2a8ac86e7c';

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

/// See also [folderContents].
@ProviderFor(folderContents)
const folderContentsProvider = FolderContentsFamily();

/// See also [folderContents].
class FolderContentsFamily extends Family<AsyncValue<List<dynamic>>> {
  /// See also [folderContents].
  const FolderContentsFamily();

  /// See also [folderContents].
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

/// See also [folderContents].
class FolderContentsProvider extends AutoDisposeFutureProvider<List<dynamic>> {
  /// See also [folderContents].
  FolderContentsProvider(
    String? folderId,
  ) : this._internal(
          (ref) => folderContents(
            ref as FolderContentsRef,
            folderId,
          ),
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
  Override overrideWith(
    FutureOr<List<dynamic>> Function(FolderContentsRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: FolderContentsProvider._internal(
        (ref) => create(ref as FolderContentsRef),
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
  AutoDisposeFutureProviderElement<List<dynamic>> createElement() {
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

mixin FolderContentsRef on AutoDisposeFutureProviderRef<List<dynamic>> {
  /// The parameter `folderId` of this provider.
  String? get folderId;
}

class _FolderContentsProviderElement
    extends AutoDisposeFutureProviderElement<List<dynamic>>
    with FolderContentsRef {
  _FolderContentsProviderElement(super.provider);

  @override
  String? get folderId => (origin as FolderContentsProvider).folderId;
}

String _$folderPathHash() => r'ad561a5836b6b1541ffb6f30122bf00a2442fbb3';

/// See also [folderPath].
@ProviderFor(folderPath)
final folderPathProvider = AutoDisposeFutureProvider<List<Folder?>>.internal(
  folderPath,
  name: r'folderPathProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$folderPathHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef FolderPathRef = AutoDisposeFutureProviderRef<List<Folder?>>;
String _$templateByIdHash() => r'258c6ca54803aad8a68b76c58f063cecbc086240';

/// See also [templateById].
@ProviderFor(templateById)
const templateByIdProvider = TemplateByIdFamily();

/// See also [templateById].
class TemplateByIdFamily extends Family<AsyncValue<Template>> {
  /// See also [templateById].
  const TemplateByIdFamily();

  /// See also [templateById].
  TemplateByIdProvider call(
    String templateId,
  ) {
    return TemplateByIdProvider(
      templateId,
    );
  }

  @override
  TemplateByIdProvider getProviderOverride(
    covariant TemplateByIdProvider provider,
  ) {
    return call(
      provider.templateId,
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

/// See also [templateById].
class TemplateByIdProvider extends AutoDisposeFutureProvider<Template> {
  /// See also [templateById].
  TemplateByIdProvider(
    String templateId,
  ) : this._internal(
          (ref) => templateById(
            ref as TemplateByIdRef,
            templateId,
          ),
          from: templateByIdProvider,
          name: r'templateByIdProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$templateByIdHash,
          dependencies: TemplateByIdFamily._dependencies,
          allTransitiveDependencies:
              TemplateByIdFamily._allTransitiveDependencies,
          templateId: templateId,
        );

  TemplateByIdProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.templateId,
  }) : super.internal();

  final String templateId;

  @override
  Override overrideWith(
    FutureOr<Template> Function(TemplateByIdRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: TemplateByIdProvider._internal(
        (ref) => create(ref as TemplateByIdRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        templateId: templateId,
      ),
    );
  }

  @override
  AutoDisposeFutureProviderElement<Template> createElement() {
    return _TemplateByIdProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is TemplateByIdProvider && other.templateId == templateId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, templateId.hashCode);

    return _SystemHash.finish(hash);
  }
}

mixin TemplateByIdRef on AutoDisposeFutureProviderRef<Template> {
  /// The parameter `templateId` of this provider.
  String get templateId;
}

class _TemplateByIdProviderElement
    extends AutoDisposeFutureProviderElement<Template> with TemplateByIdRef {
  _TemplateByIdProviderElement(super.provider);

  @override
  String get templateId => (origin as TemplateByIdProvider).templateId;
}

String _$templatesAndFoldersActionsHash() =>
    r'ebe774d8cc1b6d309c25e4893a561509a20ab751';

/// See also [templatesAndFoldersActions].
@ProviderFor(templatesAndFoldersActions)
final templatesAndFoldersActionsProvider =
    AutoDisposeProvider<TemplatesAndFoldersActions>.internal(
  templatesAndFoldersActions,
  name: r'templatesAndFoldersActionsProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$templatesAndFoldersActionsHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef TemplatesAndFoldersActionsRef
    = AutoDisposeProviderRef<TemplatesAndFoldersActions>;
String _$folderNavigationStackHash() =>
    r'fc9f47a7a42b293dcdf20cb64e55bba7139facc5';

/// See also [FolderNavigationStack].
@ProviderFor(FolderNavigationStack)
final folderNavigationStackProvider =
    AutoDisposeNotifierProvider<FolderNavigationStack, List<String?>>.internal(
  FolderNavigationStack.new,
  name: r'folderNavigationStackProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$folderNavigationStackHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$FolderNavigationStack = AutoDisposeNotifier<List<String?>>;
String _$templateCreationHash() => r'accd340ca21dcd72502b8c77c1c0e985577c91db';

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
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member
