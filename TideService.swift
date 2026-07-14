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

    func fetchTideData(for location: CLLocation, completion: @escaping ([TideData]?, [SunEvent]) -> Void) {
        guard let apiKey = TideService.storedAPIKey else {
            print("Aucune clé API configurée")
            completion(nil, [])
            return
        }
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        let urlString = "https://api.worldweatheronline.com/premium/v1/marine.ashx?key=\(apiKey)&q=\(lat),\(lon)&tide=yes&format=json"

        guard let url = URL(string: urlString) else { return }

        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil else {
                print("Erreur lors de la requête : \(error?.localizedDescription ?? "Inconnue")")
                completion(nil, [])
                return
            }

            do {
                let tideResponse = try JSONDecoder().decode(TideResponse.self, from: data)

                // Récupère tous les objets `tide_data` de tous les objets `tides`
                let allTideData = tideResponse.data.weather.flatMap { $0.tides.flatMap { $0.tide_data } }
                // Récupère le cycle du soleil (lever/coucher) fourni par la même API, jour par jour
                let sunEvents = tideResponse.data.weather.compactMap { $0.sunEvent }.sorted { $0.sunrise < $1.sunrise }

                completion(allTideData, sunEvents)
            } catch {
                print("Erreur de parsing JSON : \(error)")
                completion(nil, [])
            }
        }.resume()
    }
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
}

extension TideData {
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    var height: Double? { Double(tideHeight_mt) }
    var date: Date? { TideData.dateFormatter.date(from: tideDateTime) }
}

// Cycle du soleil (lever/coucher) pour une journée donnée
struct SunEvent {
    let sunrise: Date
    let sunset: Date
}

extension Weather {
    private static let sunDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd hh:mm a"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    // L'API renvoie une astronomie par jour ; on combine avec la date du jour pour obtenir des `Date` absolues
    var sunEvent: SunEvent? {
        guard let astro = astronomy?.first,
              let sunrise = Weather.sunDateFormatter.date(from: "\(date) \(astro.sunrise)"),
              let sunset = Weather.sunDateFormatter.date(from: "\(date) \(astro.sunset)")
        else { return nil }
        return SunEvent(sunrise: sunrise, sunset: sunset)
    }
}