import 'dart:typed_data';

/// BIP173 / BIP350 bech32 codec.
///
/// [Bech32Variant.bech32] is BIP173 (P2WPKH / P2WSH — witness version 0).
/// [Bech32Variant.bech32m] is BIP350 (P2TR — witness version 1+).
///
/// Public entry points:
///   * [encodeSegwitAddress] — HRP + witness version + 20-byte program →
///     `bc1q…` / `tb1q…` (or `bc1p…` / `tb1p…` for taproot).
///   * [decodeSegwitAddress] — inverse; returns `(hrp, witnessVersion, program)`.
///
/// Implementation intentionally lives in `utils/` so both [KeyService]
/// (address generation) and the transaction signer (address → scriptPubKey)
/// share a single codec.
enum Bech32Variant { bech32, bech32m }

class Bech32Exception implements Exception {
  final String message;
  Bech32Exception(this.message);
  @override
  String toString() => 'Bech32Exception: $message';
}

class Bech32 {
  static const String _charset = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';
  static const int _bech32Const = 1;
  static const int _bech32mConst = 0x2bc830a3;

  /// Encode a segwit address.
  ///
  /// [hrp] is `bc` (mainnet) or `tb` (testnet). [witnessVersion] is 0 for
  /// P2WPKH/P2WSH, 1 for P2TR. [program] is the 20-byte pubkey hash
  /// (P2WPKH), 32-byte script hash (P2WSH), or 32-byte x-only key (P2TR).
  static String encodeSegwitAddress(
    String hrp,
    int witnessVersion,
    Uint8List program,
  ) {
    if (witnessVersion < 0 || witnessVersion > 16) {
      throw Bech32Exception('witness version out of range: $witnessVersion');
    }
    if (program.length < 2 || program.length > 40) {
      throw Bech32Exception(
          'witness program length invalid: ${program.length}');
    }
    if (witnessVersion == 0 && program.length != 20 && program.length != 32) {
      throw Bech32Exception(
        'v0 program must be 20 (P2WPKH) or 32 (P2WSH) bytes',
      );
    }
    final variant =
        witnessVersion == 0 ? Bech32Variant.bech32 : Bech32Variant.bech32m;
    final data = <int>[witnessVersion, ..._convertBits(program, 8, 5, true)];
    return _encode(hrp, data, variant);
  }

  /// Decode a segwit address. Validates checksum variant (bech32 vs bech32m)
  /// based on witness version.
  static ({String hrp, int witnessVersion, Uint8List program})
      decodeSegwitAddress(String address) {
    final (hrp, data, variant) = _decode(address);
    if (data.isEmpty) {
      throw Bech32Exception('empty data part');
    }
    final witnessVersion = data[0];
    if (witnessVersion < 0 || witnessVersion > 16) {
      throw Bech32Exception('invalid witness version $witnessVersion');
    }
    final program = _convertBits(
      Uint8List.fromList(data.sublist(1)),
      5,
      8,
      false,
    );
    if (program.length < 2 || program.length > 40) {
      throw Bech32Exception(
        'decoded program length ${program.length} out of range',
      );
    }
    if (witnessVersion == 0 && program.length != 20 && program.length != 32) {
      throw Bech32Exception(
        'v0 program must be 20 or 32 bytes, got ${program.length}',
      );
    }
    final expected =
        witnessVersion == 0 ? Bech32Variant.bech32 : Bech32Variant.bech32m;
    if (variant != expected) {
      throw Bech32Exception(
        'checksum variant mismatch for witness version $witnessVersion',
      );
    }
    return (
      hrp: hrp,
      witnessVersion: witnessVersion,
      program: Uint8List.fromList(program),
    );
  }

  // ---- low-level ----

  static String _encode(String hrp, List<int> data, Bech32Variant v) {
    final checksum = _createChecksum(hrp, data, v);
    final combined = [...data, ...checksum];
    final buf = StringBuffer(hrp);
    buf.write('1');
    for (final c in combined) {
      buf.write(_charset[c]);
    }
    return buf.toString();
  }

  static (String hrp, List<int> data, Bech32Variant variant) _decode(
    String input,
  ) {
    if (input != input.toLowerCase() && input != input.toUpperCase()) {
      throw Bech32Exception('mixed case');
    }
    final s = input.toLowerCase();
    final sep = s.lastIndexOf('1');
    if (sep < 1 || sep + 7 > s.length || s.length > 90) {
      throw Bech32Exception('malformed bech32 string');
    }
    final hrp = s.substring(0, sep);
    final rest = s.substring(sep + 1);
    final data = <int>[];
    for (var i = 0; i < rest.length; i++) {
      final idx = _charset.indexOf(rest[i]);
      if (idx < 0) {
        throw Bech32Exception('invalid character: ${rest[i]}');
      }
      data.add(idx);
    }
    final polymod = _polymod([..._hrpExpand(hrp), ...data]);
    final Bech32Variant variant;
    if (polymod == _bech32Const) {
      variant = Bech32Variant.bech32;
    } else if (polymod == _bech32mConst) {
      variant = Bech32Variant.bech32m;
    } else {
      throw Bech32Exception('invalid checksum');
    }
    return (hrp, data.sublist(0, data.length - 6), variant);
  }

  static List<int> _createChecksum(
      String hrp, List<int> data, Bech32Variant v) {
    final values = [..._hrpExpand(hrp), ...data, 0, 0, 0, 0, 0, 0];
    final constVal = v == Bech32Variant.bech32 ? _bech32Const : _bech32mConst;
    final polymod = _polymod(values) ^ constVal;
    return [
      for (var i = 0; i < 6; i++) (polymod >> (5 * (5 - i))) & 31,
    ];
  }

  static List<int> _hrpExpand(String hrp) {
    return [
      for (var i = 0; i < hrp.length; i++) hrp.codeUnitAt(i) >> 5,
      0,
      for (var i = 0; i < hrp.length; i++) hrp.codeUnitAt(i) & 31,
    ];
  }

  static int _polymod(List<int> values) {
    const gen = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3];
    var chk = 1;
    for (final v in values) {
      final b = chk >> 25;
      chk = ((chk & 0x1ffffff) << 5) ^ v;
      for (var i = 0; i < 5; i++) {
        if (((b >> i) & 1) == 1) chk ^= gen[i];
      }
    }
    return chk;
  }

  static List<int> _convertBits(
    Uint8List data,
    int fromBits,
    int toBits,
    bool pad,
  ) {
    var acc = 0;
    var bits = 0;
    final result = <int>[];
    final maxv = (1 << toBits) - 1;
    final maxAcc = (1 << (fromBits + toBits - 1)) - 1;
    for (final value in data) {
      if (value < 0 || (value >> fromBits) != 0) {
        throw Bech32Exception('input byte out of range');
      }
      acc = ((acc << fromBits) | value) & maxAcc;
      bits += fromBits;
      while (bits >= toBits) {
        bits -= toBits;
        result.add((acc >> bits) & maxv);
      }
    }
    if (pad) {
      if (bits > 0) result.add((acc << (toBits - bits)) & maxv);
    } else if (bits >= fromBits || ((acc << (toBits - bits)) & maxv) != 0) {
      throw Bech32Exception('invalid padding');
    }
    return result;
  }
}
