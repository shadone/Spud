# Markdown Renderer — Phase 4 (Media Blocks) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render the three media block kinds — `image` (loading / failed / loaded states, "Tap to zoom" chip, italic alt caption), `audio` (teal play button + faux waveform + duration), and `video` (dark poster + centered play + faux transport bar) — replacing the Phase-3 placeholders, wired to the media tap delegate, shown live in `MarkdownLab` and snapshot-locked.

**Architecture:** Each media block becomes a dedicated `@MainActor UIView` wired into `MarkdownBlockRenderer.view(for:)` (replacing its `PlaceholderBlockView`). The renderer gains tap seams (`onTapImage` / `onTapVideo` / `onTapAudio`) plus a host-supplied async `imageLoader`; `MarkdownBodyView` forwards the taps to an extended `MarkdownBodyDelegate` and exposes the loader. Audio/video are placeholder-rendered (no `AVPlayer` / network — deterministic). Image states are deterministic too: the Lab supplies an offline synthetic loader, and the snapshot tests construct the view with an explicit state. Views are verified by snapshot + Lab eyeball; the renderer dispatch is unit-tested.

**Tech Stack:** Swift 6, UIKit (Auto Layout self-sizing, `UIStackView`, `UIImageView`, `UIActivityIndicatorView`), swift-snapshot-testing, XcodeGen.

---

## Scope

Phase 4 = the three media block VIEWS + the media tap delegate surface + the host image-loader seam. **Out of scope:** real network image loading / real `AVPlayer` / inline audio playback (integration, Phase 6 — the Lab synthesizes images and audio/video are static placeholders); animated GIF; image zoom transition animation; precise progress / scrubbing in the audio/video transports (the bars are static design props). Builds on Phases 1–3 (`docs/superpowers/specs/2026-06-15-markdown-renderer-design.md` and the three prior plans). The carried-forward limitations from Phase 3 (rounded chips, footnote ref↔def jump, fence-aware preprocessors, spoiler-in-list, H6 inline formatting) are untouched here.

## Reference (from `md-render.jsx`, the design's `AudioPlayer` / `VideoPlayer` / `ImageBlock`)

- **Audio:** a rounded row (radius 12 post / 9 comment), `secondarySystemFill` background, 0.5px separator border; a teal **circle** (38 post / 32 comment) holding a white `play.fill`; a **faux waveform** — N thin bars (34 post / 26 comment), per-bar height `5 + |sin(i·1.7)|·(maxH−5)`, the first ~1/3 teal ("played") and the rest separator-colored; a trailing **monospaced** duration label (`0:48`) in `secondaryLabel`.
- **Video:** a rounded clipped tile (radius 12 / 9), black background, a **16:9 dark poster plate** (no real poster in the Lab); a **centered play button** — a translucent-black circle (56 / 44) with a 1.5px 80%-white border and a white `play.fill`; a **transport bar** pinned to the bottom over a translucent-black strip: a small white `play.fill`, a 3pt progress track (24% filled white + a round knob), a monospaced `0:32 / 2:14` time, and a white speaker glyph.
- **Image:** a rounded clipped box (radius 12 / 9). **loading** — `secondarySystemFill`, a 16:10 box, a spinner (tertiary) above a "Loading image…" `secondaryLabel` label. **failed** — `secondarySystemFill` + 0.5px separator border, a broken-image glyph (tertiary) above "Image couldn't load" (`secondaryLabel`) and a teal "Open in browser" affordance. **loaded** — the image at its natural aspect ratio, with a bottom-right "Tap to zoom" chip (translucent-black rounded pill: a white `plus.magnifyingglass` + white "Tap to zoom"). An optional **italic alt caption** in `secondaryLabel`, `smallFont`, sits 6pt below the box in every state.

## File Structure

```
SpudMarkdownKit/Rendering/
  MarkdownImageLoader.swift     ← NEW: public typealias for the host async image provider
  MarkdownBodyDelegate.swift    ← MODIFIED: + didTapImage/didTapVideo/didTapAudio (default no-op)
  MarkdownBlockRenderer.swift   ← MODIFIED: + onTapImage/onTapVideo/onTapAudio/imageLoader; wire .image/.audio/.video
  MarkdownBodyView.swift        ← MODIFIED: + public imageLoader; forward the three media taps to the delegate
  ImageBlockView.swift          ← NEW
  AudioBlockView.swift          ← NEW
  VideoBlockView.swift          ← NEW
SpudMarkdownKitTests/
  MarkdownBlockRendererTests.swift   ← MODIFIED: + 3 dispatch tests (image/audio/video → their view types)
SpudMarkdownKitSnapshotTests/
  MarkdownMediaSnapshotTests.swift   ← NEW: audio + video + image(loaded) + image(failed), post/comment x light/dark
MarkdownLab/
  LabImageFactory.swift         ← NEW: deterministic offline synthetic image
  MarkdownLabApp.swift          ← MODIFIED: media in the sample, supply imageLoader, logging delegate
```

## Conventions (every task)

BSD-2-Clause header on every new file:
```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//
```

**MUST `make project` before every build/test** (XcodeGen picks up new files only on regeneration). Canonical unit-test command:
```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/enumerated-rolling-plum
make project
xcodebuild -project Spud.xcodeproj -scheme SpudMarkdownKit \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation \
  -only-testing:SpudMarkdownKitTests/<CLASS> test 2>&1 | tail -30
```
(iPhone 17 or 17 Pro — whichever is installed.) Format before commit: `mint run swiftformat <dirs>`. `git status -uall`; stage explicit paths (never `git add -A`). All view types are `final class … : UIView` (internal) and UIView is `@MainActor`-isolated, so no extra annotation is needed. Every new view has `@available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }`.

**Trait-change footgun (caught 3× in earlier phases):** `layer.borderColor = UIColor.separator.cgColor` is a resolved snapshot — it does NOT auto-update on light/dark switch. Any view that sets a `layer.borderColor` MUST re-resolve it in `registerForTraitChanges([UITraitUserInterfaceStyle.self]) { … }`. (`UILabel.textColor` / `UIView.backgroundColor` set to dynamic `UIColor`s are fine — only `CGColor`s need this.)

---

## Task 1: Media delegate methods + renderer seams + body-view wiring

**Files:** Create `SpudMarkdownKit/Rendering/MarkdownImageLoader.swift`; Modify `SpudMarkdownKit/Rendering/MarkdownBodyDelegate.swift`, `SpudMarkdownKit/Rendering/MarkdownBlockRenderer.swift`, `SpudMarkdownKit/Rendering/MarkdownBodyView.swift`

Plumbing only — no new view yet (the `.image`/`.audio`/`.video` cases still return `PlaceholderBlockView`, so behavior is unchanged and the build stays green). Adds the delegate surface, renderer seams, and the public loader the later tasks consume.

- [ ] **Step 1: Create** `SpudMarkdownKit/Rendering/MarkdownImageLoader.swift`:
```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// Asynchronously provides a decoded image for a body image URL. The host
/// supplies it: the Lab synthesizes one offline; Spud wires its `ImageService`
/// at integration. Invoked on the main actor (an implementation may hop to a
/// background queue internally and resume on the main actor). Returning `nil`
/// puts the image block into its failed state.
public typealias MarkdownImageLoader = @MainActor (URL) async -> UIImage?
```

- [ ] **Step 2: Rewrite** `SpudMarkdownKit/Rendering/MarkdownBodyDelegate.swift` — add the three media taps with default no-op implementations (so existing conformers don't break and a host opts in only to what it needs):
```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// Host callbacks for interactions inside a rendered markdown body. The host
/// resolves web links (in-app vs Safari per preference) and `spud-markdown://`
/// mention/community URLs, presents the media viewer / player, etc. The media
/// methods have default no-op implementations.
@MainActor
public protocol MarkdownBodyDelegate: AnyObject {
    func markdownBody(didTapLink url: URL)
    /// A loaded body image was tapped (zoom). `sourceRect` is in window
    /// coordinates, for a zoom transition.
    func markdownBody(didTapImage url: URL, altText: String?, sourceRect: CGRect)
    func markdownBody(didTapVideo url: URL)
    func markdownBody(didTapAudio url: URL)
}

public extension MarkdownBodyDelegate {
    func markdownBody(didTapImage _: URL, altText _: String?, sourceRect _: CGRect) {}
    func markdownBody(didTapVideo _: URL) {}
    func markdownBody(didTapAudio _: URL) {}
}
```

- [ ] **Step 3: Add the renderer seams** in `SpudMarkdownKit/Rendering/MarkdownBlockRenderer.swift` — directly below the existing `var onContentSizeChange: (() -> Void)?` line:
```swift
    var onTapImage: ((URL, String?, CGRect) -> Void)?
    var onTapVideo: ((URL) -> Void)?
    var onTapAudio: ((URL) -> Void)?
    var imageLoader: MarkdownImageLoader?
```
(Leave the `.image`/`.audio`/`.video` cases returning `PlaceholderBlockView` for now — Tasks 2–4 replace them. The new stored properties are written by `MarkdownBodyView` and read by those tasks; an unread stored property is not a warning.)

- [ ] **Step 4: Wire the body view** in `SpudMarkdownKit/Rendering/MarkdownBodyView.swift`. Add the public loader property below the existing `private let renderer: MarkdownBlockRenderer` declaration:
```swift
    /// Host-supplied async image provider. Set this BEFORE `setBlocks(_:)` so
    /// the image blocks pick it up as they are built.
    public var imageLoader: MarkdownImageLoader? {
        didSet { renderer.imageLoader = imageLoader }
    }
```
Then, inside `init`, directly after the existing `renderer.onContentSizeChange = { … }` closure, add:
```swift
        renderer.onTapImage = { [weak self] url, alt, rect in
            self?.delegate?.markdownBody(didTapImage: url, altText: alt, sourceRect: rect)
        }
        renderer.onTapVideo = { [weak self] url in self?.delegate?.markdownBody(didTapVideo: url) }
        renderer.onTapAudio = { [weak self] url in self?.delegate?.markdownBody(didTapAudio: url) }
```

- [ ] **Step 5: Build to verify** the plumbing compiles (placeholders unchanged):
```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/enumerated-rolling-plum
make project
xcodebuild -project Spud.xcodeproj -scheme SpudMarkdownKit \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation build 2>&1 | tail -10
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit.**
```bash
make project && mint run swiftformat SpudMarkdownKit
git add SpudMarkdownKit
git commit -m "feat(markdown): media tap delegate + renderer seams + image loader

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: ImageBlockView (loading / failed / loaded states)

**Files:** Create `SpudMarkdownKit/Rendering/ImageBlockView.swift`; Modify `SpudMarkdownKit/Rendering/MarkdownBlockRenderer.swift` (wire `.image`); Modify `SpudMarkdownKitTests/MarkdownBlockRendererTests.swift` (dispatch test)

A vertical [aspect-box, alt-caption?] view. The box swaps between loading, failed, and loaded content; an async loader (if supplied) drives loading → loaded/failed. The failed plate's "Open in browser" reuses the existing `onTapLink` seam; a loaded-image tap fires `onTapImage` with the box's window-coordinate rect.

- [ ] **Step 1: Write the failing dispatch test** — append to `SpudMarkdownKitTests/MarkdownBlockRendererTests.swift`, inside the `MarkdownBlockRendererTests` class (after the existing tests):
```swift
    func test_imageRendersImageBlockView() {
        let image = MarkdownImage(url: URL(string: "https://example.com/a.jpg")!, altText: "alt")
        XCTAssertTrue(renderer().view(for: .image(image)) is ImageBlockView)
    }
```

- [ ] **Step 2: Run to verify it fails** (`-only-testing:SpudMarkdownKitTests/MarkdownBlockRendererTests`). Expected: either `cannot find type 'ImageBlockView'` (compile fail) — acceptable RED — or, once the type exists, the assertion fails because the dispatch still returns `PlaceholderBlockView`.

- [ ] **Step 3: Create** `SpudMarkdownKit/Rendering/ImageBlockView.swift`:
```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// A body image: an aspect-ratio box showing a loading spinner, a failed plate
/// (with an "Open in browser" escape hatch), or the loaded image with a "Tap to
/// zoom" chip; an optional italic alt caption sits 6pt below in every state.
final class ImageBlockView: UIView {
    enum State: Equatable {
        case loading
        case loaded(UIImage)
        case failed
    }

    private let url: URL
    private let altText: String?
    private let context: MarkdownContext
    private let onTapImage: ((URL, String?, CGRect) -> Void)?
    private let onOpenInBrowser: ((URL) -> Void)?

    private let box = UIView()
    private var boxAspect: NSLayoutConstraint?

    init(image: MarkdownImage,
         context: MarkdownContext,
         onTapImage: ((URL, String?, CGRect) -> Void)?,
         onOpenInBrowser: ((URL) -> Void)?,
         loader: MarkdownImageLoader?) {
        url = image.url
        altText = image.altText
        self.context = context
        self.onTapImage = onTapImage
        self.onOpenInBrowser = onOpenInBrowser
        super.init(frame: .zero)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        box.clipsToBounds = true
        box.layer.cornerRadius = context.kind == .post ? 12 : 9
        box.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(box)

        if let altText {
            let caption = UILabel()
            caption.text = altText
            caption.numberOfLines = 0
            caption.font = .italicSystemFont(ofSize: context.smallFont.pointSize)
            caption.textColor = context.secondaryColor
            stack.addArrangedSubview(caption)
        }

        // The failed-state border is a CGColor snapshot; re-resolve on theme change.
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: ImageBlockView, _: UITraitCollection) in
            if view.box.layer.borderWidth > 0 {
                view.box.layer.borderColor = UIColor.separator.cgColor
            }
        }

        apply(state: .loading)

        if let loader {
            Task { [weak self] in
                let image = await loader(url)
                guard let self else { return }
                apply(state: image.map(State.loaded) ?? .failed)
            }
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    /// Replaces the box's content for `state` and updates its aspect ratio.
    func apply(state: State) {
        box.subviews.forEach { $0.removeFromSuperview() }
        box.gestureRecognizers?.forEach { box.removeGestureRecognizer($0) }
        boxAspect?.isActive = false
        box.layer.borderWidth = 0
        box.isUserInteractionEnabled = false

        switch state {
        case .loading:
            box.backgroundColor = .secondarySystemFill
            setBoxAspect(widthOverHeight: 16.0 / 10.0)
            let spinner = UIActivityIndicatorView(style: .medium)
            spinner.color = context.tertiaryColor
            spinner.startAnimating()
            placeStatusStack([spinner, statusLabel("Loading image\u{2026}", color: context.secondaryColor)])

        case let .loaded(image):
            box.backgroundColor = .clear
            let ratio = image.size.height > 0 ? image.size.width / image.size.height : 16.0 / 10.0
            setBoxAspect(widthOverHeight: ratio)
            let imageView = UIImageView(image: image)
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            imageView.translatesAutoresizingMaskIntoConstraints = false
            box.addSubview(imageView)
            NSLayoutConstraint.activate([
                imageView.topAnchor.constraint(equalTo: box.topAnchor),
                imageView.bottomAnchor.constraint(equalTo: box.bottomAnchor),
                imageView.leadingAnchor.constraint(equalTo: box.leadingAnchor),
                imageView.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            ])
            addZoomChip()
            box.isUserInteractionEnabled = true
            box.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(zoomTapped)))

        case .failed:
            box.backgroundColor = .secondarySystemFill
            box.layer.borderWidth = 0.5
            box.layer.borderColor = UIColor.separator.cgColor
            setBoxAspect(widthOverHeight: 16.0 / 10.0)
            let glyph = UIImageView(image: UIImage(systemName: "photo"))
            glyph.tintColor = context.tertiaryColor
            glyph.contentMode = .scaleAspectFit
            glyph.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: context.kind == .post ? 30 : 24)
            let open = UIButton(type: .system)
            open.setTitle("Open in browser", for: .normal)
            open.titleLabel?.font = .systemFont(ofSize: context.smallFont.pointSize, weight: .semibold)
            open.tintColor = context.accentColor
            open.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                onOpenInBrowser?(url)
            }, for: .touchUpInside)
            placeStatusStack([glyph, statusLabel("Image couldn\u{2019}t load", color: context.secondaryColor), open])
        }
    }

    private func setBoxAspect(widthOverHeight ratio: CGFloat) {
        let c = box.heightAnchor.constraint(equalTo: box.widthAnchor, multiplier: 1 / max(ratio, 0.05))
        c.isActive = true
        boxAspect = c
    }

    private func statusLabel(_ text: String, color: UIColor) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: context.smallFont.pointSize, weight: .semibold)
        label.textColor = color
        label.textAlignment = .center
        return label
    }

    private func placeStatusStack(_ views: [UIView]) {
        let stack = UIStackView(arrangedSubviews: views)
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 9
        stack.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: box.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: box.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: box.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: box.trailingAnchor, constant: -12),
        ])
    }

    private func addZoomChip() {
        let icon = UIImageView(image: UIImage(systemName: "plus.magnifyingglass"))
        icon.tintColor = .white
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: context.smallFont.pointSize, weight: .semibold)
        let label = UILabel()
        label.text = "Tap to zoom"
        label.font = .systemFont(ofSize: context.smallFont.pointSize * 0.92, weight: .semibold)
        label.textColor = .white

        let row = UIStackView(arrangedSubviews: [icon, label])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 4
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        row.translatesAutoresizingMaskIntoConstraints = false

        let chip = UIView()
        chip.backgroundColor = UIColor.black.withAlphaComponent(0.42)
        chip.layer.cornerRadius = 8
        chip.clipsToBounds = true
        chip.translatesAutoresizingMaskIntoConstraints = false
        chip.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: chip.topAnchor),
            row.bottomAnchor.constraint(equalTo: chip.bottomAnchor),
            row.leadingAnchor.constraint(equalTo: chip.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: chip.trailingAnchor),
        ])

        box.addSubview(chip)
        NSLayoutConstraint.activate([
            chip.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -9),
            chip.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -9),
        ])
    }

    @objc private func zoomTapped() {
        onTapImage?(url, altText, box.convert(box.bounds, to: nil))
    }
}
```

- [ ] **Step 4: Wire it** in `MarkdownBlockRenderer.view(for:)` — replace `case .image: return PlaceholderBlockView(label: "image")` with:
```swift
        case let .image(image):
            return ImageBlockView(
                image: image,
                context: context,
                onTapImage: onTapImage,
                onOpenInBrowser: onTapLink,
                loader: imageLoader
            )
```

- [ ] **Step 5: Run the dispatch test to verify it passes** (`-only-testing:SpudMarkdownKitTests/MarkdownBlockRendererTests`). Expected: `** TEST SUCCEEDED **` (all renderer dispatch tests, including the new image one). The visual states are eyeballed + snapshotted in Task 5.

- [ ] **Step 6: Commit.**
```bash
make project && mint run swiftformat SpudMarkdownKit SpudMarkdownKitTests
git add SpudMarkdownKit SpudMarkdownKitTests
git commit -m "feat(markdown): ImageBlockView (loading/failed/loaded + zoom + caption)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: AudioBlockView

**Files:** Create `SpudMarkdownKit/Rendering/AudioBlockView.swift`; Modify `SpudMarkdownKit/Rendering/MarkdownBlockRenderer.swift` (wire `.audio`); Modify `SpudMarkdownKitTests/MarkdownBlockRendererTests.swift` (dispatch test)

A static transport row: teal play circle + faux waveform + monospaced duration. The whole row taps through to `onTapAudio` (real playback is integration-time).

- [ ] **Step 1: Write the failing dispatch test** — append to `MarkdownBlockRendererTests`:
```swift
    func test_audioRendersAudioBlockView() {
        XCTAssertTrue(renderer().view(for: .audio(url: URL(string: "https://example.com/a.mp3")!)) is AudioBlockView)
    }
```

- [ ] **Step 2: Run to verify it fails** (compile error `cannot find type 'AudioBlockView'`, or the assertion fails against `PlaceholderBlockView`).

- [ ] **Step 3: Create** `SpudMarkdownKit/Rendering/AudioBlockView.swift`:
```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// An audio embed rendered as a transport row: a teal play button, a static
/// faux waveform, and a duration label. Tapping forwards the URL to the host
/// (real playback is wired at integration).
final class AudioBlockView: UIView {
    private let url: URL
    private let onTap: ((URL) -> Void)?

    init(url: URL, context: MarkdownContext, onTap: ((URL) -> Void)?) {
        self.url = url
        self.onTap = onTap
        super.init(frame: .zero)
        let post = context.kind == .post

        backgroundColor = .secondarySystemFill
        layer.cornerRadius = post ? 12 : 9
        layer.borderWidth = 0.5
        layer.borderColor = UIColor.separator.cgColor
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: AudioBlockView, _: UITraitCollection) in
            view.layer.borderColor = UIColor.separator.cgColor
        }

        let diameter: CGFloat = post ? 38 : 32
        let playCircle = UIView()
        playCircle.backgroundColor = context.accentColor
        playCircle.layer.cornerRadius = diameter / 2
        playCircle.translatesAutoresizingMaskIntoConstraints = false
        playCircle.setContentHuggingPriority(.required, for: .horizontal)
        let playIcon = UIImageView(image: UIImage(systemName: "play.fill"))
        playIcon.tintColor = .white
        playIcon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: post ? 16 : 13)
        playIcon.translatesAutoresizingMaskIntoConstraints = false
        playCircle.addSubview(playIcon)
        NSLayoutConstraint.activate([
            playCircle.widthAnchor.constraint(equalToConstant: diameter),
            playCircle.heightAnchor.constraint(equalToConstant: diameter),
            playIcon.centerXAnchor.constraint(equalTo: playCircle.centerXAnchor),
            playIcon.centerYAnchor.constraint(equalTo: playCircle.centerYAnchor),
        ])

        let waveform = AudioBlockView.makeWaveform(post: post, accent: context.accentColor)

        let time = UILabel()
        time.text = "0:48"
        time.font = .monospacedSystemFont(ofSize: context.smallFont.pointSize, weight: .regular)
        time.textColor = context.secondaryColor
        time.setContentHuggingPriority(.required, for: .horizontal)
        time.setContentCompressionResistancePriority(.required, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [playCircle, waveform, time])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = post ? 12 : 9
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: post ? 10 : 8, left: post ? 13 : 10, bottom: post ? 10 : 8, right: post ? 13 : 10)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        isUserInteractionEnabled = true
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    @objc private func tapped() {
        onTap?(url)
    }

    /// A static waveform: N bars of height `5 + |sin(i·1.7)|·(maxH−5)`, the first
    /// third tinted teal ("played"), the rest separator-colored.
    private static func makeWaveform(post: Bool, accent: UIColor) -> UIView {
        let barCount = post ? 34 : 26
        let playedCount = post ? 11 : 8
        let maxHeight: CGFloat = post ? 20 : 16

        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        row.distribution = .fillEqually
        row.spacing = 2
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: maxHeight + 2).isActive = true
        for i in 0 ..< barCount {
            let bar = UIView()
            bar.backgroundColor = i < playedCount ? accent : .separator
            bar.layer.cornerRadius = 1
            bar.translatesAutoresizingMaskIntoConstraints = false
            let height = 5 + abs(sin(Double(i) * 1.7)) * Double(maxHeight - 5)
            bar.heightAnchor.constraint(equalToConstant: CGFloat(height)).isActive = true
            row.addArrangedSubview(bar)
        }
        return row
    }
}
```

- [ ] **Step 4: Wire it** in `MarkdownBlockRenderer.view(for:)` — replace `case .audio: return PlaceholderBlockView(label: "audio")` with:
```swift
        case let .audio(url):
            return AudioBlockView(url: url, context: context, onTap: onTapAudio)
```

- [ ] **Step 5: Run the dispatch test to verify it passes** (`-only-testing:SpudMarkdownKitTests/MarkdownBlockRendererTests`). Expected `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit.**
```bash
make project && mint run swiftformat SpudMarkdownKit SpudMarkdownKitTests
git add SpudMarkdownKit SpudMarkdownKitTests
git commit -m "feat(markdown): AudioBlockView (play button + faux waveform)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: VideoBlockView

**Files:** Create `SpudMarkdownKit/Rendering/VideoBlockView.swift`; Modify `SpudMarkdownKit/Rendering/MarkdownBlockRenderer.swift` (wire `.video`); Modify `SpudMarkdownKitTests/MarkdownBlockRendererTests.swift` (dispatch test)

A poster tile with a centered play button over a static faux transport bar. The whole tile taps through to `onTapVideo`.

- [ ] **Step 1: Write the failing dispatch test** — append to `MarkdownBlockRendererTests`:
```swift
    func test_videoRendersVideoBlockView() {
        XCTAssertTrue(renderer().view(for: .video(url: URL(string: "https://example.com/a.mp4")!)) is VideoBlockView)
    }
```

- [ ] **Step 2: Run to verify it fails** (compile error `cannot find type 'VideoBlockView'`, or the assertion fails against `PlaceholderBlockView`).

- [ ] **Step 3: Create** `SpudMarkdownKit/Rendering/VideoBlockView.swift`:
```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// A video embed rendered as a 16:9 dark poster tile with a centered play
/// button and a static faux transport bar. Tapping forwards the URL to the host
/// (the real AVPlayer is wired at integration).
final class VideoBlockView: UIView {
    private let url: URL
    private let onTap: ((URL) -> Void)?

    init(url: URL, context: MarkdownContext, onTap: ((URL) -> Void)?) {
        self.url = url
        self.onTap = onTap
        super.init(frame: .zero)
        let post = context.kind == .post

        layer.cornerRadius = post ? 12 : 9
        clipsToBounds = true
        backgroundColor = .black

        // 16:9 poster plate (no real poster in the Lab).
        let poster = UIView()
        poster.backgroundColor = UIColor(white: 0.12, alpha: 1)
        poster.translatesAutoresizingMaskIntoConstraints = false
        addSubview(poster)
        NSLayoutConstraint.activate([
            poster.topAnchor.constraint(equalTo: topAnchor),
            poster.bottomAnchor.constraint(equalTo: bottomAnchor),
            poster.leadingAnchor.constraint(equalTo: leadingAnchor),
            poster.trailingAnchor.constraint(equalTo: trailingAnchor),
            poster.heightAnchor.constraint(equalTo: poster.widthAnchor, multiplier: 9.0 / 16.0),
        ])

        // Centered play button.
        let diameter: CGFloat = post ? 56 : 44
        let circle = UIView()
        circle.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        circle.layer.cornerRadius = diameter / 2
        circle.layer.borderWidth = 1.5
        circle.layer.borderColor = UIColor.white.withAlphaComponent(0.8).cgColor
        circle.translatesAutoresizingMaskIntoConstraints = false
        let playIcon = UIImageView(image: UIImage(systemName: "play.fill"))
        playIcon.tintColor = .white
        playIcon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: post ? 22 : 18)
        playIcon.translatesAutoresizingMaskIntoConstraints = false
        circle.addSubview(playIcon)
        addSubview(circle)
        NSLayoutConstraint.activate([
            circle.widthAnchor.constraint(equalToConstant: diameter),
            circle.heightAnchor.constraint(equalToConstant: diameter),
            circle.centerXAnchor.constraint(equalTo: poster.centerXAnchor),
            circle.centerYAnchor.constraint(equalTo: poster.centerYAnchor),
            playIcon.centerXAnchor.constraint(equalTo: circle.centerXAnchor, constant: 1),
            playIcon.centerYAnchor.constraint(equalTo: circle.centerYAnchor),
        ])

        // Bottom transport bar overlay.
        let bar = makeTransportBar(post: post, smallPointSize: context.smallFont.pointSize)
        addSubview(bar)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: poster.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: poster.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: poster.bottomAnchor),
        ])

        isUserInteractionEnabled = true
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    @objc private func tapped() {
        onTap?(url)
    }

    private func makeTransportBar(post: Bool, smallPointSize: CGFloat) -> UIView {
        let smallPlay = UIImageView(image: UIImage(systemName: "play.fill"))
        smallPlay.tintColor = .white
        smallPlay.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: post ? 15 : 13)
        smallPlay.setContentHuggingPriority(.required, for: .horizontal)

        let track = UIView()
        track.backgroundColor = UIColor.white.withAlphaComponent(0.3)
        track.layer.cornerRadius = 1.5
        track.translatesAutoresizingMaskIntoConstraints = false
        track.heightAnchor.constraint(equalToConstant: 3).isActive = true
        let fill = UIView()
        fill.backgroundColor = .white
        fill.layer.cornerRadius = 1.5
        fill.translatesAutoresizingMaskIntoConstraints = false
        track.addSubview(fill)
        NSLayoutConstraint.activate([
            fill.leadingAnchor.constraint(equalTo: track.leadingAnchor),
            fill.topAnchor.constraint(equalTo: track.topAnchor),
            fill.bottomAnchor.constraint(equalTo: track.bottomAnchor),
            fill.widthAnchor.constraint(equalTo: track.widthAnchor, multiplier: 0.24),
        ])

        let time = UILabel()
        time.text = "0:32 / 2:14"
        time.font = .monospacedSystemFont(ofSize: smallPointSize * 0.92, weight: .regular)
        time.textColor = .white
        time.setContentHuggingPriority(.required, for: .horizontal)
        time.setContentCompressionResistancePriority(.required, for: .horizontal)

        let speaker = UIImageView(image: UIImage(systemName: "speaker.wave.2.fill"))
        speaker.tintColor = .white
        speaker.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: post ? 16 : 14)
        speaker.setContentHuggingPriority(.required, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [smallPlay, track, time, speaker])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 9
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: post ? 9 : 7, left: post ? 12 : 10, bottom: post ? 9 : 7, right: post ? 12 : 10)
        row.translatesAutoresizingMaskIntoConstraints = false

        let container = UIView()
        container.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: container.topAnchor),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        return container
    }
}
```

- [ ] **Step 4: Wire it** in `MarkdownBlockRenderer.view(for:)` — replace `case .video: return PlaceholderBlockView(label: "video")` with:
```swift
        case let .video(url):
            return VideoBlockView(url: url, context: context, onTap: onTapVideo)
```

- [ ] **Step 5: Run the dispatch test to verify it passes** (`-only-testing:SpudMarkdownKitTests/MarkdownBlockRendererTests`). Expected `** TEST SUCCEEDED **`. With this, `PlaceholderBlockView` is no longer referenced by the renderer's switch — confirm `MarkdownBlockRenderer.swift` has no remaining `PlaceholderBlockView` case.

- [ ] **Step 6: Commit.**
```bash
make project && mint run swiftformat SpudMarkdownKit SpudMarkdownKitTests
git add SpudMarkdownKit SpudMarkdownKitTests
git commit -m "feat(markdown): VideoBlockView (poster + play + transport bar)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Lab media + loader + media snapshots (visual checkpoint + final verification)

**Files:** Create `MarkdownLab/LabImageFactory.swift`; Modify `MarkdownLab/MarkdownLabApp.swift`; Create `SpudMarkdownKitSnapshotTests/MarkdownMediaSnapshotTests.swift`

- [ ] **Step 1: Create** `MarkdownLab/LabImageFactory.swift` — a deterministic, offline synthetic image so the loaded state can be eyeballed without the network:
```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// Synthesizes deterministic placeholder images for the Lab so the renderer's
/// loaded image state can be eyeballed offline. The hue is derived from the URL
/// so distinct images look distinct (a stable, per-launch-consistent sum of
/// scalar values — not `hashValue`, which is seeded per process).
enum LabImageFactory {
    static func placeholder(for url: URL) -> UIImage {
        let size = CGSize(width: 480, height: 300)
        let seed = url.absoluteString.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        let hue = CGFloat(seed % 360) / 360
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let top = UIColor(hue: hue, saturation: 0.5, brightness: 0.85, alpha: 1)
            let bottom = UIColor(hue: hue, saturation: 0.6, brightness: 0.5, alpha: 1)
            let space = CGColorSpaceCreateDeviceRGB()
            guard let gradient = CGGradient(colorsSpace: space,
                                            colors: [top.cgColor, bottom.cgColor] as CFArray,
                                            locations: [0, 1]) else {
                top.setFill()
                ctx.fill(CGRect(origin: .zero, size: size))
                return
            }
            ctx.cgContext.drawLinearGradient(gradient, start: .zero,
                                             end: CGPoint(x: 0, y: size.height), options: [])
        }
    }
}
```

- [ ] **Step 2: Update** `MarkdownLab/MarkdownLabApp.swift` — extend the sample with media, supply the loader, and add a logging media delegate. Make three edits:

  (a) Replace the `defaultSample` string with one that adds an image, a deliberately-broken image, an audio embed, and a video embed (all via image syntax — the parser only makes a media block from a standalone `![…](…)`, classified by extension; the loader returns `nil` for any URL containing "broken"):
```swift
private let defaultSample = """
    Valve **finally** shipped SteamOS. Ping @glidergun@lemmy.world or !linux_gaming@lemmy.world.

    ![The Steam Deck OLED on a desk](https://example.com/photos/deck-oled.jpg)

    ![this upload is gone](https://example.com/uploads/broken-pict-rs.png)

    A short clip of the boot chime:

    ![boot chime](https://example.com/media/boot-chime.mp3)

    And the install walkthrough:

    ![install walkthrough](https://example.com/media/walkthrough.mp4)

    | Subsystem | Claimed | Measured |
    |:---|---:|---:|
    | Suspend | < 2s | 1.4s |
    | Battery | 6h | 5h42m |

    ::: spoiler Benchmarks
    Locked **60 fps** at 800p medium.
    :::

    Thanks for reading.[^1]

    [^1]: Re-download over a wired connection if the checksum fails.
    """
```

  (b) Add a `makeCoordinator()` and a logging `Coordinator` to `MarkdownBodyHost`, and change `makeUIView` to set the delegate + loader (note the signature change from `context _:` to `context:`):
```swift
    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator: MarkdownBodyDelegate {
        func markdownBody(didTapLink url: URL) { print("[MarkdownLab] link \(url)") }
        func markdownBody(didTapImage url: URL, altText: String?, sourceRect: CGRect) {
            print("[MarkdownLab] image \(url) alt=\(altText ?? "-") rect=\(sourceRect)")
        }
        func markdownBody(didTapVideo url: URL) { print("[MarkdownLab] video \(url)") }
        func markdownBody(didTapAudio url: URL) { print("[MarkdownLab] audio \(url)") }
    }

    func makeUIView(context: Context) -> MarkdownBodyView {
        let view = MarkdownBodyView(
            context: MarkdownContext(kind: config.kind, textScale: config.textScale, density: config.density)
        )
        view.delegate = context.coordinator
        view.imageLoader = { url in
            // Offline synthetic image; "broken" URLs drive the failed state.
            guard !url.absoluteString.localizedCaseInsensitiveContains("broken") else { return nil }
            return LabImageFactory.placeholder(for: url)
        }
        view.setBlocks(MarkdownParser.parse(source))
        return view
    }
```

  (c) Update `updateUIView` to keep the loader set after a live source edit (the loader survives on the view, so no change is strictly required, but reassert the delegate for clarity):
```swift
    func updateUIView(_ uiView: MarkdownBodyView, context: Context) {
        uiView.delegate = context.coordinator
        uiView.setBlocks(MarkdownParser.parse(source))
    }
```

- [ ] **Step 3: Build + boot + screenshot the Lab** (visual checkpoint — the screenshot is reviewed):
```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/enumerated-rolling-plum
make project
rm -rf /tmp/mdlab-p4-dd
xcodebuild -project Spud.xcodeproj -scheme MarkdownLab \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation \
  -derivedDataPath /tmp/mdlab-p4-dd build 2>&1 | tail -8
xcrun simctl boot "iPhone 17" 2>/dev/null; open -a Simulator; sleep 3
xcrun simctl install booted "$(find /tmp/mdlab-p4-dd -name MarkdownLab.app -type d | head -1)"
xcrun simctl launch booted info.ddenis.MarkdownLab; sleep 3
xcrun simctl io booted screenshot /tmp/mdlab-phase4.png
echo "screenshot: /tmp/mdlab-phase4.png"
```
Expected: a loaded image (a gradient tile) with an italic alt caption below and a "Tap to zoom" chip bottom-right; a failed plate ("Image couldn't load" + teal "Open in browser") for the broken URL; an audio row (teal play circle + waveform + `0:48`); a video poster (dark tile + centered play + bottom transport bar). Confirm `/tmp/mdlab-phase4.png` is > 10KB and report what you see. (The image briefly shows the loading spinner before the synchronous synthetic loader resolves — that's expected.)

- [ ] **Step 4: Write the media snapshot tests** at `SpudMarkdownKitSnapshotTests/MarkdownMediaSnapshotTests.swift`. This uses `@testable import` to construct the media views directly with explicit, deterministic state (no async loader, no network), then stacks them:
```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SnapshotTesting
@testable import SpudMarkdownKit
import UIKit
import XCTest

final class MarkdownMediaSnapshotTests: XCTestCase {
    @MainActor
    private func render(kind: MarkdownContextKind, width: CGFloat = 360) -> UIView {
        let context = MarkdownContext(kind: kind)
        let audioURL = URL(string: "https://example.com/clip.mp3")!
        let videoURL = URL(string: "https://example.com/demo.mp4")!
        let imageURL = URL(string: "https://example.com/photo.jpg")!

        let audio = AudioBlockView(url: audioURL, context: context, onTap: nil)
        let video = VideoBlockView(url: videoURL, context: context, onTap: nil)

        let loaded = ImageBlockView(
            image: MarkdownImage(url: imageURL, altText: "A teal placeholder with a caption."),
            context: context, onTapImage: nil, onOpenInBrowser: nil, loader: nil
        )
        loaded.apply(state: .loaded(Self.stubImage(width: 320, height: 180)))

        let failed = ImageBlockView(
            image: MarkdownImage(url: imageURL, altText: "Alt text still shows when an image fails."),
            context: context, onTapImage: nil, onOpenInBrowser: nil, loader: nil
        )
        failed.apply(state: .failed)

        let stack = UIStackView(arrangedSubviews: [audio, video, loaded, failed])
        stack.axis = .vertical
        stack.spacing = context.interBlockGap
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = UIView()
        container.backgroundColor = .systemBackground
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            stack.widthAnchor.constraint(equalToConstant: width - 32),
        ])
        container.widthAnchor.constraint(equalToConstant: width).isActive = true
        container.layoutIfNeeded()
        container.frame = CGRect(
            x: 0, y: 0, width: width,
            height: container.systemLayoutSizeFitting(
                CGSize(width: width, height: UIView.layoutFittingCompressedSize.height)
            ).height
        )
        return container
    }

    private static func stubImage(width: CGFloat, height: CGFloat) -> UIImage {
        let size = CGSize(width: width, height: height)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.systemTeal.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    @MainActor
    func test_mediaPostLight() {
        assertSnapshot(of: render(kind: .post), as: .image(traits: UITraitCollection(userInterfaceStyle: .light)))
    }

    @MainActor
    func test_mediaPostDark() {
        assertSnapshot(of: render(kind: .post), as: .image(traits: UITraitCollection(userInterfaceStyle: .dark)))
    }

    @MainActor
    func test_mediaCommentLight() {
        assertSnapshot(of: render(kind: .comment), as: .image(traits: UITraitCollection(userInterfaceStyle: .light)))
    }

    @MainActor
    func test_mediaCommentDark() {
        assertSnapshot(of: render(kind: .comment), as: .image(traits: UITraitCollection(userInterfaceStyle: .dark)))
    }
}
```
(If `@testable import SpudMarkdownKit` fails to resolve `AudioBlockView`/`ImageBlockView`/`VideoBlockView`/`.apply(state:)`, the framework's Debug config needs `ENABLE_TESTABILITY = YES` — it is on by default for the test action, and the existing `SpudMarkdownKitTests` already `@testable`-imports the module, so this should just work.)

- [ ] **Step 5: Record + verify the media snapshots** (first run records + fails; eyeball the 4 PNGs under `SpudMarkdownKitSnapshotTests/__Snapshots__/MarkdownMediaSnapshotTests/`; re-run to verify green):
```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/enumerated-rolling-plum
make project
xcodebuild -project Spud.xcodeproj -scheme SpudMarkdownKit \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation \
  -only-testing:SpudMarkdownKitSnapshotTests/MarkdownMediaSnapshotTests test 2>&1 | tail -15
# inspect the 4 recorded PNGs, then re-run the same command — expect ** TEST SUCCEEDED **
```
Each PNG MUST be a real render: an audio row, a video poster+transport, a loaded teal image with an italic caption + "Tap to zoom" chip, and a failed plate with an italic caption. Confirm before re-running.

- [ ] **Step 6: FINAL VERIFICATION** — full SpudMarkdownKit target + Spud app:
```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/enumerated-rolling-plum
make project
xcodebuild -project Spud.xcodeproj -scheme SpudMarkdownKit \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation test 2>&1 | tail -20
xcodebuild -project Spud.xcodeproj -scheme Spud \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation build 2>&1 | tail -12
```
Expected: SpudMarkdownKit `** TEST SUCCEEDED **` (all prior tests + the 3 new renderer dispatch tests + the 4 new media snapshots) and Spud app `** BUILD SUCCEEDED **`. Report the total test count.

- [ ] **Step 7: Commit** (Lab media + loader + media snapshot test + recorded PNGs):
```bash
make project && mint run swiftformat MarkdownLab SpudMarkdownKitSnapshotTests
git add MarkdownLab SpudMarkdownKitSnapshotTests
git commit -m "test(markdown): media block snapshots + Lab media sample/loader

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Done criteria for Phase 4

- `image`, `audio`, and `video` render as real dedicated views — no `PlaceholderBlockView` remains in `MarkdownBlockRenderer.view(for:)` (it stays only as a now-unused type, removable later).
- Image shows loading → loaded/failed driven by a host loader; loaded has the "Tap to zoom" chip and fires `didTapImage` with a window-coordinate `sourceRect`; failed has an "Open in browser" escape hatch; an italic alt caption renders in every state when present.
- Audio/video render the design's static transports and tap through to `didTapAudio` / `didTapVideo`.
- `MarkdownBodyDelegate` carries the three media methods (default no-op); `MarkdownBodyView` exposes `imageLoader`.
- The Lab shows all media live (offline synthetic image + failed plate + audio + video); media snapshots recorded + eyeballed for post/comment × light/dark; full SpudMarkdownKit target + Spud app green.

## Known limitations carried forward

- Real network image loading, animated GIF, real `AVPlayer` / inline audio playback, and the zoom transition animation are integration-time (Phase 6).
- The audio/video transport bars are static design props (no real progress / scrubbing / duration).
- No max-height clamp on very tall loaded images (the box takes the image's full aspect ratio).
- **`ImageBlockView` does not fire `onContentSizeChange` after the async load resolves** (the box swaps from the 16:10 loading placeholder to the image's natural aspect / the failed plate, changing height). Harmless for the standalone self-sizing `MarkdownBodyView` and the Lab's synchronous loader, but Phase 6 integrates into cached-height table/collection cells — pass `renderer.onContentSizeChange` into `ImageBlockView` and fire it after `apply(state:)`, like `SpoilerBlockView` does on toggle. (Flagged by the final review; the load-bearing Phase-6 item.)
- **No VoiceOver element on a loaded image** — audio/video expose `isAccessibilityElement`+label+hint+`.button`, but the loaded image's tappable box isn't an announced/activatable element (alt text renders only as a visible caption). The spec wants "VoiceOver children per image"; add an element with the alt text / "Tap to zoom" / `.image` trait at Phase 6.
- **No haptic on media tap** (CodeBlockView's Copy fires `Haptics.tap()`); media taps route to the delegate, so the host adds haptics at Phase 6.
- The Phase-3 carry-overs are untouched: rounded mention/community chips, footnote ref↔def smooth scroll, fence-aware preprocessors, spoiler-in-list extraction, H6 inline formatting, the minor Phase-2 cleanups.

## Next

- **Phase 5** — snapshot-suite breadth + the design's edge redlines (long unbroken URLs, wide tables, empty spoiler, nested quotes, malformed footnotes, unknown emoji shortcodes, raw HTML as literal text) + the small test-coverage gaps.
- **Phase 6** — integration into Spud: replace `BodyTextView`/`LinkLabel` at the post + comment body call sites; wire the delegate to real navigation (`LemmyURLParser`, `URL.spud`), media (the existing media viewer / `ImageService` / `presentVideoPlayer`), and haptics; keep the off-main parse + `NSCache` pre-warm pattern; decode the `spud-markdown://` mention/community URLs; fix the carried parser limitations + rounded chips + footnote jump.
