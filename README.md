# DicyaninMockHandTracking

Simulated hand tracking for visionOS. Drives mock hand positions and pinch gestures so hand-tracked apps can be developed and tested in the visionOS simulator, where ARKit hand tracking isn't available.

The idea: write your app against one hand-pose source. In the **simulator** it reads from `MockHandTrackingController` and you steer the hands with an on-screen control panel. On a **real device** the exact same call sites read live ARKit `HandAnchor` data — no changes to your app logic.

**New in 3.0:** drive that same mock state from a **real webcam**. The included [`WebcamHandRunner`](Examples/WebcamHandRunner) macOS app uses Vision hand-pose estimation to watch your hands and streams the poses over the local network straight into your **live, running** visionOS app — so you hold your hands up to your Mac's camera and the sphere/gun/hand in the simulator follows. See [Webcam hand tracking](#webcam-hand-tracking-30).

| Resting | Aiming + pinch |
| --- | --- |
| ![Control panel](Screenshots/control-panel.png) | ![Control panel, active](Screenshots/control-panel-active.png) |

## Install

```swift
.package(url: "https://github.com/hunterh37/DicyaninMockHandTracking.git", from: "3.0.0")
```

Three products ship from this package:

- `DicyaninMockHandTracking` — the visionOS mock controller + control overlay (add this to your app target).
- `DicyaninHandTrackingTransport` — a small, cross-platform (visionOS + macOS) networking layer that carries hand poses between processes. The webcam runner uses it; your app only needs it if you call the transport types directly.
- `DicyaninHandGlove` — a rigged **glove** that maps every hand-skeleton joint, built directly on Apple's [_Tracking and visualizing hand movement_](https://developer.apple.com/documentation/visionos/tracking-and-visualizing-hand-movement) sample. One view follows your real hands on device and the mock controller in the simulator. See [Glove hands](#glove-hands).

Then add `DicyaninMockHandTracking` (and `DicyaninHandGlove` if you want gloves) to your target's dependencies.

## Usage

Read mock hand state from the shared controller in simulator builds instead of ARKit:

```swift
import DicyaninMockHandTracking

let controller = MockHandTrackingController.shared

// Published hand state
controller.leftHandPosition   // SIMD3<Float>, head-relative
controller.rightHandPosition
controller.leftHandYaw        // Float, radians
controller.rightHandYaw
controller.isPinching         // Bool

// Fire a momentary pinch
controller.simulatePinch()

// 60 fps update stream
for await _ in controller.updates() {
    // read positions each tick
}
```

Add the on-screen control overlay (joysticks + rotation sliders + pinch) to your simulator UI:

```swift
import SwiftUI
import DicyaninMockHandTracking

MockHandControlView()
```

## Simulator vs. device

Put the source switch behind a single type so your app never branches on environment. In the simulator it reads the mock controller; on device it reads ARKit `HandAnchor`s:

```swift
import simd
import DicyaninMockHandTracking
#if !targetEnvironment(simulator)
import ARKit
#endif

struct HandPose {
    var position: SIMD3<Float>
    var isPinching: Bool
}

@MainActor
final class HandSource {
    #if targetEnvironment(simulator)
    // --- Simulator: driven by MockHandControlView ---
    private let mock = MockHandTrackingController.shared

    func rightHand() -> HandPose {
        HandPose(position: mock.rightHandPosition, isPinching: mock.isPinching)
    }

    /// 60 fps tick stream you can await in your update loop.
    func updates() -> AsyncStream<Void> { mock.updates() }

    #else
    // --- Device: real ARKit hand tracking ---
    private let session = ARKitSession()
    private let provider = HandTrackingProvider()

    func start() async throws {
        try await session.run([provider])
    }

    func rightHand() -> HandPose {
        guard let anchor = provider.latestAnchors.rightHand,
              anchor.isTracked,
              let wrist = anchor.handSkeleton?.joint(.wrist) else {
            return HandPose(position: .zero, isPinching: false)
        }
        let m = anchor.originFromAnchorTransform * wrist.anchorFromJointTransform
        let position = SIMD3<Float>(m.columns.3.x, m.columns.3.y, m.columns.3.z)
        return HandPose(position: position, isPinching: detectPinch(anchor))
    }
    #endif
}
```

Your game/app code then just calls `handSource.rightHand()` and never knows which backend produced it. Swap `MockHandControlView()` into a window only in simulator builds:

```swift
#if targetEnvironment(simulator)
MockHandControlView()
#endif
```

## Webcam hand tracking (3.0)

Develop with your actual hands instead of dragging joysticks. The
[`WebcamHandRunner`](Examples/WebcamHandRunner) macOS app estimates your hand
poses from any webcam (Apple's Vision `VNDetectHumanHandPoseRequest`) and
broadcasts them; your visionOS app subscribes and applies them to
`MockHandTrackingController.shared`. Because every existing consumer already
reacts to that controller's `@Published` state, the webcam poses flow through
the **exact same path** the on-screen joysticks use — no consumer code changes.

```
┌──────────────────────┐   hand poses (JSON/TCP)   ┌──────────────────────────┐
│  WebcamHandRunner.app │ ────────────────────────▶ │  your visionOS app (sim) │
│  webcam → Vision      │   _dicyaninhands._tcp     │  MockHandTrackingController│
└──────────────────────┘                            └──────────────────────────┘
```

**1. Launch the runner** (the simulator shares your Mac's network, so localhost just works):

```bash
cd Examples/WebcamHandRunner
xcodegen generate          # one-time, or after editing project.yml
open WebcamHandRunner.xcodeproj
# Build & run the WebcamHandRunner scheme, grant camera access, hold your hands up.
```

**2. Connect from your visionOS app** — one call at launch, in simulator builds:

```swift
import DicyaninMockHandTracking

struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    #if targetEnvironment(simulator)
                    MockHandTrackingController.shared.connectToWebcamRunner() // localhost:50673
                    #endif
                }
        }
    }
}
```

That's it. Move your hands in front of the camera and the same `leftHandPosition`
/ `rightHandPosition` / `isPinching` state updates live; pinch thumb-to-index to
fire a pinch. Tune horizontal/vertical reach and mirroring in the runner window.

On a **real Vision Pro** on the same Wi-Fi as the Mac, use Bonjour discovery
instead of localhost:

```swift
MockHandTrackingController.shared.connectToWebcamRunner(bonjourName: nil) // first runner found
```

Call `disconnectWebcamRunner()` to hand control back to the on-screen joysticks.

> The webcam gives a single 2D view, so depth (`z`) is approximated from hand
> size and yaw from the wrist→knuckle direction. It's built for fast iteration
> in the simulator, not metric precision — ship against ARKit on device.

## Glove hands

`DicyaninHandGlove` re-implements Apple's [_Tracking and visualizing hand movement_](https://developer.apple.com/documentation/visionos/tracking-and-visualizing-hand-movement) sample as a single drop-in view. Apple's sample is a `HandTrackingComponent` + `HandTrackingSystem` that maps all 27 hand-skeleton joints to entities every frame (`originFromAnchorTransform * anchorFromJointTransform`); this package vendors that engine faithfully and adds a filled-glove look, a slot for a rigged glove USDZ, and a **simulator bridge** so the glove follows `MockHandTrackingController` when ARKit hand tracking isn't available.

Re-implementing the glove sample is now one view:

```swift
import DicyaninHandGlove

ImmersiveSpace(id: "Gloves") {
    HandGloveView()
}
```

That's the whole integration. On device the gloves follow the real hand skeleton joint-for-joint; in the simulator they follow the joysticks / webcam bridge — same code path.

Tune the look, or drop in your own rigged glove model:

```swift
// Apple's original spheres-only look
HandGloveView(configuration: .init(style: .joints))

// Right hand only, custom color
HandGloveView(configuration: .init(
    tracksLeftHand: false,
    color: .orange
))

// Your own rigged glove USDZ, added to the app bundle.
// (Apple's keynote "RightGlove_v001.usdz" was never shipped publicly — supply
//  your own export, or any glove mesh, here.)
HandGloveView(configuration: .init(
    style: .model(left: "LeftGlove_v001", right: "RightGlove_v001")
))
```

> Apple's hand-tracking sample renders joints as plain spheres and ships no glove
> asset — the `RightGlove_v001.usdz` shown in WWDC23's _Go beyond the window with
> SwiftUI_ was a keynote demo asset, not a downloadable file. `.glove` gives you a
> filled, articulated glove with no asset; `.model(left:right:)` is the slot to
> load a real rigged USDZ when you have one.

## Example app

A complete, runnable visionOS example lives in [`Examples/HandTrackingDemo`](Examples/HandTrackingDemo). It opens an immersive space with a **glove on each hand** (`HandGloveView`) — drag the joysticks in `MockHandControlView` and the gloves move with them. On a real device the same view follows your actual hands joint-for-joint.

The project is defined with [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`project.yml`) and the generated `.xcodeproj` is checked in, so you can either open it directly or regenerate it:

```bash
# Just open it
open Examples/HandTrackingDemo/HandTrackingDemo.xcodeproj

# …or regenerate the project from project.yml
cd Examples/HandTrackingDemo && xcodegen generate
```

Then run the `HandTrackingDemo` scheme on a visionOS simulator, tap **Open Immersive Scene**, and steer the joysticks to move the gloves.

## Requirements

- visionOS 1.0+
- Swift 5.9+
- macOS 13.0+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) for the optional `WebcamHandRunner`

## License

MIT — see [LICENSE](LICENSE).

---

## 🚀 Built With These Packages

We ship these packages for free, and run them in our own published visionOS apps on the App Store:

### [CYBERZOMBIES](https://apps.apple.com/us/app/id6770111930): powered by [DicyaninHandTracking](https://github.com/hunterh37/DicyaninHandTracking)

<img src="https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/8f/4c/5a/8f4c5add-c887-4803-62f5-36fe134c4df5/AppIcon.lsr/512x512bb.jpg" width="100" />

Room-scale spatial combat where you raise your hands, lock on, and blast waves of cyber-infected enemies that spill out of your own walls, built on hand-driven aiming and `DicyaninARKitSession`.

### [RealityMesh](https://apps.apple.com/us/app/id6474943391): powered by [DicyaninSceneReconstruction](https://github.com/hunterh37/DicyaninSceneReconstruction)

<img src="https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/1e/b8/9b/1eb89b71-5d0b-f11f-cc22-ac723c722f98/AppIcon.lsr/512x512bb.jpg" width="100" />

Uses ARKit and the LiDAR Scanner to build a live mesh of your surroundings, then reskins your real room with customizable textures.

### [Spatial Model Viewer](https://apps.apple.com/us/app/id6475698595): powered by [DicyaninAssetPreloader](https://github.com/hunterh37/DicyaninAssetPreloader)

<img src="https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/a4/ca/3c/a4ca3c52-1768-d6fa-2f2b-4bd37dcde49c/AppIcon.lsr/512x512bb.jpg" width="100" />

Turns your space into a 3D modeling studio with glow and procedural shader effects, loading and cloning models on demand without parsing from disk on the main thread.
