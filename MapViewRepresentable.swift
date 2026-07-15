//
// MapViewRepresentable.swift
//
// Created by Nem0oo on 15.07.26
//

import SwiftUI
import MapKit

// L'API SwiftUI `Map` disponible en iOS 16 ne permet pas de récupérer la coordonnée d'un tap :
// on passe donc par un wrapper UIKit classique autour de MKMapView.
struct MapViewRepresentable: UIViewRepresentable {
    var savedLocations: [SavedLocation]
    @Binding var selectedCoordinate: CLLocationCoordinate2D?
    var regionToCenter: CLLocationCoordinate2D?
    var onSelectSaved: (SavedLocation) -> Void

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true

        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        mapView.addGestureRecognizer(tapGesture)

        if let center = regionToCenter {
            mapView.setRegion(MKCoordinateRegion(center: center, latitudinalMeters: 20000, longitudinalMeters: 20000), animated: false)
        }

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.parent = self

        // Annotations des points mémorisés
        let existingSaved = mapView.annotations.compactMap { $0 as? SavedLocationAnnotation }
        if Set(existingSaved.map(\.location.id)) != Set(savedLocations.map(\.id)) {
            mapView.removeAnnotations(existingSaved)
            mapView.addAnnotations(savedLocations.map(SavedLocationAnnotation.init))
        }

        // Repère de la sélection courante
        let existingSelection = mapView.annotations.compactMap { $0 as? SelectionAnnotation }
        if let coordinate = selectedCoordinate {
            if let existing = existingSelection.first {
                existing.coordinate = coordinate
            } else {
                mapView.addAnnotation(SelectionAnnotation(coordinate: coordinate))
            }
        } else if !existingSelection.isEmpty {
            mapView.removeAnnotations(existingSelection)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapViewRepresentable

        init(parent: MapViewRepresentable) {
            self.parent = parent
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let mapView = gesture.view as? MKMapView else { return }
            let point = gesture.location(in: mapView)
            parent.selectedCoordinate = mapView.convert(point, toCoordinateFrom: mapView)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let saved = annotation as? SavedLocationAnnotation {
                let identifier = "saved"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                    ?? MKMarkerAnnotationView(annotation: saved, reuseIdentifier: identifier)
                view.annotation = saved
                view.markerTintColor = .systemBlue
                view.glyphImage = UIImage(systemName: "star.fill")
                view.canShowCallout = true
                return view
            }

            if let selection = annotation as? SelectionAnnotation {
                let identifier = "selection"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                    ?? MKMarkerAnnotationView(annotation: selection, reuseIdentifier: identifier)
                view.annotation = selection
                view.markerTintColor = .systemRed
                view.canShowCallout = false
                return view
            }

            return nil
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let saved = (view.annotation as? SavedLocationAnnotation)?.location else { return }
            parent.onSelectSaved(saved)
            mapView.deselectAnnotation(view.annotation, animated: false)
        }
    }
}

final class SavedLocationAnnotation: NSObject, MKAnnotation {
    let location: SavedLocation
    var coordinate: CLLocationCoordinate2D { location.coordinate }
    var title: String? { location.name }

    init(location: SavedLocation) {
        self.location = location
    }
}

final class SelectionAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D
    var title: String? = "Position sélectionnée"

    init(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
    }
}
