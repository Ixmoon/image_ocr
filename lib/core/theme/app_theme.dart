import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';

// 应用主题配置类
class AppTheme {
  // 私有构造函数，防止外部实例化
  AppTheme._();

  // 浅色主题
  // 使用FlexColorScheme可以轻松创建一致且美观的Material 3主题
  static final ThemeData lightTheme = FlexThemeData.light(
    scheme: FlexScheme.deepBlue, // 选择一个预设的颜色方案
    surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
    blendLevel: 7,
    subThemesData: const FlexSubThemesData(
      blendOnLevel: 10,
      blendOnColors: false,
      useMaterial3Typography: true,
      useM2StyleDividerInM3: true,
      // 为FAB、按钮等组件配置圆角
      defaultRadius: 16.0,
    ),
    visualDensity: FlexColorScheme.comfortablePlatformDensity,
    useMaterial3: true, // 明确启用Material 3
    swapLegacyOnMaterial3: true,
  );

  // 深色主题
  static final ThemeData darkTheme = FlexThemeData.dark(
    scheme: FlexScheme.deepBlue, // 与浅色主题保持一致的色系
    surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
    blendLevel: 13,
    subThemesData: const FlexSubThemesData(
      blendOnLevel: 20,
      useMaterial3Typography: true,
      useM2StyleDividerInM3: true,
      defaultRadius: 16.0,
    ),
    visualDensity: FlexColorScheme.comfortablePlatformDensity,
    useMaterial3: true,
    swapLegacyOnMaterial3: true,
  );
}