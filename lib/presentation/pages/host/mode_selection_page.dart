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
        AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
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
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0F0F11), Color(0xFF000000)],
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 24),
                  // Header
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: Colors.white54),
                    alignment: Alignment.centerLeft,
                    padding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'ELIGE EL MODO\nDE SALA',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      height: 1.1,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Selecciona cómo quieres que suene la música en tu sala.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(height: 36),
                  // Tarjetas de modo
                  _ModeCard(
                    mode: RoomMode.spotifyFree,
                    selected: _selectedMode == RoomMode.spotifyFree,
                    onTap: () =>
                        setState(() => _selectedMode = RoomMode.spotifyFree),
                    icon: Icons.open_in_new_rounded,
                    accentColor: const Color(0xFF1DB954),
                    title: 'Spotify Free',
                    subtitle: 'La app abre la canción en Spotify. El DJ da play manualmente.',
                    features: const [
                      'Sin cuenta Premium necesaria',
                      'Abre Spotify app en móvil o navegador',
                      'Auto-abre la siguiente al saltar',
                    ],
                    badge: 'GRATIS',
                    badgeColor: const Color(0xFF1DB954),
                  ),
                  const SizedBox(height: 12),
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
                  const SizedBox(height: 12),
                  _ModeCard(
                    mode: RoomMode.youtubeIntegrated,
                    selected: _selectedMode == RoomMode.youtubeIntegrated,
                    onTap: () =>
                        setState(() => _selectedMode = RoomMode.youtubeIntegrated),
                    icon: Icons.play_circle_fill_rounded,
                    accentColor: const Color(0xFFFF0000),
                    title: 'YouTube Integrado',
                    subtitle: 'Reproductor YouTube dentro de la app. Sin cuentas.',
                    features: const [
                      'Sin cuenta ni app externa',
                      'Catálogo ilimitado (remixes, rarezas)',
                      'Control total: play, pausa, seek, cola',
                    ],
                    badge: 'TODO EN UNO',
                    badgeColor: const Color(0xFFFF0000),
                  ),
                  const SizedBox(height: 28),
                  // Botón confirmar
                  AnimatedOpacity(
                    opacity: _selectedMode != null ? 1.0 : 0.3,
                    duration: const Duration(milliseconds: 300),
                    child: ElevatedButton(
                      onPressed: _selectedMode != null ? _confirm : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFC42261),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        elevation: _selectedMode != null ? 8 : 0,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.rocket_launch_rounded, size: 20),
                          const SizedBox(width: 10),
                          Text(
                            _selectedMode != null
                                ? 'Crear Sala · ${_selectedMode!.displayName}'
                                : 'Selecciona un modo',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
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
        borderRadius: BorderRadius.circular(20),
        color: selected
            ? accentColor.withValues(alpha: 0.08)
            : Colors.white.withValues(alpha: 0.02),
        border: Border.all(
          color: selected
              ? accentColor.withValues(alpha: 0.6)
              : Colors.white.withValues(alpha: 0.07),
          width: selected ? 1.5 : 1.0,
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: accentColor.withValues(alpha: 0.15),
                  blurRadius: 20,
                  spreadRadius: 2,
                )
              ]
            : [],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icono
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accentColor.withValues(alpha: 0.12),
                  ),
                  child: Icon(icon, color: accentColor, size: 24),
                ),
                const SizedBox(width: 14),
                // Contenido
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: selected ? Colors.white : Colors.white70,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: badgeColor.withValues(alpha: 0.15),
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
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.45),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...features.map(
                        (f) => Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Row(
                            children: [
                              Icon(Icons.check_circle_rounded,
                                  size: 12,
                                  color: selected
                                      ? accentColor
                                      : Colors.white24),
                              const SizedBox(width: 6),
                              Text(
                                f,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: selected
                                      ? Colors.white70
                                      : Colors.white30,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Check de selección
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
                  ),
                  child: selected
                      ? const Icon(Icons.check_rounded,
                          size: 14, color: Colors.black)
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
