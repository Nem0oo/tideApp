//
// TideChartView.swift
//
// Created by Nem0oo on 13.11.24
//

import SwiftUI
import Charts

// Courbe de marée : interpolation cosinus entre les extrêmes (pleine/basse mer),
// ce qui correspond à l'approximation classique de la variation du niveau d'eau.
// La chronologie complète chargée est scrollable horizontalement ; `onNeedMoreData`
// est appelé quand l'utilisateur approche du bord des données déjà récupérées.
struct TideChartView: View {
    var onNeedMoreData: () -> Void = {}

    // Fenêtre visible (~ un jour et demi) et marge avant le bord chargé à partir de laquelle on précharge la suite
    private static let visibleSeconds: TimeInterval = 30 * 3600
    private static let prefetchMargin: TimeInterval = 24 * 3600
    private static let samplesPerSegment = 24

    // Jaune validé pour un accent hors palette de données (identité "soleil"),
    // toujours accompagné d'une icône + heure (le contraste seul est insuffisant en clair)
    private static let sunColor = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0xC9 / 255, green: 0x85 / 255, blue: 0x00 / 255, alpha: 1)
            : UIColor(red: 0xED / 255, green: 0xA1 / 255, blue: 0x00 / 255, alpha: 1)
    })

    private struct ExtremePoint: Identifiable {
        var id: Date { date }
        let date: Date
        let height: Double
        let isHigh: Bool
    }

    private struct CurveSample: Identifiable {
        let id: Int
        let date: Date
        let height: Double
    }

    private struct SunMarker: Identifiable {
        var id: Date { date }
        let date: Date
        let isSunrise: Bool
    }

    private struct Interval {
        let start: Date
        let end: Date
    }

    // Calculés une seule fois à la construction (et non à chaque évolution de la position de scroll)
    private let points: [ExtremePoint]
    private let samples: [CurveSample]
    private let nights: [Interval]
    private let sunMarkers: [SunMarker]
    private let timeZone: TimeZone
    @State private var scrollX: Date

    init(tideData: [TideData], sunEvents: [SunEvent], onNeedMoreData: @escaping () -> Void = {}) {
        self.onNeedMoreData = onNeedMoreData
        timeZone = tideData.first?.timeZone ?? .current

        // Tous les extrêmes chargés, triés : tout est scrollable
        let pts = tideData.compactMap { tide -> ExtremePoint? in
            guard let date = tide.date, let height = tide.height else { return nil }
            return ExtremePoint(date: date, height: height, isHigh: tide.tide_type == "HIGH")
        }
        .sorted { $0.date < $1.date }
        points = pts

        // Échantillonnage de la courbe par interpolation cosinus entre extrêmes
        var result: [CurveSample] = []
        if pts.count >= 2 {
            let steps = Self.samplesPerSegment
            for i in 0..<(pts.count - 1) {
                let a = pts[i], b = pts[i + 1]
                for s in 0...(i == pts.count - 2 ? steps : steps - 1) {
                    let u = Double(s) / Double(steps)
                    let date = a.date.addingTimeInterval(u * b.date.timeIntervalSince(a.date))
                    let height = a.height + (b.height - a.height) * (1 - cos(.pi * u)) / 2
                    result.append(CurveSample(id: result.count, date: date, height: height))
                }
            }
        }
        samples = result

        if let first = pts.first?.date, let last = pts.last?.date {
            nights = Self.nightIntervals(sunEvents: sunEvents, from: first, to: last)
            sunMarkers = Self.sunMarkers(sunEvents: sunEvents, from: first, to: last)
        } else {
            nights = []
            sunMarkers = []
        }

        _scrollX = State(initialValue: Date().addingTimeInterval(-6 * 3600))
    }

    var body: some View {
        if let first = points.first?.date, let last = points.last?.date, points.count >= 2 {
            let heights = points.map(\.height)
            let pad = max((heights.max()! - heights.min()!) * 0.15, 0.2)
            let yDomain = (heights.min()! - pad)...(heights.max()! + pad)
            let timeStyle = Date.FormatStyle(timeZone: timeZone).hour(.twoDigits(amPM: .omitted)).minute()
            let now = Date()

            VStack(alignment: .leading, spacing: 4) {
                Text("Hauteur d'eau (m)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Chart {
                    // Alternance jour/nuit dérivée du cycle du soleil (contexte, pas une 2e série/axe)
                    ForEach(nights, id: \.start) { night in
                        RectangleMark(xStart: .value("Début de nuit", night.start),
                                      xEnd: .value("Fin de nuit", night.end))
                            .foregroundStyle(Color.indigo.opacity(0.07))
                    }

                    // Aire sous la courbe
                    ForEach(samples) { sample in
                        AreaMark(x: .value("Heure", sample.date),
                                 yStart: .value("Base", yDomain.lowerBound),
                                 yEnd: .value("Hauteur", sample.height))
                            .foregroundStyle(Color.blue.opacity(0.12))
                    }

                    // Courbe
                    ForEach(samples) { sample in
                        LineMark(x: .value("Heure", sample.date),
                                 y: .value("Hauteur", sample.height))
                            .foregroundStyle(Color.blue)
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                            .interpolationMethod(.linear)
                    }

                    // Repère « maintenant »
                    if now >= first && now <= last {
                        RuleMark(x: .value("Maintenant", now))
                            .foregroundStyle(Color.orange.opacity(0.8))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .annotation(position: .topTrailing, spacing: 0,
                                        overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                                Text("maintenant")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            }
                    }

                    // Lever/coucher du soleil : icône + heure au-dessus de la zone jour/nuit correspondante
                    ForEach(sunMarkers) { marker in
                        PointMark(x: .value("Soleil", marker.date),
                                  y: .value("Hauteur", yDomain.upperBound))
                            .opacity(0)
                            .annotation(position: .top, spacing: 2,
                                        overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                                VStack(spacing: 1) {
                                    Image(systemName: marker.isSunrise ? "sunrise.fill" : "sunset.fill")
                                        .font(.system(size: 10))
                                    Text(marker.date, format: timeStyle)
                                        .font(.system(size: 9))
                                }
                                .foregroundColor(Self.sunColor)
                            }
                    }

                    // Points extrêmes + étiquette de hauteur (au-dessus d'une pleine mer, en dessous d'une basse mer)
                    ForEach(points) { point in
                        PointMark(x: .value("Heure", point.date),
                                  y: .value("Hauteur", point.height))
                            .foregroundStyle(Color.blue)
                            .symbolSize(40)
                            .annotation(position: point.isHigh ? .top : .bottom, spacing: 2,
                                        overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                                Text(String(format: "%.1f m", point.height))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundColor(.primary)
                            }
                    }
                }
                .environment(\.timeZone, timeZone)
                .chartXScale(domain: first...last)
                .chartYScale(domain: yDomain)
                .chartScrollableAxes(.horizontal)
                .chartXVisibleDomain(length: Self.visibleSeconds)
                .chartScrollPosition(x: $scrollX)
                .chartPlotStyle { plot in
                    // Place pour les icônes de lever/coucher au-dessus de la zone de tracé
                    plot.padding(.top, 26)
                }
                .chartXAxis {
                    // Une étiquette d'heure sous chaque extrême
                    AxisMarks(values: points.map(\.date)) { value in
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(date, format: timeStyle)
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                        AxisGridLine().foregroundStyle(Color.secondary.opacity(0.18))
                        AxisValueLabel().font(.caption2)
                    }
                }
                .frame(height: 220)
                .onChange(of: scrollX) { _, newX in
                    prefetchIfNeeded(visibleStart: newX, loadedEnd: last)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    // La fin de la zone visible approche du bord des données chargées : on précharge la suite
    private func prefetchIfNeeded(visibleStart: Date, loadedEnd: Date) {
        if visibleStart.addingTimeInterval(Self.visibleSeconds + Self.prefetchMargin) > loadedEnd {
            onNeedMoreData()
        }
    }

    // Découpe la période affichée en segments de nuit, à partir des levers/couchers du soleil
    private static func nightIntervals(sunEvents: [SunEvent], from windowStart: Date, to windowEnd: Date) -> [Interval] {
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

    // Lever/coucher dont l'instant tombe dans la période chargée affichée
    private static func sunMarkers(sunEvents: [SunEvent], from windowStart: Date, to windowEnd: Date) -> [SunMarker] {
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
}
