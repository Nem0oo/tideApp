//
// LocationPickerView.swift
//
// Created by Nem0oo on 15.07.26
//

import SwiftUI
import CoreLocation
import MapKit

// Fenêtre de sélection d'une zone sur la carte, avec des points mémorisés pour y revenir rapidement
struct LocationPickerView: View {
    var savedLocationsStore: SavedLocationsStore
    var currentLocation: CLLocation?
    var onSelect: (CLLocationCoordinate2D) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var cameraPosition: MapCameraPosition
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    @State private var showSaveAlert = false
    @State private var newLocationName = ""

    init(savedLocationsStore: SavedLocationsStore, currentLocation: CLLocation?,
         onSelect: @escaping (CLLocationCoordinate2D) -> Void) {
        self.savedLocationsStore = savedLocationsStore
        self.currentLocation = currentLocation
        self.onSelect = onSelect
        let initialPosition: MapCameraPosition = currentLocation.map {
            .region(MKCoordinateRegion(center: $0.coordinate, latitudinalMeters: 20000, longitudinalMeters: 20000))
        } ?? .automatic
        _cameraPosition = State(initialValue: initialPosition)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // `MapReader` convertit la position d'un tap en coordonnée géographique ; un tap sur
                // un point mémorisé est capté par son propre geste et ne déclenche pas celui de la carte.
                MapReader { proxy in
                    Map(position: $cameraPosition) {
                        UserAnnotation()

                        ForEach(savedLocationsStore.locations) { saved in
                            Annotation(saved.name, coordinate: saved.coordinate) {
                                Image(systemName: "star.fill")
                                    .font(.caption)
                                    .foregroundStyle(.white)
                                    .padding(6)
                                    .background(Circle().fill(Color.blue))
                                    .onTapGesture {
                                        selectedCoordinate = saved.coordinate
                                    }
                            }
                        }

                        if let coordinate = selectedCoordinate {
                            Marker("Position sélectionnée", coordinate: coordinate)
                                .tint(.red)
                        }
                    }
                    .onTapGesture { screenPoint in
                        if let coordinate = proxy.convert(screenPoint, from: .local) {
                            selectedCoordinate = coordinate
                        }
                    }
                }
                .frame(minHeight: 260)

                List {
                    Section(header: Text("Points mémorisés")) {
                        if savedLocationsStore.locations.isEmpty {
                            Text("Aucun point mémorisé pour l'instant. Touchez la carte puis l'étoile pour en ajouter un.")
                                .foregroundColor(.secondary)
                                .font(.footnote)
                        } else {
                            ForEach(savedLocationsStore.locations) { location in
                                Button {
                                    selectedCoordinate = location.coordinate
                                } label: {
                                    HStack {
                                        Image(systemName: "star.fill")
                                            .foregroundColor(.blue)
                                        Text(location.name)
                                        Spacer()
                                        if selectedCoordinate?.latitude == location.latitude &&
                                            selectedCoordinate?.longitude == location.longitude {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(.accentColor)
                                        }
                                    }
                                }
                                .foregroundColor(.primary)
                            }
                            .onDelete(perform: savedLocationsStore.remove)
                        }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Choisir une zone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annuler") {
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showSaveAlert = true
                    } label: {
                        Image(systemName: "star")
                    }
                    .disabled(selectedCoordinate == nil)

                    Button("Choisir") {
                        if let coordinate = selectedCoordinate {
                            onSelect(coordinate)
                            dismiss()
                        }
                    }
                    .disabled(selectedCoordinate == nil)
                }
            }
            .alert("Mémoriser ce point", isPresented: $showSaveAlert) {
                TextField("Nom du lieu", text: $newLocationName)
                Button("Annuler", role: .cancel) {
                    newLocationName = ""
                }
                Button("Enregistrer") {
                    let trimmedName = newLocationName.trimmingCharacters(in: .whitespaces)
                    if let coordinate = selectedCoordinate, !trimmedName.isEmpty {
                        savedLocationsStore.add(name: trimmedName, coordinate: coordinate)
                    }
                    newLocationName = ""
                }
            } message: {
                Text("Ce point sera disponible dans la liste pour y revenir rapidement.")
            }
            .onAppear {
                if selectedCoordinate == nil {
                    selectedCoordinate = currentLocation?.coordinate
                }
            }
        }
    }
}
