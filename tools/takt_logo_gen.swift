#!/usr/bin/env swift
//
//  TAKT logo generator — Wertwandler metronome mark.
//
//  Deterministic CoreGraphics rendering (no AI image generation): exact
//  geometry, exact token colors, sharp edges at every size.
//
//  Geometry: a trapezoid metronome body (TAKT orange), a charcoal pendulum
//  rod tilted right, a square weight on the rod. Flat, no gradients, no
//  shadows, no rounding — matching the TAKT design language.
//
//  Usage: swift takt_logo_gen.swift <out-dir>
//

import AppKit
import CoreGraphics
import Foundation

// MARK: - Tokens (mirror TaktTheme.swift)

let taktOrange = CGColor(red: 0xFC / 255.0, green: 0x97 / 255.0, blue: 0x1C / 255.0, alpha: 1)
let taktInk = CGColor(red: 0x1A / 255.0, green: 0x1A / 255.0, blue: 0x1A / 255.0, alpha: 1)

enum Variant {
  case appIcon   // orange body on transparent, generous padding
  case mark      // tight mark, transparent background
  case menuBar   // monochrome template (ink only), tight
}

func render(size: CGFloat, variant: Variant) -> CGImage? {
  let px = Int(size)
  guard
    let ctx = CGContext(
      data: nil, width: px, height: px,
      bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
  else { return nil }

  ctx.interpolationQuality = .high
  ctx.setShouldAntialias(true)

  // Inset: app icons get macOS-style breathing room, marks sit tighter.
  let inset: CGFloat = {
    switch variant {
    case .appIcon: return size * 0.14
    case .mark: return size * 0.06
    case .menuBar: return size * 0.08
    }
  }()

  let box = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)

  // --- Body: trapezoid (metronome shell) ---
  // Narrow top, wide base. Flat top edge so the shape stays square-ish and
  // reads at 16px instead of collapsing into a spike.
  let baseY = box.minY + box.height * 0.06
  let topY = box.maxY - box.height * 0.04
  let halfBase = box.width * 0.44
  let halfTop = box.width * 0.15
  let cx = box.midX

  let body = CGMutablePath()
  body.move(to: CGPoint(x: cx - halfBase, y: baseY))
  body.addLine(to: CGPoint(x: cx + halfBase, y: baseY))
  body.addLine(to: CGPoint(x: cx + halfTop, y: topY))
  body.addLine(to: CGPoint(x: cx - halfTop, y: topY))
  body.closeSubpath()

  let bodyColor: CGColor = (variant == .menuBar) ? taktInk : taktOrange
  ctx.setFillColor(bodyColor)
  ctx.addPath(body)
  ctx.fillPath()

  // --- Pendulum rod: straight line from base center, tilted right ---
  let rodColor: CGColor = (variant == .menuBar) ? taktInk : taktInk
  // Thin rod: at 512px it reads as a pendulum, not a support beam. Floored at
  // 1px so 16px renders still show a line.
  let rodWidth = max(1, size * 0.030)
  let rodBottom = CGPoint(x: cx, y: baseY + box.height * 0.10)
  // Tip sits just below the box top so the bob (centred on it) stays inside
  // the canvas at every size.
  let rodTip = CGPoint(x: cx + box.width * 0.28, y: box.maxY - box.height * 0.05)

  // On the monochrome menu-bar variant the rod must stay visible against the
  // ink body: knock it out instead of drawing ink on ink.
  if variant == .menuBar {
    ctx.setBlendMode(.clear)
  }
  ctx.setStrokeColor(rodColor)
  ctx.setLineWidth(rodWidth)
  ctx.setLineCap(.butt)
  ctx.move(to: rodBottom)
  ctx.addLine(to: rodTip)
  ctx.strokePath()

  // --- Weight: solid square bob centred on the rod tip ---
  let weightSide = max(2, size * 0.13)
  let weightRect = CGRect(
    x: rodTip.x - weightSide / 2,
    y: rodTip.y - weightSide / 2,
    width: weightSide,
    height: weightSide)
  ctx.setFillColor(rodColor)
  ctx.fill(weightRect)

  if variant == .menuBar {
    ctx.setBlendMode(.normal)
  }

  return ctx.makeImage()
}

func writePNG(_ image: CGImage, to url: URL) throws {
  let rep = NSBitmapImageRep(cgImage: image)
  rep.size = NSSize(width: image.width, height: image.height)
  guard let data = rep.representation(using: .png, properties: [:]) else {
    throw NSError(domain: "takt", code: 1, userInfo: [NSLocalizedDescriptionKey: "PNG encode failed"])
  }
  try data.write(to: url)
}

// MARK: - Main

let args = CommandLine.arguments
guard args.count >= 2 else {
  FileHandle.standardError.write("usage: swift takt_logo_gen.swift <out-dir>\n".data(using: .utf8)!)
  exit(2)
}
let outDir = URL(fileURLWithPath: args[1], isDirectory: true)
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

struct Job {
  let name: String
  let size: CGFloat
  let variant: Variant
}

let jobs: [Job] = [
  // AppIcon set (macOS requires all of these)
  Job(name: "appicon_16", size: 16, variant: .appIcon),
  Job(name: "appicon_32", size: 32, variant: .appIcon),
  Job(name: "appicon_64", size: 64, variant: .appIcon),
  Job(name: "appicon_128", size: 128, variant: .appIcon),
  Job(name: "appicon_256", size: 256, variant: .appIcon),
  Job(name: "appicon_512", size: 512, variant: .appIcon),
  Job(name: "appicon_1024", size: 1024, variant: .appIcon),
  // In-app marks
  Job(name: "mark_64", size: 64, variant: .mark),
  Job(name: "mark_128", size: 128, variant: .mark),
  Job(name: "mark_256", size: 256, variant: .mark),
  Job(name: "mark_512", size: 512, variant: .mark),
  // Menu bar template (monochrome)
  Job(name: "menubar_18", size: 18, variant: .menuBar),
  Job(name: "menubar_36", size: 36, variant: .menuBar),
  Job(name: "menubar_54", size: 54, variant: .menuBar),
]

var written: [String] = []
for job in jobs {
  guard let img = render(size: job.size, variant: job.variant) else {
    print("FAIL \(job.name)")
    exit(1)
  }
  let url = outDir.appendingPathComponent("\(job.name).png")
  try writePNG(img, to: url)
  written.append("\(job.name).png \(img.width)x\(img.height)")
}

print("WROTE \(written.count) files to \(outDir.path)")
for w in written { print("  " + w) }
