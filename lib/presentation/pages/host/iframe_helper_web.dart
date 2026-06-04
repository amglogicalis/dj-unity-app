// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'package:flutter/foundation.dart';

/// Web implementation of iframe helper that manipulates the DOM, including Shadow DOM.
void setIframePointerEvents(bool ignore) {
  try {
    // 1. Inject CSS stylesheet (with !important) into both the document head and the glass-pane shadow root
    _injectStyle(html.document.head);

    final glassPane = html.document.querySelector('flt-glass-pane');
    if (glassPane != null && glassPane.shadowRoot != null) {
      _injectStyle(glassPane.shadowRoot);
    }

    // 2. Toggle the CSS class on both the body and the glass-pane host element
    if (ignore) {
      html.document.body?.classes.add('disable-iframe-interaction');
      glassPane?.classes.add('disable-iframe-interaction');
      debugPrint('Web: Added disable-iframe-interaction class to document body and flt-glass-pane host');
    } else {
      html.document.body?.classes.remove('disable-iframe-interaction');
      glassPane?.classes.remove('disable-iframe-interaction');
      debugPrint('Web: Removed disable-iframe-interaction class');
    }

    // 3. Force direct inline styles as a double-security measure
    _applyDirectStyles(html.document, ignore);
    if (glassPane != null && glassPane.shadowRoot != null) {
      _applyDirectStyles(glassPane.shadowRoot!, ignore);
    }
  } catch (e) {
    debugPrint('Web style injector error: $e');
  }
}

void _injectStyle(dynamic root) {
  if (root == null) return;
  try {
    // Use dynamic to support both document/head and ShadowRoot which implement querySelector
    final existingStyle = root.querySelector('#dj-unity-iframe-style');
    if (existingStyle == null) {
      final style = html.StyleElement()
        ..id = 'dj-unity-iframe-style'
        ..text = '''
          .disable-iframe-interaction iframe, 
          .disable-iframe-interaction flt-platform-view,
          .disable-iframe-interaction flt-platform-view-container,
          :host(.disable-iframe-interaction) iframe, 
          :host(.disable-iframe-interaction) flt-platform-view,
          :host(.disable-iframe-interaction) flt-platform-view-container {
            pointer-events: none !important;
            visibility: hidden !important;
            opacity: 0 !important;
          }
        ''';
      root.append(style);
    }
  } catch (e) {
    debugPrint('Error injecting style: $e');
  }
}

void _applyDirectStyles(dynamic root, bool ignore) {
  if (root == null) return;
  try {
    final iframes = root.querySelectorAll('iframe');
    for (final el in iframes) {
      if (el is html.HtmlElement) {
        el.style.setProperty('pointer-events', ignore ? 'none' : 'auto', 'important');
        el.style.setProperty('visibility', ignore ? 'hidden' : 'visible', 'important');
        el.style.setProperty('opacity', ignore ? '0' : '1', 'important');
      }
    }
    final platformViews = root.querySelectorAll('flt-platform-view');
    for (final el in platformViews) {
      if (el is html.HtmlElement) {
        el.style.setProperty('pointer-events', ignore ? 'none' : 'auto', 'important');
        el.style.setProperty('visibility', ignore ? 'hidden' : 'visible', 'important');
        el.style.setProperty('opacity', ignore ? '0' : '1', 'important');
      }
    }
    final containers = root.querySelectorAll('flt-platform-view-container');
    for (final el in containers) {
      if (el is html.HtmlElement) {
        el.style.setProperty('pointer-events', ignore ? 'none' : 'auto', 'important');
        el.style.setProperty('visibility', ignore ? 'hidden' : 'visible', 'important');
        el.style.setProperty('opacity', ignore ? '0' : '1', 'important');
      }
    }
  } catch (e) {
    debugPrint('Error applying direct styles: $e');
  }
}
