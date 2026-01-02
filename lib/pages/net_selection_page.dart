import 'package:flutter/material.dart';

import '../net/net_model.dart';
import 'net_builder_page.dart';
import 'netfold_page.dart';

/// 展開図選択画面
class NetSelectionPage extends StatelessWidget {
  const NetSelectionPage({super.key});

  @override
  Widget build(BuildContext context) {
    final patterns = NetPatternInfo.allPatterns;
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
              const SizedBox(height: 24),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final crossAxisCount = constraints.maxWidth > 600 ? 4 : 2;
                    return GridView.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: 20,
                        mainAxisSpacing: 20,
                        childAspectRatio: 0.85,
                      ),
                      itemCount: patterns.length + 1,
                      itemBuilder: (context, index) {
                        if (index < patterns.length) {
                          return _NetPatternCard(pattern: patterns[index]);
                        }
                        return const _CustomNetCard();
                      },
                    );
                  },
                ),
              ),
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
        Text(
          '展開図を選ぼう',
          style: textTheme.headlineSmall?.copyWith(
            color: const Color(0xFF1E2A44),
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '好きな形を選んでタップしてね',
          style: textTheme.bodyMedium?.copyWith(
            color: const Color(0xFF526274),
          ),
        ),
      ],
    );
  }
}

class _NetPatternCard extends StatelessWidget {
  const _NetPatternCard({required this.pattern});

  final NetPatternInfo pattern;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => _navigateToFold(context),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFE0E5EC)),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: CustomPaint(
                      painter: _NetThumbnailPainter(
                        positions: pattern.thumbnailPositions,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                pattern.displayName,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1E2A44),
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _navigateToFold(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => NetFoldPage(definition: pattern.factory()),
      ),
    );
  }
}

class _CustomNetCard extends StatelessWidget {
  const _CustomNetCard();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => _navigateToBuilder(context),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFE0E5EC)),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.grid_on, size: 48, color: Color(0xFF2563EB)),
                      const SizedBox(height: 8),
                      Text(
                        '自分で作る',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF1E2A44),
                            ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'グリッドで作成',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF526274),
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _navigateToBuilder(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const NetBuilderPage(),
      ),
    );
  }
}

class _NetThumbnailPainter extends CustomPainter {
  _NetThumbnailPainter({required this.positions});

  final List<(int, int)> positions;

  @override
  void paint(Canvas canvas, Size size) {
    if (positions.isEmpty) return;

    // グリッドのサイズを計算
    int maxRow = 0;
    int maxCol = 0;
    for (final (row, col) in positions) {
      if (row > maxRow) maxRow = row;
      if (col > maxCol) maxCol = col;
    }
    final gridRows = maxRow + 1;
    final gridCols = maxCol + 1;

    // セルのサイズを計算（余白を考慮）
    final cellSize = (size.width / gridCols).clamp(0.0, size.height / gridRows);
    final totalWidth = cellSize * gridCols;
    final totalHeight = cellSize * gridRows;
    final offsetX = (size.width - totalWidth) / 2;
    final offsetY = (size.height - totalHeight) / 2;

    final fillPaint = Paint()
      ..color = NetPalette.baseFace
      ..style = PaintingStyle.fill;
    final accentPaint = Paint()
      ..color = NetPalette.accentFace
      ..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..color = const Color(0xFF2563EB)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final centerPos = _centerPosition(positions);
    for (final (row, col) in positions) {
      final rect = Rect.fromLTWH(
        offsetX + col * cellSize + 2,
        offsetY + row * cellSize + 2,
        cellSize - 4,
        cellSize - 4,
      );
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4));
      final paint = (row, col) == centerPos ? accentPaint : fillPaint;
      canvas.drawRRect(rrect, paint);
      canvas.drawRRect(rrect, strokePaint);
    }
  }

  (int, int) _centerPosition(List<(int, int)> positions) {
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

  @override
  bool shouldRepaint(covariant _NetThumbnailPainter oldDelegate) {
    return positions != oldDelegate.positions;
  }
}
