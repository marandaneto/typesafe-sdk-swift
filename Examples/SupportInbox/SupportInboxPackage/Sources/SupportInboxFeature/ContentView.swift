import SwiftUI
import TypeSafe

@MainActor
public struct ContentView: View {
    @State private var message = TicketPreset.refund.message
    @State private var selectedModel = "jev-latest"
    @State private var models: [Model] = []
    @State private var timeout = 10.0
    @State private var retries = 2
    @State private var useTotalTimeout = false
    @State private var totalTimeout = 20.0
    @State private var tab = 0
    @State private var operation: Operation?
    @State private var status = "Ready to triage a support ticket."
    @State private var response: APIResponse<SystemOneResponse>?
    @State private var requestJSON = "No request yet."
    @State private var responseJSON = "No response yet."
    @State private var endpoint = "POST /v1/systemone"
    @State private var metadata: ResponseMetadata?
    private let credentials = DemoCredentials.current

    private struct Operation: Identifiable {
        enum Kind { case triage(TriageScenario), models }
        let id = UUID()
        let kind: Kind
        let timeout: Double
        let retries: Int
        let totalTimeout: Double?
    }

    public init() {}

    public var body: some View {
        TabView(selection: $tab) {
            NavigationStack { inbox }
                .tabItem { Label("Inbox", systemImage: "tray.full") }.tag(0)
            NavigationStack { results }
                .tabItem { Label("Results", systemImage: "chart.bar.xaxis") }.tag(1)
            NavigationStack { wire }
                .tabItem { Label("API", systemImage: "curlybraces") }.tag(2)
            NavigationStack { settings }
                .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }.tag(3)
        }
        .tint(.indigo)
        .task(id: operation?.id) {
            guard let operation else { return }
            await perform(operation)
        }
    }

    private var inbox: some View {
        Form {
            Section {
                Label("Support Inbox Triage", systemImage: "sparkles")
                    .font(.title2.bold())
                Text("One customer message. Three decisions: the right team, refund intent, and urgency.")
                    .foregroundStyle(.secondary)
            }
            Section("Try a real-world scenario") {
                ForEach(TicketPreset.allCases) { preset in
                    Button(preset.rawValue) { message = preset.message }
                        .disabled(operation != nil)
                }
            }
            Section("Customer message") {
                TextEditor(text: $message)
                    .frame(minHeight: 135)
                    .accessibilityLabel("Customer message")
                    .disabled(operation != nil)
                Text("Synthetic examples only. Edited text is sent to TypeSafe's API.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button {
                    response = nil
                    operation = Operation(kind: .triage(TriageScenario(message: message, model: selectedModel)), timeout: timeout, retries: retries, totalTimeout: useTotalTimeout ? totalTimeout : nil)
                } label: {
                    Label("Analyze ticket", systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("analyze-ticket")
                .disabled(operation != nil || !credentials.isConfigured || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                activity
            } footer: {
                Text(credentials.isConfigured ? "Live API · \(selectedModel) · Requests may incur charges." : "No API key. Follow the example README to launch with your local .env.")
            }
        }
        .navigationTitle("Support Inbox")
    }

    private var results: some View {
        List {
            if let response {
                Section("Team routing · choice") {
                    if case .choice(let answer) = response.value.answers["category"] {
                        Text(answer.choice.capitalized).font(.title2.bold())
                        Text("Confidence: \(answer.confidence.formatted(.percent.precision(.fractionLength(1))))")
                        ForEach(answer.probabilities.keys.sorted(), id: \.self) { key in
                            ProbabilityRow(label: key.capitalized, value: answer.probabilities[key] ?? 0)
                        }
                    }
                }
                Section("Refund requested · noul") {
                    if case .noul(let answer) = response.value.answers["refund_requested"] {
                        ProbabilityRow(label: "Probability of yes", value: answer.noul)
                        Text("A probability, not a Boolean. The app does not automatically approve or deny refunds.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Response urgency · score") {
                    if case .score(let answer) = response.value.answers["urgency"] {
                        Text("\(answer.score.formatted(.number.precision(.fractionLength(2)))) / 3")
                            .font(.title2.bold())
                        Text("Expected score, not a rounded category. Confidence: \(answer.confidence.formatted(.percent.precision(.fractionLength(1))))")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(answer.probabilities.keys.sorted(), id: \.self) { level in
                            ProbabilityRow(label: "Level \(level)", value: answer.probabilities[level] ?? 0)
                            if case .string(let description) = answer.legend[level] {
                                Text(description).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("Usage") {
                    LabeledContent("Model", value: response.value.model)
                    LabeledContent("Input tokens", value: String(response.value.usage.inputTokens))
                    LabeledContent("Output tokens", value: String(response.value.usage.outputTokens))
                    Text("Request ID: \(response.metadata.requestID ?? "Not provided")")
                        .font(.caption).textSelection(.enabled)
                    Button("Inspect request and response") { tab = 2 }
                }
            } else {
                Section {
                    Label("No analysis yet", systemImage: "chart.bar")
                    Text("Choose a ticket in Inbox and tap Analyze ticket. All three question types run in one request.")
                }
            }
            Section { activity }
        }
        .navigationTitle("Triage results")
    }

    private var wire: some View {
        List {
            Section("Last operation") {
                Text(endpoint).font(.headline.monospaced())
                if let metadata {
                    LabeledContent("HTTP status", value: String(metadata.statusCode))
                    Text("Request ID: \(metadata.requestID ?? "Not provided")").textSelection(.enabled)
                }
                Text("Authorization is never displayed. Response JSON is the actual server body, formatted for readability.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Request JSON") { JSONPanel(text: requestJSON) }
            Section("Response JSON") { JSONPanel(text: responseJSON) }
            Section { activity }
        }
        .navigationTitle("API inspector")
    }

    private var settings: some View {
        Form {
            Section("Connection") {
                Label(credentials.isConfigured ? "Simulator key loaded" : "API key missing", systemImage: credentials.isConfigured ? "lock.shield" : "lock.slash")
                Text("https://api.typesafe.ai").font(.caption.monospaced())
                Text("Development only. Never ship a privileged API key inside a distributed app; use your backend instead.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Model") {
                Picker("Selected model", selection: $selectedModel) {
                    ForEach(Array(Set(models.map(\.name) + [selectedModel])).sorted(), id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                Button("Refresh available models") {
                    operation = Operation(kind: .models, timeout: timeout, retries: retries, totalTimeout: useTotalTimeout ? totalTimeout : nil)
                }
                .disabled(!credentials.isConfigured || operation != nil)
                ForEach(models, id: \.name) { model in
                    VStack(alignment: .leading) {
                        Text(model.name).font(.headline)
                        Text(model.description).font(.caption)
                        Text("Released \(model.releaseDate)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .disabled(operation != nil)
            Section("Reliability") {
                Stepper("Attempt timeout: \(Int(timeout)) seconds", value: $timeout, in: 1...60, step: 1)
                Stepper("Maximum retries: \(retries)", value: $retries, in: 0...5)
                Toggle("Use total deadline", isOn: $useTotalTimeout)
                if useTotalTimeout {
                    Stepper("Total deadline: \(Int(totalTimeout)) seconds", value: $totalTimeout, in: 1...120, step: 1)
                }
                Text("Attempt timeouts include the response body. The optional total deadline also covers retries and waits. Retries may repeat processing and billing.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .disabled(operation != nil)
            Section { activity }
        }
        .navigationTitle("Settings")
    }

    @ViewBuilder private var activity: some View {
        if operation != nil {
            ProgressView("Calling TypeSafe…")
            Button("Cancel request", role: .destructive) {
                operation = nil
                status = "Cancelled. No further SDK retries will be attempted."
            }
        }
        Text(status).font(.footnote).accessibilityIdentifier("request-status")
    }

    private func perform(_ work: Operation) async {
        status = "Calling TypeSafe…"
        metadata = nil
        responseJSON = "Waiting for response…"
        do {
            let client = try credentials.client(timeout: work.timeout, retries: work.retries, totalTimeout: work.totalTimeout)
            switch work.kind {
            case .triage(let scenario):
                endpoint = "POST /v1/systemone"
                requestJSON = try credentials.redacted(scenario.requestJSON())
                let result = try await client.systemOne(state: scenario.state, questions: scenario.questions, model: scenario.model)
                guard operation?.id == work.id, !Task.isCancelled else { return }
                response = result
                metadata = result.metadata
                responseJSON = credentials.responseJSON(result.rawBody)
                status = "Analysis complete · HTTP \(result.metadata.statusCode)"
                tab = 1
            case .models:
                endpoint = "GET /v1/models"
                requestJSON = "No request body."
                let result = try await client.models.list()
                guard operation?.id == work.id, !Task.isCancelled else { return }
                models = result.value.models
                metadata = result.metadata
                responseJSON = credentials.responseJSON(result.rawBody)
                status = "Loaded \(models.count) models · HTTP \(result.metadata.statusCode)"
            }
        } catch {
            guard operation?.id == work.id else { return }
            handle(error)
        }
        if operation?.id == work.id { operation = nil }
    }

    private func handle(_ error: any Error) {
        switch error {
        case is CancellationError:
            status = "Request cancelled."
        case TypeSafeError.http(let code, let body, let details):
            status = "HTTP \(code). Inspect the API tab for the server response."
            metadata = details
            responseJSON = credentials.responseJSON(body)
            tab = 2
        case TypeSafeError.timeout:
            status = "Request timed out after the configured attempts. Try a longer timeout."
        case TypeSafeError.connection(let code):
            status = "Network connection failed (\(code)). Check connectivity and try again."
        case TypeSafeError.deadlineExceeded:
            status = "The total request deadline expired, including retry waits."
        case TypeSafeError.invalidResponse(let message, let details):
            status = credentials.redacted(message)
            if let details {
                metadata = details.metadata
                responseJSON = credentials.responseJSON(details.body)
                tab = 2
            }
        case TypeSafeError.invalidConfiguration(let message), TypeSafeError.invalidRequest(let message):
            status = credentials.redacted(message)
        default:
            status = "Unexpected request failure. Check your configuration and try again."
        }
        if metadata == nil { responseJSON = "No completed response available." }
    }
}

private struct ProbabilityRow: View {
    let label: String
    let value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                Spacer()
                Text(value.formatted(.percent.precision(.fractionLength(1)))).monospacedDigit()
            }
            ProgressView(value: min(1, max(0, value)))
                .accessibilityLabel(label)
                .accessibilityValue(value.formatted(.percent))
        }
        .padding(.vertical, 3)
    }
}

private struct JSONPanel: View {
    let text: String
    var body: some View {
        ScrollView(.horizontal) {
            Text(text).font(.caption.monospaced()).textSelection(.enabled)
        }
    }
}
