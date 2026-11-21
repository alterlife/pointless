import XCTest
import AppKit
import SwiftUI
@testable import PointlessCore

final class ScreenshotGeneratorTests: XCTestCase {
  @MainActor
  func testRenderScreenshots() throws {
    let outputDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      .appendingPathComponent("docs")
      .appendingPathComponent("images")
    try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

    guard let screen = NSScreen.main ?? NSScreen.screens.first else {
      print("No screen available for screenshot generation")
      return
    }

    KeyboardNavigation.shared.start()
    let screenFrame = screen.frame
    let width = screenFrame.width
    let height = screenFrame.height

    // 1. Settings Window Mockup (shows full Pointless Settings UI)
    let settingsContent = SettingsPreviewView()
      .preferredColorScheme(.dark)
    let settingsWindow = WindowMockup(title: "Pointless Settings", size: CGSize(width: 740, height: 620)) {
      settingsContent
    }
    .preferredColorScheme(.dark)
    .frame(width: 820, height: 700)
    .background(Color(red: 0.08, green: 0.09, blue: 0.12))
    saveView(settingsWindow, size: CGSize(width: 820, height: 700), to: outputDir.appendingPathComponent("settings.png"))

    // 2. Zone Mode - Level 1 Lookahead
    let lookaheadState = OverlayState()
    lookaheadState.gridRegion = screenFrame
    lookaheadState.gridBreadcrumb = "[ · · · · ]"
    lookaheadState.gridPathPrefix = ""
    let lookaheadView = ZStack {
      SampleDesktopView(width: width, height: height)
      OverlayContentView(
        state: lookaheadState,
        screen: screen,
        allScreenFrames: [screenFrame]
      )
    }
    .frame(width: width, height: height)
    saveView(lookaheadView, size: CGSize(width: width, height: height), to: outputDir.appendingPathComponent("zone-mode-lookahead.png"))

    // 3. Zone Mode - Final Level (Labelled Points)
    let finalState = OverlayState()
    let finalRegion = CGRect(
      x: screenFrame.minX + width * 0.35,
      y: screenFrame.minY + height * 0.32,
      width: width * 0.3,
      height: height * 0.3
    )
    finalState.gridRegion = finalRegion
    finalState.gridBreadcrumb = "[ u j k · ]"
    finalState.gridPathPrefix = "ujk"
    let finalView = ZStack {
      SampleDesktopView(width: width, height: height)
      OverlayContentView(
        state: finalState,
        screen: screen,
        allScreenFrames: [screenFrame]
      )
    }
    .frame(width: width, height: height)
    saveView(finalView, size: CGSize(width: width, height: height), to: outputDir.appendingPathComponent("zone-mode-final.png"))

    // 4. Label Mode - Element Navigation
    let labelState = OverlayState()
    let mockFrames: [(CGRect, String)] = [
      (CGRect(x: width * 0.22, y: height * 0.82, width: 90, height: 28), "fj"),
      (CGRect(x: width * 0.30, y: height * 0.82, width: 90, height: 28), "fk"),
      (CGRect(x: width * 0.38, y: height * 0.82, width: 90, height: 28), "fl"),
      (CGRect(x: width * 0.22, y: height * 0.70, width: 240, height: 32), "fa"),
      (CGRect(x: width * 0.22, y: height * 0.60, width: 340, height: 28), "fs"),
      (CGRect(x: width * 0.22, y: height * 0.50, width: 140, height: 34), "fd"),
      (CGRect(x: width * 0.34, y: height * 0.50, width: 140, height: 34), "fg"),
      (CGRect(x: width * 0.55, y: height * 0.65, width: 280, height: 180), "fu"),
      (CGRect(x: width * 0.75, y: height * 0.65, width: 220, height: 180), "fi"),
      (CGRect(x: width * 0.55, y: height * 0.38, width: 520, height: 160), "fo")
    ]
    labelState.labeledElements = mockFrames.map { frame, label in
      let screenF = CGRect(
        x: screenFrame.minX + frame.minX,
        y: screenFrame.minY + frame.minY,
        width: frame.width,
        height: frame.height
      )
      return LabeledElement(
        label: label,
        element: NavigationTarget(
          element: FixtureAXNode(role: "AXButton", frame: screenF),
          screenFrame: screenF,
          role: "AXButton",
          screen: screen,
          groupingAncestor: .walkNode(0),
          node: nil,
          text: ""
        )
      )
    }
    let labelView = ZStack {
      SampleDesktopView(width: width, height: height)
      OverlayContentView(
        state: labelState,
        screen: screen,
        allScreenFrames: [screenFrame]
      )
    }
    .frame(width: width, height: height)
    saveView(labelView, size: CGSize(width: width, height: height), to: outputDir.appendingPathComponent("label-mode.png"))

    print("Generated screenshots in \(outputDir.path)")
  }

  @MainActor
  private func saveView<V: View>(_ view: V, size: CGSize, to url: URL) {
    let hostingView = NSHostingView(rootView: view)
    hostingView.frame = NSRect(origin: .zero, size: size)
    hostingView.layoutSubtreeIfNeeded()

    guard let rep = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else { return }
    hostingView.cacheDisplay(in: hostingView.bounds, to: rep)
    guard let data = rep.representation(using: .png, properties: [:]) else { return }
    try? data.write(to: url)
  }
}

// MARK: - Settings Preview for Documentation

struct SettingsPreviewView: View {
  let settingsView = SettingsView()
  @ObservedObject var navigation = KeyboardNavigation.shared

  var body: some View {
    VStack(spacing: 0) {
      // Tab Bar Mockup
      HStack(spacing: 24) {
        HStack(spacing: 6) {
          Image(systemName: "keyboard")
            .font(.system(size: 14))
          Text("Pointless")
            .font(.system(size: 13, weight: .semibold))
        }
        .foregroundColor(.white)
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .background(Capsule().fill(Color.white.opacity(0.12)))

        HStack(spacing: 6) {
          Image(systemName: "puzzlepiece.extension")
            .font(.system(size: 14))
          Text("Plugins")
            .font(.system(size: 13, weight: .regular))
        }
        .foregroundColor(.white.opacity(0.6))

        Spacer()
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 10)
      .background(Color(red: 0.13, green: 0.13, blue: 0.16))

      Divider().background(Color.white.opacity(0.08))

      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          ForEach(navigation.settings().definitions) { def in
            settingsView.settingView(for: def, host: navigation)
          }
        }
        .padding(24)
      }
      .background(Color(red: 0.11, green: 0.11, blue: 0.14))
    }
  }
}

// MARK: - Mock Desktop & Window UI for Screenshots

struct WindowMockup<Content: View>: View {
  let title: String
  let size: CGSize
  let content: () -> Content

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        HStack(spacing: 7) {
          Circle().fill(Color(red: 1.0, green: 0.38, blue: 0.35)).frame(width: 12, height: 12)
          Circle().fill(Color(red: 1.0, green: 0.74, blue: 0.22)).frame(width: 12, height: 12)
          Circle().fill(Color(red: 0.16, green: 0.78, blue: 0.25)).frame(width: 12, height: 12)
        }
        .padding(.leading, 14)
        Spacer()
        Text(title)
          .font(.system(size: 13, weight: .semibold))
          .foregroundColor(.white.opacity(0.85))
        Spacer()
        Spacer().frame(width: 50)
      }
      .frame(height: 38)
      .background(Color(red: 0.16, green: 0.16, blue: 0.18))

      Divider().background(Color.white.opacity(0.1))

      content()
    }
    .frame(width: size.width, height: size.height)
    .cornerRadius(10)
    .overlay(
      RoundedRectangle(cornerRadius: 10)
        .stroke(Color.white.opacity(0.15), lineWidth: 1)
    )
    .shadow(color: .black.opacity(0.5), radius: 24, x: 0, y: 12)
  }
}

struct SampleDesktopView: View {
  let width: CGFloat
  let height: CGFloat

  var body: some View {
    ZStack {
      // Desktop wallpaper
      LinearGradient(
        colors: [Color(red: 0.08, green: 0.10, blue: 0.15), Color(red: 0.04, green: 0.05, blue: 0.08)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )

      // Window in background
      VStack(spacing: 0) {
        HStack(spacing: 12) {
          HStack(spacing: 6) {
            Circle().fill(Color(red: 1.0, green: 0.38, blue: 0.35)).frame(width: 11, height: 11)
            Circle().fill(Color(red: 1.0, green: 0.74, blue: 0.22)).frame(width: 11, height: 11)
            Circle().fill(Color(red: 0.16, green: 0.78, blue: 0.25)).frame(width: 11, height: 11)
          }
          Text("Pointless — Productivity App")
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.white.opacity(0.6))
          Spacer()
          HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.12)).frame(width: 80, height: 24)
            RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.12)).frame(width: 80, height: 24)
            RoundedRectangle(cornerRadius: 6).fill(Color.blue.opacity(0.7)).frame(width: 90, height: 24)
          }
        }
        .padding(.horizontal, 16)
        .frame(height: 42)
        .background(Color(red: 0.14, green: 0.14, blue: 0.17))

        Divider().background(Color.white.opacity(0.08))

        HStack(spacing: 0) {
          VStack(alignment: .leading, spacing: 14) {
            ForEach(0..<7) { _ in
              HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.15)).frame(width: 18, height: 18)
                RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.2)).frame(width: 120, height: 14)
              }
            }
            Spacer()
          }
          .padding(22)
          .frame(width: 240)
          .background(Color(red: 0.11, green: 0.11, blue: 0.13))

          Divider().background(Color.white.opacity(0.08))

          VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 16) {
              RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)).frame(height: 180)
              RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)).frame(height: 180)
            }
            RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)).frame(height: 240)
            Spacer()
          }
          .padding(28)
          .background(Color(red: 0.13, green: 0.13, blue: 0.16))
        }
      }
      .frame(width: width * 0.88, height: height * 0.82)
      .cornerRadius(12)
      .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1))
      .shadow(color: .black.opacity(0.6), radius: 30, x: 0, y: 15)
    }
    .ignoresSafeArea()
  }
}
