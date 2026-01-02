import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' show Matrix4, Vector2, Vector3;

import '../net/net_controller.dart';
import '../net/net_model.dart';
import '../net/net_painter.dart';

class NetFoldPage extends StatefulWidget {
  const NetFoldPage({super.key, required this.definition});

  final NetDefinition definition;

  @override
  State<NetFoldPage> createState() => _NetFoldPageState();
}

class _NetFoldPageState extends State<NetFoldPage> with TickerProviderStateMixin {
  static const double _minCameraRadius = 3.5;
  static const double _maxCameraRadius = 11.0;
  static const double _defaultCameraRadius = 6.2;
  static const double _orbitSensitivity = 0.008;
  static const double _initialCameraAzimuth = math.pi / 3;
  static const double _initialCameraElevation = math.pi / 6;
  static const double _maxCameraElevation = math.pi / 2 - 0.01;

  late final NetController _controller;
  NetRenderSnapshot? _latestSnapshot;
  String? _selectedFaceId;

  double _cameraAzimuth = _initialCameraAzimuth;
  double _cameraElevation = _initialCameraElevation;
  double _cameraRadius = _defaultCameraRadius;
  Size? _lastFitSize;

  int _pointerCount = 0;
  double _lastScale = 1.0;
  Offset? _lastPointerPosition;
  bool _isSingleFingerOrbit = false;
  Vector2? _dragPerpendicular;
  String? _activeFaceId;
  String? _activeAngleFaceId;
  double? _maxFoldAngle;
  
  /// 掴んでいるエッジのインデックス (0=top, 1=right, 2=bottom, 3=left)
  int? _grabbedEdgeIndex;

  late final AnimationController _snapController;
  VoidCallback? _snapListener;
  double? _snapStartAngle;
  double? _snapEndAngle;
  String? _snapFaceId;
  Timer? _idleCheckTimer;
  late final AnimationController _celebrationController;
  final math.Random _random = math.Random();
  List<_SparkleParticle> _sparkles = [];
  bool _isCubeComplete = false;

  @override
  void initState() {
    super.initState();
    _controller = NetController(widget.definition);
    _snapController = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
    _celebrationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
  }

  @override
  void dispose() {
    if (_snapListener != null) {
      _snapController.removeListener(_snapListener!);
    }
    _snapController.dispose();
    _idleCheckTimer?.cancel();
    _celebrationController.dispose();
    super.dispose();
  }

  OrbitCamera get _camera => OrbitCamera(
        radius: _cameraRadius,
        azimuth: _cameraAzimuth,
        elevation: _cameraElevation,
        target: _controller.computeNetCentroid(),
      );

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final horizontalPadding = media.size.width > 900 ? 80.0 : 28.0;
    final verticalPadding = media.size.height > 700 ? 32.0 : 20.0;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: verticalPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context),
              const SizedBox(height: 20),
              Expanded(
                child: Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        _scheduleInitialCameraFit(constraints.biggest);
                        return SizedBox.expand(
                          child: Stack(
                            children: [
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onScaleStart: _handleScaleStart,
                                onScaleUpdate: _handleScaleUpdate,
                                onScaleEnd: _handleScaleEnd,
                                child: CustomPaint(
                                  painter: NetPainter(
                                    controller: _controller,
                                    camera: _camera,
                                    selectedFaceId: _selectedFaceId,
                                    grabbedEdgeIndex: _grabbedEdgeIndex,
                                    showDragVector: false,
                                    dragVectorStart: null,
                                    dragVectorEnd: null,
                                    onSnapshot: (snapshot) => _latestSnapshot = snapshot,
                                  ),
                                  child: const SizedBox.expand(),
                                ),
                              ),
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: _CelebrationOverlay(
                                    animation: _celebrationController,
                                    sparkles: _sparkles,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _buildFooter(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFF1E2A44)),
              tooltip: '戻る',
            ),
            const SizedBox(width: 8),
            Text(
              '立方体を作ろう',
              style: textTheme.headlineSmall?.copyWith(
                color: const Color(0xFF1E2A44),
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: const [
            _GuideChip(icon: Icons.pan_tool_alt, label: '面をドラッグで折る'),
            _GuideChip(icon: Icons.rotate_left, label: '空き領域を1本指で回転'),
            _GuideChip(icon: Icons.zoom_in, label: '2本指で拡大・縮小'),
          ],
        ),
      ],
    );
  }

  Widget _buildFooter(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final selectedFace = _selectedFaceId != null ? _controller.definition.faces[_selectedFaceId!] : null;
    final String? angleFaceId = _activeAngleFaceId ??
        (selectedFace?.edgeFromParentId != null ? selectedFace!.id : null);
    final double? angle = angleFaceId != null ? _controller.angleFor(angleFaceId) : null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FilledButton(
          onPressed: _handleReset,
          child: const Text('リセット'),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE0E5EC)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      selectedFace == null ? Icons.info_outline : Icons.crop_square,
                      color: const Color(0xFF2563EB),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      selectedFace == null
                          ? '面をドラッグして折ってみよう'
                          : angle == null
                              ? '${selectedFace.displayName} をドラッグ中'
                              : '${selectedFace.displayName} の角度',
                      style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: angle == null
                      ? Text(
                          '好きな面をドラッグして折ってみよう！',
                          key: const ValueKey('guide'),
                          style: textTheme.bodyMedium?.copyWith(color: const Color(0xFF526274)),
                        )
                      : Text(
                          '${angle.toStringAsFixed(0)}°（0°・90°にスナップ）',
                          key: const ValueKey('angle'),
                          style: textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF1D4ED8),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _handleReset() {
    _controller.resetAngles();
    _controller.setRootOverride(null, null);
    _idleCheckTimer?.cancel();
    _resetCelebration();
    setState(() {});
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _pointerCount = details.pointerCount;
    _lastScale = 1.0;
    _idleCheckTimer?.cancel();
    _isSingleFingerOrbit = false;
    if (_pointerCount == 1) {
      if (_shouldStartOrbit(details.localFocalPoint)) {
        _cancelSnapListener();
        _clearActiveFold();
        _isSingleFingerOrbit = true;
      } else {
        _beginFold(details.localFocalPoint);
      }
    } else {
      _cancelSnapListener();
      _clearActiveFold();
    }
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    if (_pointerCount != details.pointerCount) {
      _pointerCount = details.pointerCount;
      if (_pointerCount >= 2) {
        _isSingleFingerOrbit = false;
        _clearActiveFold();
      } else if (_pointerCount == 1 &&
          _activeFaceId == null &&
          _shouldStartOrbit(details.localFocalPoint)) {
        _isSingleFingerOrbit = true;
      }
    }
    if (_pointerCount >= 2) {
      _updateCamera(details);
      return;
    }
    if (_pointerCount == 1 && _isSingleFingerOrbit) {
      _updateCameraOrbit(details.focalPointDelta);
      return;
    }
    if (_pointerCount == 1 &&
        _activeFaceId != null &&
        _activeAngleFaceId != null &&
        _lastPointerPosition != null &&
        _grabbedEdgeIndex != null) {
      final Offset pointer = details.localFocalPoint;
      final Offset delta = pointer - _lastPointerPosition!;
      final Vector2 deltaVector = Vector2(delta.dx, delta.dy);
      final Vector2? computedDirection =
          _computeDragDirectionBySimulation(_activeFaceId!, _activeAngleFaceId!, _grabbedEdgeIndex!);
      final Vector2? dragDirection = computedDirection ?? _dragPerpendicular;
      if (dragDirection == null) {
        _lastPointerPosition = pointer;
        setState(() {});
        return;
      }
      _dragPerpendicular = dragDirection;
      final double signedDistance = _computeSignedDragDistance(deltaVector, dragDirection);
      const double pixelsPerDegree = 2.4;
      final double deltaAngle = signedDistance / pixelsPerDegree;
      final double currentAngle = _controller.angleFor(_activeAngleFaceId!);
      final double limit = _maxFoldAngle ?? 90.0;
      final double rawAngle = currentAngle + deltaAngle;
      final double newAngle = rawAngle.clamp(0.0, limit);
      _controller.setAngle(_activeAngleFaceId!, newAngle);
      _lastPointerPosition = pointer;
      _scheduleIdleCompletionCheck();
      setState(() {});
    }
  }

  void _handleScaleEnd(ScaleEndDetails details) {
    _idleCheckTimer?.cancel();
    bool startedSnap = false;
    if (_pointerCount == 1 && _activeAngleFaceId != null) {
      startedSnap = _startSnapAnimation(_activeAngleFaceId!);
    }
    _pointerCount = 0;
    _isSingleFingerOrbit = false;
    _clearActiveFold();
    if (!startedSnap) {
      _checkCubeCompletion();
    }
  }

  void _beginFold(Offset focalPoint) {
    final snapshot = _latestSnapshot;
    if (snapshot == null) {
      _activeFaceId = null;
      _activeAngleFaceId = null;
      _grabbedEdgeIndex = null;
      return;
    }
    _activeAngleFaceId = null;

    // 指がどの面の上にあるかを判定 → その面が動く
    final faceAtPointer = snapshot.findFaceAt(focalPoint);
    if (faceAtPointer == null) {
      _activeFaceId = null;
      _activeAngleFaceId = null;
      _grabbedEdgeIndex = null;
      return;
    }

    final polygon = faceAtPointer.polygon;
    if (polygon.length < 4) {
      _activeFaceId = null;
      _activeAngleFaceId = null;
      _grabbedEdgeIndex = null;
      return;
    }

    // 現在選択できるエッジのうち、タッチ位置から最も近いエッジを判定
    final int? grabbedEdge =
        _findNearestGrabbableEdgeIndex(focalPoint, polygon, faceAtPointer.id);
    if (grabbedEdge == null) {
      _clearActiveFold();
      return;
    }

    _selectedFaceId = faceAtPointer.id;
    final int axisEdge = (grabbedEdge + 2) % 4;
    final connection = _controller.connectionForFaceEdge(faceAtPointer.id, axisEdge);
    if (connection == null) {
      _clearActiveFold();
      return;
    }
    final anchorFace = snapshot[connection.otherFaceId];
    if (anchorFace != null) {
      _controller.setRootOverride(connection.otherFaceId, anchorFace.worldMatrix);
    }
    final String angleFaceId = connection.edge.childFaceId;
    
    final double currentAngle = _controller.angleFor(angleFaceId);
    _maxFoldAngle = _computeFoldLimit(angleFaceId, currentAngle);

    // 動的シミュレーション: 角度を増やしたときに掴んだエッジがどの方向に動くかを計算
    final dragDirection =
        _computeDragDirectionBySimulation(faceAtPointer.id, angleFaceId, grabbedEdge);
    if (dragDirection == null) {
      _activeFaceId = null;
      _activeAngleFaceId = null;
      _grabbedEdgeIndex = null;
      return;
    }

    _cancelSnapListener();
    _activeFaceId = faceAtPointer.id;
    _activeAngleFaceId = angleFaceId;
    _lastPointerPosition = focalPoint;
    _dragPerpendicular = dragDirection;
    _grabbedEdgeIndex = grabbedEdge;
    setState(() {});
  }

  /// 動的シミュレーションでドラッグ方向を計算
  /// 角度を増やしたときに掴んだエッジの中心がスクリーン上でどう動くかを計算
  Vector2? _computeDragDirectionBySimulation(
    String observedFaceId,
    String angleFaceId,
    int grabbedEdge,
  ) {
    final snapshot = _latestSnapshot;
    if (snapshot == null) return null;

    final double currentAngle = _controller.angleFor(angleFaceId);
    const double epsilon = 5.0;

    // 現在の掴んだエッジの中心
    final Offset currentEdgeCenter =
        _computeEdgeCenterScreen(observedFaceId, angleFaceId, currentAngle, grabbedEdge);

    // 角度を増やした場合の掴んだエッジの中心
    final double testAngle = (currentAngle + epsilon).clamp(0.0, 90.0);
    if ((testAngle - currentAngle).abs() < 0.5) {
      // 90°に達している場合は減らす方向でテスト
      final double minusAngle = (currentAngle - epsilon).clamp(0.0, 90.0);
      final Offset minusEdgeCenter =
          _computeEdgeCenterScreen(observedFaceId, angleFaceId, minusAngle, grabbedEdge);
      final Offset direction = currentEdgeCenter - minusEdgeCenter;
      if (direction.distanceSquared < 0.01) return null;
      return Vector2(direction.dx, direction.dy)..normalize();
    }

    final Offset testEdgeCenter =
        _computeEdgeCenterScreen(observedFaceId, angleFaceId, testAngle, grabbedEdge);

    // 角度を増やす方向 = スクリーン上での移動方向
    final Offset direction = testEdgeCenter - currentEdgeCenter;
    if (direction.distanceSquared < 0.01) return null;

    return Vector2(direction.dx, direction.dy)..normalize();
  }

  /// 指定した角度での掴んだエッジの中心のスクリーン座標を計算
  Offset _computeEdgeCenterScreen(
    String observedFaceId,
    String angleFaceId,
    double angle,
    int edgeIndex,
  ) {
    final snapshot = _latestSnapshot;
    if (snapshot == null) return Offset.zero;

    final double originalAngle = _controller.angleFor(angleFaceId);
    _controller.setAngle(angleFaceId, angle);

    final tempSnapshot = _controller.buildSnapshot(_camera, snapshot.size);
    final tempFace = tempSnapshot[observedFaceId];

    _controller.setAngle(angleFaceId, originalAngle);

    if (tempFace == null || tempFace.polygon.length < 4) return Offset.zero;

    return _edgeCenter(tempFace.polygon, edgeIndex);
  }

  double _computeFoldLimit(String angleFaceId, double currentAngle) {
    final bool wouldOverlap = _wouldOverlapAtAngle(angleFaceId, 90.0);
    if (!wouldOverlap) {
      return 90.0;
    }
    const double limit = 75.0;
    return math.max(limit, currentAngle);
  }

  bool _wouldOverlapAtAngle(String angleFaceId, double angle) {
    final snapshot = _latestSnapshot;
    if (snapshot == null) return false;
    final double original = _controller.angleFor(angleFaceId);
    _controller.setAngle(angleFaceId, angle);
    final tempSnapshot = _controller.buildSnapshot(_camera, snapshot.size);
    _controller.setAngle(angleFaceId, original);

    final movingFaces = _controller.movingFacesForAngle(angleFaceId);
    if (movingFaces.isEmpty) return false;
    final double epsPos = _controller.definition.faceSize * 0.01;
    const double parallelThreshold = 0.995;

    for (final movingId in movingFaces) {
      final moving = tempSnapshot[movingId];
      if (moving == null) continue;
      final Vector3 centerA = NetController.transformPoint(moving.worldMatrix, Vector3.zero());
      final Vector3 normalA = _faceNormal(moving.worldMatrix, centerA);
      for (final face in tempSnapshot.faces) {
        if (movingFaces.contains(face.id)) {
          continue;
        }
        if (_controller.areFacesDirectlyConnected(movingId, face.id)) {
          continue;
        }
        final Vector3 centerB = NetController.transformPoint(face.worldMatrix, Vector3.zero());
        if ((centerB - centerA).length > epsPos) {
          continue;
        }
        final Vector3 normalB = _faceNormal(face.worldMatrix, centerB);
        if (normalA.dot(normalB).abs() < parallelThreshold) {
          continue;
        }
        return true;
      }
    }
    return false;
  }

  Vector3 _faceNormal(Matrix4 world, Vector3 center) {
    final Vector3 tip = NetController.transformPoint(world, Vector3(0, 0, 1));
    final Vector3 normal = Vector3.copy(tip)..sub(center);
    normal.normalize();
    return normal;
  }

  /// 選択可能なエッジの中で、タッチ位置から最も近いエッジのインデックスを返す
  int? _findNearestGrabbableEdgeIndex(Offset point, List<Offset> polygon, String faceId) {
    double minDist = double.infinity;
    int? nearestEdge;

    for (int i = 0; i < 4; i++) {
      if (!_isEdgeGrabbable(faceId, i)) {
        continue;
      }
      final Offset start = polygon[i];
      final Offset end = polygon[(i + 1) % 4];
      final double dist = _distanceToLineSegment(point, start, end);
      if (dist < minDist) {
        minDist = dist;
        nearestEdge = i;
      }
    }

    return nearestEdge;
  }

  /// 掴んだエッジの反対側に回転軸が存在するかどうか
  bool _isEdgeGrabbable(String faceId, int edgeIndex) {
    final int axisEdge = (edgeIndex + 2) % 4;
    return _controller.connectionForFaceEdge(faceId, axisEdge) != null;
  }

  /// 点から線分への最短距離を計算
  double _distanceToLineSegment(Offset point, Offset start, Offset end) {
    final Offset line = end - start;
    final double lineLengthSquared = line.distanceSquared;
    if (lineLengthSquared < 0.001) {
      return (point - start).distance;
    }
    
    // 線分上の最近点を求めるためのパラメータt（0-1にクランプ）
    double t = ((point - start).dx * line.dx + (point - start).dy * line.dy) / lineLengthSquared;
    t = t.clamp(0.0, 1.0);
    
    final Offset projection = Offset(
      start.dx + t * line.dx,
      start.dy + t * line.dy,
    );
    
    return (point - projection).distance;
  }

  /// ドラッグ方向の「折る/開く」2方向に寄せて距離を算出
  double _computeSignedDragDistance(Vector2 deltaVector, Vector2 dragDirection) {
    final double length = deltaVector.length;
    if (length < 0.001) {
      return 0.0;
    }
    final double dot = deltaVector.dot(dragDirection);
    if (dot.abs() < 0.0001) {
      return 0.0;
    }
    return dot >= 0 ? length : -length;
  }

  /// エッジの中心点を計算
  Offset _edgeCenter(List<Offset> polygon, int edgeIndex) {
    final Offset start = polygon[edgeIndex];
    final Offset end = polygon[(edgeIndex + 1) % 4];
    return Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
  }

  void _updateCamera(ScaleUpdateDetails details) {
    final Offset delta = details.focalPointDelta;
    setState(() {
      _applyOrbitDelta(delta);

      final double scale = details.scale;
      final double deltaScale = scale / _lastScale;
      _cameraRadius = (_cameraRadius / deltaScale).clamp(_minCameraRadius, _maxCameraRadius);
      _lastScale = scale;
    });
  }

  void _updateCameraOrbit(Offset delta) {
    if (delta == Offset.zero) return;
    setState(() {
      _applyOrbitDelta(delta);
    });
  }

  void _applyOrbitDelta(Offset delta) {
    _cameraAzimuth -= delta.dx * _orbitSensitivity;
    _cameraElevation += delta.dy * _orbitSensitivity;
    _cameraElevation = _cameraElevation.clamp(-_maxCameraElevation, _maxCameraElevation);
    _cameraAzimuth = _wrapAngle(_cameraAzimuth);
  }

  double _wrapAngle(double angle) {
    const double twoPi = math.pi * 2;
    angle = angle % twoPi;
    if (angle > math.pi) {
      angle -= twoPi;
    } else if (angle < -math.pi) {
      angle += twoPi;
    }
    return angle;
  }

  bool _shouldStartOrbit(Offset point) {
    final snapshot = _latestSnapshot;
    if (snapshot == null) {
      return true;
    }
    return snapshot.findFaceAt(point) == null;
  }

  void _scheduleInitialCameraFit(Size size) {
    if (size.isEmpty) return;
    if (_lastFitSize == size) return;
    _lastFitSize = size;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final double fittedRadius = _computeFittedRadius(size);
      if ((fittedRadius - _cameraRadius).abs() < 0.01) return;
      setState(() {
        _cameraRadius = fittedRadius;
      });
    });
  }

  double _computeFittedRadius(Size size) {
    double radius = _cameraRadius;
    for (int i = 0; i < 2; i++) {
      final camera = OrbitCamera(
        radius: radius,
        azimuth: _cameraAzimuth,
        elevation: _cameraElevation,
      );
      final snapshot = _controller.buildSnapshot(camera, size);
      final double scale = _requiredScaleToFit(snapshot, size);
      if (scale <= 1.0) {
        break;
      }
      radius = (radius * scale * 1.06).clamp(_minCameraRadius, _maxCameraRadius);
    }
    return radius;
  }

  double _requiredScaleToFit(NetRenderSnapshot snapshot, Size size) {
    if (snapshot.faces.isEmpty) return 1.0;
    final double halfWidth = size.width / 2;
    final double halfHeight = size.height / 2;
    const double padding = 24.0;
    final double availableX = math.max(1.0, halfWidth - padding);
    final double availableY = math.max(1.0, halfHeight - padding);
    double maxAbsX = 0;
    double maxAbsY = 0;

    for (final face in snapshot.faces) {
      for (final point in face.polygon) {
        final double dx = point.dx - halfWidth;
        final double dy = point.dy - halfHeight;
        maxAbsX = math.max(maxAbsX, dx.abs());
        maxAbsY = math.max(maxAbsY, dy.abs());
      }
    }

    final double scaleX = maxAbsX / availableX;
    final double scaleY = maxAbsY / availableY;
    return math.max(scaleX, scaleY);
  }

  bool _startSnapAnimation(String faceId) {
    final double current = _controller.angleFor(faceId);
    final double rawTarget = _nearestSnapAngle(current);
    final double limit = _maxFoldAngle ?? 90.0;
    final double target = rawTarget > limit ? limit : rawTarget;
    if ((current - target).abs() < 0.5) {
      _controller.setAngle(faceId, target);
      setState(() {});
      return false;
    }

    _cancelSnapListener();
    _snapFaceId = faceId;
    _snapStartAngle = current;
    _snapEndAngle = target;
    final int duration = (140 + (current - target).abs() * 3).clamp(140, 260).round();
    _snapController.duration = Duration(milliseconds: duration);

    void listener() {
      final double t = Curves.easeOut.transform(_snapController.value);
      final double angle = ui.lerpDouble(_snapStartAngle, _snapEndAngle, t)!;
      _controller.setAngle(faceId, angle);
      if (mounted) {
        setState(() {});
      }
    }

    _snapListener = listener;
    _snapController.addListener(listener);
    _snapController.forward(from: 0).whenComplete(() {
      if (!mounted) return;
      _controller.setAngle(faceId, _snapEndAngle!);
      setState(() {});
      _cancelSnapListener();
      _checkCubeCompletion();
    });
    return true;
  }

  void _cancelSnapListener() {
    if (_snapListener != null) {
      _snapController.removeListener(_snapListener!);
      _snapListener = null;
    }
    if (_snapFaceId != null && _snapEndAngle != null) {
      _controller.setAngle(_snapFaceId!, _snapEndAngle!);
    }
    _snapFaceId = null;
  }

  double _nearestSnapAngle(double angle) {
    const snaps = [0.0, 90.0];
    double nearest = snaps.first;
    double minDiff = (angle - nearest).abs();
    for (final snap in snaps.skip(1)) {
      final double diff = (angle - snap).abs();
      if (diff < minDiff) {
        minDiff = diff;
        nearest = snap;
      }
    }
    return nearest;
  }

  void _clearActiveFold() {
    _activeFaceId = null;
    _activeAngleFaceId = null;
    _maxFoldAngle = null;
    _dragPerpendicular = null;
    _lastPointerPosition = null;
    _grabbedEdgeIndex = null;
    _selectedFaceId = null;
    setState(() {});
  }

  void _scheduleIdleCompletionCheck() {
    _idleCheckTimer?.cancel();
    _idleCheckTimer = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      if (_pointerCount == 1 && _activeAngleFaceId != null && !_snapController.isAnimating) {
        _checkCubeCompletion();
      }
    });
  }

  void _checkCubeCompletion() {
    if (_snapController.isAnimating) {
      return;
    }
    if (!_areAllAnglesClosed()) {
      _isCubeComplete = false;
      return;
    }
    final snapshot = _buildSnapshotForCheck();
    if (snapshot == null) return;
    final bool isComplete = _isClosedCube(snapshot);
    if (isComplete && !_isCubeComplete) {
      _isCubeComplete = true;
      _playCelebration();
      return;
    }
    if (!isComplete) {
      _isCubeComplete = false;
    }
  }

  bool _areAllAnglesClosed() {
    const double tolerance = 2.0;
    for (final face in _controller.faces) {
      if (face.isRoot) continue;
      final double angle = _controller.angleFor(face.id);
      if ((angle - 90.0).abs() > tolerance) {
        return false;
      }
    }
    return true;
  }

  NetRenderSnapshot? _buildSnapshotForCheck() {
    final Size? size = _latestSnapshot?.size ?? _lastFitSize;
    if (size == null || size.isEmpty) {
      return null;
    }
    return _controller.buildSnapshot(_camera, size);
  }

  bool _isClosedCube(NetRenderSnapshot snapshot) {
    if (snapshot.faces.length != 6) return false;

    final List<Vector3> centers = snapshot.faces
        .map((face) => NetController.transformPoint(face.worldMatrix, Vector3.zero()))
        .toList(growable: false);
    final Vector3 center = Vector3.zero();
    for (final c in centers) {
      center.add(c);
    }
    center.scale(1 / centers.length);

    final double half = _controller.definition.halfFaceSize;
    final double positionTolerance = half * 0.22;
    const double normalAlignment = 0.9;

    for (int i = 0; i < snapshot.faces.length; i++) {
      final face = snapshot.faces[i];
      final Vector3 faceCenter = centers[i];
      final Vector3 offset = Vector3.copy(faceCenter)..sub(center);
      final double distance = offset.length;
      if ((distance - half).abs() > positionTolerance) {
        return false;
      }
      if (distance < 1e-5) return false;
      final Vector3 direction = Vector3.copy(offset)..scale(1 / distance);
      final Vector3 normal = _faceNormal(face.worldMatrix, faceCenter);
      if (direction.dot(normal).abs() < normalAlignment) {
        return false;
      }
    }
    return true;
  }

  void _playCelebration() {
    _sparkles = _generateSparkles();
    if (mounted) {
      setState(() {});
    }
    _celebrationController.forward(from: 0);
  }

  void _resetCelebration() {
    _isCubeComplete = false;
    _sparkles = [];
    _celebrationController.stop();
    _celebrationController.value = 0;
  }

  List<_SparkleParticle> _generateSparkles() {
    const colors = [
      Color(0xFFFFB703),
      Color(0xFFFFC857),
      Color(0xFFFFE08A),
      Color(0xFF93C5FD),
      Color(0xFFA5B4FC),
      Color(0xFFFBBF24),
    ];
    return List<_SparkleParticle>.generate(26, (index) {
      return _SparkleParticle(
        angle: _random.nextDouble() * math.pi * 2,
        speed: 0.7 + _random.nextDouble() * 0.6,
        distance: 0.35 + _random.nextDouble() * 0.65,
        size: 6 + _random.nextDouble() * 6,
        spin: (_random.nextDouble() * 2 - 1) * math.pi,
        delay: _random.nextDouble() * 0.18,
        lifespan: 0.45 + _random.nextDouble() * 0.4,
        color: colors[_random.nextInt(colors.length)],
      );
    });
  }

}

class _CelebrationOverlay extends StatelessWidget {
  const _CelebrationOverlay({
    required this.animation,
    required this.sparkles,
  });

  final Animation<double> animation;
  final List<_SparkleParticle> sparkles;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final double t = animation.value;
        if (t <= 0) {
          return const SizedBox.shrink();
        }
        final double badgeFade = t < 0.72 ? 1.0 : (1 - (t - 0.72) / 0.28).clamp(0.0, 1.0);
        final double badgeScale = 0.85 + 0.25 * Curves.easeOutBack.transform(t.clamp(0.0, 1.0));

        return Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              painter: _CelebrationPainter(
                progress: t,
                sparkles: sparkles,
              ),
              child: const SizedBox.expand(),
            ),
            Opacity(
              opacity: badgeFade,
              child: Transform.scale(
                scale: badgeScale,
                child: child,
              ),
            ),
          ],
        );
      },
      child: const _CelebrationBadge(),
    );
  }
}

class _CelebrationBadge extends StatelessWidget {
  const _CelebrationBadge();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF6B7), Color(0xFFFFD56A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFC14A).withOpacity(0.4),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
        child: Text(
          '完成！',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: const Color(0xFF92400E),
                letterSpacing: 1.4,
              ),
        ),
      ),
    );
  }
}

class _CelebrationPainter extends CustomPainter {
  _CelebrationPainter({
    required this.progress,
    required this.sparkles,
  });

  final double progress;
  final List<_SparkleParticle> sparkles;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;

    final Offset center = size.center(Offset.zero);
    final double baseRadius = math.min(size.width, size.height) * 0.38;
    final double eased = Curves.easeOutCubic.transform(progress.clamp(0.0, 1.0));
    final double fade = (1 - progress).clamp(0.0, 1.0);

    final Paint ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10 * (1 - eased) + 2
      ..color = const Color(0xFFFFD85E).withOpacity(0.5 * fade);
    canvas.drawCircle(center, baseRadius * (0.25 + 0.7 * eased), ringPaint);

    final Paint glowPaint = Paint()
      ..color = const Color(0xFFFFF4B1).withOpacity(0.6 * fade)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 26);
    canvas.drawCircle(center, baseRadius * (0.16 + 0.1 * eased), glowPaint);

    for (final sparkle in sparkles) {
      final double localT =
          ((progress - sparkle.delay) / sparkle.lifespan).clamp(0.0, 1.0);
      if (localT <= 0) continue;
      final double sparkleEase = Curves.easeOutQuad.transform(localT);
      final double sparkleFade = (1 - localT).clamp(0.0, 1.0);
      final Offset direction = Offset(math.cos(sparkle.angle), math.sin(sparkle.angle));
      final Offset pos =
          center + direction * baseRadius * sparkle.distance * sparkleEase * sparkle.speed;
      final Paint sparklePaint = Paint()
        ..color = sparkle.color.withOpacity(0.85 * sparkleFade);
      _drawStar(
        canvas,
        pos,
        sparkle.size * (0.7 + 0.6 * (1 - localT)),
        sparkle.spin * sparkleEase,
        sparklePaint,
      );
    }
  }

  void _drawStar(Canvas canvas, Offset center, double radius, double rotation, Paint paint) {
    const int points = 4;
    final Path path = Path();
    for (int i = 0; i < points * 2; i++) {
      final double angle = rotation + (math.pi / points) * i;
      final double r = i.isEven ? radius : radius * 0.45;
      final Offset point = center + Offset(math.cos(angle), math.sin(angle)) * r;
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _CelebrationPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.sparkles != sparkles;
  }
}

class _SparkleParticle {
  const _SparkleParticle({
    required this.angle,
    required this.speed,
    required this.distance,
    required this.size,
    required this.spin,
    required this.delay,
    required this.lifespan,
    required this.color,
  });

  final double angle;
  final double speed;
  final double distance;
  final double size;
  final double spin;
  final double delay;
  final double lifespan;
  final Color color;
}

class _GuideChip extends StatelessWidget {
  const _GuideChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFE9EFFA),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: const Color(0xFF1D4ED8)),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF32435C),
                ),
          ),
        ],
      ),
    );
  }
}
