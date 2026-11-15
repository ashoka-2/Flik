# Flik UI Design Skill (Minimal AI-App UI)

This specification governs the design system, visual language, geometry, tokens, and component behavior for both the Windows (Electron) and Android (Flutter) Flik applications.

Based on the `minimal-ai-ui` design standard: quiet, tonal, rounded, one accent color, and zero visual clutter.

---

## 1. Core Principles

1. **One Accent, Neutrals Everywhere Else.**
   - Accent: `#3566EF` (Dark) / `#2D51BF` (Light). Used strictly for primary actions, active/selected states, links, and progress.
   - All other surfaces are pure neutral tones. No rainbow chips, no decorative purple/neon gradients, no extraneous colors.
2. **Depth Through Tone, Not Shadow.**
   - Each elevation layer is one step lighter (dark mode) or darker (light mode): `background` -> `surface` (cards, rows) -> `raised` (sheets, dialogs, inputs).
   - 1dp hairline borders (`line`: 12% white in dark mode, 10% black in light mode) separate proximate layers.
   - Subtle drop shadows are reserved exclusively for floating overlays (menus, dialogs, floating action buttons).
3. **Pill & Soft-Card Geometry.**
   - Buttons, chips, search inputs, composer bars: full pill (`border-radius: 999px` / `BorderRadius.circular(999)`).
   - Cards and grouped lists: outer radius `28px`, inner corners `6px`.
   - Icon buttons: `44px` diameter circles.
   - Bottom sheets: top corner radius `28px`.
4. **Grouped List Rows as Primary Layout.**
   - Settings, peer lists, transfer queues: stacked rows `56px` tall (`72px` with subtitle).
   - Gap between rows: `2px`.
   - Tap targets >= `44px`.
5. **Quiet Typography.**
   - Clean system sans-serif (Inter / Roboto / -apple-system / Segoe UI).
   - Weights: 400 (regular), 500 (medium), 600 (semi-bold). No shouting all-caps.
6. **16dp Screen Margin, 8dp Rhythm.**
   - Standard screen margins: 16dp (phone), 24dp (tablet), 40dp (desktop).
   - Everything snaps to an 8dp (or 4dp) grid.
7. **No Emojis as Icons.**
   - Only crisp, clean SVG icons and clear typography.

---

## 2. Color Ramp & Design Tokens

### Dark Theme (Default)
- `background`: `#151515` (Warm charcoal)
- `surface`: `#20201E` (Group card background)
- `raised`: `#303030` (Modals, popups, inputs)
- `text`: `#F9F9F7` (High-contrast legible body text)
- `muted`: `#A0A09E` (Secondary descriptions, captions)
- `line`: `rgba(255, 255, 255, 0.12)` (1dp hairline border)
- `accent`: `#3566EF` (Primary blue accent)
- `accentSoft`: `#8AABF8` (Accent text and badges)
- `danger`: `#EF4444` (Destructive actions)

### Light Theme
- `background`: `#FCFCFC`
- `surface`: `#E8E8E8`
- `raised`: `#FFFFFF`
- `text`: `#0D0D0D`
- `muted`: `#5D5D5D`
- `line`: `rgba(0, 0, 0, 0.10)`
- `accent`: `#2D51BF`
- `accentSoft`: `#2D51BF`
- `danger`: `#DC2626`

---

## 3. Motion & Transitions

- Fast: `120ms` for hover, press, feedback.
- Base: `200ms` for toggles, chips, selection states.
- Slow: `320ms` for sheets, dialogs, card landing, deck spring animations.
- Easing: `cubic-bezier(0.2, 0, 0, 1)` standard curve; `cubic-bezier(0.05, 0.7, 0.1, 1)` enter curve.
- Always respect `prefers-reduced-motion`.
