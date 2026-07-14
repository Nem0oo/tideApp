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
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
    }
    
    func startUpdatingLocation() {
        locationManager.startUpdatingLocation()
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