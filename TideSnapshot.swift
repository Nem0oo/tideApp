//
// TideSnapshot.swift
//
// Modèle partagé entre l'app et l'extension widget (fichier compilé dans les deux cibles) :
// l'app écrit un instantané des données de marée dans l'App Group, le widget le relit
// sans jamais faire de requête réseau lui-même.
//

import Foundation

struct TideSnapshot: Codable {
    struct Extreme: Codable, Identifiable {
        var id: Date { date }
        let date: Date
        let height: Double
        let isHigh: Bool
    }

    struct SunEvent: Codable {
        let sunrise: Date
        let sunset: Date
    }

    let extremes: [Extreme]
    let sunEvents: [SunEvent]
    let fetchedAt: Date
    // Identifiant du fuseau du lieu (absent des anciens instantanés) : les heures s'affichent en heure locale du lieu
    let timeZoneID: String?

    var timeZone: TimeZone {
        timeZoneID.flatMap(TimeZone.init(identifier:)) ?? .current
    }
}

extension TideSnapshot {
    // Les marées sont prévisibles longtemps à l'avance : les données ne sont "périmées" que lorsqu'il reste
    // moins de ~6 h de couverture, c'est-à-dire que l'app doit être rouverte pour recharger la suite
    func isStale(at date: Date) -> Bool {
        guard let last = extremes.last else { return true }
        return last.date < date.addingTimeInterval(6 * 3600)
    }

    func nextTwoExtremes(after date: Date) -> [Extreme] {
        Array(extremes.filter { $0.date >= date }.prefix(2))
    }

    func nextSunEvent(after date: Date) -> (isSunrise: Bool, date: Date)? {
        let candidates: [(Bool, Date)] = sunEvents.flatMap { [(true, $0.sunrise), (false, $0.sunset)] }
            .filter { $0.1 >= date }
            .sorted { $0.1 < $1.1 }
        guard let first = candidates.first else { return nil }
        return (isSunrise: first.0, date: first.1)
    }

    // Hauteur d'eau interpolée (même approximation cosinus que le graphique principal)
    func currentHeight(at date: Date) -> Double? {
        guard let idx = extremes.firstIndex(where: { $0.date > date }), idx > 0 else {
            return extremes.first?.height
        }
        let a = extremes[idx - 1]
        let b = extremes[idx]
        let total = b.date.timeIntervalSince(a.date)
        guard total > 0 else { return a.height }
        let u = date.timeIntervalSince(a.date) / total
        return a.height + (b.height - a.height) * (1 - cos(.pi * u)) / 2
    }

    // Sous-ensemble d'extrêmes utile pour tracer une mini-courbe autour de `date`,
    // avec un point de contexte de part et d'autre de la fenêtre
    func curvePoints(around date: Date) -> [Extreme] {
        let windowStart = date.addingTimeInterval(-3 * 3600)
        let windowEnd = date.addingTimeInterval(15 * 3600)
        var pts = extremes.filter { $0.date >= windowStart && $0.date <= windowEnd }
        if let before = extremes.last(where: { $0.date < windowStart }) { pts.insert(before, at: 0) }
        if let after = extremes.first(where: { $0.date > windowEnd }) { pts.append(after) }
        return pts
    }
}

enum TideSnapshotStore {
    static let appGroupID = "group.fr.gcourtot.tide"
    private static let key = "TideWidgetSnapshot"

    // Faux si l'IPA a été signé sans l'entitlement App Group (voir README) : sans lui, l'app et le widget
    // n'ont pas de conteneur partagé et le widget ne verra jamais de données.
    static var isAvailable: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) != nil
    }

    private static var defaults: UserDefaults? {
        guard isAvailable else { return nil }
        return UserDefaults(suiteName: appGroupID)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static func save(_ snapshot: TideSnapshot) {
        guard let data = try? encoder.encode(snapshot) else { return }
        guard let defaults = defaults else {
            print("App Group \(appGroupID) indisponible : snapshot du widget non enregistré (IPA signé sans entitlement ?)")
            return
        }
        defaults.set(data, forKey: key)
    }

    static func load() -> TideSnapshot? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? decoder.decode(TideSnapshot.self, from: data)
    }
}
