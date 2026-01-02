import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../net/net_model.dart';
import 'netfold_page.dart';

typedef GridPos = (int, int);

class NetBuilderPage extends StatefulWidget {
  const NetBuilderPage({super.key});

  @override
  State<NetBuilderPage> createState() => _NetBuilderPageState();
}

class _NetBuilderPageState extends State<NetBuilderPage> {
  static const int _rows = 6;
  static const int _cols = 6;
  static const int _targetFaces = 6;
  static const List<Color> _palette = NetPalette.softColors;

  Color _activeColor = _palette.first;
  Map<GridPos, Color> _selectedColors = <GridPos, Color>{};

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
                    padding: const EdgeInsets.all(28),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final size = math.min(constraints.maxWidth, constraints.maxHeight);
                        final cellSize = size / _cols;
                        return Center(
                          child: SizedBox(
                            width: size,
                            height: size,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTapUp: (details) {
                                final pos = _cellFromOffset(details.localPosition, cellSize);
                                if (pos == null) return;
                                _handleCellTap(pos);
                              },
                              onLongPressStart: (details) {
                                final pos = _cellFromOffset(details.localPosition, cellSize);
                                if (pos == null) return;
                                _handleCellRemove(pos);
                              },
                              child: CustomPaint(
                                painter: _NetGridPainter(
                                  rows: _rows,
                                  cols: _cols,
                                  selectedColors: _selectedColors,
                                ),
                              ),
                            ),
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
              '展開図をつくる',
              style: textTheme.headlineSmall?.copyWith(
                color: const Color(0xFF1E2A44),
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          '色を選んでタップして並べよう',
          style: textTheme.bodyMedium?.copyWith(
            color: const Color(0xFF526274),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: const [
            _GuideChip(icon: Icons.touch_app, label: 'タップで追加・色変更'),
            _GuideChip(icon: Icons.backspace_outlined, label: '長押しで削除'),
            _GuideChip(icon: Icons.link, label: '辺でつながるように配置'),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          '色パレット',
          style: textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: const Color(0xFF1E2A44),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: _palette
              .map(
                (color) => _ColorSwatch(
                  color: color,
                  isSelected: color == _activeColor,
                  onTap: () => _setActiveColor(color),
                ),
              )
              .toList(growable: false),
        ),
      ],
    );
  }

  Widget _buildFooter(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final validation = _validate();
    final countText = '${_selectedColors.length}/$_targetFaces';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFE0E5EC)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(validation.icon, color: validation.accentColor),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      validation.title,
                      style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      validation.detail,
                      style: textTheme.bodyMedium?.copyWith(color: const Color(0xFF526274)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                countText,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: validation.accentColor,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            FilledButton.tonal(
              onPressed: _selectedColors.isEmpty ? null : _handleReset,
              child: const Text('クリア'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: validation.isValid ? _handleBuild : null,
                child: const Text('折る'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  GridPos? _cellFromOffset(Offset local, double cellSize) {
    final col = (local.dx / cellSize).floor();
    final row = (local.dy / cellSize).floor();
    if (row < 0 || row >= _rows || col < 0 || col >= _cols) {
      return null;
    }
    return (row, col);
  }

  void _setActiveColor(Color color) {
    if (color == _activeColor) return;
    setState(() => _activeColor = color);
  }

  void _handleCellTap(GridPos pos) {
    if (_selectedColors.containsKey(pos)) {
      setState(() {
        final next = Map<GridPos, Color>.from(_selectedColors);
        next[pos] = _activeColor;
        _selectedColors = next;
      });
      return;
    }

    if (_selectedColors.length >= _targetFaces) {
      _showSnack('6面まで配置できます');
      return;
    }

    setState(() {
      final next = Map<GridPos, Color>.from(_selectedColors);
      next[pos] = _activeColor;
      _selectedColors = next;
    });
  }

  void _handleCellRemove(GridPos pos) {
    if (!_selectedColors.containsKey(pos)) {
      return;
    }
    setState(() {
      final next = Map<GridPos, Color>.from(_selectedColors)..remove(pos);
      _selectedColors = next;
    });
  }

  void _handleReset() {
    setState(() => _selectedColors = <GridPos, Color>{});
  }

  void _handleBuild() {
    final validation = _validate();
    if (!validation.isValid) return;

    final positions = _selectedColors.keys.toSet();
    final definition = NetDefinition.fromGridPositions(
      positions,
      faceColors: _selectedColors,
    );
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => NetFoldPage(definition: definition),
      ),
    );
  }

  _ValidationInfo _validate() {
    final selected = _selectedColors.keys.toSet();
    if (selected.isEmpty) {
      return const _ValidationInfo(
        isValid: false,
        title: 'まだ配置されていません',
        detail: '6つの面をタップして配置しよう',
        icon: Icons.info_outline,
        accentColor: Color(0xFF2563EB),
      );
    }

    final remaining = _targetFaces - selected.length;
    if (remaining > 0) {
      return _ValidationInfo(
        isValid: false,
        title: 'あと$remaining面',
        detail: '合計6面になるまで追加してね',
        icon: Icons.add_box_outlined,
        accentColor: const Color(0xFF2563EB),
      );
    }

    final isConnected = _isConnected(selected);
    final edgeCount = _edgeCount(selected);

    if (!isConnected) {
      return const _ValidationInfo(
        isValid: false,
        title: 'つながっていません',
        detail: 'すべての面が辺でつながるように配置してね',
        icon: Icons.link_off,
        accentColor: Color(0xFFB45309),
      );
    }

    if (edgeCount > selected.length - 1) {
      return const _ValidationInfo(
        isValid: false,
        title: 'ループがあります',
        detail: 'つながりが多すぎます。辺の数は5本まで。',
        icon: Icons.loop,
        accentColor: Color(0xFFB45309),
      );
    }

    return const _ValidationInfo(
      isValid: true,
      title: '完成！',
      detail: '「折る」を押して次へ進もう',
      icon: Icons.check_circle,
      accentColor: Color(0xFF1D4ED8),
    );
  }

  bool _isConnected(Set<GridPos> cells) {
    if (cells.isEmpty) return false;
    final start = cells.first;
    final queue = <GridPos>[start];
    final visited = <GridPos>{start};
    int index = 0;

    while (index < queue.length) {
      final current = queue[index++];
      for (final neighbor in _neighbors(current)) {
        if (!cells.contains(neighbor)) continue;
        if (!visited.add(neighbor)) continue;
        queue.add(neighbor);
      }
    }

    return visited.length == cells.length;
  }

  int _edgeCount(Set<GridPos> cells) {
    int count = 0;
    for (final pos in cells) {
      final (row, col) = pos;
      if (cells.contains((row, col + 1))) count++;
      if (cells.contains((row + 1, col))) count++;
    }
    return count;
  }

  Iterable<GridPos> _neighbors(GridPos pos) sync* {
    final (row, col) = pos;
    yield (row - 1, col);
    yield (row + 1, col);
    yield (row, col - 1);
    yield (row, col + 1);
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class _ValidationInfo {
  const _ValidationInfo({
    required this.isValid,
    required this.title,
    required this.detail,
    required this.icon,
    required this.accentColor,
  });

  final bool isValid;
  final String title;
  final String detail;
  final IconData icon;
  final Color accentColor;
}

class _NetGridPainter extends CustomPainter {
  const _NetGridPainter({
    required this.rows,
    required this.cols,
    required this.selectedColors,
  });

  final int rows;
  final int cols;
  final Map<GridPos, Color> selectedColors;

  @override
  void paint(Canvas canvas, Size size) {
    final cellSize = size.width / cols;
    final gridPaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..strokeWidth = 1;

    for (int r = 0; r <= rows; r++) {
      final dy = r * cellSize;
      canvas.drawLine(Offset(0, dy), Offset(size.width, dy), gridPaint);
    }
    for (int c = 0; c <= cols; c++) {
      final dx = c * cellSize;
      canvas.drawLine(Offset(dx, 0), Offset(dx, size.height), gridPaint);
    }

    final borderPaint = Paint()
      ..color = const Color(0xFF2563EB)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (final entry in selectedColors.entries) {
      final pos = entry.key;
      final (row, col) = pos;
      final rect = Rect.fromLTWH(col * cellSize, row * cellSize, cellSize, cellSize);
      final fillPaint = Paint()
        ..color = entry.value
        ..style = PaintingStyle.fill;
      canvas.drawRect(rect, fillPaint);
    }

    final selected = selectedColors.keys.toSet();
    for (final pos in selected) {
      final (row, col) = pos;
      final rect = Rect.fromLTWH(col * cellSize, row * cellSize, cellSize, cellSize);

      final bool hasTop = selected.contains((row - 1, col));
      final bool hasBottom = selected.contains((row + 1, col));
      final bool hasLeft = selected.contains((row, col - 1));
      final bool hasRight = selected.contains((row, col + 1));

      if (!hasTop) {
        canvas.drawLine(rect.topLeft, rect.topRight, borderPaint);
      }
      if (!hasRight) {
        canvas.drawLine(rect.topRight, rect.bottomRight, borderPaint);
      }
      if (!hasBottom) {
        canvas.drawLine(rect.bottomLeft, rect.bottomRight, borderPaint);
      }
      if (!hasLeft) {
        canvas.drawLine(rect.topLeft, rect.bottomLeft, borderPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _NetGridPainter oldDelegate) {
    return oldDelegate.rows != rows ||
        oldDelegate.cols != cols ||
        oldDelegate.selectedColors != selectedColors;
  }
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

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const double size = 34;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected ? const Color(0xFF1D4ED8) : const Color(0xFFE2E8F0),
              width: isSelected ? 2.6 : 1.4,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: isSelected
              ? const Icon(Icons.check, size: 18, color: Color(0xFF1D4ED8))
              : null,
        ),
      ),
    );
  }
}
