//
// TideChartView.swift
//
// Created by Nem0oo on 13.11.24
//

import SwiftUI

// Courbe de marée : interpolation cosinus entre les extrêmes (pleine/basse mer),
// ce qui correspond à l'approximation classique de la variation du niveau d'eau.
struct TideChartView: View {
    let tideData: [TideData]
    let sunEvents: [SunEvent]

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

    // Extrêmes triés, limités à une fenêtre autour de maintenant pour rester lisible
    private var points: [ExtremePoint] {
        let now = Date()
        let windowStart = now.addingTimeInterval(-8 * 3600)
        let windowEnd = now.addingTimeInterval(28 * 3600)

        let all = tideData.compactMap { tide -> ExtremePoint? in
            guard let date = tide.date, let height = tide.height else { return nil }
            return ExtremePoint(date: date, height: height, isHigh: tide.tide_type == "HIGH")
        }
        .sorted { $0.date < $1.date }

        let windowed = all.filter { $0.date >= windowStart && $0.date <= windowEnd }
        // Si le filtrage laisse trop peu de points (données anciennes ou futures), on prend les premiers
        return windowed.count >= 2 ? windowed : Array(all.prefix(6))
    }

    var body: some View {
        if points.count >= 2 {
            VStack(alignment: .leading, spacing: 4) {
                Text("Hauteur d'eau (m)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                GeometryReader { geometry in
                    chartContent(in: geometry.size)
                }
                .frame(height: 190)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private func chartContent(in size: CGSize) -> some View {
        let pts = points
        let insets = UIEdgeInsets(top: 34, left: 30, bottom: 22, right: 8)
        let plotWidth = size.width - insets.left - insets.right
        let plotHeight = size.height - insets.top - insets.bottom

        let minDate = pts.first!.date.timeIntervalSinceReferenceDate
        let maxDate = pts.last!.date.timeIntervalSinceReferenceDate
        let heights = pts.map { $0.height }
        let rawSpan = (heights.max()! - heights.min()!)
        let pad = max(rawSpan * 0.15, 0.2)
        let minH = heights.min()! - pad
        let maxH = heights.max()! + pad

        let xFor: (Date) -> CGFloat = { date in
            insets.left + CGFloat((date.timeIntervalSinceReferenceDate - minDate) / max(maxDate - minDate, 1)) * plotWidth
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
            nightShading(xFor: xFor, insets: insets, plotHeight: plotHeight, minDate: minDate, maxDate: maxDate)

            // Grille horizontale discrète + étiquettes de hauteur
            ForEach([minH + pad, (minH + maxH) / 2, maxH - pad], id: \.self) { level in
                Path { path in
                    path.move(to: CGPoint(x: insets.left, y: yFor(level)))
                    path.addLine(to: CGPoint(x: size.width - insets.right, y: yFor(level)))
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
            nowMarker(xFor: xFor, insets: insets, plotHeight: plotHeight, minDate: minDate, maxDate: maxDate)

            // Lever/coucher du soleil : icône + heure au bord de la zone jour/nuit correspondante
            sunMarkersView(xFor: xFor, insets: insets, minDate: minDate, maxDate: maxDate, size: size)

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
                    .position(x: min(max(x, insets.left + 18), size.width - insets.right - 18),
                              y: p.isHigh ? y - 14 : y + 14)
                Text(shortTime(p.date))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .position(x: min(max(x, insets.left + 18), size.width - insets.right - 18),
                              y: size.height - insets.bottom + 10)
            }
        }
    }

    @ViewBuilder
    private func nowMarker(xFor: (Date) -> CGFloat, insets: UIEdgeInsets, plotHeight: CGFloat,
                           minDate: TimeInterval, maxDate: TimeInterval) -> some View {
        let now = Date()
        if now.timeIntervalSinceReferenceDate >= minDate && now.timeIntervalSinceReferenceDate <= maxDate {
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
                              minDate: TimeInterval, maxDate: TimeInterval) -> some View {
        let windowStart = Date(timeIntervalSinceReferenceDate: minDate)
        let windowEnd = Date(timeIntervalSinceReferenceDate: maxDate)
        ForEach(nightIntervals(from: windowStart, to: windowEnd), id: \.self) { interval in
            let x0 = xFor(interval.start)
            let x1 = xFor(interval.end)
            Rectangle()
                .fill(Color.indigo.opacity(0.07))
                .frame(width: max(x1 - x0, 0), height: plotHeight)
                .position(x: (x0 + x1) / 2, y: insets.top + plotHeight / 2)
        }
    }

    // Découpe la fenêtre affichée en segments de nuit, à partir des levers/couchers du soleil
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
                                minDate: TimeInterval, maxDate: TimeInterval, size: CGSize) -> some View {
        let windowStart = Date(timeIntervalSinceReferenceDate: minDate)
        let windowEnd = Date(timeIntervalSinceReferenceDate: maxDate)
        ForEach(sunMarkers(from: windowStart, to: windowEnd), id: \.self) { marker in
            let x = min(max(xFor(marker.date), insets.left + 12), size.width - insets.right - 12)
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

    // Lever/coucher du jour affiché dont l'instant tombe dans la fenêtre visible
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
