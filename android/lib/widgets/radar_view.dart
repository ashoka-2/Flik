import 'dart:math';
import 'package:flutter/material.dart';
import '../models/peer.dart';
import '../theme/tokens.dart';

// Renders the spatial semicircle radar arc with peer bubbles placed at angles -60 to +60 degrees.
class RadarView extends StatelessWidget {
  final List<DiscoveredPeer> peers;
  final String? lockedPeerId;
  final double compassHeading;
  final void Function(DiscoveredPeer peer) onPeerTap;
  final void Function(DiscoveredPeer peer, double newAngle)? onPeerDrag;
  final VoidCallback? onSendToAll;

  const RadarView({
    super.key,
    required this.peers,
    this.lockedPeerId,
    this.compassHeading = 0.0,
    required this.onPeerTap,
    this.onPeerDrag,
    this.onSendToAll,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final centerX = width / 2;
        final centerY = height - 20; // Base of arc
        final radius = min(width * 0.42, height * 0.75);

        return Stack(
          alignment: Alignment.center,
          children: [
            // Arc Painter
            CustomPaint(
              size: Size(width, height),
              painter: _RadarArcPainter(
                centerX: centerX,
                centerY: centerY,
                radius: radius,
              ),
            ),

            // Peer bubbles
            for (final peer in peers) _buildPeerBubble(peer, centerX, centerY, radius),

            // Center device indicator ("You")
            Positioned(
              left: centerX - 24,
              top: centerY - 24,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: FlikTokens.raised,
                  shape: BoxShape.circle,
                  border: Border.all(color: FlikTokens.line, width: 2),
                ),
                child: const Icon(Icons.phone_android, size: 22, color: FlikTokens.text),
              ),
            ),

            // "Send to All (N)" button if multiple peers
            if (peers.length > 1 && onSendToAll != null)
              Positioned(
                bottom: 8,
                child: OutlinedButton(
                  onPressed: onSendToAll,
                  style: OutlinedButton.styleFrom(
                    backgroundColor: FlikTokens.surface,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                  child: Text(
                    'Send to All (${peers.length})',
                    style: const TextStyle(fontSize: 13, color: FlikTokens.accentSoft),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildPeerBubble(DiscoveredPeer peer, double centerX, double centerY, double radius) {
    // Convert angle in degrees (-60 to +60) to polar coordinates
    // 0 deg is straight up (-pi / 2)
    final angleRad = (peer.angle - 90) * (pi / 180);
    final bubbleX = centerX + radius * cos(angleRad);
    final bubbleY = centerY + radius * sin(angleRad);
    final isLocked = peer.deviceId == lockedPeerId;

    return Positioned(
      left: bubbleX - 32,
      top: bubbleY - 32,
      child: GestureDetector(
        onTap: () => onPeerTap(peer),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: FlikTokens.fastMotion,
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: isLocked ? FlikTokens.accent : FlikTokens.surface,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isLocked ? Colors.white : FlikTokens.line,
                  width: isLocked ? 2 : 1,
                ),
                boxShadow: isLocked
                    ? [
                        BoxShadow(
                          color: FlikTokens.accent.withOpacity(0.4),
                          blurRadius: 16,
                          spreadRadius: 2,
                        )
                      ]
                    : [],
              ),
              child: Icon(
                peer.platform == 'windows' ? Icons.desktop_windows : Icons.phone_android,
                color: isLocked ? Colors.white : FlikTokens.text,
                size: 24,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: FlikTokens.raised,
                borderRadius: BorderRadius.circular(FlikTokens.radiusPill),
              ),
              child: Text(
                peer.deviceName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: FlikTokens.text),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RadarArcPainter extends CustomPainter {
  final double centerX;
  final double centerY;
  final double radius;

  _RadarArcPainter({
    required this.centerX,
    required this.centerY,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final arcPaint = Paint()
      ..color = FlikTokens.line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // Draw main semicircle arc from 210 deg to 330 deg (-60 to +60)
    canvas.drawArc(
      Rect.fromCircle(center: Offset(centerX, centerY), radius: radius),
      pi * 1.15,
      pi * 0.7,
      false,
      arcPaint,
    );

    // Inner subtle guide circle
    final innerPaint = Paint()
      ..color = FlikTokens.line.withOpacity(0.06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas.drawArc(
      Rect.fromCircle(center: Offset(centerX, centerY), radius: radius * 0.55),
      pi * 1.15,
      pi * 0.7,
      false,
      innerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RadarArcPainter oldDelegate) {
    return oldDelegate.centerX != centerX || oldDelegate.centerY != centerY || oldDelegate.radius != radius;
  }
}
