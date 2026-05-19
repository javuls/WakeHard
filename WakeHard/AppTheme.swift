import SwiftUI

enum AppTheme {
    static let background = Color(red: 0.055, green: 0.059, blue: 0.067)
    static let panel = Color(red: 0.090, green: 0.094, blue: 0.106)
    static let panelSecondary = Color(red: 0.130, green: 0.137, blue: 0.153)
    static let border = Color.white.opacity(0.075)
    static let primary = Color(red: 0.940, green: 0.945, blue: 0.955)
    static let secondary = Color(red: 0.630, green: 0.660, blue: 0.700)
    static let muted = Color(red: 0.445, green: 0.475, blue: 0.520)
    static let disabled = Color(red: 0.350, green: 0.370, blue: 0.405)
    static let accent = Color(red: 0.760, green: 0.965, blue: 0.585)
}

struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(AppTheme.primary)
            .frame(width: 34, height: 34)
            .background(configuration.isPressed ? AppTheme.panelSecondary.opacity(0.7) : AppTheme.panelSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(configuration.isPressed ? AppTheme.accent.opacity(0.78) : AppTheme.accent)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(AppTheme.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(configuration.isPressed ? AppTheme.panelSecondary.opacity(0.7) : AppTheme.panelSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
