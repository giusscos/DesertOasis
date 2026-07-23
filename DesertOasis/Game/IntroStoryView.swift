import SwiftUI

struct IntroStoryView: View {
    var onBegin: () -> Void

    @State private var currentSlide = 0
    @State private var textOpacity: Double = 0
    @State private var showStars = false

    private let slides: [IntroSlide] = [
        IntroSlide(
            headline: "What Was Lost",
            paragraphs: [
                "Long ago, this land bloomed with life. Rivers carved green valleys, and an ancient oasis stood at the heart of it all — a place where travellers found rest, where birds gathered, and where life itself was born.",
                "Then the desert came.",
            ],
            icon: "leaf.fill",
            iconColor: Color(red: 0.35, green: 0.72, blue: 0.40)
        ),
        IntroSlide(
            headline: "The Silence",
            paragraphs: [
                "Slowly at first — a crack in the earth, a spring gone dry. Then faster, relentless. The sands swallowed the rivers, the groves, and the memories of what once was.",
                "Now only dust remains. And the ruins of your camp — the last trace of the old oasis.",
            ],
            icon: "wind",
            iconColor: Color(red: 0.90, green: 0.78, blue: 0.45)
        ),
        IntroSlide(
            headline: "Your Mission",
            paragraphs: [
                "But deep beneath the dunes, the water still flows. You are the last keeper of this place.",
                "Find the hidden springs. Carry the water home. Nurture the land, one bucket at a time.",
                "The desert is vast. The sun is merciless. But the oasis remembers — and with your help, it will bloom again.",
            ],
            icon: "drop.fill",
            iconColor: Color(red: 0.35, green: 0.60, blue: 0.95)
        ),
    ]

    // Pre-generated star positions using a seeded PRNG so they're always the same.
    private static let starData: [(x: Double, y: Double, r: Double, a: Double)] = {
        var rng = IntroSeededRandom(seed: 42)
        return (0..<90).map { _ in
            (rng.next(), rng.next(), rng.next() * 1.6 + 0.5, rng.next() * 0.6 + 0.2)
        }
    }()

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.03, blue: 0.13),
                    Color(red: 0.14, green: 0.09, blue: 0.04),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            Canvas { ctx, size in
                for star in IntroStoryView.starData {
                    let x = star.x * size.width
                    let y = star.y * size.height * 0.62
                    let r = star.r
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                        with: .color(.white.opacity(star.a))
                    )
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .opacity(showStars ? 1 : 0)
            .animation(.easeIn(duration: 1.8), value: showStars)

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Skip") { onBegin() }
                        .font(.system(size: 14, weight: .semibold, design: .serif))
                        .foregroundStyle(.white.opacity(0.48))
                        .padding(.horizontal, 20)
                        .padding(.top, 18)
                }

                Spacer()

                currentSlideContent
                    .opacity(textOpacity)

                Spacer()

                VStack(spacing: 20) {
                    HStack(spacing: 8) {
                        ForEach(0..<slides.count, id: \.self) { i in
                            Circle()
                                .fill(i == currentSlide ? Color.white : Color.white.opacity(0.28))
                                .frame(width: i == currentSlide ? 8 : 6, height: i == currentSlide ? 8 : 6)
                                .animation(.spring(duration: 0.35), value: currentSlide)
                        }
                    }

                    if currentSlide < slides.count - 1 {
                        Button { advanceSlide() } label: {
                            Text("Continue")
                                .font(.system(size: 16, weight: .bold, design: .serif))
                                .foregroundStyle(.white)
                                .frame(maxWidth: 200)
                                .padding(.vertical, 13)
                                .background(
                                    Color(red: 0.68, green: 0.48, blue: 0.14).opacity(0.88),
                                    in: RoundedRectangle(cornerRadius: 14)
                                )
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button { onBegin() } label: {
                            Text("Begin Your Journey")
                                .font(.system(size: 16, weight: .bold, design: .serif))
                                .foregroundStyle(.white)
                                .frame(maxWidth: 260)
                                .padding(.vertical, 13)
                                .background(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.92, green: 0.72, blue: 0.28),
                                            Color(red: 0.65, green: 0.42, blue: 0.10),
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ),
                                    in: RoundedRectangle(cornerRadius: 14)
                                )
                                .shadow(
                                    color: Color(red: 0.92, green: 0.72, blue: 0.28).opacity(0.45),
                                    radius: 14
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 54)
            }
        }
        .onAppear {
            showStars = true
            withAnimation(.easeIn(duration: 0.9).delay(0.35)) {
                textOpacity = 1
            }
        }
    }

    @ViewBuilder
    private var currentSlideContent: some View {
        let slide = slides[currentSlide]
        VStack(spacing: 22) {
            Image(systemName: slide.icon)
                .font(.system(size: 44, weight: .thin))
                .foregroundStyle(slide.iconColor)
                .shadow(color: slide.iconColor.opacity(0.55), radius: 16)

            Text(slide.headline)
                .font(.system(size: 30, weight: .bold, design: .serif))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            VStack(spacing: 14) {
                ForEach(Array(slide.paragraphs.enumerated()), id: \.offset) { _, para in
                    Text(para)
                        .font(.system(size: 15, weight: .regular, design: .serif))
                        .foregroundStyle(.white.opacity(0.82))
                        .multilineTextAlignment(.center)
                        .lineSpacing(5)
                }
            }
            .padding(.horizontal, 36)
        }
        .id(currentSlide)
    }

    private func advanceSlide() {
        withAnimation(.easeOut(duration: 0.28)) { textOpacity = 0 }
        Task {
            try? await Task.sleep(for: .milliseconds(310))
            await MainActor.run {
                currentSlide = min(currentSlide + 1, slides.count - 1)
                withAnimation(.easeIn(duration: 0.55)) { textOpacity = 1 }
            }
        }
    }
}

private struct IntroSlide {
    let headline: String
    let paragraphs: [String]
    let icon: String
    let iconColor: Color
}

private struct IntroSeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double((state >> 33) & 0x7FFFFFFF) / Double(0x7FFFFFFF)
    }
}
