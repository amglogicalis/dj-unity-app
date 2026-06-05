import 'package:flutter/material.dart';
import 'package:hybrid_music_room/data/models/room_mode.dart';

/// Pantalla de selección de modo al crear una sala como Host (DJ).
/// El usuario elige entre los 3 modos disponibles antes de entrar a la sala.
class ModeSelectionPage extends StatefulWidget {
  const ModeSelectionPage({super.key});

  @override
  State<ModeSelectionPage> createState() => _ModeSelectionPageState();
}

class _ModeSelectionPageState extends State<ModeSelectionPage>
    with SingleTickerProviderStateMixin {
  RoomMode? _selectedMode;
  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _fadeAnim =
        CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _confirm() {
    if (_selectedMode == null) return;
    Navigator.pushReplacementNamed(
      context,
      '/host',
      arguments: _selectedMode,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0F0F12), Color(0xFF060608)],
          ),
        ),
        child: Stack(
          children: [
            // Ambient glow top-left (pink)
            Positioned(
              top: -80,
              left: -80,
              child: Container(
                width: 320,
                height: 320,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFFC42261).withValues(alpha: 0.18),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            // Ambient glow bottom-right (neon green)
            Positioned(
              bottom: -60,
              right: -60,
              child: Container(
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF39FF14).withValues(alpha: 0.10),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            // Main content
            SafeArea(
              child: FadeTransition(
                opacity: _fadeAnim,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 20),
                      // Back button
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back_ios_new_rounded,
                            color: Colors.white54),
                        alignment: Alignment.centerLeft,
                        padding: EdgeInsets.zero,
                      ),
                      const SizedBox(height: 20),
                      // Header with gradient title
                      ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: [Colors.white, Color(0xFFE0E0E0)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ).createShader(bounds),
                        child: const Text(
                          'ELIGE EL\nMODO DE SALA',
                          style: TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            height: 1.1,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Accent divider line
                      Container(
                        height: 2,
                        width: 48,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFFC42261), Color(0xFF39FF14)],
                          ),
                          borderRadius: BorderRadius.all(Radius.circular(2)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Selecciona cómo quieres que suene la música en tu sala.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                      const SizedBox(height: 32),
                      // Mode cards
                      _ModeCard(
                        mode: RoomMode.youtubeIntegrated,
                        selected: _selectedMode == RoomMode.youtubeIntegrated,
                        onTap: () =>
                            setState(() => _selectedMode = RoomMode.youtubeIntegrated),
                        icon: Icons.play_circle_fill_rounded,
                        accentColor: const Color(0xFFC42261),
                        title: 'YouTube Integrado',
                        subtitle: 'Reproductor YouTube dentro de la app. Sin cuentas.',
                        features: const [
                          'Sin cuenta ni app externa',
                          'Catálogo ilimitado (remixes, rarezas)',
                          'Control total: play, pausa, seek, cola',
                        ],
                        badge: 'RECOMENDADO',
                        badgeColor: const Color(0xFFC42261),
                      ),
                      const SizedBox(height: 14),
                      _ModeCard(
                        mode: RoomMode.spotifyPremium,
                        selected: _selectedMode == RoomMode.spotifyPremium,
                        onTap: () =>
                            setState(() => _selectedMode = RoomMode.spotifyPremium),
                        icon: Icons.tune_rounded,
                        accentColor: const Color(0xFF1DB954),
                        title: 'Spotify Premium',
                        subtitle: 'Control total desde la app. Spotify en segundo plano.',
                        features: const [
                          'Play, pausa, skip desde la app',
                          'Añade a la cola real de Spotify',
                          'Requiere cuenta Premium del DJ',
                        ],
                        badge: 'PREMIUM',
                        badgeColor: const Color(0xFFFFD700),
                      ),
                      const SizedBox(height: 14),
                      _ModeCard(
                        mode: RoomMode.spotifyFree,
                        selected: _selectedMode == RoomMode.spotifyFree,
                        onTap: () =>
                            setState(() => _selectedMode = RoomMode.spotifyFree),
                        icon: Icons.open_in_new_rounded,
                        accentColor: const Color(0xFF39FF14),
                        title: 'Spotify Free',
                        subtitle: 'La app abre la canción en Spotify. El DJ da play manualmente.',
                        features: const [
                          'Sin cuenta Premium necesaria',
                          'Abre Spotify app en móvil o navegador',
                          'Auto-abre la siguiente al saltar',
                        ],
                        badge: 'GRATIS',
                        badgeColor: const Color(0xFF39FF14),
                      ),
                      const SizedBox(height: 32),
                      // Confirm button
                      AnimatedOpacity(
                        opacity: _selectedMode != null ? 1.0 : 0.35,
                        duration: const Duration(milliseconds: 300),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            gradient: _selectedMode != null
                                ? const LinearGradient(
                                    colors: [Color(0xFFC42261), Color(0xFF9B1D4F)],
                                  )
                                : null,
                            color: _selectedMode != null
                                ? null
                                : Colors.white.withValues(alpha: 0.05),
                            boxShadow: _selectedMode != null
                                ? [
                                    BoxShadow(
                                      color: const Color(0xFFC42261).withValues(alpha: 0.4),
                                      blurRadius: 20,
                                      offset: const Offset(0, 6),
                                    )
                                  ]
                                : [],
                          ),
                          child: ElevatedButton(
                            onPressed: _selectedMode != null ? _confirm : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              foregroundColor: Colors.white,
                              shadowColor: Colors.transparent,
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                              elevation: 0,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.rocket_launch_rounded, size: 20),
                                const SizedBox(width: 10),
                                Flexible(
                                  child: Text(
                                    _selectedMode != null
                                        ? 'Crear Sala · ${_selectedMode!.displayName}'
                                        : 'Selecciona un modo',
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 36),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Widget: Tarjeta de selección de modo
// ─────────────────────────────────────────────
class _ModeCard extends StatelessWidget {
  final RoomMode mode;
  final bool selected;
  final VoidCallback onTap;
  final IconData icon;
  final Color accentColor;
  final String title;
  final String subtitle;
  final List<String> features;
  final String badge;
  final Color badgeColor;

  const _ModeCard({
    required this.mode,
    required this.selected,
    required this.onTap,
    required this.icon,
    required this.accentColor,
    required this.title,
    required this.subtitle,
    required this.features,
    required this.badge,
    required this.badgeColor,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: selected
            ? accentColor.withValues(alpha: 0.07)
            : Colors.white.withValues(alpha: 0.025),
        border: Border.all(
          color: selected
              ? accentColor.withValues(alpha: 0.6)
              : Colors.white.withValues(alpha: 0.06),
          width: selected ? 1.5 : 1.0,
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: accentColor.withValues(alpha: 0.18),
                  blurRadius: 24,
                  spreadRadius: 0,
                )
              ]
            : [],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accentColor.withValues(alpha: 0.10),
                    border: Border.all(
                      color: accentColor.withValues(alpha: selected ? 0.5 : 0.2),
                    ),
                  ),
                  child: Icon(icon, color: accentColor, size: 22),
                ),
                const SizedBox(width: 14),
                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Title + badge in a Wrap to prevent overflow ──
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: selected ? Colors.white : Colors.white70,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: badgeColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: badgeColor.withValues(alpha: 0.4)),
                            ),
                            child: Text(
                              badge,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                color: badgeColor,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.45),
                        ),
                      ),
                      const SizedBox(height: 10),
                      ...features.map(
                        (f) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              Icon(Icons.check_circle_rounded,
                                  size: 12,
                                  color: selected
                                      ? accentColor
                                      : Colors.white24),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  f,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: selected
                                        ? Colors.white70
                                        : Colors.white30,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                // Selection indicator
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected
                        ? accentColor
                        : Colors.white.withValues(alpha: 0.05),
                    border: Border.all(
                      color: selected
                          ? accentColor
                          : Colors.white.withValues(alpha: 0.15),
                    ),
                    boxShadow: selected
                        ? [
                            BoxShadow(
                              color: accentColor.withValues(alpha: 0.5),
                              blurRadius: 8,
                            )
                          ]
                        : [],
                  ),
                  child: selected
                      ? Icon(Icons.check_rounded,
                          size: 14,
                          color: accentColor.computeLuminance() > 0.4
                              ? Colors.black
                              : Colors.white)
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
