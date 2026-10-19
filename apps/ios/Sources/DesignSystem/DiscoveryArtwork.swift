import SwiftUI

/// Original architectural motif, not a reconstruction or historical map.
/// All drawing coordinates are proportions of the available illustration area.
struct DiscoveryArtwork: View {
    private let ink = Color(red: 0.055, green: 0.065, blue: 0.060)
    private let bronze = Color(red: 0.49, green: 0.32, blue: 0.18)
    private let stone = Color(red: 0.86, green: 0.75, blue: 0.54)
    private let dusk = Color(red: 0.27, green: 0.25, blue: 0.19)
    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            func polygon(_ points: [(CGFloat, CGFloat)], _ color: Color) {
                var path = Path()
                path.move(to: CGPoint(x: points[0].0 * w, y: points[0].1 * h))
                for p in points.dropFirst() { path.addLine(to: CGPoint(x: p.0 * w, y: p.1 * h)) }
                path.closeSubpath(); context.fill(path, with: .color(color))
            }
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(Gradient(colors: [bronze, dusk, ink]), startPoint: .zero, endPoint: CGPoint(x: w * 0.5, y: h)))
            let sun = CGRect(x: w * 0.71, y: h * 0.05, width: w * 0.2, height: w * 0.2)
            context.fill(Path(ellipseIn: sun), with: .color(stone.opacity(0.7)))
            polygon([(0,0.42),(0.16,0.30),(0.33,0.39),(0.51,0.26),(0.74,0.40),(1,0.29),(1,1),(0,1)], dusk)
            // Receding silhouettes establish depth without depicting a specific ruin.
            for i in 0..<8 {
                let x = CGFloat(i) * 0.13
                polygon([(x,0.51),(x,0.44),(x+0.09,0.41),(x+0.11,0.51)], bronze.opacity(0.7))
            }
            polygon([(0,0.68),(0.39,0.49),(1,0.62),(1,1),(0,1)], ink.opacity(0.65))
            // Lit stone columns and their side faces, arranged as an original motif.
            for i in 0..<5 {
                let x = 0.26 + CGFloat(i) * 0.145
                let top = 0.17 + CGFloat(i) * 0.025
                let bottom = 0.62 + CGFloat(i) * 0.025
                polygon([(x,top),(x+0.043,top),(x+0.037,bottom),(x+0.006,bottom)], stone)
                polygon([(x+0.043,top),(x+0.063,top+0.015),(x+0.057,bottom+0.014),(x+0.037,bottom)], bronze)
                polygon([(x-0.012,top-0.025),(x+0.06,top-0.025),(x+0.063,top+0.005),(x-0.01,top+0.005)], stone)
                polygon([(x-0.008,bottom),(x+0.058,bottom),(x+0.068,bottom+0.025),(x-0.02,bottom+0.025)], bronze)
                var flute = Path(); flute.move(to: CGPoint(x: (x+0.017)*w, y: (top+0.03)*h)); flute.addLine(to: CGPoint(x: (x+0.019)*w, y: (bottom-0.01)*h))
                context.stroke(flute, with: .color(ink.opacity(0.28)), lineWidth: 1)
            }
            polygon([(0.23,0.105),(0.94,0.225),(0.94,0.26),(0.23,0.14)], stone)
            polygon([(0.23,0.14),(0.94,0.26),(0.96,0.28),(0.24,0.165)], bronze)
            polygon([(0.18,0.66),(0.92,0.81),(1,0.92),(0.05,0.73)], stone.opacity(0.35))
            polygon([(0.05,0.73),(1,0.92),(1,1),(0,1)], ink.opacity(0.5))
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(Gradient(stops: [.init(color: ink.opacity(0), location: 0.3), .init(color: ink.opacity(0.8), location: 0.62), .init(color: ink, location: 1)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
        }.accessibilityHidden(true)
    }
}

struct DiscoveryHero<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .padding(BibleTheme.Space.xl)
            .frame(maxWidth: .infinity, minHeight: 280, alignment: .bottomLeading)
            .background { DiscoveryArtwork() }
            .foregroundStyle(Color(red: 0.98, green: 0.97, blue: 0.92))
            .clipShape(RoundedRectangle(cornerRadius: BibleTheme.Radius.surface))
            .overlay { RoundedRectangle(cornerRadius: BibleTheme.Radius.surface).strokeBorder(Color.white.opacity(0.16)) }
    }
}
