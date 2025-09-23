
// 用于管理批量处理状态的数据模型
class ImageProcessingState {
  final bool isProcessing; // 是否正在处理中
  final int totalCount; // 总任务数
  final int processedCount; // 已完成任务数
  final List<String> results; // 已成功处理的结果图片路径列表
  final List<String> failedPaths; // 新增：处理失败的图片路径列表
  final String? error; // 错误信息

  // 使用const构造函数以获得性能优化
  const ImageProcessingState({
    required this.isProcessing,
    required this.totalCount,
    required this.processedCount,
    required this.results,
    required this.failedPaths,
    this.error,
  });

  // 初始状态���厂构造函数
  factory ImageProcessingState.initial() {
    return const ImageProcessingState(
      isProcessing: false,
      totalCount: 0,
      processedCount: 0,
      results: [],
      failedPaths: [],
      error: null,
    );
  }

  // 计算处理进度 (0.0 to 1.0)
  double get progress => totalCount == 0 ? 0.0 : processedCount / totalCount;

  // copyWith 方法，方便地创建新状态实例
  ImageProcessingState copyWith({
    bool? isProcessing,
    int? totalCount,
    int? processedCount,
    List<String>? results,
    List<String>? failedPaths,
    String? error,
  }) {
    return ImageProcessingState(
      isProcessing: isProcessing ?? this.isProcessing,
      totalCount: totalCount ?? this.totalCount,
      processedCount: processedCount ?? this.processedCount,
      results: results ?? this.results,
      failedPaths: failedPaths ?? this.failedPaths,
      error: error ?? this.error,
    );
  }
}