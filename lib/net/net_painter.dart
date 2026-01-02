import 'package:flutter/material.dart';

import 'net_controller.dart';

class NetPainter extends CustomPainter {
  NetPainter({
    required this.controller,
    required this.camera,
    required this.selectedFaceId,
    this.grabbedEdgeIndex,
    required this.showDragVector,
    this.dragVectorStart,
    this.dragVectorEnd,
    this.onSnapshot,
  });

  final NetController controller;
  final OrbitCamera camera;
  final String? selectedFaceId;
  /// 掴んでいるエッジのインデックス (0=top, 1=right, 2=bottom, 3=left)
  final int? grabbedEdgeIndex;
  final bool showDragVector;
  final Offset? dragVectorStart;
  final Offset? dragVectorEnd;
  final ValueChanged<NetRenderSnapshot>? onSnapshot;

  @override
  void paint(Canvas canvas, Size size) {
    final snapshot = controller.buildSnapshot(camera, size);
    onSnapshot?.call(snapshot);

    _drawFaces(canvas, snapshot);
    _drawHinge(canvas, snapshot);
    _drawGrabbedEdge(canvas, snapshot);
    _drawDragVector(canvas);
  }

  void _drawFaces(Canvas canvas, NetRenderSnapshot snapshot) {
    final Paint borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    final Paint seamPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF475569).withOpacity(0.55);

    for (final face in snapshot.faces) {
      _drawFaceSurface(canvas, face);

      final bool isSelected = face.id == selectedFaceId;
      borderPaint
        ..color = isSelected
            ? const Color(0xFF1D4ED8)
            : face.baseColor.withValues(alpha: 0.9)
        ..strokeWidth = isSelected ? 3.2 : 1.4;
      canvas.drawPath(face.path, borderPaint);

      if (face.polygon.length >= 4) {
        for (int i = 0; i < 4; i++) {
          if (controller.isConnectedEdge(face.id, i)) {
            continue;
          }
          final Offset start = face.polygon[i];
          final Offset end = face.polygon[(i + 1) % 4];
          canvas.drawLine(start, end, seamPaint);
        }
      }
    }
  }

  void _drawFaceSurface(
    Canvas canvas,
    FaceProjection face,
  ) {
    final Paint fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = face.baseColor;
    canvas.drawPath(face.path, fillPaint);
  }

  void _drawHinge(Canvas canvas, NetRenderSnapshot snapshot) {
    final selected = selectedFaceId != null ? snapshot[selectedFaceId!] : null;
    final hinge = selected?.hingeEdge;
    if (hinge == null) {
      return;
    }
    final Paint hingePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF2563EB);
    final Path hingePath = Path()
      ..moveTo(hinge.start.dx, hinge.start.dy)
      ..lineTo(hinge.end.dx, hinge.end.dy);
    canvas.drawPath(hingePath, hingePaint);
  }

  void _drawGrabbedEdge(Canvas canvas, NetRenderSnapshot snapshot) {
    if (grabbedEdgeIndex == null || selectedFaceId == null) {
      return;
    }
    final face = snapshot[selectedFaceId!];
    if (face == null || face.polygon.length < 4) {
      return;
    }
    
    // polygon: [topLeft, topRight, bottomRight, bottomLeft]
    // edges: 0=top (0->1), 1=right (1->2), 2=bottom (2->3), 3=left (3->0)
    final polygon = face.polygon;
    final int idx = grabbedEdgeIndex!;
    final Offset start = polygon[idx];
    final Offset end = polygon[(idx + 1) % 4];
    
    final Paint edgePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFFF6B00); // オレンジ色でハイライト
    
    canvas.drawLine(start, end, edgePaint);
  }

  void _drawDragVector(Canvas canvas) {
    if (!showDragVector || dragVectorStart == null || dragVectorEnd == null) {
      return;
    }
    final Offset start = dragVectorStart!;
    final Offset end = dragVectorEnd!;
    if ((end - start).distanceSquared < 4) {
      return;
    }

    final Paint vectorPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF16A34A);
    canvas.drawLine(start, end, vectorPaint);

    final Paint startPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFF16A34A);
    canvas.drawCircle(start, 4, startPaint);

    final Offset direction = (start - end);
    final double length = direction.distance;
    if (length > 0.1) {
      final Offset unit = direction / length;
      const double headLength = 10;
      const double headWidth = 6;
      final Offset left = end + Offset(
        unit.dx * headLength - unit.dy * headWidth,
        unit.dy * headLength + unit.dx * headWidth,
      );
      final Offset right = end + Offset(
        unit.dx * headLength + unit.dy * headWidth,
        unit.dy * headLength - unit.dx * headWidth,
      );
      final Path head = Path()
        ..moveTo(end.dx, end.dy)
        ..lineTo(left.dx, left.dy)
        ..lineTo(right.dx, right.dy)
        ..close();
      canvas.drawPath(head, startPaint);
    }
  }

  @override
  bool shouldRepaint(covariant NetPainter oldDelegate) {
    return oldDelegate.controller != controller ||
        oldDelegate.camera != camera ||
        oldDelegate.selectedFaceId != selectedFaceId ||
        oldDelegate.grabbedEdgeIndex != grabbedEdgeIndex ||
        oldDelegate.showDragVector != showDragVector ||
        oldDelegate.dragVectorStart != dragVectorStart ||
        oldDelegate.dragVectorEnd != dragVectorEnd;
  }
}
