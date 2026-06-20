# DicyaninMockHandTracking

Simulated hand tracking for visionOS. Drives mock hand positions and pinch gestures so hand-tracked apps can be developed and tested in the visionOS simulator, where ARKit hand tracking isn't available.

## Install

```swift
.package(url: "https://github.com/hunterh37/DicyaninMockHandTracking.git", from: "2.0.0")
```

Then add `DicyaninMockHandTracking` to your target's dependencies.

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

## Requirements

- visionOS 1.0+
- Swift 5.9+
