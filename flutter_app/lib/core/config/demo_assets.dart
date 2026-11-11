// Local sample assets are used only when USE_DEMO_DATA is enabled.
String demoMemoryAsset(String id) {
  final number = int.tryParse(id.replaceAll(RegExp(r'[^0-9]'), '')) ?? 1;
  return 'asset:assets/demo/memory-${(number - 1) % 9 + 1}.jpg';
}
