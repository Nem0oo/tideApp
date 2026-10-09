//
// LocationManager.swift
//
// Created by Nem0oo on 13.11.24
//
 
import CoreLocation
import Combine

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    @Published var location: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    var isLocationDenied: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        authorizationStatus = locationManager.authorizationStatus
        locationManager.requestWhenInUseAuthorization()
    }
    
    func startUpdatingLocation() {
        locationManager.startUpdatingLocation()
    }
    
    // Appelé au premier choix de l'utilisateur et à chaque changement dans les Réglages iOS :
    // on démarre la localisation dès que l'autorisation est accordée (la demande initiale est asynchrone)
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let newLocation = locations.last else { return }
        location = newLocation
        locationManager.stopUpdatingLocation() // Stop after getting the location
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Erreur lors de la récupération de la localisation : \(error)")
    }
}