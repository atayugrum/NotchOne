import SwiftUI

/// Notifications tab: what came in since NotchOne started, to read later. Kept in memory only.
struct NotificationsPanel: View {
    let live: LiveActivityStore

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            if live.notifications.isEmpty {
                Text("Notifications will collect here. They stay until NotchOne quits.")
                    .font(Typo.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: Space.xs) {
                        ForEach(live.notifications) { record in
                            NotificationRow(record: record) { live.open(record) }
                        }
                    }
                }
                HStack {
                    Text("\(live.notifications.count) notifications")
                        .font(Typo.micro)
                        .foregroundStyle(.secondary)
                    Spacer()
                    PillButton(title: "Clear", symbol: "trash") { live.clearNotifications() }
                }
            }
        }
    }
}

private struct NotificationRow: View {
    let record: NotificationRecord
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(alignment: .top, spacing: Space.s) {
                icon
                VStack(alignment: .leading, spacing: 1) {
                    Text(record.banner.title).font(Typo.captionStrong).lineLimit(2)
                    if !record.banner.body.isEmpty {
                        Text(record.banner.body).font(Typo.caption).foregroundStyle(.secondary).lineLimit(3)
                    }
                }
                Spacer(minLength: 0)
                Text(record.date, style: .time).font(Typo.micro).foregroundStyle(.secondary)
            }
            .padding(Space.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var icon: some View {
        if let id = record.appBundleID, let image = AppInfo.icon(for: id) {
            Image(nsImage: image).resizable().frame(width: 22, height: 22)
        } else {
            Image(systemName: "bell.fill").font(Typo.icon(13)).frame(width: 22, height: 22).foregroundStyle(.secondary)
        }
    }
}
