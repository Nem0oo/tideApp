//
// TideChartView.swift
//
// Created by Nem0oo on 13.11.24
//

import SwiftUI

// Courbe de marée : interpolation cosinus entre les extrêmes (pleine/basse mer),
// ce qui correspond à l'approximation classique de la variation du niveau d'eau.
// La chronologie complète chargée est scrollable horizontalement ; `onNeedMoreData`
// est appelé quand l'utilisateur approche du bord des données déjà récupérées.
struct TideChartView: View {
    let tideData: [TideData]
    let sunEvents: [SunEvent]
    var onNeedMoreData: () -> Void = {}

    private static let pointsPerHour: CGFloat = 14
    private static let insets = UIEdgeInsets(top: 34, left: 30, bottom: 22, right: 16)
    private static let chartHeight: CGFloat = 190

    // Jaune validé pour un accent hors palette de données (identité "soleil"),
    // toujours accompagné d'une icône + heure (le contraste seul est insuffisant en clair)
    private static let sunColor = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0xC9 / 255, green: 0x85 / 255, blue: 0x00 / 255, alpha: 1)
            : UIColor(red: 0xED / 255, green: 0xA1 / 255, blue: 0x00 / 255, alpha: 1)
    })

    private struct ExtremePoint {
        let date: Date
        let height: Double
        let isHigh: Bool
    }

    private struct SunMarker: Hashable {
        let date: Date
        let isSunrise: Bool
    }

    private struct Interval: Hashable {
        let start: Date
        let end: Date
    }

    private struct ScrollOffsetPreferenceKey: PreferenceKey {
        static var defaultValue: CGFloat = .infinity
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = min(value, nextValue())
        }
    }


    // Tous les extrêmes chargés, triés : plus de fenêtre fixe, tout est scrollable
    private var points: [ExtremePoint] {
        tideData.compactMap { tide -> ExtremePoint? in
            guard let date = tide.date, let height = tide.height else { return nil }
            return ExtremePoint(date: date, height: height, isHigh: tide.tide_type == "HIGH")
        }
        .sorted { $0.date < $1.date }
    }

    var body: some View {
        let pts = points
        if pts.count >= 2 {
            VStack(alignment: .leading, spacing: 4) {
                Text("Hauteur d'eau (m)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                GeometryReader { outerGeo in
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            chartContent(pts: pts)
                        }
                        .coordinateSpace(name: "tideScroll")
                        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { minX in
                            // Le repère est passé à portée du bord visible : on précharge la suite
                            if minX < outerGeo.size.width * 1.5 {
                                onNeedMoreData()
                            }
                        }
                        .onAppear {
                            proxy.scrollTo("now-anchor", anchor: UnitPoint(x: 0.25, y: 0.5))
                        }
                    }
                }
                .frame(height: Self.chartHeight)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private func chartContent(pts: [ExtremePoint]) -> some View {
        let insets = Self.insets
        let firstDate = pts.first!.date
        let lastDate = pts.last!.date
        let totalHours = max(lastDate.timeIntervalSince(firstDate) / 3600, 1)
        let plotWidth = CGFloat(totalHours) * Self.pointsPerHour
        let plotHeight = Self.chartHeight - insets.top - insets.bottom
        let contentWidth = plotWidth + insets.left + insets.right

        let heights = pts.map { $0.height }
        let rawSpan = (heights.max()! - heights.min()!)
        let pad = max(rawSpan * 0.15, 0.2)
        let minH = heights.min()! - pad
        let maxH = heights.max()! + pad

        let xFor: (Date) -> CGFloat = { date in
            insets.left + CGFloat(date.timeIntervalSince(firstDate) / 3600) * Self.pointsPerHour
        }
        let yFor: (Double) -> CGFloat = { h in
            insets.top + CGFloat(1 - (h - minH) / (maxH - minH)) * plotHeight
        }

        // Échantillonnage de la courbe par interpolation cosinus entre extrêmes
        let samples: [CGPoint] = {
            var result: [CGPoint] = []
            for i in 0..<(pts.count - 1) {
                let a = pts[i], b = pts[i + 1]
                let steps = 24
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

        ZStack(alignment: .topLeading) {
            // Alternance jour/nuit dérivée du cycle du soleil (contexte, pas une 2e série/axe)
            nightShading(xFor: xFor, insets: insets, plotHeight: plotHeight, firstDate: firstDate, lastDate: lastDate)

            // Grille horizontale discrète + étiquettes de hauteur
            ForEach([minH + pad, (minH + maxH) / 2, maxH - pad], id: \.self) { level in
                Path { path in
                    path.move(to: CGPoint(x: insets.left, y: yFor(level)))
                    path.addLine(to: CGPoint(x: contentWidth - insets.right, y: yFor(level)))
                }
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                Text(String(format: "%.1f", level))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .position(x: insets.left - 16, y: yFor(level))
            }

            // Aire sous la courbe
            Path { path in
                guard let first = samples.first, let last = samples.last else { return }
                path.move(to: CGPoint(x: first.x, y: insets.top + plotHeight))
                path.addLine(to: first)
                for p in samples.dropFirst() { path.addLine(to: p) }
                path.addLine(to: CGPoint(x: last.x, y: insets.top + plotHeight))
                path.closeSubpath()
            }
            .fill(Color.blue.opacity(0.12))

            // Courbe
            Path { path in
                guard let first = samples.first else { return }
                path.move(to: first)
                for p in samples.dropFirst() { path.addLine(to: p) }
            }
            .stroke(Color.blue, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

            // Repère « maintenant »
            nowMarker(xFor: xFor, insets: insets, plotHeight: plotHeight, firstDate: firstDate, lastDate: lastDate)

            // Lever/coucher du soleil : icône + heure au bord de la zone jour/nuit correspondante
            sunMarkersView(xFor: xFor, insets: insets, firstDate: firstDate, lastDate: lastDate, contentWidth: contentWidth)

            // Ancre invisible utilisée pour centrer le scroll initial sur « maintenant »
            Color.clear
                .frame(width: 1, height: 1)
                .position(x: xFor(Date()), y: insets.top + plotHeight / 2)
                .id("now-anchor")

            // Repère invisible proche du bord chargé : sa position dans le viewport déclenche le préchargement
            let sentinelDate = lastDate.addingTimeInterval(-min(24 * 3600, totalHours * 3600 * 0.4))
            Color.clear
                .frame(width: 1, height: 1)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: ScrollOffsetPreferenceKey.self,
                            value: geo.frame(in: .named("tideScroll")).minX
                        )
                    }
                )
                .position(x: xFor(sentinelDate), y: insets.top + plotHeight / 2)

            // Points extrêmes + étiquettes (hauteur au-dessus/en dessous, heure de l'autre côté)
            ForEach(0..<pts.count, id: \.self) { i in
                let p = pts[i]
                let x = xFor(p.date)
                let y = yFor(p.height)
                Circle()
                    .fill(Color.blue)
                    .frame(width: 8, height: 8)
                    .overlay(Circle().stroke(Color(UIColor.systemBackground), lineWidth: 2))
                    .position(x: x, y: y)
                Text(String(format: "%.1f m", p.height))
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.primary)
                    .position(x: min(max(x, insets.left + 18), contentWidth - insets.right - 18),
                              y: p.isHigh ? y - 14 : y + 14)
                Text(shortTime(p.date))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .position(x: min(max(x, insets.left + 18), contentWidth - insets.right - 18),
                              y: Self.chartHeight - insets.bottom + 10)
            }
        }
        .frame(width: contentWidth, height: Self.chartHeight)
    }

    @ViewBuilder
    private func nowMarker(xFor: (Date) -> CGFloat, insets: UIEdgeInsets, plotHeight: CGFloat,
                           firstDate: Date, lastDate: Date) -> some View {
        let now = Date()
        if now >= firstDate && now <= lastDate {
            let x = xFor(now)
            Path { path in
                path.move(to: CGPoint(x: x, y: insets.top))
                path.addLine(to: CGPoint(x: x, y: insets.top + plotHeight))
            }
            .stroke(Color.orange.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            Text("maintenant")
                .font(.caption2)
                .foregroundColor(.orange)
                .position(x: x, y: insets.top - 10)
        }
    }

    @ViewBuilder
    private func nightShading(xFor: @escaping (Date) -> CGFloat, insets: UIEdgeInsets, plotHeight: CGFloat,
                              firstDate: Date, lastDate: Date) -> some View {
        ForEach(nightIntervals(from: firstDate, to: lastDate), id: \.self) { interval in
            let x0 = xFor(interval.start)
            let x1 = xFor(interval.end)
            Rectangle()
                .fill(Color.indigo.opacity(0.07))
                .frame(width: max(x1 - x0, 0), height: plotHeight)
                .position(x: (x0 + x1) / 2, y: insets.top + plotHeight / 2)
        }
    }

    // Découpe la période affichée en segments de nuit, à partir des levers/couchers du soleil
    private func nightIntervals(from windowStart: Date, to windowEnd: Date) -> [Interval] {
        let daySegments = sunEvents
            .map { Interval(start: max($0.sunrise, windowStart), end: min($0.sunset, windowEnd)) }
            .filter { $0.start < $0.end }
            .sorted { $0.start < $1.start }

        var result: [Interval] = []
        var cursor = windowStart
        for segment in daySegments {
            if segment.start > cursor {
                result.append(Interval(start: cursor, end: segment.start))
            }
            cursor = max(cursor, segment.end)
        }
        if cursor < windowEnd {
            result.append(Interval(start: cursor, end: windowEnd))
        }
        return result
    }

    @ViewBuilder
    private func sunMarkersView(xFor: @escaping (Date) -> CGFloat, insets: UIEdgeInsets,
                                firstDate: Date, lastDate: Date, contentWidth: CGFloat) -> some View {
        ForEach(sunMarkers(from: firstDate, to: lastDate), id: \.self) { marker in
            let x = min(max(xFor(marker.date), insets.left + 12), contentWidth - insets.right - 12)
            VStack(spacing: 1) {
                Image(systemName: marker.isSunrise ? "sunrise.fill" : "sunset.fill")
                    .font(.system(size: 10))
                Text(shortTime(marker.date))
                    .font(.system(size: 9))
            }
            .foregroundColor(TideChartView.sunColor)
            .position(x: x, y: 12)
        }
    }

    // Lever/coucher dont l'instant tombe dans la période chargée affichée
    private func sunMarkers(from windowStart: Date, to windowEnd: Date) -> [SunMarker] {
        sunEvents.flatMap { event -> [SunMarker] in
            var markers: [SunMarker] = []
            if event.sunrise >= windowStart && event.sunrise <= windowEnd {
                markers.append(SunMarker(date: event.sunrise, isSunrise: true))
            }
            if event.sunset >= windowStart && event.sunset <= windowEnd {
                markers.append(SunMarker(date: event.sunset, isSunrise: false))
            }
            return markers
        }
    }

    private func shortTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
