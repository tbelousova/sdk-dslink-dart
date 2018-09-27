library dslink.utils.consts;

import 'dart:math' as Math;
import "dart:io";

//FIXME:Dart1.0
/*
import "package:bignum/bignum.dart";
const double_NAN = double.NAN;
const double_NEGATIVE_INFINITY = double.NEGATIVE_INFINITY;
const double_INFINITY = double.INFINITY;
const Math_PI = Math.PI;
const double_MAX_FINITE = double.MAX_FINITE;
const Math_E = Math.E;
const Math_LN2 = Math.LN2;
const Math_LN10 = Math.LN10;
const Math_LOG2E = Math.LOG2E;
const Math_LOG10E = Math.LOG10E;
const Math_SQRT2 = Math.SQRT2;
const Math_SQRT1_2 = Math.SQRT1_2;
const Duration_ZERO = Duration.ZERO;

void socketJoinMulticast(RawDatagramSocket socket, InternetAddress group, [NetworkInterface interface]) {
  socket.joinMulticast(group, interface: interface);
}

List<int> bigIntegerToByteArray(data) {
  return (data as BigInteger).toByteArray();
}

String bigIntegerToRadix(value, int radix) {
  //FIXME:Dart1.0
  return (value as BigInteger).toRadix(radix);
}

dynamic newBigInteger([a, b, c]) {
  //FIXME:Dart1.0
  return new BigInteger(a,b,c);
  }

dynamic newBigIntegerFromBytes(int signum, List<int> magnitude) {
  //FIXME:Dart1.0
  return new BigInteger.fromBytes(signum, magnitude);
}
*/


//FIXME:Dart2.0
import "package:pointycastle/export.dart" hide PublicKey, PrivateKey;
import 'dart:convert';
import 'dart:typed_data';
const double_NAN = double.nan;
const double_NEGATIVE_INFINITY = double.negativeInfinity;
const double_INFINITY = double.infinity;
const Math_PI = Math.pi;
const double_MAX_FINITE = double.maxFinite;
const Math_E = Math.e;
const Math_LN2 = Math.ln2;
const Math_LN10 = Math.ln10;
const Math_LOG2E = Math.log2e;
const Math_LOG10E = Math.log10e;
const Math_SQRT2 = Math.sqrt2;
const Math_SQRT1_2 = Math.sqrt1_2;
const Duration_ZERO = Duration.zero;

const JSON = json;
const BASE64 = base64;
const UTF8 = utf8;



void socketJoinMulticast(RawDatagramSocket socket, InternetAddress group, [NetworkInterface interface]) {
  //FIXME:Dart2.0
  socket.joinMulticast(group, interface);
}


List<int> bigIntegerToByteArray(data) {
  //FIXME:Dart2.0
  return _bigIntToByteArray(data as BigInt);
}



String bigIntegerToRadix(value, int radix) {
  //FIXME:Dart1.0
  //return (value as BigInteger).toRadix(radix);
}

dynamic newBigInteger([a, b, c]) {
  //FIXME:Dart2.0
  if (a is num && b==null && c==null) {
    return new BigInt.from(a);
  }
  if (a is String && b is int) {
    return BigInt.parse(a, radix: b);
  }
  return null;
}

dynamic newBigIntegerFromBytes(int signum, List<int> magnitude) {
  //FIXME:Dart2.0
  return _bytesToBigInt(magnitude);
}

//FIXME:Dart2.0

List<int> _bigIntToByteArray(BigInt data) {
  String str;
  bool neg = false;
  if (data < BigInt.zero) {
    str = (~data).toRadixString(16);
    neg = true;
  } else {
    str = data.toRadixString(16);
  }
  int p = 0;
  int len = str.length;
  int blen = (len + 1) ~/ 2;
  int boff = 0;
  List bytes;
  if (neg) {
    if (len & 1 == 1) {
      p = -1;
    }
    int byte0 = ~int.parse(str.substring(0, p + 2), radix: 16);
    if (byte0 < -128) byte0 += 256;
    if (byte0 >= 0) {
      boff = 1;
      bytes = new List<int>(blen + 1);
      bytes[0] = -1;
      bytes[1] = byte0;
    } else {
      bytes = new List<int>(blen);
      bytes[0] = byte0;
    }
    for (int i = 1; i < blen; ++i) {
      int byte = ~int.parse(str.substring(p + (i << 1), p + (i << 1) + 2), radix: 16);
      if (byte < -128) byte += 256;
      bytes[i + boff] = byte;
    }
  } else {
    if (len & 1 == 1) {
      p = -1;
    }
    int byte0 = int.parse(str.substring(0, p + 2), radix: 16);
    if (byte0 > 127) byte0 -= 256;
    if (byte0 < 0) {
      boff = 1;
      bytes = new List<int>(blen + 1);
      bytes[0] = 0;
      bytes[1] = byte0;
    } else {
      bytes = new List<int>(blen);
      bytes[0] = byte0;
    }
    for (int i = 1; i < blen; ++i) {
      int byte = int.parse(str.substring(p + (i << 1), p + (i << 1) + 2), radix: 16);
      if (byte > 127) byte -= 256;
      bytes[i + boff] = byte;
    }
  }
  return bytes;
}

BigInt _bytesToBigInt(List<int> bytes) {
  BigInt read(int start, int end) {
    if (end - start <= 4) {
      int result = 0;
      for (int i = end - 1; i >= start; i--) {
        result = result * 256 + bytes[i];
      }
      return new BigInt.from(result);
    }
    int mid = start + ((end - start) >> 1);
    var result = read(start, mid) + read(mid, end) * (BigInt.one << ((mid - start) * 8));
    return result;
  }

  return read(0, bytes.length);
}


const _MASK_16 = 0xFFFF;
const _MASK_32 = 0xFFFFFFFF;

int clip16(int x) => (x & _MASK_16);
int clip32(int x) => (x & _MASK_32);

abstract class SecureRandomBase implements SecureRandom {
  int nextUint16() {
    var b0 = nextUint8();
    var b1 = nextUint8();
    return clip16((b1 << 8) | b0);
  }

  int nextUint32() {
    var b0 = nextUint8();
    var b1 = nextUint8();
    var b2 = nextUint8();
    var b3 = nextUint8();
    return clip32((b3 << 24) | (b2 << 16) | (b1 << 8) | b0);
  }

  BigInt nextBigInteger(int bitLength) {
    return newBigIntegerFromBytes(1, _randomBits(bitLength));
  }

  Uint8List nextBytes(int count) {
    var bytes = new Uint8List(count);
    for (var i = 0; i < count; i++) {
      bytes[i] = nextUint8();
    }
    return bytes;
  }

  List<int> _randomBits(int numBits) {
    if (numBits < 0) {
      throw new ArgumentError("numBits must be non-negative");
    }

    var numBytes = (numBits + 7) ~/ 8; // avoid overflow
    var randomBits = new Uint8List(numBytes);

    // Generate random bytes and mask out any excess bits
    if (numBytes > 0) {
      for (var i = 0; i < numBytes; i++) {
        randomBits[i] = nextUint8();
      }
      int excessBits = 8 * numBytes - numBits;
      randomBits[0] &= (1 << (8 - excessBits)) - 1;
    }
    return randomBits;
  }
}