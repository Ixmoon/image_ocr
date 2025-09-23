// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'template_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$templatesHash() => r'86187d31a09be8b7958c37eb629b1d46493dab19';

/// See also [Templates].
@ProviderFor(Templates)
final templatesProvider =
    AsyncNotifierProvider<Templates, List<Template>>.internal(
  Templates.new,
  name: r'templatesProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$templatesHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$Templates = AsyncNotifier<List<Template>>;
String _$templateCreationHash() => r'9ed445399a14e891584b12fd3e2bedc6cfbd9d53';

/// See also [TemplateCreation].
@ProviderFor(TemplateCreation)
final templateCreationProvider =
    AutoDisposeNotifierProvider<TemplateCreation, Template?>.internal(
  TemplateCreation.new,
  name: r'templateCreationProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$templateCreationHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$TemplateCreation = AutoDisposeNotifier<Template?>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member
