import SwiftUI

extension Color {
    /// Shorthand for `Theme.signal` at the call sites that read better with it,
    /// or TokyoNight cyan when TokyoNight is active.
    static var eqRSignal: Color {
        Theme.isTokyoNight ? Theme.TokyoNight.cyan : Theme.signal
    }

    /// Shorthand for `Theme.currentAccentColor` matching TokyoNight or system accent.
    static var eqRAccent: Color {
        Theme.currentAccentColor
    }
}
