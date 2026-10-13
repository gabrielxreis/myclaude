import SwiftUI

// Mochi's outfits are Coucou's character: empty stand-ins in My Cloud.

let kVIEW_TILT: CGFloat = -0.30

struct MochiH {
    let R, rx, ry: CGFloat
    let yaw, pitch: CGFloat
    let view: CGFloat      // = VIEW_TILT (-0.30)
    let physDx, physDy: CGFloat
    let roll: CGFloat

    init(R: CGFloat, yaw: CGFloat = 0, pitch: CGFloat = 0,
         physDx: CGFloat = 0, physDy: CGFloat = 0, roll: CGFloat = 0) {
        self.R = R
        self.rx = R * 1.14
        self.ry = R * 0.88
        self.yaw = yaw
        self.pitch = pitch
        self.view = kVIEW_TILT
        self.physDx = physDx
        self.physDy = physDy
        self.roll = roll
    }
}

struct EyeFrame {
    let sd: CGFloat   // -1 left, +1 right
    let x, y: CGFloat
    let fx, fy: CGFloat
    let visible: Bool
    let w, h: CGFloat
}

func mEyeFrames(_ H: MochiH) -> [EyeFrame] { [] }

func mochiEyePositions(yaw: CGFloat, pitch: CGFloat, rx: CGFloat, ry: CGFloat)
    -> [(ex: CGFloat, ey: CGFloat, fx: CGFloat, fy: CGFloat)] { [] }

func mochiOutfitPath(_ rx: CGFloat, _ ry: CGFloat) -> Path { Path() }

func outfitBodyTransform(context: GraphicsContext, cx: CGFloat, cy: CGFloat,
                          tilt: CGFloat, sx: CGFloat, sy: CGFloat) -> GraphicsContext { context }

func drawOutfitFrontStatic(
    context: GraphicsContext,
    outfit: Outfit, H: MochiH,
    cx: CGFloat, cy: CGFloat, tilt: CGFloat, sx: CGFloat, sy: CGFloat,
    roll: CGFloat, morph: CGFloat, isMini: Bool,
    presence: CGFloat = 1, rollTurns: CGFloat = 1
) { }

func drawOutfitBehindStatic(
    context: GraphicsContext,
    outfit: Outfit, H: MochiH,
    cx: CGFloat, cy: CGFloat, tilt: CGFloat, sx: CGFloat, sy: CGFloat,
    roll: CGFloat, morph: CGFloat, isMini: Bool,
    presence: CGFloat = 1, rollTurns: CGFloat = 1
) { }
