abstract class PlatformWebSocketConnection {
  Stream<String> get messages;

  Future<void> close();
}
