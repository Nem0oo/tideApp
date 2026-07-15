//
// LocationPickerView.swift
//
// Created by Nem0oo on 15.07.26
//

import SwiftUI
import CoreLocation

// Fenêtre de sélection d'une zone sur la carte, avec des points mémorisés pour y revenir rapidement
struct LocationPickerView: View {
    @ObservedObject var savedLocationsStore: SavedLocationsStore
    var currentLocation: CLLocation?
    var onSelect: (CLLocationCoordinate2D) -> Void

    @Environment(\.presentationMode) private var presentationMode
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    @State private var showSaveAlert = false
    @State private var newLocationName = ""

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                MapViewRepresentable(
                    savedLocations: savedLocationsStore.locations,
                    selectedCoordinate: $selectedCoordinate,
                    regionToCenter: currentLocation?.coordinate,
                    onSelectSaved: { saved in
                        selectedCoordinate = saved.coordinate
                    }
                )
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
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annuler") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        showSaveAlert = true
                    } label: {
                        Image(systemName: "star")
                    }
                    .disabled(selectedCoordinate == nil)

                    Button("Choisir") {
                        if let coordinate = selectedCoordinate {
                            onSelect(coordinate)
                            presentationMode.wrappedValue.dismiss()
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
