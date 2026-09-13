import SwiftUI

extension EditorTheme {
    var workspaceCanvas: Color { Color(hex: codeHex) }
    var separatorColor: Color { Color(hex: lineHex) }
}

struct ContentShape: Shape {
    var radius: CGFloat = 12
    func path(in rect: CGRect) -> Path {
        RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect)
    }
}

/// Content stays opaque. Glass is reserved for the navigation and control layer.
struct ContentSurface: View {
    let theme: EditorTheme
    var radius: CGFloat = 12
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(theme.background)
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(theme.foreground.opacity(contrast == .increased ? 0.5 : 0.09), lineWidth: 0.5)
            }
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}

private struct NavigationGlass: ViewModifier {
    var radius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @ViewBuilder func body(content: Content) -> some View {
        if reduceTransparency || contrast == .increased {
            content.background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: radius))
        } else if #available(macOS 26.0, *) {
            content.background {
                Color.clear.glassEffect(.regular, in: .rect(cornerRadius: radius))
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius))
        }
    }
}

/// Delegate rendering, pressed states, focus and accessibility to system buttons.
struct NativeActionStyle: PrimitiveButtonStyle {
    let theme: EditorTheme
    var prominent = false
    @ViewBuilder func makeBody(configuration: Configuration) -> some View {
        if #available(macOS 26.0, *) {
            if prominent {
                Button(configuration).buttonStyle(.glassProminent).tint(theme.accent)
            } else {
                Button(configuration).buttonStyle(.glass)
            }
        } else {
            if prominent {
                Button(configuration).buttonStyle(.borderedProminent).tint(theme.accent)
            } else {
                Button(configuration).buttonStyle(.bordered)
            }
        }
    }
}

extension View {
    func navigationGlass(radius: CGFloat = 16) -> some View {
        modifier(NavigationGlass(radius: radius))
    }
    func nativeDialog(theme: EditorTheme) -> some View {
        background(theme.workspaceCanvas)
            .tint(theme.accent)
            .foregroundStyle(theme.foreground)
            .groupBoxStyle(.automatic)
            .buttonStyle(NativeActionStyle(theme: theme))
    }
}
