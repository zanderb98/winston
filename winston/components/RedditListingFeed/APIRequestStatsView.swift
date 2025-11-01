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
    
    // Time window selection
    enum TimeWindow: CaseIterable {
        case fiveMinutes
        case fifteenMinutes
        case thirtyMinutes
        case oneHour
        case oneDay

        var duration: TimeInterval {
            switch self {
            case .fiveMinutes: return 5 * 60
            case .fifteenMinutes: return 15 * 60
            case .thirtyMinutes: return 30 * 60
            case .oneHour: return 60 * 60
            case .oneDay: return 24 * 60 * 60
            }
        }

        var label: String {
            switch self {
            case .fiveMinutes: return "5m"
            case .fifteenMinutes: return "15m"
            case .thirtyMinutes: return "30m"
            case .oneHour: return "1h"
            case .oneDay: return "1d"
            }
        }
    }

    @State private var timeWindow: TimeWindow = .fifteenMinutes

    // Limit window to selected time window
    private var windowStart: Date { Date().addingTimeInterval(-timeWindow.duration) }
    private var recentEntries: [APIRequestLog] {
        entries.filter { $0.startedAt >= windowStart }
    }

    // Dynamic x-axis bounds: at most selected window, but scale to earliest available
    private var xLowerBound: Date? {
        guard let earliest = recentEntries.min(by: { $0.startedAt < $1.startedAt })?.startedAt else { return nil }
        return max(earliest, windowStart)
    }
    private var xUpperBound: Date { Date() }

    // Base palette and deterministic expansion to ensure unique colors per endpoint
    private let basePalette: [Color] = [
        .blue, .red, .green, .orange, .purple, .pink, .teal, .brown, .indigo, .mint
    ]

    private var uniqueEndpoints: [String] {
        // Use endpoints present in the current chart window, stable sorted
        let set = Set(recentEntries.map { $0.endpoint })
        return Array(set).sorted()
    }

    private var endpointColors: [String: Color] {
        var mapping: [String: Color] = [:]
        let count = uniqueEndpoints.count
        if count <= basePalette.count {
            for (idx, ep) in uniqueEndpoints.enumerated() {
                mapping[ep] = basePalette[idx]
            }
        } else {
            // Generate additional distinct hues if needed
            for (idx, ep) in uniqueEndpoints.enumerated() {
                if idx < basePalette.count {
                    mapping[ep] = basePalette[idx]
                } else {
                    // Distribute hues around the color wheel
                    let fraction = Double(idx - basePalette.count + 1) / Double(count - basePalette.count + 1)
                    mapping[ep] = Color(hue: fraction, saturation: 0.75, brightness: 0.9)
                }
            }
        }
        return mapping
    }

    private func color(for endpoint: String) -> Color {
        endpointColors[endpoint] ?? .blue
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            
            HStack(spacing: 8) {
                Text("API Response Times")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text(timeWindow.label)
                    .font(.footnote)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                    .onTapGesture {
                        cycleTimeWindow()
                    }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("Time window")
                    .accessibilityValue(timeWindow.label)
            }
            
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
                            PointMark(
                                x: .value("Time", point.time),
                                y: .value("Duration (s)", point.duration / 1000.0)
                            )
                            .foregroundStyle(by: .value("Endpoint", series.endpoint))
                            .symbolSize(35) 
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
                            if let seconds = value.as(Double.self) {
                                Text(String(format: "%.1fs", seconds))
                            }
                        }
                    }
                }
                .chartLegend(.hidden)
                .chartForegroundStyleScale(domain: uniqueEndpoints, range: uniqueEndpoints.map { color(for: $0) })
                .chartXScale(domain: (xLowerBound ?? windowStart)...xUpperBound)
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
//                Text("Summary")
//                    .font(.headline)
                
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
                    let seconds = stat.avgDuration / 1000.0
                    Text(String(format: "%.1f", seconds))
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    Text("s avg")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Rectangle()
                    .fill(color(for: stat.endpoint))
                    .frame(height: 3)
                    .opacity(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(isSelected(stat.endpoint) ? color(for: stat.endpoint).opacity(0.15) : Color(.secondarySystemBackground))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isSelected(stat.endpoint) ? color(for: stat.endpoint) : Color.clear, lineWidth: 2)
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
    
    // MARK: - Time Window Controls
    private func cycleTimeWindow() {
        let all = TimeWindow.allCases
        if let idx = all.firstIndex(of: timeWindow) {
            let next = all.index(after: idx)
            timeWindow = next < all.endIndex ? all[next] : all.first!
        } else {
            timeWindow = .fifteenMinutes
        }
    }
    
    // MARK: - Data Processing
    
    private var chartData: [EndpointSeries] {
        let grouped = Dictionary(grouping: recentEntries.sorted(by: { $0.startedAt < $1.startedAt }), by: { $0.endpoint })
        
        return grouped.compactMap { endpoint, logs in
            guard !logs.isEmpty else { return nil }
            
            let avgDuration = logs.map(\.durationMs).reduce(0, +) / Double(logs.count)
            
            let points = logs.enumerated().map { index, log in
                ChartDataPoint(
                    index: index + 1,
                    time: log.startedAt,
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
        let grouped = Dictionary(grouping: recentEntries, by: { $0.endpoint })
        
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
    let time: Date
    let duration: Double
}

struct EndpointStat {
    let endpoint: String
    let avgDuration: Double
}
