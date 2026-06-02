# 🎵 DJ Unity App

**DJ Unity** es una aplicación móvil que convierte cualquier reunión, fiesta o evento en una experiencia musical colaborativa. El DJ controla la sala y los invitados añaden canciones a la cola desde sus propios dispositivos, sin necesidad de registro.

---

## 📱 Descarga la App (Android)

> **[⬇️ Descargar DJ Unity APK](../../releases/latest)**

Instala el `.apk` directamente en tu Android (requiere permitir instalación de fuentes desconocidas).

---

## ✨ Características

- 🎧 **Modo YouTube Music** — Reproduce canciones directamente desde YouTube con búsqueda automática
- 🟢 **Modo Spotify Premium** — Control total vía Spotify Connect (requiere cuenta Premium)
- 🟩 **Modo Spotify Free** — Los invitados votan canciones que se abren en Spotify
- 👥 **Sala colaborativa** — Los invitados se unen con un código PIN de 4 dígitos
- 📋 **Cola en tiempo real** — La playlist se sincroniza instantáneamente via Firebase
- ⏭️ **Skip & control** — El DJ tiene control total: play, pause, skip, barra de progreso
- 📱 **Diseño optimizado** — UI premium con colores personalizados y modo oscuro

---

## 🚀 Cómo usar

### Como DJ (Host)
1. Abre la app → **Crear Sala**
2. Elige el modo de reproducción (YouTube / Spotify Premium / Spotify Free)
3. Comparte el **código PIN** de 4 dígitos con tus invitados
4. ¡A controlar la música!

### Como Invitado
1. Abre la app → **Unirse a Sala**
2. Introduce el código PIN del DJ
3. Busca canciones y añádelas a la cola

---

## 🛠️ Tecnología

| Componente | Tecnología |
|---|---|
| Framework | Flutter (Dart) |
| Base de datos | Firebase Firestore |
| Reproducción YouTube | `youtube_player_iframe` |
| Integración Spotify | `spotify_sdk` |
| Arquitectura | Feature-based, Widget composition |

---

## 🔧 Compilar desde código fuente

### Requisitos
- Flutter SDK ≥ 3.22
- Android SDK (API 21+)
- Cuenta Firebase con Firestore habilitado

### Pasos
```bash
git clone https://github.com/amglogicalis/dj-unity-app.git
cd dj-unity-app
flutter pub get
flutter run
```

> **Nota:** Para compilar la APK de release necesitas tu propio `android/key.properties` y keystore (no incluidos por seguridad).

---

## 📋 Requisitos del dispositivo

- Android 5.0 (Lollipop) o superior
- Conexión a internet (WiFi o datos móviles)
- Para Spotify: app de Spotify instalada

---

*Desarrollado con ❤️ por AMGLogicalis*
