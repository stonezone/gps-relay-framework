import SwiftUI
import LocationCore

public struct ContentView: View {
    @StateObject private var viewModel = WatchLocationViewModel()

    public var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // MARK: - Workout Control Section
                    workoutControlSection

                    // MARK: - Status Section
                    statusSection

                    // MARK: - Current GPS Fix Section
                    if let fix = viewModel.currentFix {
                        currentFixSection(fix: fix)
                    }

                    Spacer()

                    // MARK: - Version Footer
                    Text("v1.0.0")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 4)
                }
                .padding()
            }
            .navigationTitle("GPS Tracker")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - VERSION UPDATE NOTE
    // When making changes to the app, update the version number above:
    // - Patch (x.x.X): Bug fixes, minor tweaks
    // - Minor (x.X.x): New features, UI changes
    // - Major (X.x.x): Breaking changes, major refactors

    // MARK: - Workout Control Section
    private var workoutControlSection: some View {
        VStack(spacing: 12) {
            Button(action: {
                if viewModel.isTracking {
                    viewModel.stopTracking()
                } else {
                    viewModel.startTracking()
                }
            }) {
                HStack {
                    Image(systemName: viewModel.isTracking ? "stop.circle.fill" : "play.circle.fill")
                        .font(.title3)
                    Text(viewModel.isTracking ? "Stop" : "Start")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(viewModel.isTracking ? Color.red : Color.green)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())

            Text(viewModel.statusMessage)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Status Section
    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "figure.run")
                    .foregroundColor(.blue)
                Text("Workout Status")
                    .font(.headline)
            }

            HStack {
                Circle()
                    .fill(viewModel.isTracking ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                Text(viewModel.workoutState)
                    .font(.subheadline)
                Spacer()
            }

            HStack {
                Text("Fixes sent:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(viewModel.fixCount)")
                    .font(.caption)
                    .fontWeight(.medium)
            }
        }
        .padding(12)
        .background(Color.gray.opacity(0.2))
        .cornerRadius(8)
    }

    // MARK: - Current GPS Fix Section
    private func currentFixSection(fix: LocationFix) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "location.fill")
                    .foregroundColor(.blue)
                Text("Last Fix")
                    .font(.headline)
            }

            VStack(spacing: 6) {
                fixDetailRow(label: "Lat", value: String(format: "%.4f°", fix.coordinate.latitude))
                fixDetailRow(label: "Lon", value: String(format: "%.4f°", fix.coordinate.longitude))
                fixDetailRow(label: "Acc", value: String(format: "±%.0fm", fix.horizontalAccuracyMeters))
                if let altitude = fix.altitudeMeters {
                    fixDetailRow(label: "Alt", value: String(format: "%.0fm", altitude))
                }
            }

            if let timestamp = viewModel.lastFixTimestamp {
                Text(formatTimestamp(timestamp))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(Color.gray.opacity(0.2))
        .cornerRadius(8)
    }

    // MARK: - Helper Views
    private func fixDetailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
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
