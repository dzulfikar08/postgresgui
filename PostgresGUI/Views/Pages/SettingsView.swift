//
//  SettingsView.swift
//  PostgresGUI
//
//  Application settings view.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage(Constants.UserDefaultsKeys.queryResultsDateFormat)
    private var dateFormatRawValue = QueryResultsDateFormat.iso8601.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.Spacing.medium) {
            Text("Settings")
                .font(.title2)

            GroupBox("Date Format") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("", selection: $dateFormatRawValue) {
                        ForEach(QueryResultsDateFormat.allCases) { option in
                            HStack {
                                Text(option.displayName)
                                Spacer(minLength: 12)
                                Text(option.example)
                                    .foregroundStyle(.secondary)
                                    .font(.system(size: Constants.FontSize.small, design: .monospaced))
                            }
                            .tag(option.rawValue)
                        }
                    }
                    .pickerStyle(.radioGroup)
                }
                .padding(.top, 4)
            }
        }
        .frame(width: 520, height: 280, alignment: .topLeading)
        .padding()
    }
}

#Preview {
    SettingsView()
}
