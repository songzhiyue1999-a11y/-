# Design QA

## 2026-10-06 targeted visual check

- Reference 1: user screenshot of the keyword text appearing too low in a tall field. Latest Chrome capture shows the keyword at the top of a textarea, aligned with the persona field.
- Reference 2: user screenshot of two black paw prints on white. The preview now uses `public/assets/cat-paws-preview.png`, an original generated image with the same diagonal composition and no visible text or watermark. Latest Chrome capture shows the complete image inside the Xiaohongshu post preview without cropping or distortion.
- Three-column workbench layout and independent scrolling remain intact at the inspected desktop viewport.
- Browser interactions: draft save/reload/open/delete and isolated RAG delete/reload passed. Live XHS search returned `XHS_AUTH_REQUIRED`; that integration is recorded separately in `docs/QA_LOG.md`.

final result: passed

- Source visual truth: the modern SaaS dashboard reference supplied in the conversation, used for style rather than content.
- Rendered implementation: `public/assets/xiaomao-dashboard-preview.png` (1440×900, browser viewport 1440×900, device scale 1).
- Side-by-side review: performed against the earlier product concept and browser capture during implementation; the superseded concept asset was removed after the brand rename.
- Focused status review: `../../work/profile-status-after.png` (browser crop of the left profile card).
- State: current clean installation with empty search/RAG results and local CLI selected. Example content and cloud API data from the design exploration are not used as runtime defaults.

## Findings and comparison history

1. Initial browser pass found a P1 layout problem: the overview collapsed to 12px because its grid row shrank below its content. Added `grid-auto-rows: max-content` to `.workspace`. The 1440×900 capture now shows the full title and four metrics above the form.
2. User screenshot found a P2 profile status problem: the empty inline `<i>` occupied no width and appeared as a vertical bar. The status row now uses flex alignment and a fixed 6×6px circle. The focused browser crop shows a round dot and a single-line “本地草稿” label.
3. Final comparison found no actionable P0/P1/P2 mismatch with the requested visual direction. The product name, avatar, sample counts and API state reflect the user's latest instructions and the app's actual initial state.

## Required fidelity surfaces

- Typography: bold sans-serif page heading, readable dark body text and compact secondary labels; no clipped heading or form label at 1440×900 and 1440×720.
- Spacing and layout: dark left rail, white central canvas and separate right configuration rail; four pastel metric cards and two stage panels are visible without overlap. Outer page height equals viewport; each column scrolls independently.
- Colors and tokens: black/white main frame with pale blue, lavender, mint and cream metric backgrounds; restrained mint selection and success states.
- Images and icons: the user-supplied avatar loads in both profile and post preview; line icons render through `lucide-react` rather than text glyph stand-ins. The initial hero illustration is intentionally removed.
- Copy and content: brand is “小猫站点”, creator is “苹什喵”, and the brand's old icon and English subtitle are absent. Existing workflow labels and actions remain intact.

## Browser checks

- 1440×900: body scroll height 900px; all three columns render and scroll independently.
- 1440×720: body scroll height 720px; sidebar, workspace and configuration rail remain individually scrollable.
- Text model route toggles local CLI → cloud API → local CLI and updates visible fields.
- Fresh in-app browser tab: title and main content load; console error/warn list is empty; no framework overlay.
- `npm run build` and `git diff --check` passed.

final result: passed
