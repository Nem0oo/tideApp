//
// ContentView.swift
//
// Created by Nem0oo on 13.11.24
//
 
import SwiftUI
import CoreLocation

struct ContentView: View {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var savedLocationsStore = SavedLocationsStore()
    @AppStorage(TideService.apiKeyDefaultsKey) private var apiKey: String = ""
    @State private var tideData: [TideData] = []
    @State private var sunEvents: [SunEvent] = []
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var hasFetchedData = false // Nouvelle variable pour éviter les appels multiples
    @State private var showSettings = false
    @State private var showLocationPicker = false
    // Zone choisie manuellement sur la carte ; tant qu'elle est définie, elle prime sur le GPS
    @State private var manualCoordinate: CLLocationCoordinate2D?

    // Nombre de jours chargés par appel API : un premier lot avec un peu d'historique,
    // puis des tranches futures rechargées à la demande pendant le scroll du graphique
    private let initialNumberOfDays = 6
    private let moreNumberOfDays = 5

    var body: some View {
        NavigationView {
            VStack {
                if apiKey.isEmpty {
                    Spacer()
                    Image(systemName: "key.slash")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("Aucune clé API configurée")
                        .padding(.top, 4)
                    Button("Ajouter une clé API") {
                        showSettings = true
                    }
                    .padding(.top, 8)
                    Spacer()
                } else if !tideData.isEmpty {
                    TideChartView(tideData: tideData, sunEvents: sunEvents, onNeedMoreData: loadMoreTideData)
                    if isLoadingMore {
                        ProgressView("Chargement des jours suivants...")
                            .font(.caption)
                            .padding(.vertical, 4)
                    }
                    List(tideData, id: \.tideDateTime) { tide in
                        HStack {
                            Text("\(tideTypeInFrench(tide.tide_type)) : \(formattedDateAndTime(from: tide.tideDateTime))")
                            Spacer()
                            Text("\(tide.tideHeight_mt)m")
                        }
                    }
                } else if isLoading {
                    ProgressView("Chargement des données de marée...")
                } else {
                    Text("Aucune donnée de marée disponible")
                }

                if let location = effectiveLocation {
                    HStack {
                        Text("Coordonnées : \(location.coordinate.latitude), \(location.coordinate.longitude)")
                            .font(.caption)
                        if manualCoordinate != nil {
                            Button("Revenir à ma position") {
                                manualCoordinate = nil
                                hasFetchedData = true
                                refreshTideData()
                            }
                            .font(.caption)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Marées")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape")
                            .font(.title2)
                    }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button(action: { showLocationPicker = true }) {
                        Image(systemName: "map")
                            .font(.title2)
                    }
                    Button(action: refreshTideData) {
                        Image(systemName: "arrow.clockwise")
                            .font(.title2)
                    }
                    .disabled(isLoading || apiKey.isEmpty)
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showLocationPicker) {
                LocationPickerView(savedLocationsStore: savedLocationsStore, currentLocation: effectiveLocation) { coordinate in
                    // CLLocationCoordinate2D n'est pas Equatable sur toutes les toolchains :
                    // on recharge directement ici plutôt que via .onChange(of: manualCoordinate)
                    manualCoordinate = coordinate
                    hasFetchedData = true
                    refreshTideData()
                }
            }
            .onAppear {
                locationManager.startUpdatingLocation()
            }
            .onChange(of: locationManager.location) { newLocation in
                if newLocation != nil && !hasFetchedData {
                    refreshTideData()
                    hasFetchedData = true // Empêche les appels répétés
                }
            }
            .onChange(of: apiKey) { newKey in
                // Relance la récupération dès qu'une clé est saisie
                if !newKey.isEmpty && tideData.isEmpty {
                    refreshTideData()
                }
            }
        }
    }

    // Le point choisi manuellement sur la carte prime sur la position GPS tant qu'il est défini
    private var effectiveLocation: CLLocation? {
        if let manualCoordinate = manualCoordinate {
            return CLLocation(latitude: manualCoordinate.latitude, longitude: manualCoordinate.longitude)
        }
        return locationManager.location
    }

    private func refreshTideData() {
        guard let location = effectiveLocation else { return }

        // Beaucoup de clés API (marine.ashx) refusent les dates passées : on démarre à aujourd'hui
        let startDate = Date()

        isLoading = true
        TideService().fetchTideData(for: location, startDate: startDate, numberOfDays: initialNumberOfDays) { tideData, sunEvents in
            DispatchQueue.main.async {
                self.tideData = tideData ?? []
                self.sunEvents = sunEvents
                self.isLoading = false
            }
        }
    }

    // Appelé par le graphique quand l'utilisateur scrolle près du bord des données déjà chargées
    private func loadMoreTideData() {
        guard !isLoadingMore, let location = effectiveLocation else { return }
        guard let currentMax = tideData.compactMap({ $0.date }).max() else { return }

        let nextStart = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: currentMax)) ?? currentMax

        isLoadingMore = true
        TideService().fetchTideData(for: location, startDate: nextStart, numberOfDays: moreNumberOfDays) { newData, newSunEvents in
            DispatchQueue.main.async {
                self.isLoadingMore = false
                if let newData = newData, !newData.isEmpty {
                    let existingKeys = Set(self.tideData.map { $0.tideDateTime })
                    let merged = self.tideData + newData.filter { !existingKeys.contains($0.tideDateTime) }
                    self.tideData = merged.sorted { $0.tideDateTime < $1.tideDateTime }
                }
                let existingSunrises = Set(self.sunEvents.map { $0.sunrise })
                let mergedSunEvents = self.sunEvents + newSunEvents.filter { !existingSunrises.contains($0.sunrise) }
                self.sunEvents = mergedSunEvents.sorted { $0.sunrise < $1.sunrise }
            }
        }
    }

    private func tideTypeInFrench(_ tideType: String) -> String {
        return tideType == "HIGH" ? "Haute" : "Basse"
    }
    
    private func formattedDateAndTime(from dateTimeString: String) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        
        guard let date = dateFormatter.date(from: dateTimeString) else { return dateTimeString }
        
        dateFormatter.dateFormat = "dd/MM/yyyy HH:mm"
        return dateFormatter.string(from: date)
    }
}