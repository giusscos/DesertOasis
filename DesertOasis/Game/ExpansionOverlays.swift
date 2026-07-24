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
                    .font(.system(size: 22, weight: .bold, design: .serif))
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
                                .font(.system(size: 16, weight: .semibold, design: .serif))
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
                    .font(.system(size: 14, weight: .semibold, design: .serif))
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
                            .font(.system(size: 15, weight: .semibold, design: .serif))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Text("Merchant Trade")
                        .font(.system(size: 20, weight: .bold, design: .serif))
                        .foregroundStyle(.white)
                    Spacer()
                    Label("\(beads)", systemImage: "circle.hexagongrid.fill")
                        .font(.system(size: 14, weight: .bold, design: .serif))
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
                    .font(.system(size: 16, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                Text(good.detail)
                    .font(.system(size: 12, design: .serif))
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
            if owned && good != .mapScrap {
                Text("Owned")
                    .font(.system(size: 12, weight: .semibold, design: .serif))
                    .foregroundStyle(.white.opacity(0.45))
            } else {
                Button {
                    onBuy(good)
                } label: {
                    Text("\(good.cost)")
                        .font(.system(size: 14, weight: .bold, design: .serif))
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

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button(action: onClose) {
                        Label("Back", systemImage: "chevron.left")
                            .font(.system(size: 15, weight: .semibold, design: .serif))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Text("Keeper's Diary")
                        .font(.system(size: 20, weight: .bold, design: .serif))
                        .foregroundStyle(.white)
                    Spacer()
                    Color.clear.frame(width: 60)
                }
                .padding(16)

                Divider().background(.white.opacity(0.12))

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if pageIDs.isEmpty {
                            Text("Dreams will fill these pages as you restore the oasis.")
                                .font(.system(size: 15, design: .serif))
                                .foregroundStyle(.white.opacity(0.5))
                                .padding(.top, 40)
                                .frame(maxWidth: .infinity)
                        }
                        ForEach(pageIDs, id: \.self) { id in
                            if let page = DiaryCatalog.page(id: id) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(page.title)
                                        .font(.system(size: 16, weight: .bold, design: .serif))
                                        .foregroundStyle(id == revealID
                                                         ? Color(red: 0.95, green: 0.78, blue: 0.22)
                                                         : .white)
                                    Text(page.body)
                                        .font(.system(size: 14, design: .serif))
                                        .foregroundStyle(.white.opacity(0.75))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.07)))
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .frame(maxWidth: 500)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color(red: 0.09, green: 0.07, blue: 0.05).opacity(0.97))
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.12), lineWidth: 1))
            )
            .padding(20)
        }
    }
}

// MARK: - Achievements

struct AchievementsOverlayView: View {
    let manager: AchievementManager
    var onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button(action: onClose) {
                        Label("Back", systemImage: "chevron.left")
                            .font(.system(size: 15, weight: .semibold, design: .serif))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Text("Achievements")
                        .font(.system(size: 20, weight: .bold, design: .serif))
                        .foregroundStyle(.white)
                    Spacer()
                    Color.clear.frame(width: 60)
                }
                .padding(16)

                Divider().background(.white.opacity(0.12))

                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(AchievementManager.catalog) { def in
                            let unlocked = manager.isUnlocked(def.id)
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: unlocked ? "medal.fill" : "lock.fill")
                                    .foregroundStyle(unlocked
                                                     ? Color(red: 0.95, green: 0.78, blue: 0.22)
                                                     : .white.opacity(0.35))
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(def.title)
                                        .font(.system(size: 15, weight: .bold, design: .serif))
                                        .foregroundStyle(unlocked ? .white : .white.opacity(0.45))
                                    Text(def.body)
                                        .font(.system(size: 12, design: .serif))
                                        .foregroundStyle(.white.opacity(unlocked ? 0.65 : 0.3))
                                }
                                Spacer()
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.06)))
                        }
                    }
                    .padding(16)
                }
            }
            .frame(maxWidth: 500)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color(red: 0.09, green: 0.07, blue: 0.05).opacity(0.97))
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.12), lineWidth: 1))
            )
            .padding(20)
        }
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
                    .font(.system(size: 20, weight: .bold))
                Text("Tool")
                    .font(.system(size: 10, weight: .bold, design: .serif))
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
                    .font(.system(size: 11, weight: .bold, design: .serif))
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
