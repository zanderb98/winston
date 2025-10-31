import SwiftUI
import SwiftData
import Charts

struct APIRequestStatsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.useTheme) private var theme

    @State private var entries: [APIRequestLog] = []
    @State private var stats: [APIEndpointStats] = []
    @State private var searchText: String = ""
    @State private var selectedEndpoints: [String] = []

    var body: some View {
        let filtered = filteredEntries()

        List {
            if !entries.isEmpty {
                Section("Overview") {
                    APIRollingAverageChart(entries: entries, selectedEndpoints: $selectedEndpoints)
                }
                .themedListSection()
            }

            Section("Requests") {
                ForEach(filtered) { e in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(e.method)
                                .font(.subheadline).bold()
                                .foregroundStyle(.secondary)
                            Text(e.fullEndpoint ?? e.endpoint)
                                .font(.subheadline)
                                .lineLimit(2)
                            Spacer()
                            Text(format(ms: e.durationMs))
                                .font(.subheadline).monospacedDigit()
                        }
                        HStack(spacing: 8) {
                            Label(e.status.rawValue.capitalized, systemImage: icon(for: e.status))
                                .labelStyle(.iconOnly)
                                .foregroundStyle(color(for: e.status))
                            if let code = e.code {
                                Text("\(code)")
                                    .font(.caption).monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            Text(e.startedAt, style: .time)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let err = e.errorDescription, !err.isEmpty {
                            Text(err)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                    }
                }
            }
            .themedListSection()
        }
        .themedListBG(theme.lists.bg)
        .navigationTitle("API Requests")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Clear All", systemImage: "trash", role: .destructive) {
                        Task { await APIRequestStore.shared.clearAll(in: modelContext); refresh() }
                    }
                    if selectedEndpoints.isEmpty{
                        Button("Show All Endpoints", systemImage: "line.3.horizontal.decrease.circle") {
                            selectedEndpoints = []
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .searchable(text: $searchText)
        .onAppear { refresh() }
    }

    private func refresh() {
        Task(priority: .userInitiated) {
            entries = await APIRequestStore.shared.fetchAll(in: modelContext)
            stats = await APIRequestStore.shared.stats(in: modelContext)
        }
    }

    private func filteredEntries() -> [APIRequestLog] {
        var list = entries
        if !selectedEndpoints.isEmpty { list = list.filter { selectedEndpoints.contains($0.endpoint) } }
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            list = list.filter { $0.endpoint.lowercased().contains(q) || ($0.errorDescription?.lowercased().contains(q) ?? false) }
        }
        return list
    }

    private func format(ms: Double) -> String {
        if ms < 1000 { return String(format: "%.0f ms", ms) }
        return String(format: "%.2f s", ms / 1000.0)
    }

    private func icon(for status: APIRequestLog.Status) -> String {
        switch status {
        case .success: return "checkmark.circle.fill"
        case .failure: return "xmark.octagon.fill"
        case .cancelled: return "minus.circle.fill"
        }
    }

    private func color(for status: APIRequestLog.Status) -> Color {
        switch status {
            case .success: return .green
            case .failure: return .red
            case .cancelled: return .orange
        }
    }
}

struct APIRollingAverageChart: View {
    let entries: [APIRequestLog]
    @Binding var selectedEndpoints: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("API Response Times")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Individual request durations")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            if filteredChartData.isEmpty {
                ContentUnavailableView(
                    selectedEndpoints.isEmpty ? "No Data Available" : "No Data for Selected Endpoints",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text(selectedEndpoints.isEmpty ? "API requests will appear here once logged" : "Try selecting different endpoints")
                )
                .frame(height: 300)
            } else {
                Chart {
                    ForEach(filteredChartData) { series in
                        ForEach(series.data) { point in
                            LineMark(
                                x: .value("Request", point.index),
                                y: .value("Duration (ms)", point.duration)
                            )
                            .foregroundStyle(by: .value("Endpoint", series.endpoint))
                            .lineStyle(StrokeStyle(lineWidth: 2.5))
                            .interpolationMethod(.catmullRom)
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(position: .bottom) { value in
                        AxisGridLine()
                        AxisValueLabel()
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let duration = value.as(Double.self) {
                                Text("\(Int(duration))ms")
                            }
                        }
                    }
                }
                .chartLegend(position: .bottom, alignment: .leading, spacing: 12)
                .frame(height: 300)
                .padding(.vertical, 8)
            }
            
            // Summary statistics
            if !chartData.isEmpty {
                summaryView
            }
        }
    }
    
    private var summaryView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Summary")
                    .font(.headline)
                
                Spacer()
                
                if !selectedEndpoints.isEmpty {
                    Button(action: {
                        selectedEndpoints.removeAll()
                    }) {
                        Text("Clear Selection")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }
            }
            
            if endpointStats.count <= 8 {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    ForEach(endpointStats, id: \.endpoint) { stat in
                        summaryCard(for: stat)
                    }
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(150)), count: 4), spacing: 12) {
                        ForEach(endpointStats, id: \.endpoint) { stat in
                            summaryCard(for: stat)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
        .padding(.top, 8)
    }
    
    private func summaryCard(for stat: EndpointStat) -> some View {
        Button(action: {
            toggleEndpoint(stat.endpoint)
        }) {
            VStack(alignment: .leading, spacing: 4) {
                Text(stat.endpoint)
                    .font(.caption)
                    .foregroundStyle(isSelected(stat.endpoint) ? .primary : .secondary)
                    .lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(Int(stat.avgDuration))")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    Text("ms avg")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(isSelected(stat.endpoint) ? Color.blue.opacity(0.15) : Color(.secondarySystemBackground))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isSelected(stat.endpoint) ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Helper Methods
    
    private func isSelected(_ endpoint: String) -> Bool {
        selectedEndpoints.contains(endpoint)
    }
    
    private func toggleEndpoint(_ endpoint: String) {
        if let index = selectedEndpoints.firstIndex(of: endpoint) {
            selectedEndpoints.remove(at: index)
        } else {
            selectedEndpoints.append(endpoint)
        }
    }
    
    // MARK: - Data Processing
    
    private var chartData: [EndpointSeries] {
        let grouped = Dictionary(grouping: entries.sorted(by: { $0.startedAt < $1.startedAt }), by: { $0.endpoint })
        
        return grouped.compactMap { endpoint, logs in
            guard !logs.isEmpty else { return nil }
            
            let avgDuration = logs.map(\.durationMs).reduce(0, +) / Double(logs.count)
            
            let points = logs.enumerated().map { index, log in
                ChartDataPoint(
                    index: index + 1,
                    duration: log.durationMs
                )
            }
            
            return EndpointSeries(endpoint: endpoint, avgDuration: avgDuration, data: points)
        }
        .sorted { $0.avgDuration > $1.avgDuration }
    }
    
    private var filteredChartData: [EndpointSeries] {
        if selectedEndpoints.isEmpty {
            return chartData
        }
        return chartData.filter { selectedEndpoints.contains($0.endpoint) }
    }
    
    private var endpointStats: [EndpointStat] {
        let grouped = Dictionary(grouping: entries, by: { $0.endpoint })
        
        return grouped.map { endpoint, logs in
            let avgDuration = logs.map(\.durationMs).reduce(0, +) / Double(logs.count)
            return EndpointStat(endpoint: endpoint, avgDuration: avgDuration)
        }
        .sorted { $0.avgDuration > $1.avgDuration }
    }
}

// MARK: - Data Models

struct EndpointSeries: Identifiable {
    let id = UUID()
    let endpoint: String
    let avgDuration: Double
    let data: [ChartDataPoint]
}

struct ChartDataPoint: Identifiable {
    let id = UUID()
    let index: Int
    let duration: Double
}

struct EndpointStat {
    let endpoint: String
    let avgDuration: Double
}
