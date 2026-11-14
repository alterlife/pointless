// Bad words that must never appear in navigation labels.
// Filtered from LDNOOBW (https://github.com/LDNOOBW/List-of-Dirty-Naughty-Obscene-and-Otherwise-Bad-Words,
// en list, CC-BY-4.0): lowercase alpha words of length <= 4 — the longest a label can be.
// Regenerate by filtering the en list to `^[a-z]{1,4}$`.
enum BannedLabelWords {
  static let all: Set<String> = [
    "anal", "anus", "ass", "bbw", "bdsm", "boob", "butt", "clit", "cock",
    "coon", "cum", "cunt", "dick", "dvda", "fag", "fuck", "guro", "jizz",
    "kike", "milf", "mong", "nsfw", "nude", "orgy", "paki", "poof", "poon",
    "porn", "pthc", "quim", "rape", "scat", "sex", "sexo", "sexy", "shit",
    "slut", "smut", "spic", "suck", "tit", "tits", "twat", "wank", "xx",
    "xxx", "yaoi"
  ]
}
