part of dslink.responder;

typedef LocalNode NodeFactory(String path);
typedef SimpleNode SimpleNodeFactory(String path);
typedef Future<ByteData> IconResolver(String name);

/// A simple table result.
/// This is used to return simple tables from an action.
class SimpleTableResult {
  /// Table Columns
  List columns;

  /// Table Rows
  List rows;

  SimpleTableResult([this.rows, this.columns]);
}

abstract class WaitForMe {
  Future get onLoaded;
}

/// An Asynchronous Table Result
/// This can be used to return asynchronous tables from actions.
class AsyncTableResult {
  /// Invoke Response.
  InvokeResponse response;
  /// Table Columns
  List columns;
  /// Table Rows
  List rows;
  /// Stream Status
  String status = StreamStatus.open;
  /// Table Metadata
  Map meta;
  /// Handler for when this is closed.
  OnInvokeClosed onClose;

  AsyncTableResult([this.columns]);

  /// Updates table rows to [rows].
  /// [stat] is the stream status.
  /// [meta] is the action result metadata.
  void update(List rows, [String stat, Map meta]) {
    if (this.rows == null) {
      this.rows = rows;
    } else {
      this.rows.addAll(rows);
    }
    this.meta = meta;
    if (stat != null) {
      status = stat;
    }

    if (response == null) {
      new Future(write);
    } else {
      write();
    }
  }

  /// Write this result to the result given by [resp].
  void write([InvokeResponse resp]) {
    if (resp != null) {
      if (response == null) {
        response = resp;
      } else {
        logger.warning("can not use same AsyncTableResult twice");
      }
    }

    if (response != null && (rows != null || meta != null || status == StreamStatus.closed)) {
      response.updateStream(rows, columns: columns, streamStatus: status, meta: meta);
      rows = null;
      columns = null;
    }
  }

  /// Closes this response.
  void close() {
    if (response != null) {
      response.close();
    } else {
      status = StreamStatus.closed;
    }
  }
}

/// A Live-Updating Table
class LiveTable {
  final List<TableColumn> columns;
  final List<LiveTableRow> rows;

  LiveTable.create(this.columns, this.rows);

  factory LiveTable([List<TableColumn> columns]) {
    return new LiveTable.create(columns == null ? [] : columns, []);
  }

  void onRowUpdate(LiveTableRow row) {
    if (_resp != null) {
      _resp.updateStream([row.values], meta: {
        "modify": "replace ${row.index}-${row.index}"
      });
    }
  }

  void doOnClose(Function f) {
    _onClose.add(f);
  }

  List<Function> _onClose = [];

  LiveTableRow createRow(List<dynamic> values, {bool ready: true}) {
    if (values == null) values = [];
    var row = new LiveTableRow(this, values);
    row.index = rows.length;
    rows.add(row);
    if (ready && _resp != null) {
      _resp.updateStream([row.values], meta: {
        "mode": "append"
      });
    }
    return row;
  }

  void clear() {
    rows.length = 0;
    if (_resp != null) {
      _resp.updateStream([], meta: {
        "mode": "refresh"
      }, columns: []);
    }
  }

  void refresh([int idx = -1]) {
    if (_resp != null) {
      _resp.updateStream(getCurrentState(), columns: columns.map((x) {
        return x.getData();
      }).toList(), streamStatus: StreamStatus.open, meta: {
        "mode": "refresh"
      });
    }
  }

  void reindex() {
    var i = 0;
    for (LiveTableRow row in rows) {
      row.index = i;
      i++;
    }
  }

  void override() {
    refresh();
  }

  void resend() {
    sendTo(_resp);
  }

  void sendTo(InvokeResponse resp) {
    _resp = resp;

    _resp.onClose = (r) {
      close(true);
    };

    if (autoStartSend) {
      resp.updateStream(getCurrentState(), columns: columns.map((x) {
        return x.getData();
      }).toList(), streamStatus: StreamStatus.open, meta: {
        "mode": "refresh"
      });
    }
  }

  void close([bool isFromRequester = false]) {
    while (_onClose.isNotEmpty) {
      _onClose.removeAt(0)();
    }

    if (!isFromRequester) {
      _resp.close();
    }
  }

  List getCurrentState([int from = -1]) {
    List<LiveTableRow> rw = rows;
    if (from != -1) {
      rw = rw.sublist(from);
    }
    return rw.map((x) => x.values).toList();
  }

  InvokeResponse get response => _resp;
  InvokeResponse _resp;

  bool autoStartSend = true;
}

class LiveTableRow {
  final LiveTable table;
  final List<dynamic> values;

  int index = -1;

  LiveTableRow(this.table, this.values);

  void setValue(int idx, value) {
    if (idx > values.length - 1) {
      values.length += 1;
    }
    values[idx] = value;
    table.onRowUpdate(this);
  }

  void delete() {
    table.rows.remove(this);
    var idx = index;
    table.refresh(idx);
    table.reindex();
  }
}

/// Interface for node providers that are serializable.
abstract class SerializableNodeProvider {
  /// Initialize the node provider.
  void init([Map<String, dynamic> m, Map<String, NodeFactory> profiles]);

  /// Save the node provider to a map.
  Map save();

  /// Persist the node provider.
  void persist([bool now = false]);
}

/// Interface for node providers that are mutable.
abstract class MutableNodeProvider {
  /// Updates the value of the node at [path] to the given [value].
  void updateValue(String path, Object value);
  /// Adds a node at the given [path] that is initialized with the given data in [m].
  LocalNode addNode(String path, Map m);
  /// Removes the node specified at [path].
  void removeNode(String path);
  // Add a profile to the node provider.
  void addProfile(String name, NodeFactory factory);
}

class SysGetIconNode extends SimpleNode {
  SysGetIconNode(String path, [SimpleNodeProvider provider]) : super(
    path,
    provider
  ) {
    configs.addAll({
      r"$invokable": "read",
      r"$params": [
        {
          "name": "Icon",
          "type": "string"
        }
      ],
      r"$columns": [
        {
          "name": "Data",
          "type": "binary"
        }
      ],
      r"$result": "table"
    });
  }

  @override
  onInvoke(Map<String, dynamic> params) async {
    String name = params["Icon"];
    IconResolver resolver = provider._iconResolver;

    ByteData data = await resolver(name);

    return [[
      data
    ]];
  }
}

class SimpleNodeProvider extends NodeProviderImpl
    implements SerializableNodeProvider, MutableNodeProvider {
  /// Global instance.
  /// This is by default always the first instance of [SimpleNodeProvider].
  static SimpleNodeProvider instance;

  ExecutableFunction _persist;
  IconResolver _iconResolver;

  /// All the nodes in this node provider.
  final Map<String, LocalNode> nodes = new Map<String, LocalNode>();

  List<SimpleNodeFactory> _resolverFactories = [];

  @override
  LocalNode getNode(String path) {
    return _getNode(path);
  }

  void setIconResolver(IconResolver resolver) {
    _iconResolver = resolver;

    nodes["/sys/getIcon"] = new SysGetIconNode("/sys/getIcon", this);
  }

  LocalNode _getNode(String path, {bool allowStubs: false}) {
    if (nodes.containsKey(path)) {
      SimpleNode node = nodes[path];
      if (allowStubs || node._stub == false) {
        return node;
      }
    }

    if (_resolverFactories.isNotEmpty) {
      for (var f in _resolverFactories) {
        var node = f(path);
        if (node != null) {
          return node;
        }
      }
    }

    return null;
  }

  /// Gets a node at the given [path] if it exists.
  /// If it does not exist, create a new node and return it.
  ///
  /// When [addToTree] is false, the node will not be inserted into the node provider.
  /// When [init] is false, onCreated() is not called.
  LocalNode getOrCreateNode(String path, [bool addToTree = true, bool init = true]) {
    LocalNode node = _getNode(path, allowStubs: true);

    if (node != null) {
      if (addToTree) {
        Path po = new Path(path);
        if (!po.isRoot) {
          LocalNode parent = getNode(po.parentPath);

          if (parent != null && !parent.children.containsKey(po.name)) {
            parent.addChild(po.name, node);
            parent.listChangeController.add(po.name);
            node.listChangeController.add(r"$is");
          }
        }

        if (node is SimpleNode) {
          node._stub = false;
        }
      }

      return node;
    }

    if (addToTree) {
      return createNode(path, init);
    } else {
      node = new SimpleNode(path, this)
        .._stub = true;
      nodes[path] = node;
      return node;
    }
  }

  /// Checks if this provider has the node at [path].
  bool hasNode(String path) {
    SimpleNode node = nodes[path];

    if (node == null) {
      return false;
    }

    if (node.isStubNode == true) {
      return false;
    }

    return true;
  }

  void registerResolver(SimpleNodeFactory factory) {
    if (!_resolverFactories.contains(factory)) {
      _resolverFactories.add(factory);
    }
  }

  void unregisterResolver(SimpleNodeFactory factory) {
    _resolverFactories.remove(factory);
  }

  @override
  void addProfile(String name, NodeFactory factory) {
    _profiles[name] = factory;
  }

  /// Sets the function that persists the nodes.
  void setPersistFunction(ExecutableFunction doPersist) {
    _persist = doPersist;
  }

  /// Persist the nodes in this provider.
  /// If you are not using a LinkProvider, then call [setPersistFunction] to set
  /// the function that is called to persist.
  void persist([bool now = false]) {
    if (now) {
      if (_persist == null) {
        return;
      }

      _persist();
    } else {
      new Future.delayed(const Duration(seconds: 5), () {
        if (_persist == null) {
          return;
        }

        _persist();
      });
    }
  }

  /// Creates a node at [path].
  /// If a node already exists at this path, an exception is thrown.
  /// If [init] is false, onCreated() is not called.
  SimpleNode createNode(String path, [bool init = true]) {
    Path p = new Path(path);
    LocalNode existing = nodes[path];

    if (existing != null) {
      if (existing is SimpleNode) {
        if (existing._stub != true) {
          throw new Exception("Node at ${path} already exists.");
        } else {
          existing._stub = false;
        }
      } else {
        throw new Exception("Node at ${path} already exists.");
      }
    }

    SimpleNode node = existing == null ? new SimpleNode(path, this) : existing;
    nodes[path] = node;

    if (init) {
      node.onCreated();
    }

    SimpleNode pnode;

    if (p.parentPath != "") {
      pnode = getNode(p.parentPath);
    }

    if (pnode != null) {
      pnode.children[p.name] = node;
      pnode.onChildAdded(p.name, node);
      pnode.updateList(p.name);
    }

    return node;
  }

  /// Creates a [SimpleNodeProvider].
  /// If [m] and optionally [profiles] is specified,
  /// the provider is initialized with these values.
  SimpleNodeProvider([Map<String, dynamic> m, Map<String, NodeFactory> profiles]) {
    // by default, the first SimpleNodeProvider is the static instance
    if (instance == null) {
       instance = this;
    }

    root = new SimpleNode("/", this);
    nodes["/"] = root;
    defs = new SimpleHiddenNode('/defs', this);
    nodes[defs.path] = defs;
    sys = new SimpleHiddenNode('/sys', this);
    nodes[sys.path] = sys;

    init(m, profiles);
  }

  /// Root node
  SimpleNode root;

  /// defs node
  SimpleHiddenNode defs;

  /// sys node
  SimpleHiddenNode sys;

  @override
  void init([Map<String, dynamic> m, Map<String, NodeFactory> profiles]) {
    if (profiles != null) {
      if (profiles.isNotEmpty) {
        _profiles.addAll(profiles);
      } else {
        _profiles = profiles;
      }
    }

    if (m != null) {
      root.load(m);
    }
  }

  Map<String, NodeFactory> get profileMap => _profiles;

  @override
  Map save() {
    return root.save();
  }

  @override
  void updateValue(String path, Object value) {
    SimpleNode node = getNode(path);
    node.updateValue(value);
  }

  /// Sets the given [node] to the given [path].
  void setNode(String path, SimpleNode node, {bool registerChildren: false}) {
    if (path == '/' || !path.startsWith('/')) return null;
    Path p = new Path(path);
    SimpleNode pnode = getNode(p.parentPath);

    nodes[path] = node;

    node.onCreated();

    if (pnode != null) {
      pnode.children[p.name] = node;
      pnode.onChildAdded(p.name, node);
      pnode.updateList(p.name);
    }

    if (registerChildren) {
      for (SimpleNode c in node.children.values) {
        setNode(c.path, c);
      }
    }
  }

  @override
  SimpleNode addNode(String path, Map m) {
    if (path == '/' || !path.startsWith('/')) return null;

    Path p = new Path(path);
    SimpleNode oldNode = _getNode(path, allowStubs: true);

    SimpleNode pnode = getNode(p.parentPath);
    SimpleNode node;

    if (pnode != null) {
      node = pnode.onLoadChild(p.name, m, this);
    }

    if (node == null) {
      String profile = m[r'$is'];
      if (_profiles.containsKey(profile)) {
        node = _profiles[profile](path);
      } else {
        node = getOrCreateNode(path, true, false);
      }
    }

    if (oldNode != null) {
      logger.fine("Found old node for ${path}: Copying subscriptions.");

      for (ValueUpdateCallback func in oldNode.callbacks.keys) {
        node.subscribe(func, oldNode.callbacks[func]);
      }

      if (node is SimpleNode) {
        try {
          node._listChangeController = oldNode._listChangeController;
          node._listChangeController.onStartListen = () {
            node.onStartListListen();
          };
          node._listChangeController.onAllCancel = () {
            node.onAllListCancel();
          };
        } catch (e) {}

        if (node._hasListListener) {
          node.onStartListListen();
        }
      }
    }

    nodes[path] = node;
    node.load(m);
    node.onCreated();

    if (pnode != null) {
      pnode.addChild(p.name, node);
      pnode.onChildAdded(p.name, node);
      pnode.updateList(p.name);
    }

    node.updateList(r"$is");

    if (oldNode != null) {
      oldNode.updateList(r"$is");
    }

    return node;
  }

  @override
  void removeNode(String path, {bool recurse: true}) {
    if (path == '/' || !path.startsWith('/')) return;
    SimpleNode node = getNode(path);

    if (node == null) {
      return;
    }

    if (recurse) {
      String base = path;
      if (!base.endsWith("/")) {
        base += "/";
      }

      int baseSlashFreq = countCharacterFrequency(base, "/");

      List<String> targets = nodes.keys.where((String x) {
        return x.startsWith(base) &&
          baseSlashFreq == countCharacterFrequency(x, "/");
      }).toList();

      for (String target in targets) {
        removeNode(target);
      }
    }

    Path p = new Path(path);
    SimpleNode pnode = getNode(p.parentPath);
    node.onRemoving();
    node.removed = true;

    if (pnode != null) {
      pnode.children.remove(p.name);
      pnode.onChildRemoved(p.name, node);
      pnode.updateList(p.name);
    }

    if (node.callbacks.isEmpty && !node._hasListListener) {
      nodes.remove(path);
    } else {
      node._stub = true;
    }
  }

  Map<String, NodeFactory> _profiles = new Map<String, NodeFactory>();

  /// Permissions
  IPermissionManager permissions = new DummyPermissionManager();

  /// Creates a responder with the given [dsId].
  Responder createResponder(String dsId, String sessionId) {
    return new Responder(this, dsId);
  }

  @override
  String toString({bool showInstances: false}) {
    var buff = new StringBuffer();

    void doNode(LocalNode node, [int depth = 0]) {
      Path p = new Path(node.path);
      buff.write("${'  ' * depth}- ${p.name}");

      if (showInstances) {
        buff.write(": ${node}");
      }

      buff.writeln();
      for (var child in node.children.values) {
        doNode(child, depth + 1);
      }
    }

    doNode(root);
    return buff.toString().trim();
  }
}

/// A Simple Node Implementation
/// A flexible node implementation that should fit most use cases.
class SimpleNode extends LocalNodeImpl {
  final SimpleNodeProvider provider;

  static  AESFastEngine _encryptEngine;
  static  KeyParameter _encryptParams;
  static initEncryption(String key) {
    _encryptEngine = new AESFastEngine();
    _encryptParams = new KeyParameter(UTF8.encode(key).sublist(48,80));
  }
  
  /// encrypt the string and prefix the value with '\u001Bpw:'
  /// so it's compatible with old plain text password
  static String encryptString(String str) {
    if (str == '') {
      return '';
    }
    _encryptEngine.reset();
    _encryptEngine.init(true, _encryptParams);

    Uint8List utf8bytes = UTF8.encode(str);
    Uint8List block = new Uint8List((utf8bytes.length + 31 )~/32 * 32);
    block.setRange(0, utf8bytes.length, utf8bytes);
    return '\u001Bpw:${Base64.encode(_encryptEngine.process(block))}';
  }
  static String decryptString(String str) {
    if (str.startsWith('\u001Bpw:')) {
      _encryptEngine.reset();
      _encryptEngine.init(false, _encryptParams);
      String rslt = UTF8.decode(_encryptEngine.process(Base64.decode(str.substring(4))));
      int pos = rslt.indexOf('\u0000');
      if (pos >= 0) rslt = rslt.substring(0, pos);
      return rslt;
    } else if (str.length == 22) {
      // a workaround for the broken password database, need to be removed later
      // 22 is the length of a AES block after base64 encoding
      // encoded password should always be 24 or more bytes, and a plain 22 bytes password is rare
      try{
        _encryptEngine.reset();
         _encryptEngine.init(false, _encryptParams);
         String rslt = UTF8.decode(_encryptEngine.process(Base64.decode(str)));
         int pos = rslt.indexOf('\u0000');
         if (pos >= 0) rslt = rslt.substring(0, pos);
         return rslt;
      } catch(err) {
        return str;
      }
    } else {
      return str;
    }
  }
  
  bool _stub = false;

  /// Is this node a stub node?
  /// Stub nodes are nodes which are stored in the tree, but are not actually
  /// part of their parent.
  bool get isStubNode => _stub;

  SimpleNode(String path, [SimpleNodeProvider nodeprovider]) :
    provider = nodeprovider == null ? SimpleNodeProvider.instance : nodeprovider,
      super(path);

  /// Marks a node as being removed.
  bool removed = false;

  /// Marks this node as being serializable.
  /// If true, this node can be serialized into a JSON file and then loaded back.
  /// If false, this node can't be serialized into a JSON file.
  bool serializable = true;

  /// Load this node from the provided map as [m].
  void load(Map m) {
    if (_loaded) {
      configs.clear();
      attributes.clear();
      children.clear();
    }
    String childPathPre;
    if (path == '/') {
      childPathPre = '/';
    } else {
      childPathPre = '$path/';
    }

    m.forEach((/*String*/ key, value) {
      if (key.startsWith('?')) {
        if (key == '?value') {
          updateValue(value);
        }
      } else if (key.startsWith(r'$')) {
        if (_encryptEngine != null && key.startsWith(r'$$') && value is String) {
          configs[key] = decryptString(value);
        } else {
          configs[key] = value;
        }
       
      } else if (key.startsWith('@')) {
        attributes[key] = value;
      } else if (value is Map) {
        String childPath = '$childPathPre$key';
        provider.addNode(childPath, value);
      }
    });
    _loaded = true;
  }

  /// Save this node into a map.
  Map save() {
    Map rslt = {};
    configs.forEach((str, val) {
      if (_encryptEngine != null && val is String && str.startsWith(r'$$') && str.endsWith('password')) {
        rslt[str] = encryptString(val);
      } else {
        rslt[str] = val;
      }
    });

    attributes.forEach((str, val) {
      rslt[str] = val;
    });

    if (_lastValueUpdate != null && _lastValueUpdate.value != null) {
      rslt['?value'] = _lastValueUpdate.value;
    }

    children.forEach((str, Node node) {
      if (node is SimpleNode && node.serializable == true) {
        rslt[str] = node.save();
      }
    });

    return rslt;
  }

  /// Handles the invoke method from the internals of the responder.
  /// Use [onInvoke] to handle when a node is invoked.
  InvokeResponse invoke(
    Map<String, dynamic> params,
    Responder responder,
    InvokeResponse response,
    Node parentNode,
      [int maxPermission = Permission.CONFIG]) {
    Object rslt;
    try {
      rslt = onInvoke(params);
    } catch (e, stack) {
      var error = new DSError("invokeException", msg: e.toString());
      try {
        error.detail = stack.toString();
      } catch (e) {}
      response.close(error);
      return response;
    }

    var rtype = "values";
    if (configs.containsKey(r"$result")) {
      rtype = configs[r"$result"];
    }

    if (rslt == null) {
      // Create a default result based on the result type
      if (rtype == "values") {
        rslt = {};
      } else if (rtype == "table") {
        rslt = [];
      } else if (rtype == "stream") {
        rslt = [];
      }
    }
    if (rslt is Iterable) {
      response.updateStream(rslt.toList(), streamStatus: StreamStatus.closed);
    } else if (rslt is Map) {
      var columns = [];
      var out = [];
      for (var x in rslt.keys) {
        columns.add({
          "name": x,
          "type": "dynamic"
        });
        out.add(rslt[x]);
      }

      response.updateStream(
        [out],
        columns: columns,
        streamStatus: StreamStatus.closed
      );
    } else if (rslt is SimpleTableResult) {
      response.updateStream(rslt.rows,
          columns: rslt.columns, streamStatus: StreamStatus.closed);
    } else if (rslt is DSError) {
      response.close(rslt);
    } else if (rslt is AsyncTableResult) {
      (rslt as AsyncTableResult).write(response);
      response.onClose = (var response) {
        if ((rslt as AsyncTableResult).onClose != null) {
          (rslt as AsyncTableResult).onClose(response);
        }
      };
      return response;
    } else if (rslt is Table) {
      response.updateStream(rslt.rows,
          columns: rslt.columns, streamStatus: StreamStatus.closed);
    } else if (rslt is Stream) {
      var r = new AsyncTableResult();

      response.onClose = (var response) {
        if (r.onClose != null) {
          r.onClose(response);
        }
      };

      Stream stream = rslt;

      if (rtype == "stream") {
        StreamSubscription sub;

        r.onClose = (_) {
          if (sub != null) {
            sub.cancel();
          }
        };

        sub = stream.listen((v) {
          if (v is TableMetadata) {
            r.meta = v.meta;
            return;
          } else if (v is TableColumns) {
            r.columns = v.columns.map((x) => x.getData()).toList();
            return;
          }

          if (v is Iterable) {
            r.update(v.toList(), StreamStatus.open);
          } else if (v is Map) {
            var meta;
            if (v.containsKey("__META__")) {
              meta = v["__META__"];
            }
            r.update([v], StreamStatus.open, meta);
          } else {
            throw new Exception("Unknown Value from Stream");
          }
        }, onDone: () {
          r.close();
        }, onError: (e, stack) {
          var error = new DSError("invokeException", msg: e.toString());
          try {
            error.detail = stack.toString();
          } catch (e) {}
          response.close(error);
        }, cancelOnError: true);
        r.write(response);
        return response;
      } else {
        var list = [];
        StreamSubscription sub;

        r.onClose = (_) {
          if (sub != null) {
            sub.cancel();
          }
        };

        sub = stream.listen((v) {
          if (v is TableMetadata) {
            r.meta = v.meta;
            return;
          } else if (v is TableColumns) {
            r.columns = v.columns.map((x) => x.getData()).toList();
            return;
          }

          if (v is Iterable) {
            list.addAll(v);
          } else if (v is Map) {
            list.add(v);
          } else {
            throw new Exception("Unknown Value from Stream");
          }
        }, onDone: () {
          r.update(list);
          r.close();
        }, onError: (e, stack) {
          var error = new DSError("invokeException", msg: e.toString());
          try {
            error.detail = stack.toString();
          } catch (e) {}
          response.close(error);
        }, cancelOnError: true);
      }
      r.write(response);
      return response;
    } else if (rslt is Future) {
      var r = new AsyncTableResult();

      response.onClose = (var response) {
        if (r.onClose != null) {
          r.onClose(response);
        }
      };

      rslt.then((value) {
        if (value is DSError) {
          response.close(value);
        } else if (value is LiveTable) {
          r = null;
          value.sendTo(response);
        } else if (value is Stream) {
          Stream stream = value;
          StreamSubscription sub;

          r.onClose = (_) {
            if (sub != null) {
              sub.cancel();
            }
          };

          sub = stream.listen((v) {
            if (v is TableMetadata) {
              r.meta = v.meta;
              return;
            } else if (v is TableColumns) {
              r.columns = v.columns.map((x) => x.getData()).toList();
              return;
            }

            if (v is Iterable) {
              r.update(v.toList());
            } else if (v is Map) {
              var meta;
              if (v.containsKey("__META__")) {
                meta = v["__META__"];
              }
              r.update([v], StreamStatus.open, meta);
            } else {
              throw new Exception("Unknown Value from Stream");
            }
          }, onDone: () {
            r.close();
          }, onError: (e, stack) {
            var error = new DSError("invokeException", msg: e.toString());
            try {
              error.detail = stack.toString();
            } catch (e) {}
            response.close(error);
          }, cancelOnError: true);
        } else if (value is Table) {
          Table table = value;
          r.columns = table.columns.map((x) => x.getData()).toList();
          r.update(table.rows, StreamStatus.closed, table.meta);
          r.close();
        } else {
          r.update(value is Iterable ? value.toList() : [value]);
          r.close();
        }
      }).catchError((e, stack) {
        var error = new DSError("invokeException", msg: e.toString());
        try {
          error.detail = stack.toString();
        } catch (e) {}
        response.close(error);
      });
      r.write(response);
      return response;
    } else if (rslt is LiveTable) {
      rslt.sendTo(response);
    } else {
      response.close();
    }

    return response;
  }

  /// This is called when this node is invoked.
  /// You can return the following types from this method:
  /// - [Iterable]
  /// - [Map]
  /// - [Table]
  /// - [Stream]
  /// - [SimpleTableResult]
  /// - [AsyncTableResult]
  ///
  /// You can also return a future that resolves to one (like if the method is async) of the following types:
  /// - [Stream]
  /// - [Iterable]
  /// - [Map]
  /// - [Table]
  dynamic onInvoke(Map<String, dynamic> params) {
    return null;
  }

  /// Gets the parent node of this node.
  SimpleNode get parent => provider.getNode(new Path(path).parentPath);

  /// Callback used to accept or reject a value when it is set.
  /// Return true to reject the value, and false to accept it.
  bool onSetValue(Object val) => false;

  /// Callback used to accept or reject a value of a config when it is set.
  /// Return true to reject the value, and false to accept it.
  bool onSetConfig(String name, Object value) => false;

  /// Callback used to accept or reject a value of an attribute when it is set.
  /// Return true to reject the value, and false to accept it.
  bool onSetAttribute(String name, Object value) => false;

  // Callback used to notify a node that it is being subscribed to.
  void onSubscribe() {}

  // Callback used to notify a node that a subscribe has unsubscribed.
  void onUnsubscribe() {}

  /// Callback used to notify a node that it was created.
  /// This is called after a node is deserialized as well.
  void onCreated() {}

  /// Callback used to notify a node that it is about to be removed.
  void onRemoving() {}

  /// Callback used to notify a node that one of it's children has been removed.
  void onChildRemoved(String name, Node node) {}

  /// Callback used to notify a node that a child has been added to it.
  void onChildAdded(String name, Node node) {}

  @override
  RespSubscribeListener subscribe(ValueUpdateCallback callback, [int qos = 0]) {
    onSubscribe();
    return super.subscribe(callback, qos);
  }

  @override
  void unsubscribe(ValueUpdateCallback callback) {
    onUnsubscribe();
    super.unsubscribe(callback);
  }

  /// Callback to override how a child of this node is loaded.
  /// If this method returns null, the default strategy is used.
  SimpleNode onLoadChild(String name, Map data, SimpleNodeProvider provider) {
    return null;
  }

  /// Creates a child with the given [name].
  /// If [m] is specified, the node is loaded with that map.
  SimpleNode createChild(String name, [Map m]) {
    var tp = new Path(path).child(name).path;
    return provider.addNode(tp, m == null ? {} : m);
  }

  /// Gets the name of this node.
  /// This is the last component of this node's path.
  String get name => new Path(path).name;

  /// Gets the current display name of this node.
  /// This is the $name config. If it does not exist, then null is returned.
  String get displayName => configs[r"$name"];

  /// Sets the display name of this node.
  /// This is the $name config. If this is set to null, then the display name is removed.
  set displayName(String value) {
    if (value == null) {
      configs.remove(r"$name");
    } else {
      configs[r"$name"] = value;
    }

    updateList(r"$name");
  }

  /// Gets the current value type of this node.
  /// This is the $type config. If it does not exist, then null is returned.
  String get type => configs[r"$type"];

  /// Sets the value type of this node.
  /// This is the $type config. If this is set to null, then the value type is removed.
  set type(String value) {
    if (value == null) {
      configs.remove(r"$type");
    } else {
      configs[r"$type"] = value;
    }

    updateList(r"$type");
  }

  /// Gets the current value of the $writable config.
  /// If it does not exist, then null is returned.
  String get writable => configs[r"$writable"];

  /// Sets the value of the writable config.
  /// If this is set to null, then the writable config is removed.
  set writable(value) {
    if (value == null) {
      configs.remove(r"$writable");
    } else if (value is bool) {
      if (value) {
        configs[r"$writable"] = "write";
      } else {
        configs.remove(r"$writable");
      }
    } else {
      configs[r"$writable"] = value.toString();
    }

    updateList(r"$writable");
  }

  /// Checks if this node has the specified config.
  bool hasConfig(String name) => configs.containsKey(
      name.startsWith(r"$") ? name : '\$' + name
  );

  /// Checks if this node has the specified attribute.
  bool hasAttribute(String name) => attributes.containsKey(
      name.startsWith("@") ? name : '@' + name
  );

  /// Remove this node from it's parent.
  void remove() {
    provider.removeNode(path);
  }

  /// Add this node to the given node.
  /// If [input] is a String, it is interpreted as a node path and resolved to a node.
  /// If [input] is a [SimpleNode], it will be attached to that.
  void attach(input, {String name}) {
    if (name == null) {
      name = this.name;
    }

    if (input is String) {
      provider.getNode(input).addChild(name, this);
    } else if (input is SimpleNode) {
      input.addChild(name, this);
    } else {
      throw "Invalid Input";
    }
  }

  /// Adds the given [node] as a child of this node with the given [name].
  void addChild(String name, Node node) {
    super.addChild(name, node);
    updateList(name);
  }

  /// Removes a child from this node.
  /// If [input] is a String, a child named with the specified [input] is removed.
  /// If [input] is a Node, the child that owns that node is removed.
  /// The name of the removed node is returned.
  String removeChild(dynamic input) {
    String name = super.removeChild(input);
    if (name != null) {
      updateList(name);
    }
    return name;
  }

  Response setAttribute(
      String name, Object value, Responder responder, Response response) {
    if (onSetAttribute(name, value) != true) {
      // when callback returns true, value is rejected
      super.setAttribute(name, value, responder, response);
    }
    return response;
  }

  Response setConfig(
      String name, Object value, Responder responder, Response response) {
    if (onSetConfig(name, value) != true) {
      // when callback returns true, value is rejected
      super.setConfig(name, value, responder, response);
    }
    return response;
  }

  Response setValue(Object value, Responder responder, Response response,
      [int maxPermission = Permission.CONFIG]) {
    if (onSetValue(value) !=  true)
      // when callback returns true, value is rejected
      super.setValue(value, responder, response, maxPermission);
    return response;
  }

  operator [](String name) => get(name);

  operator []=(String name, value) {
    if (name.startsWith(r"$") || name.startsWith(r"@")) {
      if (name.startsWith(r"$")) {
        configs[name] = value;
      } else {
        attributes[name] = value;
      }
    } else {
      if (value == null) {
          removeChild(name);
        return;
      } else if (value is Map) {
          createChild(name, value);
        return;
      } else {
        addChild(name, value);
        return;// value;
      }
    }
  }
}

/// A hidden node.
class SimpleHiddenNode extends SimpleNode {
  SimpleHiddenNode(String path, SimpleNodeProvider provider) : super(path, provider) {
    configs[r'$hidden'] = true;
  }

  @override
  Map<String, dynamic> getSimpleMap() {
    var rslt = <String, dynamic>{
      r'$hidden': true
    };

    if (configs.containsKey(r'$is')) {
      rslt[r'$is'] = configs[r'$is'];
    }

    if (configs.containsKey(r'$type')) {
      rslt[r'$type'] = configs[r'$type'];
    }

    if (configs.containsKey(r'$name')) {
      rslt[r'$name'] = configs[r'$name'];
    }

    if (configs.containsKey(r'$invokable')) {
      rslt[r'$invokable'] = configs[r'$invokable'];
    }

    if (configs.containsKey(r'$writable')) {
      rslt[r'$writable'] = configs[r'$writable'];
    }
    return rslt;
  }
}
