import SwiftUI

/// Native perspective and shading; no web view or scroll interception.
struct NestSculpture: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var floating = false
    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width * 0.45, geometry.size.height * 0.75)
            ZStack {
                Ellipse().fill(Theme.forest.opacity(0.09)).frame(width: size * 1.65, height: 20).blur(radius: 10).offset(y: size * 0.65)
                Ellipse().stroke(LinearGradient(colors: [Theme.gold.opacity(0.15), Theme.gold, Theme.paper, Theme.gold.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 3).frame(width: size * 2.1, height: size * 0.85).rotationEffect(.degrees(-28)).rotation3DEffect(.degrees(floating ? 14 : -12), axis: (x: 1, y: 0.5, z: 0), perspective: 0.6)
                HStack(spacing: -size * 0.28) {
                    sphere([Theme.paper, Theme.sage, Theme.forest], size: size).offset(y: floating ? -9 : 6)
                    sphere([Theme.paper, Theme.blush, Theme.berry], size: size * 0.8).offset(y: floating ? 8 : -5)
                }.rotation3DEffect(.degrees(floating ? 10 : -10), axis: (x: 0.2, y: 1, z: 0), perspective: 0.7)
                Image(systemName: "heart.fill").font(.system(size: size * 0.2, weight: .light)).foregroundStyle(Theme.paper).shadow(color: Theme.forest.opacity(0.3), radius: 4, y: 3).offset(x: -size * 0.18, y: floating ? -9 : 6)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.onAppear { if !reduceMotion { withAnimation(.easeInOut(duration: 4.5).repeatForever(autoreverses: true)) { floating = true } } }.onChange(of: reduceMotion) { _, reduced in if reduced { withAnimation(nil) { floating = false } } }
    }
    private func sphere(_ colors: [Color], size: CGFloat) -> some View {
        Circle().fill(RadialGradient(colors: colors, center: .init(x: 0.28, y: 0.22), startRadius: 0, endRadius: size * 0.85)).frame(width: size, height: size).overlay { Circle().stroke(.white.opacity(0.35), lineWidth: 0.7) }.shadow(color: colors.last!.opacity(0.22), radius: 16, x: 3, y: 15)
    }
}

private struct NestScrollMotion: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        let reduced = reduceMotion
        return content.scrollTransition(.interactive, axis: .vertical) { view, phase in
            view.opacity(reduced || phase.isIdentity ? 1 : 0.92)
                .scaleEffect(reduced || phase.isIdentity ? 1 : 0.975)
                .rotation3DEffect(.degrees(reduced ? 0 : phase.value * -3), axis: (x: 1, y: 0, z: 0), perspective: 0.4)
        }
    }
}
extension View { func nestScrollMotion() -> some View { modifier(NestScrollMotion()) } }

struct NestStartingView: View {
    let onConnect: () -> Void
    let onExperiences: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                NestSculpture().frame(height: 180).accessibilityHidden(true)
                Text("A place for your\nnext chapter.").font(.system(size: 29, weight: .medium, design: .serif))
                Text("Start by meeting someone. When it feels right, Nest becomes a private space for the life you build together.").font(.subheadline).foregroundStyle(Theme.muted).lineSpacing(3)
                Button("Explore my introductions", action: onConnect).buttonStyle(ForestButton())
                Button("Find an experience", action: onExperiences).buttonStyle(OutlineButton())
            }.padding(22).background(Theme.paper, in: RoundedRectangle(cornerRadius: 27)).nestScrollMotion()
            Text("FROM A FIRST HELLO TO A SHARED LIFE").font(.system(size: 10, weight: .bold)).tracking(1.3).foregroundStyle(Theme.berry)
            stage("01", "Make a connection", "Explore introductions, share interest and start a conversation.", "heart", active: true)
            stage("02", "Build your Together space", "Invite your partner to plan dates, save moments and share a couple profile.", "calendar", active: false)
            stage("03", "Find your people", "Nest4 introduces you to another couple when all four people agree.", "person.2", active: false)
            stage("04", "Make room for a home", "Compare routines, discuss differences and plan a move after you both opt in.", "house", active: false)
        }
    }
    private func stage(_ number: String, _ title: String, _ detail: String, _ icon: String, active: Bool) -> some View {
        HStack(alignment: .top, spacing: 15) {
            ZStack { RoundedRectangle(cornerRadius: 15).fill(active ? Theme.forest : Theme.sage.opacity(0.25)); Image(systemName: icon).foregroundStyle(active ? Theme.paper : Theme.forest) }.frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 5) { HStack { Text(title).font(.headline); Spacer(); Text(number).font(.caption.weight(.semibold)).foregroundStyle(Theme.muted) }; Text(detail).font(.subheadline).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true); if !active { Text("Opens with your partner").font(.caption).foregroundStyle(Theme.berry) } }
        }.padding(.vertical, 8)
    }
}
