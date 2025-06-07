import SwiftUI

struct SettingsView: View {
    @AppStorage("ollamaBaseURL") private var ollamaBaseURL = AppConstants.ollamaDefaultBaseURL
    @AppStorage("titleSummaryPrompt") private var titleSummaryPrompt = AppConstants.titleSummaryPrompt
    
    @AppStorage("contextWindowLength") private var contextWindowLength = AppConstants.contextWindowLength
    @State private var contextWindowLengthString: String = ""
    
    @AppStorage("defaultModelName") private var defaultModelName = AppConstants.defaultModelName
    @State private var availableModels: [String] = []
    
    @AppStorage("fontSize") private var fontSize = AppConstants.defaultFontSize
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Default Model")
                        .font(.headline)
                    
                    Picker(selection: $defaultModelName, label: EmptyView()) {
                        ForEach(availableModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                }
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("Ollama Base URL")
                        .font(.headline)
                    
                    TextField("Enter Ollama Base URL", text: $ollamaBaseURL)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("Context Window Length")
                        .font(.headline)
                    
                    HStack {
                        TextField("Enter value", text: $contextWindowLengthString)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 100)
                            .onAppear {
                                contextWindowLengthString = "\(contextWindowLength)"
                            }
                        
                        Text("tokens")
                    }
                }
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("Chat Font Size")
                        .font(.headline)
                    
                    HStack {
                        Slider(value: $fontSize, in: 10...24, step: 1)
                            .frame(width: 200)
                        
                        Text("\(Int(fontSize))pt")
                            .frame(width: 40, alignment: .leading)
                    }
                }
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("Thread Title Summary Prompt")
                        .font(.headline)
                    
                    ZStack {
                        TextEditor(text: $titleSummaryPrompt)
                            .font(.system(size: fontSize))
                            .padding(.vertical, 12)
                            .padding(.horizontal, 6)
                            .lineSpacing(5)
                            .frame(minHeight: 100)
                    }
                    .scrollContentBackground(.hidden)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(6)
                }
                
                Button("Restore Defaults") {
                    ollamaBaseURL = AppConstants.ollamaDefaultBaseURL
                    titleSummaryPrompt = AppConstants.titleSummaryPrompt
                    contextWindowLength = AppConstants.contextWindowLength
                    contextWindowLengthString = "\(AppConstants.contextWindowLength)"
                    defaultModelName = AppConstants.defaultModelName
                    fontSize = AppConstants.defaultFontSize
                }
            }
            .padding()
        }
        .onChange(of: contextWindowLengthString) { oldValue, newValue in
            if let value = Int(newValue) {
                contextWindowLength = value
            }
        }
        .task {
            await fetchAvailableModels()
        }
        .frame(minWidth: 500, maxWidth: 700, minHeight: 500, maxHeight: 700)
    }
    
    private func fetchAvailableModels() async {
        let ollamaService = OllamaService()
        
        do {
            let modelNames = try await ollamaService.fetchModelList()
            availableModels = modelNames
        } catch {
            availableModels = []
        }
    }
}

#Preview {
    SettingsView()
}
