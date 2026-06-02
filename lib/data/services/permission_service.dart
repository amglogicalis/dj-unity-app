import 'package:permission_handler/permission_handler.dart';

/// Servicio responsable de gestionar todos los permisos necesarios
/// para la aplicación, dependiendo del rol (Host o Invitado).
class PermissionService {
  
  /// Solicita los permisos necesarios para que el teléfono Host funcione
  /// correctamente (Segundo plano, notificaciones para controles de audio).
  Future<bool> requestHostPermissions() async {
    // 1. Permiso de notificaciones: vital para mostrar los controles de música en la barra de estado
    PermissionStatus notificationStatus = await Permission.notification.request();

    // 2. Optimización de batería: vital en Android para evitar que el sistema
    // mate la app cuando está en segundo plano reproduciendo música.
    PermissionStatus batteryOptimizationStatus = await Permission.ignoreBatteryOptimizations.request();

    // 3. El acceso a red e Internet viene por defecto en el AndroidManifest.xml
    // y en el Info.plist de iOS (requiriendo configuración adicional de Background Modes: Audio).
    
    // Verificamos si los permisos principales fueron concedidos.
    // Nota: depends en las reglas de negocio si es estrictamente obligatorio ignorar la batería
    return notificationStatus.isGranted && batteryOptimizationStatus.isGranted;
  }

  /// Solicita permisos necesarios para un Invitado (por ejemplo, escanear el código QR)
  Future<bool> requestGuestPermissions() async {
    PermissionStatus cameraStatus = await Permission.camera.request();
    return cameraStatus.isGranted;
  }

  /// Comprueba específicamente si el permiso de notificaciones está activo
  Future<bool> isNotificationGranted() async {
    return await Permission.notification.isGranted;
  }

  /// Comprueba si la app está exenta de las optimizaciones de batería del sistema
  Future<bool> isBatteryOptimizationIgnored() async {
    return await Permission.ignoreBatteryOptimizations.isGranted;
  }
}
