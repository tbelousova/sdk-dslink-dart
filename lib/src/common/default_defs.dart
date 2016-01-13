part of dslink.common;

Map defaultProfileMap = {
  "node": {},
  "static": {},
  "getHistory": {
    r"$invokable": "read",
    r"$result": "table",
    r"$params": [
      {"name": "Timerange", "type": "string", "editor": "daterange"},
      {
        "name": "Interval",
        "type": "enum",
        "editor": buildEnumType([
          "default",
          "none",
          "1Y",
          "3N",
          "1N",
          "1W",
          "1D",
          "12H",
          "6H",
          "4H",
          "3H",
          "2H",
          "1H",
          "30M",
          "15M",
          "10M",
          "5M",
          "1M",
          "30S",
          "15S",
          "10S",
          "5S",
          "1S"
        ])
      },
      {
        "name": "Rollup",
        "type": buildEnumType([
          "avg",
          "min",
          "max",
          "sum",
          "first",
          "last",
          "and",
          "or",
          "count",
          "auto"
        ])
      }
    ],
    r"$columns": [
      {"name": "timestamp", "type": "time"},
      {"name": "value", "type": "dynamic"}
    ]
  },
  "broker": {
    "userNode": {
      "addChild": {
        r"$invokable": "config",
        r"$params": [
          {"name": "Name", "type": "string"}
        ]
      },
      "addLink": {
        r"$invokable": "config",
        r"$params": [
          {"name": "Name", "type": "string"},
          {"name": "Id", "type": "string"}
        ]
      },
      "remove": {r"$invokable": "config"}
    },
    "userRoot": {
      "addChild": {
        r"$invokable": "config",
        r"$params": [
          {"name": "Name", "type": "string"}
        ]
      },
      "addLink": {
        r"$invokable": "config",
        r"$params": [
          {"name": "Name", "type": "string"},
          {"name": "Id", "type": "string"}
        ]
      }
    },
    "dataNode": {
      "addNode": {
        r"$invokable": "write",
        r"$params": [
          {"name": "Name", "type": "string"}
        ]
      },
      "addValue": {
        r"$invokable": "write",
        r"$params": [
          {"name": "Name", "type": "string"},
          {
            "name": "Type",
            "type": "enum[string,number,bool,array,map,binary,dynamic]"
          },
          {
            "name": "Editor",
            "type": "enum[none,textarea,password,daterange,date]"
          }
        ]
      },
      "deleteNode": {
        r"$invokable": "write",
        r"$params": [
          {"name": "Recursive", "type": "bool"}
        ]
      },
      "renameNode": {
        r"$invokable": "write",
        r"$params": [
          {"name": "Name", "type": "string"}
        ]
      },
      "duplicateNode": {
        r"$invokable": "write",
        r"$params": [
          {"name": "Name", "type": "string"}
        ]
      },
    },
    "dataRoot": {
      "addNode": {
        r"$invokable": "write",
        r"$params": [
          {"name": "Name", "type": "string"}
        ]
      },
      "addValue": {
        r"$invokable": "write",
        r"$params": [
          {"name": "Name", "type": "string"},
          {
            "name": "Type",
            "type": "enum[string,number,bool,array,map,binary,dynamic]"
          },
          {
            "name": "Editor",
            "type": "enum[none,textarea,password,daterange,date]"
          }
        ]
      },
      "publish": {
        r"$invokable": "write",
        r"$params": [
          {"name": "Path", "type": "string"},
          {"name": "Value", "type": "dynamic"}
        ]
      }
    },
    "token": {
      "delete": {r"$invokable": "config", r"$params": []}
    },
    "tokenGroup": {
      "add": {
        r"$invokable": "config",
        r"$params": [
          {"name": "TimeRange", "type": "string", "editor": "daterange"},
          {
            "name": "Count",
            "type": "number",
            "description": "how many times this token can be used"
          },
          {
            "name": "Managed",
            "type": "bool",
            "description":
                "when a managed token is deleted, server will delete all the dslinks associated with the token"
          },
        ],
        r"$columns": [
          {"name": "tokenName", "type": "string"}
        ]
      }
    }
  }
};
