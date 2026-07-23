import SwiftUI

// MARK: - Missions list overlay

struct MissionsOverlayView: View {
    let missionManager: MissionManager
    var onBack: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.60).ignoresSafeArea()

            VStack(spacing: 0) {
                headerBar

                Divider().background(.white.opacity(0.12))

                ScrollView {
                    LazyVStack(spacing: 24) {
                        if !missionManager.active.isEmpty {
                            missionSection(
                                title: "Active",
                                icon: "flag.fill",
                                color: Color(red: 0.95, green: 0.78, blue: 0.22),
                                missions: missionManager.active,
                                status: .active
                            )
                        }
                        if !missionManager.completed.isEmpty {
                            missionSection(
                                title: "Completed",
                                icon: "checkmark.seal.fill",
                                color: Color(red: 0.25, green: 0.78, blue: 0.48),
                                missions: missionManager.completed,
                                status: .completed
                            )
                        }
                        if !missionManager.failed.isEmpty {
                            missionSection(
                                title: "Failed",
                                icon: "xmark.seal.fill",
                                color: Color(red: 0.80, green: 0.28, blue: 0.22),
                                missions: missionManager.failed,
                                status: .failed
                            )
                        }
                        if missionManager.records.isEmpty {
                            emptyState
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
            Button { onBack() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Back")
                        .font(.system(size: 15, weight: .semibold, design: .serif))
                }
                .foregroundStyle(.white.opacity(0.8))
            }
            .buttonStyle(.plain)

            Spacer()

            HStack(spacing: 7) {
                Image(systemName: "list.bullet.clipboard")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Text("Missions")
                    .font(.system(size: 20, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
            }

            Spacer()

            // Visual balance for the back button
            HStack(spacing: 6) {
                Image(systemName: "chevron.left").opacity(0)
                Text("Back").opacity(0)
            }
            .font(.system(size: 15))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "map")
                .font(.system(size: 40, weight: .thin))
                .foregroundStyle(.white.opacity(0.28))
            Text("No missions yet.\nExplore the desert to begin your journey.")
                .font(.system(size: 15, design: .serif))
                .foregroundStyle(.white.opacity(0.44))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
        .padding(.top, 52)
    }

    @ViewBuilder
    private func missionSection(
        title: String,
        icon: String,
        color: Color,
        missions: [MissionDefinition],
        status: MissionStatus
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .serif))
                    .foregroundStyle(color)
                    .tracking(1.8)
                Spacer()
                Text("\(missions.count)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(color.opacity(0.7))
            }

            VStack(spacing: 8) {
                ForEach(missions, id: \.id) { mission in
                    MissionRowView(mission: mission, status: status)
                }
            }
        }
    }
}

// MARK: - Mission row

private struct MissionRowView: View {
    let mission: MissionDefinition
    let status: MissionStatus

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            statusIcon
                .frame(width: 22)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 5) {
                Text(mission.title)
                    .font(.system(size: 14, weight: .bold, design: .serif))
                    .foregroundStyle(titleColor)
                Text(mission.body)
                    .font(.system(size: 12, design: .serif))
                    .foregroundStyle(.white.opacity(status == .active ? 0.70 : 0.48))
                    .lineSpacing(3)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 10).fill(fillColor)
        }
        .overlay {
            if status == .active {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(red: 0.95, green: 0.78, blue: 0.22).opacity(0.30), lineWidth: 1)
            }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch status {
        case .active:
            Image(systemName: "circle.dotted")
                .font(.system(size: 16))
                .foregroundStyle(Color(red: 0.95, green: 0.78, blue: 0.22))
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(Color(red: 0.25, green: 0.78, blue: 0.48))
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(Color(red: 0.80, green: 0.28, blue: 0.22))
        }
    }

    private var titleColor: Color {
        switch status {
        case .active:    Color(red: 1.0, green: 0.93, blue: 0.68)
        case .completed: .white.opacity(0.72)
        case .failed:    .white.opacity(0.42)
        }
    }

    private var fillColor: Color {
        switch status {
        case .active:    Color(red: 0.95, green: 0.78, blue: 0.22).opacity(0.07)
        case .completed: Color.white.opacity(0.04)
        case .failed:    Color.white.opacity(0.02)
        }
    }
}

// MARK: - Mission offer card (shown over dialogue when an NPC proposes a mission)

struct MissionOfferView: View {
    let mission: MissionDefinition
    var onAccept: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        VStack {
            VStack(spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "scroll.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(red: 0.95, green: 0.78, blue: 0.22))
                    Text("New Mission")
                        .font(.system(size: 11, weight: .bold, design: .serif))
                        .foregroundStyle(Color(red: 0.95, green: 0.78, blue: 0.22))
                        .tracking(1.5)
                        .textCase(.uppercase)
                }

                Text(mission.title)
                    .font(.system(size: 17, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text(mission.body)
                    .font(.system(size: 13, design: .serif))
                    .foregroundStyle(.white.opacity(0.80))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)

                HStack(spacing: 12) {
                    Button { onDismiss() } label: {
                        Text("Dismiss")
                            .font(.system(size: 14, weight: .semibold, design: .serif))
                            .foregroundStyle(.white.opacity(0.72))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(.white.opacity(0.18), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)

                    Button { onAccept() } label: {
                        Text("Accept")
                            .font(.system(size: 14, weight: .bold, design: .serif))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                Color(red: 0.70, green: 0.50, blue: 0.14).opacity(0.90),
                                in: RoundedRectangle(cornerRadius: 10)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(red: 0.09, green: 0.07, blue: 0.04).opacity(0.96))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color(red: 0.95, green: 0.78, blue: 0.22).opacity(0.45), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.55), radius: 18)
            )
            .frame(maxWidth: 360)
            .padding(.horizontal, 24)
            .padding(.top, 70)

            Spacer()
        }
    }
}
