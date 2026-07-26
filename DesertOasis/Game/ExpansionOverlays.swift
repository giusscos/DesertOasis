import SwiftUI

// MARK: - Tool picker (long-press)

struct ToolPickerOverlay: View {
    let unlocked: [EquippableTool]
    let equipped: EquippableTool
    var onSelect: (EquippableTool) -> Void
    var onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
                .onTapGesture { onClose() }

            VStack(spacing: 14) {
                Text("Tools")
                    .font(.system(.title2, design: .serif, weight: .bold))
                    .foregroundStyle(.white)

                ForEach(unlocked) { tool in
                    Button {
                        onSelect(tool)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: tool.systemImage)
                                .font(.system(size: 18, weight: .semibold))
                                .frame(width: 28)
                            Text(tool.displayName)
                                .font(.system(.callout, design: .serif, weight: .semibold))
                            Spacer()
                            if tool == equipped {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color(red: 0.95, green: 0.78, blue: 0.22))
                            }
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(tool == equipped
                                      ? Color(red: 0.25, green: 0.45, blue: 0.70).opacity(0.85)
                                      : Color.white.opacity(0.10))
                        )
                    }
                    .buttonStyle(.plain)
                }

                Button("Close", action: onClose)
                    .font(.system(.subheadline, design: .serif, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.top, 4)
            }
            .padding(22)
            .frame(maxWidth: 320)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(red: 0.09, green: 0.07, blue: 0.05).opacity(0.97))
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.12), lineWidth: 1))
            )
        }
    }
}

// MARK: - Merchant trade

struct TradeOverlayView: View {
    let beads: Int
    let hasLantern: Bool
    let hasCampTrinket: Bool
    var onBuy: (TradeGood) -> Void
    var onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button(action: onClose) {
                        Label("Back", systemImage: "chevron.left")
                            .font(.system(.subheadline, design: .serif, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Text("Merchant Trade")
                        .font(.system(.title3, design: .serif, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                    Label("\(beads)", systemImage: "circle.hexagongrid.fill")
                        .font(.system(.subheadline, design: .serif, weight: .bold))
                        .foregroundStyle(Color(red: 0.95, green: 0.78, blue: 0.22))
                }
                .padding(16)

                Divider().background(.white.opacity(0.12))

                VStack(spacing: 12) {
                    ForEach(TradeGood.allCases) { good in
                        let owned = (good == .lantern && hasLantern)
                            || (good == .campTrinket && hasCampTrinket)
                        tradeRow(good, owned: owned)
                    }
                }
                .padding(16)
            }
            .frame(maxWidth: 420)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color(red: 0.09, green: 0.07, blue: 0.05).opacity(0.97))
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.12), lineWidth: 1))
            )
            .padding(24)
        }
    }

    private func tradeRow(_ good: TradeGood, owned: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: good.systemImage)
                .font(.system(size: 20))
                .foregroundStyle(Color(red: 0.95, green: 0.78, blue: 0.22))
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(good.displayName)
                    .font(.system(.callout, design: .serif, weight: .bold))
                    .foregroundStyle(.white)
                Text(good.detail)
                    .font(.system(.caption, design: .serif))
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
            if owned && good != .mapScrap {
                Text("Owned")
                    .font(.system(.caption, design: .serif, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
            } else {
                Button {
                    onBuy(good)
                } label: {
                    Text("\(good.cost)")
                        .font(.system(.subheadline, design: .serif, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color(red: 0.95, green: 0.78, blue: 0.22), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(beads < good.cost)
                .opacity(beads < good.cost ? 0.4 : 1)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.06)))
    }
}

// MARK: - Diary

struct DiaryOverlayView: View {
    let pageIDs: [String]
    var revealID: String?
    var onClose: () -> Void

    private var resolvedPages: [(id: String, title: String, body: String)] {
        pageIDs.compactMap { id in
            guard let page = DiaryCatalog.page(id: id) else { return nil }
            return (id, page.title, page.body)
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Button(action: onClose) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(.white.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Keeper's Diary")
                            .font(.system(.title3, design: .serif, weight: .bold))
                            .foregroundStyle(.white)
                        Text("\(resolvedPages.count) of \(DiaryCatalog.allIDs.count) pages")
                            .font(.system(.caption2, design: .serif, weight: .medium))
                            .foregroundStyle(.white.opacity(0.45))
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "book.closed.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color(red: 0.95, green: 0.78, blue: 0.22).opacity(0.9))
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 14)

                if resolvedPages.isEmpty {
                    emptyState
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(resolvedPages, id: \.id) { entry in
                                diaryPageCard(id: entry.id, title: entry.title, body: entry.body)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 18)
                    }
                    .frame(maxHeight: 440)
                }
            }
            .frame(maxWidth: 440)
            .fixedSize(horizontal: false, vertical: true)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color(red: 0.09, green: 0.07, blue: 0.05).opacity(0.97))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22)
                            .stroke(.white.opacity(0.14), lineWidth: 1)
                    )
            )
            .padding(24)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.95, green: 0.78, blue: 0.22).opacity(0.12))
                    .frame(width: 72, height: 72)
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(Color(red: 0.95, green: 0.78, blue: 0.22))
            }

            Text("No pages yet")
                .font(.system(.headline, design: .serif, weight: .bold))
                .foregroundStyle(.white)

            Text("Dreams will fill these pages as you restore the oasis — sleep after milestones, and seek landmarks in the dunes.")
                .font(.system(.subheadline, design: .serif))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.white.opacity(0.05))
        )
    }

    private func diaryPageCard(id: String, title: String, body: String) -> some View {
        let isReveal = id == revealID
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: isReveal ? "sparkles" : "doc.text")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(isReveal
                                     ? Color(red: 0.95, green: 0.78, blue: 0.22)
                                     : .white.opacity(0.4))
                Text(title)
                    .font(.system(.callout, design: .serif, weight: .bold))
                    .foregroundStyle(isReveal
                                     ? Color(red: 0.95, green: 0.78, blue: 0.22)
                                     : .white)
            }
            Text(body)
                .font(.system(.subheadline, design: .serif))
                .foregroundStyle(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.white.opacity(isReveal ? 0.10 : 0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            isReveal
                                ? Color(red: 0.95, green: 0.78, blue: 0.22).opacity(0.35)
                                : Color.white.opacity(0.06),
                            lineWidth: 1
                        )
                )
        )
    }
}

// MARK: - Achievements

struct AchievementsOverlayView: View {
    let manager: AchievementManager
    var onClose: () -> Void

    private var unlockedCount: Int {
        AchievementManager.catalog.filter { manager.isUnlocked($0.id) }.count
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.60).ignoresSafeArea()

            VStack(spacing: 0) {
                headerBar

                Divider().background(.white.opacity(0.12))

                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(AchievementManager.catalog) { def in
                            achievementRow(def, unlocked: manager.isUnlocked(def.id))
                        }
                    }
                    .padding(20)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color(red: 0.09, green: 0.07, blue: 0.05).opacity(0.97))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22)
                            .stroke(.white.opacity(0.12), lineWidth: 1)
                    )
            )
            .frame(maxWidth: 500)
            .padding(.horizontal, 20)
            .padding(.vertical, 44)
        }
    }

    private var headerBar: some View {
        HStack {
            Button { onClose() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Back")
                        .font(.system(.subheadline, design: .serif, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.8))
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 2) {
                HStack(spacing: 7) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(red: 0.95, green: 0.78, blue: 0.22).opacity(0.9))
                    Text("Achievements")
                        .font(.system(.title3, design: .serif, weight: .bold))
                        .foregroundStyle(.white)
                }
                Text("\(unlockedCount) of \(AchievementManager.catalog.count) unlocked")
                    .font(.system(.caption2, design: .serif, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }

            Spacer()

            // Visual balance for the back button
            HStack(spacing: 6) {
                Image(systemName: "chevron.left").opacity(0)
                Text("Back").opacity(0)
            }
            .font(.system(.subheadline))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private func achievementRow(_ def: AchievementDefinition, unlocked: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: unlocked ? "medal.fill" : "lock.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(unlocked
                                 ? Color(red: 0.95, green: 0.78, blue: 0.22)
                                 : .white.opacity(0.35))
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(unlocked
                              ? Color(red: 0.95, green: 0.78, blue: 0.22).opacity(0.14)
                              : Color.white.opacity(0.06))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(def.title)
                    .font(.system(.subheadline, design: .serif, weight: .bold))
                    .foregroundStyle(unlocked ? .white : .white.opacity(0.5))
                Text(def.body)
                    .font(.system(.caption, design: .serif))
                    .foregroundStyle(.white.opacity(unlocked ? 0.65 : 0.32))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.white.opacity(unlocked ? 0.08 : 0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            unlocked
                                ? Color(red: 0.95, green: 0.78, blue: 0.22).opacity(0.28)
                                : Color.white.opacity(0.05),
                            lineWidth: 1
                        )
                )
        )
    }
}

// MARK: - Tool HUD button (tap cycle / long-press list)

struct ToolActionButton: View {
    let tool: EquippableTool
    var showsKeyCaption: Bool
    var onTap: () -> Void
    var onLongPress: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 3) {
                Image(systemName: tool.systemImage)
                    .font(.system(.title3, weight: .bold))
                Text("Tool")
                    .font(.system(.caption2, design: .serif, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(width: 64, height: 64)
            .background(Color(red: 0.35, green: 0.28, blue: 0.18).opacity(0.88), in: Circle())
            .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 1.5))
            .shadow(radius: 4)
            .contentShape(Circle())
            .onTapGesture { onTap() }
            .onLongPressGesture(minimumDuration: 0.45) { onLongPress() }

            if showsKeyCaption {
                KeyCaptionBadge(label: "Q")
                    .offset(x: 6, y: -4)
            }
        }
    }
}

// MARK: - Compass / detector live HUD

/// Circular dial: top = player forward; needle points toward world north.
struct CompassHUDView: View {
    /// Radians relative to player forward (0 = north ahead).
    let angle: Float
    var stormJittering: Bool = false

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.92, green: 0.86, blue: 0.68),
                            Color(red: 0.72, green: 0.62, blue: 0.42),
                        ],
                        center: .center,
                        startRadius: 2,
                        endRadius: 26
                    )
                )
                .overlay(Circle().stroke(Color(red: 0.45, green: 0.32, blue: 0.14), lineWidth: 2))
                .shadow(color: .black.opacity(0.35), radius: 4, y: 1)

            // Cardinal ticks (top = player forward)
            ForEach(0..<4, id: \.self) { i in
                Capsule()
                    .fill(i == 0 ? Color(red: 0.55, green: 0.18, blue: 0.12) : Color.black.opacity(0.35))
                    .frame(width: i == 0 ? 2.5 : 1.5, height: i == 0 ? 7 : 5)
                    .offset(y: -18)
                    .rotationEffect(.degrees(Double(i) * 90))
            }

            // "N" stays with the needle so it always marks world north.
            Text("N")
                .font(.system(size: 8, weight: .black, design: .serif))
                .foregroundStyle(Color(red: 0.45, green: 0.18, blue: 0.12))
                .offset(y: -11)
                .rotationEffect(.radians(Double(angle)))
                .animation(stormJittering ? nil : .easeOut(duration: 0.12), value: angle)

            // Needle — always points toward world north.
            Image(systemName: "location.north.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color(red: 0.78, green: 0.12, blue: 0.10))
                .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                .rotationEffect(.radians(Double(angle)))
                .animation(stormJittering ? nil : .easeOut(duration: 0.12), value: angle)

            Circle()
                .fill(Color(red: 0.35, green: 0.28, blue: 0.18))
                .frame(width: 5, height: 5)
                .overlay(Circle().stroke(.white.opacity(0.4), lineWidth: 0.8))
        }
        .frame(width: 48, height: 48)
        .accessibilityLabel("Compass, north")
    }
}

struct DetectorHUDView: View {
    let signal: Float

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 12, weight: .bold))
                Text("Water")
                    .font(.system(.caption2, design: .serif, weight: .bold))
            }
            .foregroundStyle(.white)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.black.opacity(0.35))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.20, green: 0.55, blue: 0.75),
                                    Color(red: 0.95, green: 0.70, blue: 0.20),
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(6, geo.size.width * CGFloat(max(0, min(1, signal)))))
                        .animation(.easeOut(duration: 0.15), value: signal)
                }
            }
            .frame(height: 8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: 120)
        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.2), lineWidth: 1))
        .accessibilityLabel("Water detector signal")
    }
}

#if DEBUG

// MARK: - Debug performance

@Observable
final class PerformanceMonitor {
    var currentFPS: Float = 0
    var avgFPS: Float = 0
    var minFPS: Float = 0
    var maxFPS: Float = 0
    /// Share of frames at ≥55 FPS (0…100).
    var stabilityPercent: Float = 0
    var sampleCount: Int = 0
    var isBenchmarking = false

    private var smoothedFPS: Float = 60
    private var sumFPS: Double = 0
    private var frameCount: Int = 0
    private var minSeen: Float = .greatestFiniteMagnitude
    private var maxSeen: Float = 0
    private var stableFrames: Int = 0
    private var publishAccumulator: Float = 0

    func resetBenchmark() {
        sumFPS = 0
        frameCount = 0
        minSeen = .greatestFiniteMagnitude
        maxSeen = 0
        stableFrames = 0
        avgFPS = 0
        minFPS = 0
        maxFPS = 0
        stabilityPercent = 0
        sampleCount = 0
    }

    func setBenchmarking(_ enabled: Bool) {
        isBenchmarking = enabled
        if enabled { resetBenchmark() }
    }

    func sample(deltaTime: Float) {
        guard deltaTime > 0.000_05, deltaTime < 1 else { return }
        let fps = 1 / deltaTime
        smoothedFPS = smoothedFPS * 0.85 + fps * 0.15

        if isBenchmarking {
            frameCount += 1
            sumFPS += Double(fps)
            minSeen = min(minSeen, fps)
            maxSeen = max(maxSeen, fps)
            if fps >= 55 { stableFrames += 1 }
        }

        publishAccumulator += deltaTime
        guard publishAccumulator >= 0.12 else { return }
        publishAccumulator = 0
        currentFPS = smoothedFPS
        guard isBenchmarking, frameCount > 0 else { return }
        avgFPS = Float(sumFPS / Double(frameCount))
        minFPS = minSeen
        maxFPS = maxSeen
        stabilityPercent = Float(stableFrames) / Float(frameCount) * 100
        sampleCount = frameCount
    }
}

struct FPSDebugOverlay: View {
    let monitor: PerformanceMonitor
    var showFPS: Bool
    var showBenchmark: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if showFPS {
                Text(String(format: "FPS  %.0f", monitor.currentFPS))
                    .font(.system(.footnote, design: .monospaced, weight: .bold))
                    .foregroundStyle(fpsColor(monitor.currentFPS))
            }
            if showBenchmark {
                Group {
                    if monitor.sampleCount == 0 {
                        Text("Benchmark…")
                            .foregroundStyle(.white.opacity(0.7))
                    } else {
                        Text(String(format: "Avg  %.1f", monitor.avgFPS))
                        Text(String(format: "Min  %.1f", monitor.minFPS))
                        Text(String(format: "Max  %.1f", monitor.maxFPS))
                        Text(String(format: "Stable  %.0f%%", monitor.stabilityPercent))
                            .foregroundStyle(stabilityColor(monitor.stabilityPercent))
                        Text("n=\(monitor.sampleCount)")
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
                .font(.system(.caption2, design: .monospaced, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.15), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Performance debug")
    }

    private func fpsColor(_ fps: Float) -> Color {
        if fps >= 55 { return Color(red: 0.35, green: 0.90, blue: 0.45) }
        if fps >= 40 { return Color(red: 0.95, green: 0.75, blue: 0.20) }
        return Color(red: 0.95, green: 0.30, blue: 0.25)
    }

    private func stabilityColor(_ pct: Float) -> Color {
        if pct >= 90 { return Color(red: 0.35, green: 0.90, blue: 0.45) }
        if pct >= 70 { return Color(red: 0.95, green: 0.75, blue: 0.20) }
        return Color(red: 0.95, green: 0.30, blue: 0.25)
    }
}

struct CampZoneDebugHUD: View {
    let name: String
    let distance: Float
    let bearingDegrees: Float
    let remainingCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Next camp (debug)")
                .font(.system(.caption2, design: .serif, weight: .semibold))
                .foregroundStyle(Color(red: 0.40, green: 0.90, blue: 0.95))
            Text(name)
                .font(.system(.caption, design: .serif, weight: .bold))
                .foregroundStyle(.white)
            Text(String(format: "%.0f m  ·  %.0f°", distance, bearingDegrees))
                .font(.system(.caption2, design: .monospaced, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
            if remainingCount > 1 {
                Text("+\(remainingCount - 1) more unmarked")
                    .font(.system(.caption2, design: .serif))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(red: 0.30, green: 0.85, blue: 0.90).opacity(0.45), lineWidth: 1)
        )
    }
}

#endif
