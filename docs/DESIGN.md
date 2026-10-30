# Native design adaptation

The visual direction follows [naplesblue/apple-design-skill](https://github.com/naplesblue/apple-design-skill): a cool `#f5f5f7` ground, white content surfaces, grayscale hierarchy, `#0071e3` as the single focus/action accent, and subtle hairline separation.

## Applied to AppKit

- `Theme.swift` owns shared accent/background/surface/hairline/radius tokens.
- Adjacent browsing panes share one rounded workspace surface with thin separators. The active pane uses its caption/focus state rather than a repeated colored box outline.
- System typography and native table, menu, keyboard, alert, and sheet behavior are preserved.
- Translucency is limited to the overlapping header material. File rows and reading surfaces remain opaque.
- Reduce Transparency substitutes an opaque header; Increase Contrast strengthens separators. Native sheets and controls retain their system accessibility behavior.
- The Remote Workspace follows a grouped settings form above a local/remote browser, with explicit Upload/Download labels beside the transfer workflow.

## Deliberate native exceptions

The source skill is written primarily for web/mobile interfaces. Desktop file browsers need dense rows, keyboard navigation, resizable windows, and full-width lists. Web reading-container limits, CSS imports, mobile safe areas/device frames, 44 px touch sizing, and custom CSS sheet animations are therefore not copied literally. macOS renders the native controls and modal transitions. No looping decorative animation or async list entrance fade is added.

This app targets macOS 13+. The header uses `NSVisualEffectView`; it does not require or claim access to newer OS-only Liquid Glass APIs.

## Review gate

Check actual two/four-pane and connection-window screenshots before release: cool ground, white surface, one blue accent, clear current location/destination, legible labels at minimum size, and no decorative glass on file rows. Keep keyboard focus checks separate from visual checks, especially with multiple windows open.
