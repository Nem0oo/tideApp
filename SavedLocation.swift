//
// SavedLocation.swift
//
// Created by Nem0oo on 15.07.26
//

import Foundation
import CoreLocation

struct SavedLocation: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var latitude: Double
    var longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(id: UUID = UUID(), name: String, coordinate: CLLocationCoordinate2D) {
        self.id = id
        self.name = name
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }
}

// Points mémorisés par l'utilisateur pour y revenir rapidement, persistés dans UserDefaults
final class SavedLocationsStore: ObservableObject {
    private static let defaultsKey = "TideSavedLocations"

    @Published private(set) var locations: [SavedLocation] = []

    init() {
        load()
    }

    func add(name: String, coordinate: CLLocationCoordinate2D) {
        locations.append(SavedLocation(name: name, coordinate: coordinate))
        save()
    }

    func remove(at offsets: IndexSet) {
        locations.remove(atOffsets: offsets)
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
              let decoded = try? JSONDecoder().decode([SavedLocation].self, from: data) else { return }
        locations = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(locations) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}
