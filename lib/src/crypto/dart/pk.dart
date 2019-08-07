library dslink.pk.dart;

import "dart:async";
import "dart:convert";
import "dart:typed_data";
import "dart:math" as Math;
//FIXME:Dart1.0
//*Dart1-open-block
import "dart:collection";
import "dart:isolate";
//Dart1-close-block*/

//FIXME:Dart2.0
/*Dart2-open-block
import "package:pointycastle/ecc/ecc_fp.dart" as fp;
import "package:pointycastle/export.dart" hide PublicKey, PrivateKey;
Dart2-close-block*/

import 'package:dslink/convert_consts.dart';


//FIXME:Dart1.0
//*Dart1-open-block
import "package:dscipher/cipher.dart" hide PublicKey, PrivateKey;
import "package:dscipher/digests/sha256.dart";
import "package:dscipher/key_generators/ec_key_generator.dart";
import "package:dscipher/params/key_generators/ec_key_generator_parameters.dart";
import "package:dscipher/random/secure_random_base.dart";
import "package:dscipher/random/block_ctr_random.dart";
import "package:dscipher/block/aes_fast.dart";

import "package:dscipher/ecc/ecc_base.dart";
import "package:dscipher/ecc/ecc_fp.dart" as fp;
//Dart1-close-block*/


import "../pk.dart";
import "../../../utils.dart";

//FIXME:Dart1.0
//*Dart1-open-block
part "isolate.dart";
//Dart1-close-block*/

/// hard code the EC curve data here, so the compiler don"t have to register all curves
ECDomainParameters __secp256r1;
ECDomainParameters get _secp256r1 {
  if (__secp256r1 != null) {
    return __secp256r1;
  }

  var q = newBigInteger(
    "ffffffff00000001000000000000000000000000ffffffffffffffffffffffff", 16);
  var a = newBigInteger(
    "ffffffff00000001000000000000000000000000fffffffffffffffffffffffc", 16);
  var b = newBigInteger(
    "5ac635d8aa3a93e7b3ebbd55769886bc651d06b0cc53b0f63bce3c3e27d2604b", 16);
  var g = newBigInteger(
    "046b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c2964fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5",
    16);
  var n = newBigInteger(
    "ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551", 16);
  var h = newBigInteger("1", 16);
  var seed =
  newBigInteger("c49d360886e704936a6678e1139d26b7819f7e90", 16);
  var seedBytes =  bigIntegerToByteArray(seed);

  var curve = new fp.ECCurve(q, a, b);
  return new ECDomainParametersImpl(
    "secp256r1",
    curve,
    curve.decodePoint(bigIntegerToByteArray(g)),
    n,
    h,
    seedBytes
  );
}

class DartCryptoProvider implements CryptoProvider {
  static final DartCryptoProvider INSTANCE = new DartCryptoProvider();
  final DSRandomImpl random = new DSRandomImpl();

  ECPrivateKey _cachedPrivate;
  ECPublicKey _cachedPublic;
  int _cachedTime = -1;

  Future<ECDH> assign(PublicKey publicKeyRemote, ECDH old) async {
    //FIXME:Dart1.0
    //*Dart1-open-block
    if (ECDHIsolate.running) {
      if (old is ECDHImpl) {
        return ECDHIsolate._sendRequest(
            publicKeyRemote,
            /*old._ecPrivateKey.d.toRadix(16))*/
            bigIntegerToRadix(old._ecPrivateKey.d, 16));
      } else {
        return ECDHIsolate._sendRequest(publicKeyRemote, null);
      }
    }
    //Dart1-close-block*/
    int ts = (new DateTime.now()).millisecondsSinceEpoch;

    /// reuse same ECDH server pair for up to 1 minute
    if (_cachedPrivate == null ||
        ts - _cachedTime > 60000 ||
        (old is ECDHImpl && old._ecPrivateKey == _cachedPrivate)) {
      var gen = new ECKeyGenerator();
      var rsapars = new ECKeyGeneratorParameters(_secp256r1);
      var params = new ParametersWithRandom(rsapars, random);
      gen.init(params);
      var pair = gen.generateKeyPair();
      _cachedPrivate = pair.privateKey;
      _cachedPublic = pair.publicKey;
      _cachedTime = ts;
    }

    PublicKeyImpl publicKeyRemoteImpl;

    if (publicKeyRemote is! PublicKeyImpl) {
      throw "Not a PublicKeyImpl: ${publicKeyRemoteImpl}";
    } else {
      publicKeyRemoteImpl = publicKeyRemote;
    }

    var Q2 = publicKeyRemoteImpl.ecPublicKey.Q * _cachedPrivate.d;
    return new ECDHImpl(_cachedPrivate, _cachedPublic, Q2);
  }

  Future<ECDH> getSecret(PublicKey publicKeyRemote) async {
    //FIXME:Dart1.0
    //*Dart1-open-block
    if (ECDHIsolate.running) {
      return ECDHIsolate._sendRequest(publicKeyRemote, "");
    }
    //Dart1-close-block*/
    var gen = new ECKeyGenerator();
    var rsapars = new ECKeyGeneratorParameters(_secp256r1);
    var params = new ParametersWithRandom(rsapars, random);
    gen.init(params);
    var pair = gen.generateKeyPair()
      as AsymmetricKeyPair<ECPublicKey, ECPrivateKey>;

    PublicKeyImpl publicKeyRemoteImpl;

    if (publicKeyRemote is! PublicKeyImpl) {
      throw "Not a PublicKeyImpl: ${publicKeyRemoteImpl}";
    } else {
      publicKeyRemoteImpl = publicKeyRemote;
    }

    var Q2 = publicKeyRemoteImpl.ecPublicKey.Q * pair.privateKey.d;
    return new ECDHImpl(pair.privateKey, pair.publicKey, Q2);
  }

  Future<PrivateKey> generate() async {
    return generateSync();
  }

  PrivateKey generateSync() {
    var gen = new ECKeyGenerator();
    var rsapars = new ECKeyGeneratorParameters(_secp256r1);
    var params = new ParametersWithRandom(rsapars, random);
    gen.init(params);
    var pair = gen.generateKeyPair();
    return new PrivateKeyImpl(pair.privateKey, pair.publicKey);
  }

  PrivateKey loadFromString(String str) {
    if (str.contains(" ")) {
      List ss = str.split(" ");
      var d = newBigIntegerFromBytes(1, Base64.decode(ss[0]));
      ECPrivateKey pri = new ECPrivateKey(d, _secp256r1);
      var Q = _secp256r1.curve.decodePoint(Base64.decode(ss[1]));
      ECPublicKey pub = new ECPublicKey(Q, _secp256r1);
      return new PrivateKeyImpl(pri, pub);
    } else {
      var d = newBigIntegerFromBytes(1, Base64.decode(str));
      ECPrivateKey pri = new ECPrivateKey(d, _secp256r1);
      return new PrivateKeyImpl(pri);
    }
  }

  PublicKey getKeyFromBytes(Uint8List bytes) {
    ECPoint Q = _secp256r1.curve.decodePoint(bytes);
    return new PublicKeyImpl(new ECPublicKey(Q, _secp256r1));
  }

  String base64_sha256(Uint8List bytes) {
    SHA256Digest sha256 = new SHA256Digest();
    Uint8List hashed = sha256.process(new Uint8List.fromList(bytes));
    return Base64.encode(hashed);
  }
}

class ECDHImpl extends ECDH {
  String get encodedPublicKey => Base64.encode(_ecPublicKey.Q.getEncoded(false));

  Uint8List bytes;

  ECPrivateKey _ecPrivateKey;
  ECPublicKey _ecPublicKey;

  ECDHImpl(this._ecPrivateKey, this._ecPublicKey, ECPoint Q2) {
    //var Q2 = _ecPublicKeyRemote.Q * _ecPrivateKey.d;
    bytes = bigintToUint8List(Q2.x.toBigInteger());
    if (bytes.length > 32) {
      bytes = bytes.sublist(bytes.length - 32);
    } else if (bytes.length < 32) {
      var newbytes = new Uint8List(32);
      int dlen = 32 - bytes.length;
      for (int i = 0; i < bytes.length; ++i) {
        newbytes[i + dlen] = bytes[i];
      }
      for (int i = 0; i < dlen; ++i) {
        newbytes[i] = 0;
      }
      bytes = newbytes;
    }
  }

  String hashSalt(String salt) {
    Uint8List encoded = toUTF8(salt);
    Uint8List raw = new Uint8List(encoded.length + bytes.length);
    int i;
    for (i = 0; i < encoded.length; i++) {
      raw[i] = encoded[i];
    }

    for (var x = 0; x < bytes.length; x++) {
      raw[i] = bytes[x];
      i++;
    }
    SHA256Digest sha256 = new SHA256Digest();
    var hashed = sha256.process(raw);
    return Base64.encode(hashed);
  }
}

class PublicKeyImpl extends PublicKey {
  static final publicExp = newBigInteger(65537);

  ECPublicKey ecPublicKey;
  String qBase64;
  String qHash64;

  PublicKeyImpl(this.ecPublicKey) {
    List<int> bytes = ecPublicKey.Q.getEncoded(false);
    qBase64 = Base64.encode(bytes);
    SHA256Digest sha256 = new SHA256Digest();
    qHash64 = Base64.encode(sha256.process(bytes));
  }
}

class PrivateKeyImpl implements PrivateKey {
  PublicKey publicKey;
  ECPrivateKey ecPrivateKey;
  ECPublicKey ecPublicKey;

  PrivateKeyImpl(this.ecPrivateKey, [this.ecPublicKey]) {
    if (ecPublicKey == null) {
      ecPublicKey = new ECPublicKey(_secp256r1.G * ecPrivateKey.d, _secp256r1);
    }
    publicKey = new PublicKeyImpl(ecPublicKey);
  }

  String saveToString() {
    return "${Base64.encode(bigintToUint8List(ecPrivateKey.d))} ${publicKey.qBase64}";
  }

  Future<ECDHImpl> getSecret(String key) async {
    ECPoint p = ecPrivateKey.parameters.curve.decodePoint(Base64.decode(key));
    ECPublicKey publicKey = new ECPublicKey(p, _secp256r1);
    var Q2 = publicKey.Q * ecPrivateKey.d;
    return new ECDHImpl(ecPrivateKey, ecPublicKey, Q2);
  }
}

/// random number generator
class DSRandomImpl extends SecureRandomBase implements DSRandom {
  bool get needsEntropy => true;

  BlockCtrRandom _delegate;
  AESFastEngine _aes;

  String get algorithmName => _delegate.algorithmName;

  DSRandomImpl([int seed = -1]) {
    _aes = new AESFastEngine();
    _delegate = new BlockCtrRandom(_aes);
    // use the native prng, but still need to use randmize to add more seed later
    Math.Random r = new Math.Random();
    final keyBytes = [
      r.nextInt(256),
      r.nextInt(256),
      r.nextInt(256),
      r.nextInt(256),
      r.nextInt(256),
      r.nextInt(256),
      r.nextInt(256),
      r.nextInt(256),
      r.nextInt(256),
      r.nextInt(256),
      r.nextInt(256),
      r.nextInt(256),
      r.nextInt(256),
      r.nextInt(256),
      r.nextInt(256),
      r.nextInt(256)
    ];
    final key = new KeyParameter(new Uint8List.fromList(keyBytes));
    r = new Math.Random((new DateTime.now()).millisecondsSinceEpoch);
    final iv = new Uint8List.fromList([
      r.nextInt(256),
      r.nextInt(256),
      r.nextInt(256),
      r.nextInt(256),
      r.nextInt(256),
      r.nextInt(256),
      r.nextInt(256),
      r.nextInt(256)
    ]);
    final params = new ParametersWithIV<CipherParameters>(key, iv);
    _delegate.seed(params);
  }

  void seed(CipherParameters params) {
    if (params is ParametersWithIV<CipherParameters>) {
      _delegate.seed(params);
    } else {
      throw "${params} is not a ParametersWithIV implementation.";
    }
  }

  void addEntropy(String str) {
    List<int> utf = const Utf8Encoder().convert(str);
    int length2 = (utf.length).ceil() * 16;
    if (length2 > utf.length) {
      utf = utf.toList();
      while (length2 > utf.length) {
        utf.add(0);
      }
    }

    final bytes = new Uint8List.fromList(utf);

    final out = new Uint8List(16);
    for (var offset = 0; offset < bytes.lengthInBytes;) {
      var len = _aes.processBlock(bytes, offset, out, 0);
      offset += len;
    }
  }

  int nextUint8() {
    return _delegate.nextUint8();
  }
}

String bytes2hex(List<int> bytes) {
  var result = new StringBuffer();
  for (var part in bytes) {
    result.write("${part < 16 ? "0" : ""}${part.toRadixString(16)}");
  }
  return result.toString();
}

/// BigInteger.toByteArray contains negative values, so we need a different version
/// this version also remove the byte for sign, so it's not able to serialize negative number
Uint8List bigintToUint8List(input) {
  List<int> rslt =  bigIntegerToByteArray(input);
  if (rslt.length > 32 && rslt[0] == 0){
    rslt = rslt.sublist(1);
  }
  int len = rslt.length;
  for (int i = 0; i < len; ++i) {
    if (rslt[i] < 0) {
      rslt[i] &= 0xff;
    }
  }
  return new Uint8List.fromList(rslt);
}
