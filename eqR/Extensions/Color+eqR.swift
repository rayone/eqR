import SwiftUI

extension Color {
    /// Shorthand for the response curve's colour: TokyoNight cyan.
    static var eqRSignal: Color { Theme.TokyoNight.cyan }

    /// Shorthand for `Theme.currentAccentColor` matching TokyoNight or system accent.
    static var eqRAccent: Color {
        Theme.currentAccentColor
    }
}
