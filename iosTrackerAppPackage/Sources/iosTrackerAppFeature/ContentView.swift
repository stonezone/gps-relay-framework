import SwiftUI
import LocationCore

public struct ContentView: View {
    @StateObject private var viewModel = LocationRelayViewModel()

    public var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // MARK: - Relay Control Section
                    relayControlSection

                    // MARK: - WebSocket Configuration Section
                    webSocketConfigSection

                    // MARK: - Current GPS Fix Section
                    currentFixSection

                    // MARK: - Relay Health Section
                    relayHealthSection

                    // MARK: - Watch Connection Section
                    watchConnectionSection

                    Spacer()

                    // MARK: - Version Footer
                    Text("v1.0.0")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 8)
                }
                .padding()
            }
            .navigationTitle("iOS Tracker")
        }
    }

    // MARK: - VERSION UPDATE NOTE
    // When making changes to the app, update the version number above:
    // - Patch (x.x.X): Bug fixes, minor tweaks
    // - Minor (x.X.x): New features, UI changes
    // - Major (X.x.x): Breaking changes, major refactors

    // MARK: - Relay Control Section
    private var relayControlSection: some View {
        VStack(spacing: 12) {
            Button(action: {
                if viewModel.isRelayActive {
                    viewModel.stopRelay()
                } else {
                    viewModel.startRelay()
                }
            }) {
                HStack {
                    Image(systemName: viewModel.isRelayActive ? "stop.circle.fill" : "play.circle.fill")
                        .font(.title2)
                    Text(viewModel.isRelayActive ? "Stop Tracking" : "Start Tracking")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(viewModel.isRelayActive ? Color.red : Color.green)
                .foregroundColor(.white)
                .cornerRadius(12)
            }

            Text(viewModel.statusMessage)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - WebSocket Configuration Section
    private var webSocketConfigSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Jetson WebSocket URL")
                .font(.headline)

            HStack {
                Image(systemName: "network")
                    .foregroundColor(.blue)
                TextField("ws://192.168.55.1:8765", text: $viewModel.webSocketURL)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocapitalization(.none)
                    .keyboardType(.URL)
                    .disabled(viewModel.isRelayActive)
            }

            if viewModel.isRelayActive {
                Text("Stop relay to change URL")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Current GPS Fix Section
    private var currentFixSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "location.fill")
                    .foregroundColor(.blue)
                Text("Current GPS Fix")
                    .font(.headline)
                Spacer()
                if let timestamp = viewModel.lastFixTimestamp {
                    Text(formatTimestamp(timestamp))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if let fix = viewModel.currentFix {
                VStack(spacing: 8) {
                    fixDetailRow(label: "Latitude", value: String(format: "%.6f°", fix.coordinate.latitude))
                    fixDetailRow(label: "Longitude", value: String(format: "%.6f°", fix.coordinate.longitude))
                    fixDetailRow(label: "Source", value: fix.source.rawValue)
                    fixDetailRow(label: "Accuracy", value: String(format: "±%.1f m", fix.horizontalAccuracyMeters))
                    if let altitude = fix.altitudeMeters {
                        fixDetailRow(label: "Altitude", value: String(format: "%.1f m", altitude))
                    }
                    fixDetailRow(label: "Speed", value: String(format: "%.1f m/s", fix.speedMetersPerSecond))
                }
            } else {
                Text("No GPS fix available")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - watchTracker GPS Section
    private var relayHealthSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("watchTracker GPS")
                .font(.headline)

            HStack {
                Circle()
                    .fill(healthStatusColor)
                    .frame(width: 12, height: 12)
                Text(healthStatusText)
                    .font(.subheadline)
                Spacer()
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - watchTrackerApp Connection Section
    private var watchConnectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("watchTrackerApp Connection")
                .font(.headline)

            HStack {
                Image(systemName: viewModel.isWatchConnected ? "applewatch" : "applewatch.slash")
                    .foregroundColor(viewModel.isWatchConnected ? .green : .gray)
                Text(viewModel.isWatchConnected ? "Connected" : "Not Connected")
                    .font(.subheadline)
                Spacer()
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Helper Views
    private func fixDetailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }

    // MARK: - Computed Properties
    private var healthStatusColor: Color {
        switch viewModel.relayHealth {
        case .idle:
            return .gray
        case .streaming:
            return .green
        case .degraded:
            return .orange
        }
    }

    private var healthStatusText: String {
        switch viewModel.relayHealth {
        case .idle:
            return "Idle"
        case .streaming:
            return "Streaming"
        case .degraded:
            return "Degraded"
        }
    }

    // MARK: - Helper Methods
    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    public init() {}
}
