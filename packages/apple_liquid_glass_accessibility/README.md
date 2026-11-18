# Apple Liquid Glass Accessibility

Feeds the iOS and macOS accessibility settings that Flutter does not report
into `apple_liquid_glass`: Reduce Transparency, Show Borders (Button Shapes
before iOS 26.1), Prefer Cross-Fade Transitions, the Liquid Glass slider of
iOS 27 and, from iOS 27, whether the system prefers that apps reduce their
resource usage.

Unpublished prerelease; the API may change.

## Usage

Wrap the app in a `GlassPlatformTraits`, or return one from
`WidgetsApp.builder` so presented content sees the settings too:

```dart
WidgetsApp(
  color: const Color(0xFF007AFF),
  builder: (context, child) => GlassPlatformTraits(child: child!),
  home: const HomePage(),
);
```

Glass then draws flat under Reduce Transparency, outlines its surfaces under
Show Borders, follows the Liquid Glass slider, turns to the
`AdaptiveGlassRenderer`'s fallback while the system prefers reduced
resource usage and, with Reduce Motion, cross-fades pages as Prefer
Cross-Fade Transitions says. The settings reach the subtree as `GlassTraits`. Until the
platform reports them, and on other platforms, the enclosing traits stay.

To read the settings without glass, listen to
`AppleAccessibilityFeatures.watch()`. It gives the current settings, then
each change.

macOS reports Show Borders from 26.1 and has no Prefer Cross-Fade
Transitions setting. There `prefersCrossFade` is null, and cross-fading
follows Reduce Motion, as it does on iOS by default. macOS has no
preference for reduced resource usage either: `prefersReducedResourceUsage`
is null there and before iOS 27, and the glass keeps its renderer.
