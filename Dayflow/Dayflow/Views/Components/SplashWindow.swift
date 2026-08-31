//
//  SplashWindow.swift
//  Takt
//
//  Launch splash: activity blocks snap up on the beat, wordmark and day-rule follow.
//

import AppKit
import SwiftUI

final class SplashWindow: NSWindow {
  var onClose: (() -> Void)?

  /// Fixed lifetime. The window closes on this deadline regardless of animation
  /// progress, so a dropped frame can never delay launch.
  private static let lifetime: TimeInterval = 0.9

  init(onClose: @escaping () -> Void) {
    self.onClose = onClose

    super.init(
      contentRect: NSRect(x: 0, y: 0, width: 250, height: 250),
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )

    isOpaque = true
    backgroundColor = NSColor(srgbRed: 0.102, green: 0.102, blue: 0.102, alpha: 1)  // #1A1A1A
    level = .floating
    hasShadow = false
    isMovableByWindowBackground = false
    ignoresMouseEvents = true
    center()

    contentView = NSHostingView(rootView: SplashView())
    makeKeyAndOrderFront(nil)

    DispatchQueue.main.asyncAfter(deadline: .now() + Self.lifetime) { [weak self] in
      guard let self else { return }
      self.close()
      self.onClose?()
    }
  }
}

// MARK: - Splash

struct SplashView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  @State private var blocksIn = false
  @State private var wordmarkIn = false
  @State private var ruleIn = false
  @State private var cardIn = false

  /// Height and color per block. Fixed on purpose — the silhouette reads as a
  /// real day, not a random chart. Do not randomise.
  private static let blocks: [(height: CGFloat, color: Color)] = [
    (20, TaktColor.accent),
    (38, TaktColor.accent),
    (54, TaktColor.accent),
    (30, TaktColor.accentPressed),
    (44, TaktColor.accent),
    (16, Color(hex: "6B6B6B")),  // #6B6B6B — neutral idle block
    (34, TaktColor.accent),
  ]

  private let stagger: Double = 0.05
  private let blockGrow: Double = 0.26

  var body: some View {
    ZStack {
      TaktColor.ink

      VStack(spacing: 24) {
        blockRow
        wordmarkGroup
      }
    }
    .frame(width: 250, height: 250)
    .opacity(cardIn ? 1 : 0)
    .onAppear(perform: run)
  }

  private var blockRow: some View {
    HStack(alignment: .bottom, spacing: 5) {
      ForEach(Array(Self.blocks.enumerated()), id: \.offset) { index, block in
        Rectangle()
          .fill(block.color)
          .frame(width: 9, height: block.height)
          .scaleEffect(y: blocksIn ? 1 : 0, anchor: .bottom)
          .animation(
            reduceMotion
              ? nil
              : .timingCurve(0.2, 0.9, 0.3, 1, duration: blockGrow)
                .delay(Double(index) * stagger),
            value: blocksIn
          )
      }
    }
    .frame(height: 54, alignment: .bottom)
  }

  private var wordmarkGroup: some View {
    VStack(spacing: 11) {
      Text("TAKT")
        .font(TaktFont.display(34))
        .kerning(2.04)  // 0.06em at 34pt
        .foregroundStyle(.white)
        .opacity(wordmarkIn ? 1 : 0)
        .offset(y: wordmarkIn ? 0 : 6)

      // Day rule: track with a fill that sweeps from the leading edge.
      Rectangle()
        .fill(TaktColor.inkDivider)
        .frame(width: 108, height: 2)
        .overlay(alignment: .leading) {
          Rectangle()
            .fill(TaktColor.accent)
            .scaleEffect(x: ruleIn ? 1 : 0, anchor: .leading)
        }
    }
  }

  private func run() {
    guard !reduceMotion else {
      withAnimation(.easeOut(duration: 0.15)) {
        cardIn = true
        blocksIn = true
        wordmarkIn = true
        ruleIn = true
      }
      return
    }

    withAnimation(.easeOut(duration: 0.08)) { cardIn = true }

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
      blocksIn = true  // per-block delays are attached in blockRow
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
      withAnimation(.easeOut(duration: 0.28)) { wordmarkIn = true }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
      withAnimation(.timingCurve(0.3, 0.7, 0.2, 1, duration: 0.46)) { ruleIn = true }
    }
  }
}