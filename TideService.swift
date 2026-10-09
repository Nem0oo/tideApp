//
// TideService.swift
//
// Created by Nem0oo on 13.11.24
//
 
import Foundation
import CoreLocation

// Service pour récupérer les données de marée
class TideService {
    // Clé sous laquelle la clé API est stockée dans UserDefaults (saisie via le menu Réglages)
    static let apiKeyDefaultsKey = "TideAPIKey"

    static var storedAPIKey: String? {
        let key = UserDefaults.standard.string(forKey: apiKeyDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (key?.isEmpty == false) ? key : nil
    }

    private static let requestDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    // Fuseau horaire du lieu interrogé : l'API renvoie des heures locales à ce lieu, pas à l'appareil.
    // Géocodage inverse, avec repli sur un fuseau estimé par la longitude (points en mer) puis sur celui de l'appareil.
    func resolveTimeZone(for location: CLLocation, completion: @escaping (TimeZone) -> Void) {
        CLGeocoder().reverseGeocodeLocation(location) { placemarks, error in
            if let timeZone = placemarks?.first?.timeZone {
                completion(timeZone)
            } else if error == nil || (error as? CLError)?.code == .geocodeFoundNoResult {
                let offset = Int((location.coordinate.longitude / 15).rounded()) * 3600
                completion(TimeZone(secondsFromGMT: offset) ?? .current)
            } else {
                completion(.current)
            }
        }
    }

    // `startDate`/`numberOfDays` permettent de paginer : on ne charge que quelques jours à la fois,
    // et on redemande une nouvelle tranche future quand l'utilisateur scrolle vers le bord des données chargées.
    // `completion` est toujours appelé (nil en cas d'échec), potentiellement hors du thread principal.
    func fetchTideData(for location: CLLocation, startDate: Date, numberOfDays: Int, timeZone: TimeZone,
                       completion: @escaping (TideFetchResult?) -> Void) {
        guard let apiKey = TideService.storedAPIKey else {
            print("Aucune clé API configurée")
            completion(nil)
            return
        }

        var components = URLComponents(string: "https://api.worldweatheronline.com/premium/v1/marine.ashx")
        components?.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "q", value: "\(location.coordinate.latitude),\(location.coordinate.longitude)"),
            URLQueryItem(name: "tide", value: "yes"),
            URLQueryItem(name: "date", value: TideService.requestDateFormatter.string(from: startDate)),
            URLQueryItem(name: "num_of_days", value: String(numberOfDays)),
            URLQueryItem(name: "format", value: "json"),
        ]
        guard let url = components?.url else {
            print("URL de requête invalide")
            completion(nil)
            return
        }

        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil else {
                print("Erreur lors de la requête : \(error?.localizedDescription ?? "Inconnue")")
                completion(nil)
                return
            }
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                print("Réponse HTTP inattendue : \(http.statusCode)")
                completion(nil)
                return
            }

            do {
                let tideResponse = try JSONDecoder().decode(TideResponse.self, from: data)

                // Récupère tous les objets `tide_data` de tous les objets `tides`
                let allTideData = tideResponse.data.weather.flatMap { $0.tides.flatMap { $0.tide_data } }
                    .map { tide -> TideData in
                        var tide = tide
                        tide.timeZone = timeZone
                        return tide
                    }
                // Récupère le cycle du soleil (lever/coucher) fourni par la même API, jour par jour
                let sunEvents = tideResponse.data.weather.compactMap { $0.sunEvent(in: timeZone) }.sorted { $0.sunrise < $1.sunrise }

                completion(TideFetchResult(tideData: allTideData, sunEvents: sunEvents, timeZone: timeZone))
            } catch {
                // L'API renvoie parfois une erreur (quota, plage de dates non autorisée, etc.)
                // sous forme de JSON valide mais qui ne correspond pas au schéma attendu : on l'affiche pour diagnostiquer.
                let rawBody = String(data: data, encoding: .utf8) ?? "<non lisible>"
                print("Erreur de parsing JSON : \(error)\nRéponse brute de l'API : \(rawBody)")
                completion(nil)
            }
        }.resume()
    }
}

struct TideFetchResult {
    let tideData: [TideData]
    let sunEvents: [SunEvent]
    let timeZone: TimeZone
}

// Modèles pour décode les données JSON
struct TideResponse: Codable {
    let data: WeatherData
}

struct WeatherData: Codable {
    let weather: [Weather]
}

struct Weather: Codable {
    let date: String
    // Optionnel : certains plans/API ne renvoient pas l'astronomie, la marée doit rester utilisable sans elle
    let astronomy: [Astronomy]?
    let tides: [Tides]
}

struct Astronomy: Codable {
    let sunrise: String
    let sunset: String
}

struct Tides: Codable {
    let tide_data: [TideData]
}

struct TideData: Codable {
    let tideTime: String
    let tideHeight_mt: String
    let tideDateTime: String
    let tide_type: String
    // Fuseau du lieu (heures de l'API = heure locale du lieu) ; renseigné après le décodage
    var timeZone: TimeZone = .current

    private enum CodingKeys: String, CodingKey {
        case tideTime, tideHeight_mt, tideDateTime, tide_type
    }
}

extension TideData {
    private static let formatterLock = NSLock()
    private static var formatters: [String: DateFormatter] = [:]

    private static func formatter(for timeZone: TimeZone) -> DateFormatter {
        formatterLock.lock()
        defer { formatterLock.unlock() }
        if let cached = formatters[timeZone.identifier] { return cached }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatters[timeZone.identifier] = formatter
        return formatter
    }

    var height: Double? { Double(tideHeight_mt) }
    var date: Date? { TideData.formatter(for: timeZone).date(from: tideDateTime) }
}

// Cycle du soleil (lever/coucher) pour une journée donnée
struct SunEvent {
    let sunrise: Date
    let sunset: Date
}

extension Weather {
    // L'API renvoie une astronomie par jour, en heure locale du lieu ; on combine avec la date du jour
    // et le fuseau du lieu pour obtenir des `Date` absolues
    func sunEvent(in timeZone: TimeZone) -> SunEvent? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd hh:mm a"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        guard let astro = astronomy?.first,
              let sunrise = formatter.date(from: "\(date) \(astro.sunrise)"),
              let sunset = formatter.date(from: "\(date) \(astro.sunset)")
        else { return nil }
        return SunEvent(sunrise: sunrise, sunset: sunset)
    }
}
