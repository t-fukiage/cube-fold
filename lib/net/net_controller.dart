import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import 'net_model.dart';

class NetController {
  NetController(this.definition) {
    for (final face in definition.faces.values) {
      if (!face.isRoot) {
        _angles[face.id] = 0;
      }
    }
  }

  factory NetController.cubeNet() => NetController(NetDefinition.cubeCrossNet());

  final NetDefinition definition;
  final Map<String, double> _angles = <String, double>{};
  String? _rootOverrideFaceId;
  Matrix4 _rootTransform = Matrix4.identity();

  Iterable<FaceDefinition> get faces => definition.faces.values;

  double angleFor(String faceId) => _angles[faceId] ?? 0;

  String get activeRootId => _rootOverrideFaceId ?? definition.rootFaceId;

  void setAngle(String faceId, double angle) {
    final face = definition.faces[faceId];
    if (face == null || face.isRoot) {
      return;
    }
    _angles[faceId] = angle.clamp(0, 90);
  }

  void resetAngles() {
    _angles.updateAll((key, value) => 0);
  }

  void setRootOverride(String? faceId, Matrix4? worldTransform) {
    _rootOverrideFaceId = faceId;
    if (worldTransform == null) {
      _rootTransform = Matrix4.identity();
    } else {
      _rootTransform = Matrix4.copy(worldTransform);
    }
  }

  Set<String> movingFacesForAngle(String angleFaceId) {
    return _collectMovingFacesForAngle(angleFaceId);
  }

  bool areFacesDirectlyConnected(String a, String b) {
    for (final edge in definition.edges.values) {
      if ((edge.parentFaceId == a && edge.childFaceId == b) ||
          (edge.parentFaceId == b && edge.childFaceId == a)) {
        return true;
      }
    }
    return false;
  }

  Set<String> _collectMovingFacesForAngle(String angleFaceId) {
    final face = definition.faces[angleFaceId];
    if (face == null) {
      return {};
    }
    final EdgeDefinition? hinge = definition.edgeById(face.edgeFromParentId);
    if (hinge == null) {
      return {};
    }

    final Map<String, List<String>> graph = {};
    for (final face in faces) {
      graph[face.id] = <String>[];
    }
    for (final edge in definition.edges.values) {
      if (edge.id == hinge.id) {
        continue;
      }
      graph[edge.parentFaceId]!.add(edge.childFaceId);
      graph[edge.childFaceId]!.add(edge.parentFaceId);
    }

    final Set<String> fixed = {};
    final List<String> stack = [activeRootId];
    while (stack.isNotEmpty) {
      final String current = stack.removeLast();
      if (!fixed.add(current)) {
        continue;
      }
      final List<String> neighbors = graph[current] ?? const [];
      for (final neighbor in neighbors) {
        if (!fixed.contains(neighbor)) {
          stack.add(neighbor);
        }
      }
    }

    final Set<String> moving = {};
    for (final face in faces) {
      if (!fixed.contains(face.id)) {
        moving.add(face.id);
      }
    }
    return moving;
  }


  int? hingeEdgeIndexForFace(String faceId) {
    final face = definition.faces[faceId];
    if (face == null || face.isRoot) {
      return null;
    }
    final edge = definition.edgeById(face.edgeFromParentId);
    if (edge == null) {
      return null;
    }
    final Vector3 offset = Vector3.copy(edge.childOffsetFromHinge);
    final Quaternion inverse = edge.childOrientation.conjugated();
    inverse.normalize();
    inverse.rotate(offset);
    final double ax = offset.x.abs();
    final double ay = offset.y.abs();
    if (ax >= ay) {
      return offset.x >= 0 ? 3 : 1;
    }
    return offset.y >= 0 ? 0 : 2;
  }

  int? hingeEdgeIndexForParentEdge(EdgeDefinition edge) {
    final double x = edge.hingeOrigin.x;
    final double y = edge.hingeOrigin.y;
    if (x.abs() < 1e-6 && y.abs() < 1e-6) {
      return null;
    }
    if (x.abs() >= y.abs()) {
      return x >= 0 ? 1 : 3;
    }
    return y >= 0 ? 2 : 0;
  }

  bool isConnectedEdge(String faceId, int edgeIndex) {
    final int? parentEdgeIndex = hingeEdgeIndexForFace(faceId);
    if (parentEdgeIndex != null && parentEdgeIndex == edgeIndex) {
      return true;
    }
    for (final edge in definition.edges.values) {
      if (edge.parentFaceId != faceId) {
        continue;
      }
      final int? parentSideEdgeIndex = hingeEdgeIndexForParentEdge(edge);
      if (parentSideEdgeIndex == edgeIndex) {
        return true;
      }
    }
    return false;
  }

  ({EdgeDefinition edge, String otherFaceId, bool faceIsChild})? connectionForFaceEdge(
    String faceId,
    int edgeIndex,
  ) {
    final face = definition.faces[faceId];
    if (face == null) {
      return null;
    }

    final int? parentEdgeIndex = hingeEdgeIndexForFace(faceId);
    if (parentEdgeIndex != null && parentEdgeIndex == edgeIndex) {
      final edge = definition.edgeById(face.edgeFromParentId);
      if (edge != null) {
        return (edge: edge, otherFaceId: edge.parentFaceId, faceIsChild: true);
      }
    }

    for (final edge in definition.edges.values) {
      if (edge.parentFaceId != faceId) {
        continue;
      }
      final int? parentSideEdgeIndex = hingeEdgeIndexForParentEdge(edge);
      if (parentSideEdgeIndex == edgeIndex) {
        return (edge: edge, otherFaceId: edge.childFaceId, faceIsChild: false);
      }
    }
    return null;
  }

  Vector3 computeNetCentroid() {
    final worldTransforms = _computeWorldTransforms();
    if (worldTransforms.isEmpty) {
      return Vector3.zero();
    }
    final Vector3 center = Vector3.zero();
    int count = 0;
    for (final face in faces) {
      final Matrix4 worldMatrix = worldTransforms[face.id]!;
      center.add(transformPoint(worldMatrix, Vector3.zero()));
      count++;
    }
    if (count > 0) {
      center.scale(1 / count);
    }
    return center;
  }

  NetRenderSnapshot buildSnapshot(OrbitCamera camera, Size size) {
    final worldTransforms = _computeWorldTransforms();
    final viewMatrix = camera.viewMatrix();
    final projectionMatrix = camera.projectionMatrix(size.aspectRatio);
    final vpMatrix = projectionMatrix * viewMatrix;

    final half = definition.halfFaceSize;
    final localVertices = <Vector3>[
      Vector3(-half, -half, 0),
      Vector3(half, -half, 0),
      Vector3(half, half, 0),
      Vector3(-half, half, 0),
    ];

    final List<FaceProjection> projections = [];
    final Map<String, FaceProjection> faceLookup = {};

    for (final face in faces) {
      final Matrix4 worldMatrix = worldTransforms[face.id]!;
      final List<Vector3> worldVertices = localVertices
          .map((vertex) => transformPoint(worldMatrix, vertex))
          .toList(growable: false);
      final List<Vector3> cameraVertices = worldVertices
          .map((vertex) => transformPoint(viewMatrix, vertex))
          .toList(growable: false);
      final List<Offset> screenVertices = worldVertices
          .map((vertex) => projectToScreen(vertex, vpMatrix, size))
          .toList(growable: false);

      final Path path = Path()..addPolygon(screenVertices, true);
      final double depth = cameraVertices
              .map((vector) => vector.z)
              .fold<double>(0, (prev, value) => prev + value) /
          cameraVertices.length;

      final Vector3 normalWorld = _transformDirection(worldMatrix, Vector3(0, 0, 1))
        ..normalize();
      final Vector3 lightDirection = Vector3(0.35, 0.65, -1)..normalize();
      final double light = math.max(0.0, normalWorld.dot(lightDirection));
      final Color baseColor = face.color;
      final Color highlightColor = Color.lerp(baseColor, Colors.white, 0.4)!;
      final Color fillColor = Color.lerp(baseColor, highlightColor, light)!;

      EdgeProjection? hingeProjection;
      final hinge = definition.edgeById(face.edgeFromParentId);
      if (hinge != null) {
        final Matrix4 parentMatrix = worldTransforms[hinge.parentFaceId]!;
        final Vector3 axisNormalized = Vector3.copy(hinge.hingeAxis)..normalize();
        final Vector3 startLocal = hinge.hingeOrigin + axisNormalized * definition.halfFaceSize;
        final Vector3 endLocal = hinge.hingeOrigin - axisNormalized * definition.halfFaceSize;
        final Offset start = projectToScreen(
          transformPoint(parentMatrix, startLocal),
          vpMatrix,
          size,
        );
        final Offset end = projectToScreen(
          transformPoint(parentMatrix, endLocal),
          vpMatrix,
          size,
        );
        hingeProjection = EdgeProjection(
          id: hinge.id,
          start: start,
          end: end,
        );
      }

      final faceProjection = FaceProjection(
        id: face.id,
        definition: face,
        polygon: screenVertices,
        path: path,
        depth: depth,
        fillColor: fillColor,
        baseColor: baseColor,
        normal: normalWorld,
        hingeEdge: hingeProjection,
        worldMatrix: worldMatrix,
      );

      projections.add(faceProjection);
      faceLookup[face.id] = faceProjection;
    }

    projections.sort((a, b) => a.depth.compareTo(b.depth));

    return NetRenderSnapshot(
      faces: projections,
      faceLookup: faceLookup,
      camera: camera,
      viewMatrix: viewMatrix,
      projectionMatrix: projectionMatrix,
      vpMatrix: vpMatrix,
      size: size,
    );
  }

  Map<String, Matrix4> _computeWorldTransforms() {
    final Map<String, List<EdgeDefinition>> edgesByParent = {};
    final Map<String, List<EdgeDefinition>> edgesByChild = {};
    for (final edge in definition.edges.values) {
      edgesByParent.putIfAbsent(edge.parentFaceId, () => []).add(edge);
      edgesByChild.putIfAbsent(edge.childFaceId, () => []).add(edge);
    }

    final Map<String, Matrix4> world = <String, Matrix4>{};
    final String rootId = activeRootId;
    world[rootId] = Matrix4.copy(_rootTransform);
    final List<String> stack = <String>[rootId];

    while (stack.isNotEmpty) {
      final String currentId = stack.removeLast();
      final Matrix4 currentWorld = world[currentId]!;

      final forwardEdges = edgesByParent[currentId] ?? const <EdgeDefinition>[];
      for (final edge in forwardEdges) {
        final String childId = edge.childFaceId;
        if (world.containsKey(childId)) {
          continue;
        }
        final double angleRad = (_angles[childId] ?? 0) * math.pi / 180;
        final Matrix4 childToParent = _childToParentTransform(edge, angleRad);
        world[childId] = currentWorld * childToParent;
        stack.add(childId);
      }

      final reverseEdges = edgesByChild[currentId] ?? const <EdgeDefinition>[];
      for (final edge in reverseEdges) {
        final String parentId = edge.parentFaceId;
        if (world.containsKey(parentId)) {
          continue;
        }
        final double angleRad = (_angles[currentId] ?? 0) * math.pi / 180;
        final Matrix4 childToParent = _childToParentTransform(edge, angleRad);
        final Matrix4 parentWorld = currentWorld * Matrix4.inverted(childToParent);
        world[parentId] = parentWorld;
        stack.add(parentId);
      }
    }

    return world;
  }

  Matrix4 _childToParentTransform(EdgeDefinition edge, double angleRad) {
    final Vector3 hingeOrigin = edge.hingeOrigin;
    final Matrix4 translateToHinge = Matrix4.identity()
      ..translateByVector3(hingeOrigin);
    final Vector3 offset = edge.childOffsetFromHinge;
    final Matrix4 translateFromHinge = Matrix4.identity()
      ..translateByVector3(offset);
    final Matrix4 orientationMatrix = Matrix4.compose(
      Vector3.zero(),
      edge.childOrientation,
      Vector3.all(1),
    );

    final Vector3 hingeAxis = Vector3.copy(edge.hingeAxis)..normalize();
    final Quaternion rotationQuaternion = Quaternion.axisAngle(hingeAxis, angleRad);
    final Matrix4 rotationMatrix = Matrix4.compose(
      Vector3.zero(),
      rotationQuaternion,
      Vector3.all(1),
    );
    return translateToHinge *
        rotationMatrix *
        translateFromHinge *
        orientationMatrix;
  }

  static Vector3 transformPoint(Matrix4 matrix, Vector3 point) {
    final Vector3 copy = Vector3.copy(point);
    return matrix.transform3(copy);
  }

  static Vector3 _transformDirection(Matrix4 matrix, Vector3 direction) {
    final Vector3 copy = Vector3.copy(direction);
    final double m00 = matrix.entry(0, 0);
    final double m01 = matrix.entry(0, 1);
    final double m02 = matrix.entry(0, 2);
    final double m10 = matrix.entry(1, 0);
    final double m11 = matrix.entry(1, 1);
    final double m12 = matrix.entry(1, 2);
    final double m20 = matrix.entry(2, 0);
    final double m21 = matrix.entry(2, 1);
    final double m22 = matrix.entry(2, 2);
    return Vector3(
      m00 * copy.x + m01 * copy.y + m02 * copy.z,
      m10 * copy.x + m11 * copy.y + m12 * copy.z,
      m20 * copy.x + m21 * copy.y + m22 * copy.z,
    );
  }

  static Offset projectToScreen(
    Vector3 world,
    Matrix4 vpMatrix,
    Size size,
  ) {
    final Vector4 clip = vpMatrix.transform(Vector4(world.x, world.y, world.z, 1));
    final double w = clip.w == 0 ? 1e-6 : clip.w;
    final Vector3 ndc = Vector3(clip.x / w, clip.y / w, clip.z / w);
    final double x = (ndc.x * 0.5 + 0.5) * size.width;
    final double y = (-ndc.y * 0.5 + 0.5) * size.height;
    return Offset(x, y);
  }
}


class OrbitCamera {
  OrbitCamera({
    required this.radius,
    required this.azimuth,
    required this.elevation,
    Vector3? target,
    this.fovY = math.pi / 3,
  }) : target = target ?? Vector3.zero();

  final double radius;
  final double azimuth;
  final double elevation;
  final Vector3 target;
  final double fovY;

  Vector3 get position {
    final double x = radius * math.cos(elevation) * math.sin(azimuth);
    final double y = radius * math.sin(elevation);
    final double z = radius * math.cos(elevation) * math.cos(azimuth);
    return Vector3(x, y, z)..add(target);
  }

  Matrix4 viewMatrix() {
    final Vector3 eye = position;
    final Vector3 up = Vector3(0, 1, 0);
    return makeViewMatrix(eye, target, up);
  }

  Matrix4 projectionMatrix(double aspect) {
    const double near = 0.1;
    const double far = 30;
    return makePerspectiveMatrix(fovY, aspect, near, far);
  }
}

class FaceProjection {
  const FaceProjection({
    required this.id,
    required this.definition,
    required this.polygon,
    required this.path,
    required this.depth,
    required this.fillColor,
    required this.baseColor,
    required this.normal,
    required this.hingeEdge,
    required this.worldMatrix,
  });

  final String id;
  final FaceDefinition definition;
  final List<Offset> polygon;
  final Path path;
  final double depth;
  final Color fillColor;
  final Color baseColor;
  final Vector3 normal;
  final EdgeProjection? hingeEdge;
  final Matrix4 worldMatrix;
}

class EdgeProjection {
  const EdgeProjection({
    required this.id,
    required this.start,
    required this.end,
  });

  final String id;
  final Offset start;
  final Offset end;
}

class NetRenderSnapshot {
  const NetRenderSnapshot({
    required this.faces,
    required this.faceLookup,
    required this.camera,
    required this.viewMatrix,
    required this.projectionMatrix,
    required this.vpMatrix,
    required this.size,
  });

  final List<FaceProjection> faces;
  final Map<String, FaceProjection> faceLookup;
  final OrbitCamera camera;
  final Matrix4 viewMatrix;
  final Matrix4 projectionMatrix;
  final Matrix4 vpMatrix;
  final Size size;

  FaceProjection? findFaceAt(Offset point) {
    for (final face in faces.reversed) {
      if (face.path.contains(point)) {
        return face;
      }
    }
    return null;
  }

  FaceProjection? operator [](String faceId) => faceLookup[faceId];
}
