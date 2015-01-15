part of dslink.responder;

/// node can be subscribed or listed by multiple responder
abstract class DsRespNode extends DsNode {
  DsRespNode(String path) : super(path);

  /// list and subscribe can be called on a node that doesn't exist
  /// other api like set remove, invoke, can only be applied to existing node
  bool get exists;

  DsResponse list(DsResponder responder, DsResponse response);
  void subscribe(DsSubscribeResponse subscription, DsResponder responder);
  void unsubscribe(DsSubscribeResponse subscription, DsResponder responder);

  DsResponse invoke(Map params, DsResponder responder, DsResponse rid);

  DsResponse setAttribute(String name, String value, DsResponder responder, DsResponse rid);
  DsResponse removeAttribute(String name, DsResponder responder, DsResponse rid);
  DsResponse setConfig(String name, Object value, DsResponder responder, DsResponse rid);
  DsResponse removeConfig(String name, DsResponder responder, DsResponse rid);
  /// set node value
  DsResponse setValue(Object value, DsResponder responder, DsResponse rid);
}
/// node provider for responder
/// one nodeProvider can be reused by multiple responders
abstract class DsNodeProvider {
  /// get a existing node or create a dummy node for requester to listen on
  DsRespNode getNode(String path);
}