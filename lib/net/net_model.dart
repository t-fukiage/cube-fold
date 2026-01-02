import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

class NetPalette {
  static const Color baseFace = Color(0xFFDDE7FB);
  static const Color accentFace = Color(0xFFFFE2D6);
  static const List<Color> softColors = [
    Color(0xFFDDE7FB),
    Color(0xFFFFE2D6),
    Color(0xFFE6F4EC),
    Color(0xFFF1E8FF),
    Color(0xFFFFE2F0),
    Color(0xFFFFF1CC),
    Color(0xFFE2F2FF),
    Color(0xFFECE3D8),
  ];
}

/// 定義レベルのFace情報。将来的に複数展開図へ拡張するための骨組み。
class FaceDefinition {
  const FaceDefinition({
    required this.id,
    required this.displayName,
    this.parentId,
    this.edgeFromParentId,
    required this.color,
  });

  final String id;
  final String displayName;
  final String? parentId;
  final String? edgeFromParentId;
  final Color color;

  bool get isRoot => parentId == null;
}

/// 2つの面をつなぐ折り目（ヒンジ）。
class EdgeDefinition {
  const EdgeDefinition({
    required this.id,
    required this.parentFaceId,
    required this.childFaceId,
    required this.hingeOrigin,
    required this.hingeAxis,
    required this.childOffsetFromHinge,
    required this.childOrientation,
  });

  final String id;
  final String parentFaceId;
  final String childFaceId;

  /// 親面ローカル座標におけるヒンジの基準点。
  final Vector3 hingeOrigin;

  /// 親面ローカル座標におけるヒンジ軸方向。必ず正規化されている想定。
  final Vector3 hingeAxis;

  /// ヒンジ原点から子面中心へのベクトル（親面ローカル座標）。
  final Vector3 childOffsetFromHinge;

  /// 子面ローカル軸の回転（親面に対しての初期姿勢）。
  final Quaternion childOrientation;
}

/// 展開図のメタ情報（選択画面用）。
class NetPatternInfo {
  const NetPatternInfo({
    required this.id,
    required this.displayName,
    required this.thumbnailPositions,
    required this.factory,
  });

  final String id;
  final String displayName;
  /// 2Dプレビュー用の(row, col)座標リスト
  final List<(int, int)> thumbnailPositions;
  final NetDefinition Function() factory;

  /// 利用可能な全パターン
  static final List<NetPatternInfo> allPatterns = [
    NetPatternInfo(
      id: 'cross',
      displayName: '十字型',
      thumbnailPositions: [(0, 1), (1, 0), (1, 1), (1, 2), (2, 1), (3, 1)],
      factory: NetDefinition.cubeCrossNet,
    ),
    NetPatternInfo(
      id: 't_shape',
      displayName: 'T字型',
      thumbnailPositions: [(0, 1), (1, 0), (1, 1), (1, 2), (2, 2), (3, 2)],
      factory: NetDefinition.cubeTNet,
    ),
    NetPatternInfo(
      id: 'stair',
      displayName: '階段型',
      thumbnailPositions: [(0, 0), (1, 0), (1, 1), (2, 1), (2, 2), (3, 2)],
      factory: NetDefinition.cubeStairNet,
    ),
    NetPatternInfo(
      id: 'l_shape',
      displayName: 'L字型',
      thumbnailPositions: [(0, 0), (1, 0), (2, 0), (2, 1), (2, 2), (3, 2)],
      factory: NetDefinition.cubeLNet,
    ),
  ];
}

/// 展開図全体の定義。
class NetDefinition {
  const NetDefinition({
    required this.faces,
    required this.edges,
    required this.rootFaceId,
    required this.faceSize,
  });

  final Map<String, FaceDefinition> faces;
  final Map<String, EdgeDefinition> edges;
  final String rootFaceId;
  final double faceSize;

  double get halfFaceSize => faceSize / 2;

  EdgeDefinition? edgeById(String? id) {
    if (id == null) return null;
    return edges[id];
  }

  EdgeDefinition? edgeForChild(String childFaceId) {
    return edges.values.firstWhere(
      (edge) => edge.childFaceId == childFaceId,
      orElse: () => throw ArgumentError('Edge not found for $childFaceId'),
    );
  }

  /// グリッド上に配置した6面の正方形から展開図を生成する。
  factory NetDefinition.fromGridPositions(
    Set<(int, int)> positions, {
    double faceSize = 1.0,
    Map<(int, int), Color>? faceColors,
  }) {
    if (positions.length != 6) {
      throw ArgumentError('Grid positions must contain exactly 6 faces.');
    }

    final ordered = positions.toList()
      ..sort((a, b) {
        final rowCompare = a.$1.compareTo(b.$1);
        if (rowCompare != 0) return rowCompare;
        return a.$2.compareTo(b.$2);
      });

    final rootPos = ordered.first;
    final String rootId = _gridFaceId(rootPos);
    final Map<(int, int), String> idByPos = {
      for (final pos in positions) pos: _gridFaceId(pos),
    };

    final Map<(int, int), (int, int)?> parent = {rootPos: null};
    final queue = <(int, int)>[rootPos];
    int index = 0;
    while (index < queue.length) {
      final current = queue[index++];
      for (final neighbor in _gridNeighbors(current)) {
        if (!positions.contains(neighbor)) continue;
        if (parent.containsKey(neighbor)) continue;
        parent[neighbor] = current;
        queue.add(neighbor);
      }
    }

    if (parent.length != positions.length) {
      throw ArgumentError('Grid positions must be edge-connected.');
    }

    final centerPos = _gridCenter(positions);

    final half = faceSize / 2;
    final identity = Quaternion.identity();
    final Map<String, FaceDefinition> faces = {};
    final Map<String, EdgeDefinition> edges = {};

    for (int i = 0; i < ordered.length; i++) {
      final pos = ordered[i];
      final faceId = idByPos[pos]!;
      final displayName = '面${i + 1}';
      final color = faceColors?[pos] ??
          (pos == centerPos ? NetPalette.accentFace : NetPalette.baseFace);

      if (pos == rootPos) {
        faces[faceId] = FaceDefinition(
          id: faceId,
          displayName: displayName,
          color: color,
        );
        continue;
      }

      final parentPos = parent[pos];
      if (parentPos == null) {
        throw ArgumentError('Parent not found for $pos');
      }
      final parentId = idByPos[parentPos]!;
      final edgeId = 'edge_${parentId}_$faceId';
      final int dr = pos.$1 - parentPos.$1;
      final int dc = pos.$2 - parentPos.$2;

      final Vector3 hingeOrigin;
      final Vector3 hingeAxis;
      final Vector3 childOffset;
      if (dr == -1 && dc == 0) {
        hingeOrigin = Vector3(0, -half, 0);
        hingeAxis = Vector3(-1, 0, 0);
        childOffset = Vector3(0, -half, 0);
      } else if (dr == 1 && dc == 0) {
        hingeOrigin = Vector3(0, half, 0);
        hingeAxis = Vector3(1, 0, 0);
        childOffset = Vector3(0, half, 0);
      } else if (dr == 0 && dc == -1) {
        hingeOrigin = Vector3(-half, 0, 0);
        hingeAxis = Vector3(0, 1, 0);
        childOffset = Vector3(-half, 0, 0);
      } else if (dr == 0 && dc == 1) {
        hingeOrigin = Vector3(half, 0, 0);
        hingeAxis = Vector3(0, -1, 0);
        childOffset = Vector3(half, 0, 0);
      } else {
        throw ArgumentError('Grid positions must be adjacent: $parentPos -> $pos');
      }

      edges[edgeId] = EdgeDefinition(
        id: edgeId,
        parentFaceId: parentId,
        childFaceId: faceId,
        hingeOrigin: hingeOrigin,
        hingeAxis: hingeAxis,
        childOffsetFromHinge: childOffset,
        childOrientation: identity,
      );

      faces[faceId] = FaceDefinition(
        id: faceId,
        displayName: displayName,
        parentId: parentId,
        edgeFromParentId: edgeId,
        color: color,
      );
    }

    return NetDefinition(
      faces: faces,
      edges: edges,
      rootFaceId: rootId,
      faceSize: faceSize,
    );
  }

  /// 十字型（既存）
  factory NetDefinition.cubeCrossNet() {
    const faceSize = 1.0;
    const rootFaceId = 'center';

    const faces = <String, FaceDefinition>{
      'center': FaceDefinition(
        id: 'center',
        displayName: '中心',
        color: NetPalette.accentFace,
      ),
      'top': FaceDefinition(
        id: 'top',
        displayName: '上',
        parentId: 'center',
        edgeFromParentId: 'edge_center_top',
        color: NetPalette.baseFace,
      ),
      'bottom': FaceDefinition(
        id: 'bottom',
        displayName: '下',
        parentId: 'center',
        edgeFromParentId: 'edge_center_bottom',
        color: NetPalette.baseFace,
      ),
      'left': FaceDefinition(
        id: 'left',
        displayName: '左',
        parentId: 'center',
        edgeFromParentId: 'edge_center_left',
        color: NetPalette.baseFace,
      ),
      'right': FaceDefinition(
        id: 'right',
        displayName: '右',
        parentId: 'center',
        edgeFromParentId: 'edge_center_right',
        color: NetPalette.baseFace,
      ),
      'bottom_tail': FaceDefinition(
        id: 'bottom_tail',
        displayName: '下のしっぽ',
        parentId: 'bottom',
        edgeFromParentId: 'edge_bottom_tail',
        color: NetPalette.baseFace,
      ),
    };

    final half = faceSize / 2;
    final identity = Quaternion.identity();

    final edges = <String, EdgeDefinition>{
      'edge_center_top': EdgeDefinition(
        id: 'edge_center_top',
        parentFaceId: 'center',
        childFaceId: 'top',
        hingeOrigin: Vector3(0, -half, 0),
        hingeAxis: Vector3(-1, 0, 0),
        childOffsetFromHinge: Vector3(0, -half, 0),
        childOrientation: identity,
      ),
      'edge_center_bottom': EdgeDefinition(
        id: 'edge_center_bottom',
        parentFaceId: 'center',
        childFaceId: 'bottom',
        hingeOrigin: Vector3(0, half, 0),
        hingeAxis: Vector3(1, 0, 0),
        childOffsetFromHinge: Vector3(0, half, 0),
        childOrientation: identity,
      ),
      'edge_center_left': EdgeDefinition(
        id: 'edge_center_left',
        parentFaceId: 'center',
        childFaceId: 'left',
        hingeOrigin: Vector3(-half, 0, 0),
        hingeAxis: Vector3(0, 1, 0),
        childOffsetFromHinge: Vector3(-half, 0, 0),
        childOrientation: identity,
      ),
      'edge_center_right': EdgeDefinition(
        id: 'edge_center_right',
        parentFaceId: 'center',
        childFaceId: 'right',
        hingeOrigin: Vector3(half, 0, 0),
        hingeAxis: Vector3(0, -1, 0),
        childOffsetFromHinge: Vector3(half, 0, 0),
        childOrientation: identity,
      ),
      'edge_bottom_tail': EdgeDefinition(
        id: 'edge_bottom_tail',
        parentFaceId: 'bottom',
        childFaceId: 'bottom_tail',
        hingeOrigin: Vector3(0, half, 0),
        hingeAxis: Vector3(1, 0, 0),
        childOffsetFromHinge: Vector3(0, half, 0),
        childOrientation: identity,
      ),
    };

    return NetDefinition(
      faces: faces,
      edges: edges,
      rootFaceId: rootFaceId,
      faceSize: faceSize,
    );
  }

  /// T字型 - 十字型の変形、下の面が右にずれる
  factory NetDefinition.cubeTNet() {
    const faceSize = 1.0;
    const rootFaceId = 'center';

    const faces = <String, FaceDefinition>{
      'center': FaceDefinition(
        id: 'center',
        displayName: '中心',
        color: NetPalette.accentFace,
      ),
      'top': FaceDefinition(
        id: 'top',
        displayName: '上',
        parentId: 'center',
        edgeFromParentId: 'edge_center_top',
        color: NetPalette.baseFace,
      ),
      'left': FaceDefinition(
        id: 'left',
        displayName: '左',
        parentId: 'center',
        edgeFromParentId: 'edge_center_left',
        color: NetPalette.baseFace,
      ),
      'right': FaceDefinition(
        id: 'right',
        displayName: '右',
        parentId: 'center',
        edgeFromParentId: 'edge_center_right',
        color: NetPalette.baseFace,
      ),
      'right_bottom': FaceDefinition(
        id: 'right_bottom',
        displayName: '右下',
        parentId: 'right',
        edgeFromParentId: 'edge_right_bottom',
        color: NetPalette.baseFace,
      ),
      'right_bottom_tail': FaceDefinition(
        id: 'right_bottom_tail',
        displayName: '右下のしっぽ',
        parentId: 'right_bottom',
        edgeFromParentId: 'edge_right_bottom_tail',
        color: NetPalette.baseFace,
      ),
    };

    final half = faceSize / 2;
    final identity = Quaternion.identity();

    final edges = <String, EdgeDefinition>{
      'edge_center_top': EdgeDefinition(
        id: 'edge_center_top',
        parentFaceId: 'center',
        childFaceId: 'top',
        hingeOrigin: Vector3(0, -half, 0),
        hingeAxis: Vector3(-1, 0, 0),
        childOffsetFromHinge: Vector3(0, -half, 0),
        childOrientation: identity,
      ),
      'edge_center_left': EdgeDefinition(
        id: 'edge_center_left',
        parentFaceId: 'center',
        childFaceId: 'left',
        hingeOrigin: Vector3(-half, 0, 0),
        hingeAxis: Vector3(0, 1, 0),
        childOffsetFromHinge: Vector3(-half, 0, 0),
        childOrientation: identity,
      ),
      'edge_center_right': EdgeDefinition(
        id: 'edge_center_right',
        parentFaceId: 'center',
        childFaceId: 'right',
        hingeOrigin: Vector3(half, 0, 0),
        hingeAxis: Vector3(0, -1, 0),
        childOffsetFromHinge: Vector3(half, 0, 0),
        childOrientation: identity,
      ),
      'edge_right_bottom': EdgeDefinition(
        id: 'edge_right_bottom',
        parentFaceId: 'right',
        childFaceId: 'right_bottom',
        hingeOrigin: Vector3(0, half, 0),
        hingeAxis: Vector3(1, 0, 0),
        childOffsetFromHinge: Vector3(0, half, 0),
        childOrientation: identity,
      ),
      'edge_right_bottom_tail': EdgeDefinition(
        id: 'edge_right_bottom_tail',
        parentFaceId: 'right_bottom',
        childFaceId: 'right_bottom_tail',
        hingeOrigin: Vector3(0, half, 0),
        hingeAxis: Vector3(1, 0, 0),
        childOffsetFromHinge: Vector3(0, half, 0),
        childOrientation: identity,
      ),
    };

    return NetDefinition(
      faces: faces,
      edges: edges,
      rootFaceId: rootFaceId,
      faceSize: faceSize,
    );
  }

  /// 階段型 - 面が階段状に並ぶ
  factory NetDefinition.cubeStairNet() {
    const faceSize = 1.0;
    const rootFaceId = 'step1';

    const faces = <String, FaceDefinition>{
      'step1': FaceDefinition(
        id: 'step1',
        displayName: '段1',
        color: NetPalette.baseFace,
      ),
      'step1_bottom': FaceDefinition(
        id: 'step1_bottom',
        displayName: '段1下',
        parentId: 'step1',
        edgeFromParentId: 'edge_step1_bottom',
        color: NetPalette.baseFace,
      ),
      'step2': FaceDefinition(
        id: 'step2',
        displayName: '段2',
        parentId: 'step1_bottom',
        edgeFromParentId: 'edge_step1_bottom_right',
        color: NetPalette.accentFace,
      ),
      'step2_bottom': FaceDefinition(
        id: 'step2_bottom',
        displayName: '段2下',
        parentId: 'step2',
        edgeFromParentId: 'edge_step2_bottom',
        color: NetPalette.baseFace,
      ),
      'step3': FaceDefinition(
        id: 'step3',
        displayName: '段3',
        parentId: 'step2_bottom',
        edgeFromParentId: 'edge_step2_bottom_right',
        color: NetPalette.baseFace,
      ),
      'step3_bottom': FaceDefinition(
        id: 'step3_bottom',
        displayName: '段3下',
        parentId: 'step3',
        edgeFromParentId: 'edge_step3_bottom',
        color: NetPalette.baseFace,
      ),
    };

    final half = faceSize / 2;
    final identity = Quaternion.identity();

    final edges = <String, EdgeDefinition>{
      'edge_step1_bottom': EdgeDefinition(
        id: 'edge_step1_bottom',
        parentFaceId: 'step1',
        childFaceId: 'step1_bottom',
        hingeOrigin: Vector3(0, half, 0),
        hingeAxis: Vector3(1, 0, 0),
        childOffsetFromHinge: Vector3(0, half, 0),
        childOrientation: identity,
      ),
      'edge_step1_bottom_right': EdgeDefinition(
        id: 'edge_step1_bottom_right',
        parentFaceId: 'step1_bottom',
        childFaceId: 'step2',
        hingeOrigin: Vector3(half, 0, 0),
        hingeAxis: Vector3(0, -1, 0),
        childOffsetFromHinge: Vector3(half, 0, 0),
        childOrientation: identity,
      ),
      'edge_step2_bottom': EdgeDefinition(
        id: 'edge_step2_bottom',
        parentFaceId: 'step2',
        childFaceId: 'step2_bottom',
        hingeOrigin: Vector3(0, half, 0),
        hingeAxis: Vector3(1, 0, 0),
        childOffsetFromHinge: Vector3(0, half, 0),
        childOrientation: identity,
      ),
      'edge_step2_bottom_right': EdgeDefinition(
        id: 'edge_step2_bottom_right',
        parentFaceId: 'step2_bottom',
        childFaceId: 'step3',
        hingeOrigin: Vector3(half, 0, 0),
        hingeAxis: Vector3(0, -1, 0),
        childOffsetFromHinge: Vector3(half, 0, 0),
        childOrientation: identity,
      ),
      'edge_step3_bottom': EdgeDefinition(
        id: 'edge_step3_bottom',
        parentFaceId: 'step3',
        childFaceId: 'step3_bottom',
        hingeOrigin: Vector3(0, half, 0),
        hingeAxis: Vector3(1, 0, 0),
        childOffsetFromHinge: Vector3(0, half, 0),
        childOrientation: identity,
      ),
    };

    return NetDefinition(
      faces: faces,
      edges: edges,
      rootFaceId: rootFaceId,
      faceSize: faceSize,
    );
  }

  /// L字型 - 縦に3つ連なって曲がる
  factory NetDefinition.cubeLNet() {
    const faceSize = 1.0;
    const rootFaceId = 'top';

    const faces = <String, FaceDefinition>{
      'top': FaceDefinition(
        id: 'top',
        displayName: '上',
        color: NetPalette.baseFace,
      ),
      'middle': FaceDefinition(
        id: 'middle',
        displayName: '中央',
        parentId: 'top',
        edgeFromParentId: 'edge_top_middle',
        color: NetPalette.baseFace,
      ),
      'corner': FaceDefinition(
        id: 'corner',
        displayName: '角',
        parentId: 'middle',
        edgeFromParentId: 'edge_middle_corner',
        color: NetPalette.baseFace,
      ),
      'corner_right': FaceDefinition(
        id: 'corner_right',
        displayName: '角右',
        parentId: 'corner',
        edgeFromParentId: 'edge_corner_right',
        color: NetPalette.accentFace,
      ),
      'corner_right2': FaceDefinition(
        id: 'corner_right2',
        displayName: '角右2',
        parentId: 'corner_right',
        edgeFromParentId: 'edge_corner_right2',
        color: NetPalette.baseFace,
      ),
      'corner_right3': FaceDefinition(
        id: 'corner_right3',
        displayName: '角右3',
        parentId: 'corner_right2',
        edgeFromParentId: 'edge_corner_right3',
        color: NetPalette.baseFace,
      ),
    };

    final half = faceSize / 2;
    final identity = Quaternion.identity();

    final edges = <String, EdgeDefinition>{
      'edge_top_middle': EdgeDefinition(
        id: 'edge_top_middle',
        parentFaceId: 'top',
        childFaceId: 'middle',
        hingeOrigin: Vector3(0, half, 0),
        hingeAxis: Vector3(1, 0, 0),
        childOffsetFromHinge: Vector3(0, half, 0),
        childOrientation: identity,
      ),
      'edge_middle_corner': EdgeDefinition(
        id: 'edge_middle_corner',
        parentFaceId: 'middle',
        childFaceId: 'corner',
        hingeOrigin: Vector3(0, half, 0),
        hingeAxis: Vector3(1, 0, 0),
        childOffsetFromHinge: Vector3(0, half, 0),
        childOrientation: identity,
      ),
      'edge_corner_right': EdgeDefinition(
        id: 'edge_corner_right',
        parentFaceId: 'corner',
        childFaceId: 'corner_right',
        hingeOrigin: Vector3(half, 0, 0),
        hingeAxis: Vector3(0, -1, 0),
        childOffsetFromHinge: Vector3(half, 0, 0),
        childOrientation: identity,
      ),
      'edge_corner_right2': EdgeDefinition(
        id: 'edge_corner_right2',
        parentFaceId: 'corner_right',
        childFaceId: 'corner_right2',
        hingeOrigin: Vector3(half, 0, 0),
        hingeAxis: Vector3(0, -1, 0),
        childOffsetFromHinge: Vector3(half, 0, 0),
        childOrientation: identity,
      ),
      'edge_corner_right3': EdgeDefinition(
        id: 'edge_corner_right3',
        parentFaceId: 'corner_right2',
        childFaceId: 'corner_right3',
        hingeOrigin: Vector3(0, half, 0),
        hingeAxis: Vector3(1, 0, 0),
        childOffsetFromHinge: Vector3(0, half, 0),
        childOrientation: identity,
      ),
    };

    return NetDefinition(
      faces: faces,
      edges: edges,
      rootFaceId: rootFaceId,
      faceSize: faceSize,
    );
  }
}

String _gridFaceId((int, int) pos) => 'cell_${pos.$1}_${pos.$2}';

Iterable<(int, int)> _gridNeighbors((int, int) pos) sync* {
  final (row, col) = pos;
  yield (row - 1, col);
  yield (row + 1, col);
  yield (row, col - 1);
  yield (row, col + 1);
}

(int, int) _gridCenter(Set<(int, int)> positions) {
  double sumRow = 0;
  double sumCol = 0;
  for (final (row, col) in positions) {
    sumRow += row;
    sumCol += col;
  }
  final double avgRow = sumRow / positions.length;
  final double avgCol = sumCol / positions.length;

  (int, int) best = positions.first;
  double bestDist = double.infinity;
  for (final pos in positions) {
    final double dr = pos.$1 - avgRow;
    final double dc = pos.$2 - avgCol;
    final double dist = dr * dr + dc * dc;
    if (dist < bestDist) {
      bestDist = dist;
      best = pos;
    }
  }
  return best;
}
