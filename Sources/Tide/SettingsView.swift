//
// SettingsView.swift
//
// Created by Nem0oo on 13.11.24
//

import SwiftUI

struct SettingsView: View {
    @AppStorage(TideService.apiKeyDefaultsKey) private var apiKey: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Clé API"),
                        footer: Text("Clé WorldWeatherOnline utilisée pour récupérer les données de marée. Obtenez-en une sur worldweatheronline.com.")) {
                    TextField("Entrez votre clé API", text: $apiKey)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .font(.system(.body, design: .monospaced))

                    if !apiKey.isEmpty {
                        Button(role: .destructive) {
                            apiKey = ""
                        } label: {
                            Text("Effacer la clé")
                        }
                    }
                }
            }
            .navigationTitle("Réglages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("OK") {
                        dismiss()
                    }
                }
            }
        }
    }
}
