import AppKit

struct ParsedShortcut {
  let modifiers: NSEvent.ModifierFlags
  let keyCode: UInt16
}

func parseShortcutString(_ display: String) -> ParsedShortcut {
  var mods: NSEvent.ModifierFlags = []
  var remaining = display
  let modifierChars: Set<Character> = ["\u{2303}", "\u{2325}", "\u{21E7}", "\u{2318}"]

  while let first = remaining.first, modifierChars.contains(first) {
    switch first {
    case "\u{2303}": mods.insert(.control)
    case "\u{2325}": mods.insert(.option)
    case "\u{21E7}": mods.insert(.shift)
    case "\u{2318}": mods.insert(.command)
    default: break
    }
    remaining.removeFirst()
  }

  return ParsedShortcut(modifiers: mods, keyCode: keyCodeFromName(remaining))
}

private func keyCodeFromName(_ name: String) -> UInt16 {
  switch name {
  case "Space": return 49
  case "Return": return 36
  case "Tab": return 48
  case "Delete": return 51
  case "Esc": return 53
  case "\u{2190}": return 123
  case "\u{2192}": return 124
  case "\u{2193}": return 125
  case "\u{2191}": return 126
  default:
    return carbonKeyCode(for: name.lowercased()) ?? 49
  }
}

private func carbonKeyCode(for char: String) -> UInt16? {
  let map: [String: UInt16] = [
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
    "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
    "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22,
    "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
    "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37,
    "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44,
    "n": 45, "m": 46, ".": 47
  ]
  return map[char]
}
