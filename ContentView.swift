//
// ContentView.swift
//
// Created by Nem0oo on 13.11.24
//
 
import SwiftUI
import CoreLocation
import WidgetKit

struct ContentView: View {
    @State private var locationManager = LocationManager()
    @State private var savedLocationsStore = SavedLocationsStore()
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
    // Fuseau du lieu affiché (les heures de l'API sont en heure locale du lieu)
    @State private var locationTimeZone: TimeZone = .current
    // Incrémenté à chaque changement de lieu / rafraîchissement : les réponses d'une génération
    // périmée (ancien lieu, requête dépassée) sont ignorées
    @State private var requestGeneration = 0
    @State private var loadFailed = false
    // Dernier chargement réussi : sert à rafraîchir au retour au premier plan et quand on a beaucoup bougé
    @State private var lastFetchDate: Date?
    @State private var lastFetchedLocation: CLLocation?
    // Évite de relancer en boucle le chargement de la suite quand l'API refuse ou ne renvoie plus rien
    @State private var lastLoadMoreFailure: Date?
    @Environment(\.scenePhase) private var scenePhase

    // Délai au-delà duquel un retour au premier plan relance le chargement, et distance de déplacement
    // au-delà de laquelle une nouvelle position GPS recharge les marées
    private let foregroundRefreshInterval: TimeInterval = 3600
    private let significantMoveDistance: CLLocationDistance = 5000

    // Nombre de jours chargés par appel API : un premier lot avec un peu d'historique,
    // puis des tranches futures rechargées à la demande pendant le scroll du graphique
    private let initialNumberOfDays = 6
    private let moreNumberOfDays = 5

    var body: some View {
        NavigationStack {
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
                } else if locationManager.isLocationDenied && manualCoordinate == nil {
                    Spacer()
                    Image(systemName: "location.slash")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("Localisation désactivée")
                        .padding(.top, 4)
                    Text("Autorisez l'accès à la position dans les Réglages iOS, ou choisissez une zone sur la carte.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("Ouvrir les Réglages iOS") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .padding(.top, 8)
                    Spacer()
                } else {
                    Text(loadFailed ? "Impossible de charger les données de marée" : "Aucune donnée de marée disponible")
                }
                if loadFailed && !tideData.isEmpty {
                    Text("Actualisation impossible : données précédentes affichées")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let location = effectiveLocation {
                    HStack {
                        Text("Coordonnées : \(location.coordinate.latitude), \(location.coordinate.longitude)")
                            .font(.caption)
                        if manualCoordinate != nil {
                            Button("Revenir à ma position") {
                                manualCoordinate = nil
                                hasFetchedData = true
                                refreshTideData(resetting: true)
                            }
                            .font(.caption)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Marées")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape")
                            .font(.title2)
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button(action: { showLocationPicker = true }) {
                        Image(systemName: "map")
                            .font(.title2)
                    }
                    Button(action: { refreshTideData() }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.title2)
                    }
                    .disabled(isLoading || apiKey.isEmpty)
                }
            }
            .sheet(isPresented: $showSettings, onDismiss: {
                // Relance la récupération une fois la clé saisie (et non à chaque frappe dans le champ)
                if !apiKey.isEmpty && tideData.isEmpty && !isLoading {
                    refreshTideData()
                }
            }) {
                SettingsView()
            }
            .sheet(isPresented: $showLocationPicker) {
                LocationPickerView(savedLocationsStore: savedLocationsStore, currentLocation: effectiveLocation) { coordinate in
                    // CLLocationCoordinate2D n'est pas Equatable sur toutes les toolchains :
                    // on recharge directement ici plutôt que via .onChange(of: manualCoordinate)
                    manualCoordinate = coordinate
                    hasFetchedData = true
                    refreshTideData(resetting: true)
                }
            }
            .onAppear {
                locationManager.startUpdatingLocation()
            }
            .onChange(of: locationManager.location) { _, newLocation in
                guard let newLocation = newLocation else { return }
                if !hasFetchedData {
                    refreshTideData()
                    hasFetchedData = true // Empêche les appels répétés
                } else if manualCoordinate == nil, let last = lastFetchedLocation,
                          newLocation.distance(from: last) > significantMoveDistance {
                    // La position GPS a beaucoup changé depuis le dernier chargement
                    refreshTideData(resetting: true)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                // La localisation s'arrête après un fix : on la relance à chaque retour au premier plan
                locationManager.startUpdatingLocation()
                let isStale = lastFetchDate.map { Date().timeIntervalSince($0) > foregroundRefreshInterval } ?? true
                if hasFetchedData && isStale && !apiKey.isEmpty && !isLoading {
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

    // `resetting` : le lieu a changé, les données affichées ne le concernent plus et sont vidées tout de suite.
    // Sinon, un échec réseau conserve les données (et le snapshot du widget) précédents.
    private func refreshTideData(resetting: Bool = false) {
        guard let location = effectiveLocation else { return }

        requestGeneration += 1
        let generation = requestGeneration
        if resetting {
            tideData = []
            sunEvents = []
        }
        loadFailed = false
        isLoadingMore = false

        // Beaucoup de clés API (marine.ashx) refusent les dates passées : on démarre à aujourd'hui
        let startDate = Date()

        isLoading = true
        let service = TideService()
        service.resolveTimeZone(for: location) { timeZone in
            service.fetchTideData(for: location, startDate: startDate, numberOfDays: initialNumberOfDays, timeZone: timeZone) { result in
                DispatchQueue.main.async {
                    guard generation == self.requestGeneration else { return }
                    self.isLoading = false
                    guard let result = result else {
                        self.loadFailed = true
                        return
                    }
                    self.locationTimeZone = result.timeZone
                    self.lastFetchDate = Date()
                    self.lastFetchedLocation = location
                    self.tideData = result.tideData
                    self.sunEvents = result.sunEvents
                    self.publishWidgetSnapshot()
                }
            }
        }
    }

    // Appelé par le graphique quand l'utilisateur scrolle près du bord des données déjà chargées
    private func loadMoreTideData() {
        guard !isLoadingMore, !isLoading, let location = effectiveLocation else { return }
        if let failure = lastLoadMoreFailure, Date().timeIntervalSince(failure) < 60 { return }
        guard let currentMax = tideData.compactMap({ $0.date }).max() else { return }

        let nextStart = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: currentMax)) ?? currentMax
        let generation = requestGeneration

        isLoadingMore = true
        TideService().fetchTideData(for: location, startDate: nextStart, numberOfDays: moreNumberOfDays, timeZone: locationTimeZone) { result in
            DispatchQueue.main.async {
                // Le lieu a changé (ou un rafraîchissement a eu lieu) pendant la requête : résultat obsolète
                guard generation == self.requestGeneration else { return }
                self.isLoadingMore = false
                guard let result = result, !result.tideData.isEmpty else {
                    self.lastLoadMoreFailure = Date()
                    return
                }
                self.lastLoadMoreFailure = nil
                let existingKeys = Set(self.tideData.map { $0.tideDateTime })
                let merged = self.tideData + result.tideData.filter { !existingKeys.contains($0.tideDateTime) }
                self.tideData = merged.sorted { $0.tideDateTime < $1.tideDateTime }
                let existingSunrises = Set(self.sunEvents.map { $0.sunrise })
                let mergedSunEvents = self.sunEvents + result.sunEvents.filter { !existingSunrises.contains($0.sunrise) }
                self.sunEvents = mergedSunEvents.sorted { $0.sunrise < $1.sunrise }
                self.publishWidgetSnapshot()
            }
        }
    }

    // Republie un instantané pour le widget dans l'App Group et déclenche son rafraîchissement
    private func publishWidgetSnapshot() {
        guard !tideData.isEmpty else { return }
        let extremes = tideData.compactMap { tide -> TideSnapshot.Extreme? in
            guard let date = tide.date, let height = tide.height else { return nil }
            return TideSnapshot.Extreme(date: date, height: height, isHigh: tide.tide_type == "HIGH")
        }.sorted { $0.date < $1.date }
        let events = sunEvents.map { TideSnapshot.SunEvent(sunrise: $0.sunrise, sunset: $0.sunset) }
        TideSnapshotStore.save(TideSnapshot(extremes: extremes, sunEvents: events, fetchedAt: Date(), timeZoneID: locationTimeZone.identifier))
        WidgetCenter.shared.reloadAllTimelines()
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