# Mynube: a personal vault

Mynube is a private place to keep a life, with a deliberately small shared circle. The product borrows Pinterest’s visual rhythm and Instagram’s direct, photographic storytelling. Content and ownership come first; no public discovery, engagement counts or dashboard chrome.

## Identity

The lower-case `mynube` wordmark pairs with a small white cloud: a continuous silhouette with balanced lobes, soft joins and generous clear space. Its terracotta container keeps the white shape legible in both themes. The same vector geometry is drawn in Flutter, used in the web favicon, and exported for iOS and Android by `scripts/render-brand.swift`. Native icons are opaque and keep the mark inside the adaptive safe area.

| Role | Light | Dark |
| --- | --- | --- |
| Canvas | warm paper `#FAF9F6` | neutral charcoal `#18181B` |
| Surface | white `#FFFFFF` | `#232326` |
| Text | charcoal ink `#292725` | warm white `#F5F2ED` |
| Accent | terracotta `#B94F38` | soft terracotta `#F1A28C` |
| Secondary | warm stone `#786A5D` | pale stone `#C4B7A7` |

Manrope gives navigation and interface text a friendly, clear voice. Five explicit bundled weights avoid variation differences between renderers. DM Serif Display is reserved for the welcome headline. Fonts and their OFL licenses ship locally; viewing personal photos never requires Google Fonts requests. Sample onboarding/demo photography is bundled with source references in `flutter_app/assets/demo/SOURCES.md`. Production libraries never substitute sample photos for missing private media.

## Layout and components

- **Vault:** two-column masonry on phones and three columns in the centered desktop content area. Natural photo proportions, minimal metadata, favorites, search and real photo/video filters. Adding memories opens a focused progress sheet; file details/comments are secondary.
- **Shared:** chronological, author-led moments, swipeable media and a clear circle boundary. Removing a post keeps its original in the vault.
- **Collections:** photographic covers, stacked visual treatment, clear ownership, and explicit recipient controls. These use the existing album API and permissions.
- **Profile:** centered personal details, a compact identity row on desktop, aligned name/storage cards, and stacked cards on phones or at larger text sizes. Visible field labels remain clear without floating over the input background.
- **Desktop:** persistent side navigation, hover feedback and focusable controls. Vault, Shared and Collections use the same fixed eyebrow/title/subtitle, right-aligned primary action, divider and centered 660 px content column. Their contents scroll below the header. Empty sections share the same centered icon, message and action; short viewports can scroll that state too.
- **iOS/Android:** thumb-friendly bottom navigation, safe-area spacing, system theme/status-bar treatment, keyboard-aware forms/sheets and familiar native page transitions. Video pauses when the app leaves the foreground.

Shared components live in `lib/shared/widgets/vault_ui.dart`. Colors and typography live in `lib/core/theme/app_theme.dart`; avoid independent feature palettes. Surfaces have restrained 14–24 px corners. Actions keep at least a 44–48 px touch area. Charcoal and warm paper form the continuous canvas; terracotta is reserved for actions and emphasis. Brand decoration remains secondary to a person’s own photography.

## Voice and motion

Use ordinary language: “Add memories”, “Your vault”, “Choose who sees it”, “Shared with you”. Explain privacy where someone makes a sharing decision. Avoid endpoints, multipart terminology, account-role chips and infrastructure status in everyday browsing. Do not imply end-to-end encryption or guaranteed background photo backup.

Entry transitions use short fades and small movement; hover zoom is subtle. Decorative motion respects reduced-motion settings. Larger text, compact widths, light/dark themes and native platform variants have automated layout coverage. OS-managed upload after app termination remains a separate capability, not a design claim.

The normal build follows the OS theme. `APP_THEME=light|dark` is an optional compile-time override for reproducible previews; it does not change production’s system default. Physical iPhone/Android acceptance and assistive-technology testing remain release gates.
