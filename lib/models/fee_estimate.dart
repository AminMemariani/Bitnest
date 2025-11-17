/// Fee estimate model.
class FeeEstimate {
  /// Fee rate in satoshis per virtual byte (sat/vB)
  final int satPerVByte;

  /// Estimated confirmation time in blocks
  final int? estimatedBlocks;

  FeeEstimate({
    required this.satPerVByte,
    this.estimatedBlocks,
  });

  factory FeeEstimate.fromJson(Map<String, dynamic> json) {
    // Esplora API returns fee estimates in different formats
    // Handle both single value and object formats
    int satPerVByte;
    if (json['feeRate'] != null) {
      satPerVByte = (json['feeRate'] as num).toInt();
    } else if (json['sat_per_vbyte'] != null) {
      satPerVByte = (json['sat_per_vbyte'] as num).toInt();
    } else if (json['satPerVByte'] != null) {
      satPerVByte = (json['satPerVByte'] as num).toInt();
    } else {
      // Fallback: try to extract from blocks object
      final blocks = json['blocks'] as Map<String, dynamic>?;
      if (blocks != null && blocks.isNotEmpty) {
        final firstKey = blocks.keys.first;
        satPerVByte = (blocks[firstKey] as num).toInt();
      } else {
        satPerVByte = 10; // Default fallback
      }
    }

    return FeeEstimate(
      satPerVByte: satPerVByte,
      estimatedBlocks: json['estimatedBlocks'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'satPerVByte': satPerVByte,
      'estimatedBlocks': estimatedBlocks,
    };
  }
}

