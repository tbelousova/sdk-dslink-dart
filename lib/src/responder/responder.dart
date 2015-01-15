part of dslink.responder;

/// a responder for one connection
class DsResponder extends DsConnectionHandler {
  final Map<int, DsResponse> _responses = new Map<int, DsResponse>();
  DsSubscribeResponse _subscription;
  /// caching of nodes
  final DsNodeProvider nodeProvider;

  DsResponder(this.nodeProvider) {
    _subscription = new DsSubscribeResponse(this, 0);
    _responses[0] = _subscription;
  }

  void onDisconnected() {
    // TODO close and clear all responses
  }
  void onReconnected() {
  }


  DsResponse addResponse(DsResponse response) {
    if (response._streamStatus != DsStreamStatus.closed) {
      _responses[response.rid] = response;
    }
    return response;
  }
  void onData(List list) {
    for (Object resp in list) {
      if (resp is Map) {
        _onReceiveRequest(resp);
      }
    }
  }
  void _onReceiveRequest(Map m) {
    if (m['method'] is String && m['rid'] is int) {
      if (_responses.containsKey(m['rid'])) {
        // when rid is invalid, nothing needs to be sent back
        return;
      }
      switch (m['method']) {
        case 'list':
          _list(m);
          return;
        case 'subscribe':
          _subscribe(m);
          return;
        case 'unsubscribe':
          _unsubscribe(m);
          return;
        case 'invoke':
          _invoke(m);
          return;
        case 'set':
          _set(m);
          return;
        case 'remove':
          _remove(m);
          return;
        case 'close':
          _close(m);
          return;
        default:
      }
    }
    if (m['rid'] is int) {
      _closeResponse(m['rid'], error: new DsError('invalid request method'));
    }
  }
  /// close the response from responder side and notify requester
  void _closeResponse(int rid, {DsResponse response, DsError error}) {
    if (response != null) {
      if (_responses[response.rid] != response) {
        // this response is no longer valid
        return;
      }
      response._streamStatus = DsStreamStatus.closed;
      rid = response.rid;
    }
    Map m = {
      'rid': rid,
      'stream': DsStreamStatus.closed
    };
    if (error != null) {
      m['error'] = error.serialize();
    }
    addToSendList(m);
  }
  void updateReponse(DsResponse response, List updates, {String status, List<DsTableColumn> columns}) {
    if (_responses[response.rid] == response) {
      Map m = {
        'rid': response.rid
      };
      if (status != null && status != response._streamStatus) {
        response._streamStatus = status;
        m['stream'] = status;
      }
      if (columns != null) {
        m['columns'] = columns;
      }
      if (updates != null) {
        m['updates'] = updates;
      }
      addToSendList(m);
      if (response._streamStatus == DsStreamStatus.closed) {
        _responses.remove(response.rid);
      }
    }
  }


  void _list(Map m) {
    DsPath path = DsPath.getValidNodePath(m['path']);
    if (path != null && path.absolute) {
      int rid = m['rid'];
      nodeProvider.getNode(path.path).list(this, addResponse(new DsResponse(this, rid)));
    } else {
      _closeResponse(m['rid'], error: new DsError('invalid path'));
    }
  }
  void _subscribe(Map m) {
    if (m['paths'] is List) {
      int rid = m['rid'];
      for (Object str in m['paths']) {
        DsPath path = DsPath.getValidNodePath(m['str']);
        if (path != null && path.absolute) {
          nodeProvider.getNode(path.path).subscribe(_subscription, this);
        }
      }
      _closeResponse(m['rid']);
    } else {
      _closeResponse(m['rid'], error: new DsError('invalid paths'));
    }
  }
  void _unsubscribe(Map m) {
    if (m['paths'] is List) {
      int rid = m['rid'];
      for (Object str in m['paths']) {
        DsPath path = DsPath.getValidNodePath(m['str']);
        if (path != null && path.absolute) {
          nodeProvider.getNode(path.path).unsubscribe(_subscription, this);
        }
      }
      _closeResponse(m['rid']);
    } else {
      _closeResponse(m['rid'], error: new DsError('invalid paths'));
    }
  }
  void _invoke(Map m) {
    DsPath path = DsPath.getValidNodePath(m['path']);
    if (path != null && path.absolute) {
      int rid = m['rid'];
      Map params = {};
      if (m['params'] is Map) {
        (m['params'] as Map).forEach((key, value) {
          // only allow primitive types in parameters
          if (value is! List && value is! Map) {
            params[key] = value;
          }
        });
      }
      nodeProvider.getNode(path.path).invoke(params, this, addResponse(new DsResponse(this, rid)));
    } else {
      _closeResponse(m['rid'], error: new DsError('invalid path'));
    }
  }
  void _set(Map m) {
    DsPath path = DsPath.getValidPath(m['path']);
    if (path == null || path.absolute) {
      _closeResponse(m['rid'], error: new DsError('invalid path'));
      return;
    }
    if (!m.containsKey('value')) {
      _closeResponse(m['rid'], error: new DsError('missing value'));
      return;
    }
    Object value = m['value'];
    int rid = m['rid'];
    if (path.isNode) {
      nodeProvider.getNode(path.path).setValue(value, this, addResponse(new DsResponse(this, rid)));
    } else if (path.isConfig) {
      nodeProvider.getNode(path.parentPath).setConfig(path.name, value, this, addResponse(new DsResponse(this, rid)));
    } else if (path.isAttribute) {
      if (value is String) {
        nodeProvider.getNode(path.parentPath).setAttribute(path.name, value, this, addResponse(new DsResponse(this, rid)));
      } else {
        _closeResponse(m['rid'], error: new DsError('attribute value must be string'));
      }
    } else {
      // shouldn't be possible to reach here
      throw 'unexpected case';
    }
  }

  void _remove(Map m) {
    DsPath path = DsPath.getValidPath(m['path']);
    if (path == null || path.absolute) {
      _closeResponse(m['rid'], error: new DsError('invalid path'));
      return;
    }
    int rid = m['rid'];
    if (path.isNode) {
      _closeResponse(m['rid'], error: new DsError('can not remove a node'));
    } else if (path.isConfig) {
      nodeProvider.getNode(path.parentPath).removeConfig(path.name, this, addResponse(new DsResponse(this, rid)));
    } else if (path.isAttribute) {
      nodeProvider.getNode(path.parentPath).removeAttribute(path.name, this, addResponse(new DsResponse(this, rid)));
    } else {
      // shouldn't be possible to reach here
      throw 'unexpected case';
    }
  }
  
  void _close(Map m) {
    if (m['rid'] is int) {
      int rid = m['rid'];
      if (_responses.containsKey(rid)) {
        _responses[rid]._close();
        _responses.remove(rid);
      }
    }
  }
}