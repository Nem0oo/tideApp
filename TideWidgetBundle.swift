import WidgetKit
import SwiftUI

struct TideWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: TideSnapshot?
}

struct TideWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> TideWidgetEntry {
        TideWidgetEntry(date: Date(), snapshot: TideSnapshotStore.load())
    }

    func getSnapshot(in context: Context, completion: @escaping (TideWidgetEntry) -> Void) {
        completion(TideWidgetEntry(date: Date(), snapshot: TideSnapshotStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TideWidgetEntry>) -> Void) {
        let snapshot = TideSnapshotStore.load()
        let now = Date()

        // Une entrée toutes les 15 min sur les 3 prochaines heures : le repère "maintenant"
        // et les prochains extrêmes avancent sans dépendre d'un refresh système fréquent
        // (l'app republie de toute façon un instantané + reloadAllTimelines() à chaque fetch)
        var entries: [TideWidgetEntry] = []
        for i in 0..<12 {
            let entryDate = Calendar.current.date(byAdding: .minute, value: i * 15, to: now) ?? now
            entries.append(TideWidgetEntry(date: entryDate, snapshot: snapshot))
        }

        let refreshDate = Calendar.current.date(byAdding: .hour, value: 3, to: now) ?? now.addingTimeInterval(3 * 3600)
        completion(Timeline(entries: entries, policy: .after(refreshDate)))
    }
}

private func widgetTime(_ date: Date, in snapshot: TideSnapshot) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    formatter.timeZone = snapshot.timeZone
    return formatter.string(from: date)
}

struct TideWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: TideWidgetEntry

    var body: some View {
        if let snapshot = entry.snapshot, !snapshot.extremes.isEmpty {
            switch family {
            case .systemSmall:
                SmallTideView(snapshot: snapshot, now: entry.date)
            default:
                MediumTideView(snapshot: snapshot, now: entry.date)
            }
        } else {
            EmptyTideView()
        }
    }
}

private struct EmptyTideView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "water.waves")
                .font(.title2)
                .foregroundColor(.blue)
            Text(TideSnapshotStore.isAvailable ? "Ouvrez Marées" : "App Group indisponible")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemBackground))
    }
}

// Signale que l'instantané ne couvre bientôt plus les prochaines heures (il faut rouvrir l'app)
private struct StaleBadge: View {
    let snapshot: TideSnapshot

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundColor(.orange)
            Text("Données du \(snapshot.fetchedAt, format: .dateTime.day().month())")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

private struct SmallTideView: View {
    let snapshot: TideSnapshot
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "water.waves")
                    .foregroundColor(.blue)
                Text("Marées")
                    .font(.caption.weight(.semibold))
                Spacer()
            }

            if let height = snapshot.currentHeight(at: now) {
                Text(String(format: "%.1f m", height))
                    .font(.title2.weight(.bold))
            }

            VStack(alignment: .leading, spacing: 3) {
                ForEach(snapshot.nextTwoExtremes(after: now)) { extreme in
                    HStack(spacing: 4) {
                        Image(systemName: extreme.isHigh ? "arrow.up" : "arrow.down")
                            .font(.caption2)
                            .foregroundColor(extreme.isHigh ? .blue : .cyan)
                        Text(String(format: "%.1f m", extreme.height))
                            .font(.caption2.weight(.medium))
                        Text(widgetTime(extreme.date, in: snapshot))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer(minLength: 0)

            if snapshot.isStale(at: now) {
                StaleBadge(snapshot: snapshot)
            } else if let sun = snapshot.nextSunEvent(after: now) {
                HStack(spacing: 4) {
                    Image(systemName: sun.isSunrise ? "sunrise.fill" : "sunset.fill")
                        .font(.caption2)
                        .foregroundColor(.orange)
                    Text(widgetTime(sun.date, in: snapshot))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color(UIColor.systemBackground))
    }
}

private struct MediumTideView: View {
    let snapshot: TideSnapshot
    let now: Date

    var body: some View {
        HStack(spacing: 12) {
            MiniTideCurve(snapshot: snapshot, now: now)
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "water.waves")
                        .foregroundColor(.blue)
                    Text("Marées")
                        .font(.caption.weight(.semibold))
                }

                ForEach(snapshot.nextTwoExtremes(after: now)) { extreme in
                    HStack(spacing: 4) {
                        Image(systemName: extreme.isHigh ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                            .font(.caption)
                            .foregroundColor(extreme.isHigh ? .blue : .cyan)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(String(format: "%.1f m", extreme.height))
                                .font(.caption.weight(.semibold))
                            Text(widgetTime(extreme.date, in: snapshot))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                if snapshot.isStale(at: now) {
                StaleBadge(snapshot: snapshot)
            } else if let sun = snapshot.nextSunEvent(after: now) {
                    HStack(spacing: 4) {
                        Image(systemName: sun.isSunrise ? "sunrise.fill" : "sunset.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                        Text(widgetTime(sun.date, in: snapshot))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer(minLength: 0)
            }
            .frame(width: 96, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemBackground))
    }
}

// Courbe compacte par interpolation cosinus entre extrêmes, avec repère "maintenant" ;
// même principe que TideChartView mais sans scroll ni étiquettes, taille widget oblige.
private struct MiniTideCurve: View {
    let snapshot: TideSnapshot
    let now: Date

    var body: some View {
        GeometryReader { geo in
            let pts = snapshot.curvePoints(around: now)
            if pts.count >= 2 {
                let firstDate = pts.first!.date
                let lastDate = pts.last!.date
                let totalSeconds = max(lastDate.timeIntervalSince(firstDate), 1)
                let heights = pts.map { $0.height }
                let minH = heights.min()!
                let maxH = heights.max()!
                let span = max(maxH - minH, 0.1)

                let xFor: (Date) -> CGFloat = { date in
                    CGFloat(date.timeIntervalSince(firstDate) / totalSeconds) * geo.size.width
                }
                let yFor: (Double) -> CGFloat = { h in
                    (1 - CGFloat((h - minH) / span)) * geo.size.height
                }

                let samples: [CGPoint] = {
                    var result: [CGPoint] = []
                    for i in 0..<(pts.count - 1) {
                        let a = pts[i], b = pts[i + 1]
                        let steps = 16
                        for s in 0...(i == pts.count - 2 ? steps : steps - 1) {
                            let u = Double(s) / Double(steps)
                            let t = a.date.timeIntervalSinceReferenceDate
                                + u * (b.date.timeIntervalSinceReferenceDate - a.date.timeIntervalSinceReferenceDate)
                            let h = a.height + (b.height - a.height) * (1 - cos(.pi * u)) / 2
                            result.append(CGPoint(x: xFor(Date(timeIntervalSinceReferenceDate: t)), y: yFor(h)))
                        }
                    }
                    return result
                }()

                ZStack {
                    Path { path in
                        guard let first = samples.first, let last = samples.last else { return }
                        path.move(to: CGPoint(x: first.x, y: geo.size.height))
                        path.addLine(to: first)
                        for p in samples.dropFirst() { path.addLine(to: p) }
                        path.addLine(to: CGPoint(x: last.x, y: geo.size.height))
                        path.closeSubpath()
                    }
                    .fill(Color.blue.opacity(0.15))

                    Path { path in
                        guard let first = samples.first else { return }
                        path.move(to: first)
                        for p in samples.dropFirst() { path.addLine(to: p) }
                    }
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                    if now >= firstDate && now <= lastDate {
                        Path { path in
                            let x = xFor(now)
                            path.move(to: CGPoint(x: x, y: 0))
                            path.addLine(to: CGPoint(x: x, y: geo.size.height))
                        }
                        .stroke(Color.orange.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                }
            }
        }
    }
}

struct TideWidget: Widget {
    let kind = "TideWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TideWidgetProvider()) { entry in
            TideWidgetView(entry: entry)
        }
        .configurationDisplayName("Marées")
        .description("Courbe de marée, prochains extrêmes et prochain lever/coucher du soleil.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct TideWidgetBundle: WidgetBundle {
    var body: some Widget {
        TideWidget()
    }
}
