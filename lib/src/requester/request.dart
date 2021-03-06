part of dslink.requester;

/// request class handles raw response from responder
class Request {
  final Requester requester;
  final int rid;
  final Map data;

  /// raw request callback
  final RequestUpdater updater;
  bool _isClosed = false;
  bool get isClosed => _isClosed;

  Request(this.requester, this.rid, this.updater, this.data);

  String streamStatus = StreamStatus.initialize;

  /// resend the data if previous sending failed
  void resend() {
    requester.addToSendList(data);
  }
  
  void addReqParams(Map m) {
    requester.addToSendList({'rid':rid, 'params':m});
  }

  void _update(Map m) {
    if (m["stream"] is String) {
      streamStatus = m["stream"];
    }
    List updates;
    List columns;
    Map meta;
    if (m["updates"] is List) {
      updates = m["updates"];
    }
    if (m["columns"] is List) {
      columns = m["columns"];
    }
    if (m["meta"] is Map) {
      meta = m["meta"];
    }
    // remove the request from global Map
    if (streamStatus == StreamStatus.closed) {
      requester._requests.remove(rid);
    }
    DSError error;
    if (m.containsKey("error") && m["error"] is Map) {
      error = new DSError.fromMap(m["error"]);
      requester._errorController.add(error);
    }

    updater.onUpdate(streamStatus, updates, columns, meta, error);
  }

  /// close the request and finish data
  void _close([DSError error]) {
    if (streamStatus != StreamStatus.closed) {
      streamStatus = StreamStatus.closed;
      updater.onUpdate(StreamStatus.closed, null, null, null, error);
    }
  }

  /// close the request from the client side
  void close() {
    // _close will also be called later from the requester;
    requester.closeRequest(this);
  }
}
