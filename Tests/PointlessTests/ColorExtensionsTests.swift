import AppKit
@testable import PointlessCore
import SwiftUI
import XCTest

final class ColorExtensionsTests: XCTestCase {
  func testToHexGrayscaleBlackDoesNotCrash() {
    let hex = Color.black.toHex()
    XCTAssertEqual(hex, "#000000")
  }

  func testToHexGrayscaleWhiteDoesNotCrash() {
    let hex = Color.white.toHex()
    XCTAssertEqual(hex, "#FFFFFF")
  }

  func testToHexGrayscaleMidGrayDoesNotCrash() {
    let grayColor = Color(nsColor: NSColor(white: 0.5, alpha: 1.0))
    let hex = grayColor.toHex()
    XCTAssertEqual(hex, "#808080")
  }

  func testToHexPrimaryColors() {
    let pureRed = Color(red: 1.0, green: 0.0, blue: 0.0)
    XCTAssertEqual(pureRed.toHex(), "#FF0000")

    let pureGreen = Color(red: 0.0, green: 1.0, blue: 0.0)
    XCTAssertEqual(pureGreen.toHex(), "#00FF00")

    let pureBlue = Color(red: 0.0, green: 0.0, blue: 1.0)
    XCTAssertEqual(pureBlue.toHex(), "#0000FF")
  }

  func testInitFromHexValidStrings() {
    let red = Color(hex: "#FF0000")
    XCTAssertNotNil(red)
    XCTAssertEqual(red?.toHex(), "#FF0000")

    let blueWithoutPrefix = Color(hex: "0000FF")
    XCTAssertNotNil(blueWithoutPrefix)
    XCTAssertEqual(blueWithoutPrefix?.toHex(), "#0000FF")

    let lowercase = Color(hex: "#00ff00")
    XCTAssertNotNil(lowercase)
    XCTAssertEqual(lowercase?.toHex(), "#00FF00")
  }

  func testInitFromHexRejectsInvalidStrings() {
    XCTAssertNil(Color(hex: ""))
    XCTAssertNil(Color(hex: "#FFF"))
    XCTAssertNil(Color(hex: "#12345"))
    XCTAssertNil(Color(hex: "#1234567"))
    XCTAssertNil(Color(hex: "#ZZZZZZ"))
    XCTAssertNil(Color(hex: "007AGH"))
  }
}
