//
// ContentView.swift
//
// Created by Nem0oo on 13.11.24
//
 
import SwiftUI

struct ContentView: View {
    @StateObject private var locationManager = LocationManager()
    @AppStorage(TideService.apiKeyDefaultsKey) private var apiKey: String = ""
    @State private var tideData: [TideData] = []
    @State private var sunEvents: [SunEvent] = []
    @State private var isLoading = false
    @State private var hasFetchedData = false // Nouvelle variable pour éviter les appels multiples
    @State private var showSettings = false

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
                    TideChartView(tideData: tideData, sunEvents: sunEvents)
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

                if let location = locationManager.location {
                    Text("Coordonnées : \(location.coordinate.latitude), \(location.coordinate.longitude)")
                        .font(.caption)
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
                ToolbarItem(placement: .navigationBarTrailing) {
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
    
    private func refreshTideData() {
        guard let location = locationManager.location else { return }
        
        isLoading = true
        TideService().fetchTideData(for: location) { tideData, sunEvents in
            DispatchQueue.main.async {
                self.tideData = tideData ?? []
                self.sunEvents = sunEvents
                self.isLoading = false
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