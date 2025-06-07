import SwiftUI
import SwiftData

struct ChatThreadView: View {
    @AppStorage("titleSummaryPrompt") private var titleSummaryPrompt = AppConstants.titleSummaryPrompt
    @AppStorage("defaultModelName") private var defaultModelName = AppConstants.defaultModelName
    
    @Environment(\.modelContext) private var context
    @Bindable var thread: ChatThread
    @Binding var isDraft: Bool
    
    @FocusState private var isTextFieldFocused: Bool
    @State private var currentInputMessage: String = ""
    @State private var attachedImages: [Data] = []
    
    @State private var errorMessage: String?
    @State private var shouldShowErrorAlert = false
    
    @State private var scrollProxy: ScrollViewProxy?
    @State private var streamingTask: Task<Void, Never>?
    
    let availableModels: [String]
    
    var body: some View {
        VStack {
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(chronologicalMessages) { message in
                            ChatBubbleView(message: message, isThinking: thread.isThinking) {
                                retry(message)
                            }
                            .id(message.id)
                        }
                    }
                    .padding()
                }
                .frame(maxHeight: .infinity)
                .onChange(of: thread.messages.count) { oldValue, newValue in
                    scrollToBottom(proxy: proxy)
                }
                .onAppear {
                    scrollProxy = proxy
                    scrollToBottom(proxy: proxy)
                }
            }
            
            ChatInputView(
                currentInputMessage: $currentInputMessage,
                isTextFieldFocused: _isTextFieldFocused,
                isThinking: thread.isThinking,
                onSubmit: insertChatMessage,
                onStop: stopGeneration,
                selectedModel: Binding(
                    get: { thread.selectedModel ?? "" },
                    set: { thread.selectedModel = $0 }
                ),
                modelOptions: availableModels,
                attachedImages: $attachedImages,
                onImagesChanged: { images in
                    attachedImages = images
                }
            )
            .onAppear {
                isTextFieldFocused = true
            }
            .onChange(of: thread.id) { _, _ in
                isTextFieldFocused = true
            }
        }
        .padding()
        .onAppear {
            ensureModelSelected()
        }
        .onDisappear {
            streamingTask?.cancel()
        }
        .alert("Error", isPresented: $shouldShowErrorAlert, actions: {
            Button("OK") {
                errorMessage = nil
            }
        }, message: {
            Text(errorMessage ?? "An unknown error occurred.")
        })
    }
    
    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let lastMessage = chronologicalMessages.last {
            withAnimation {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }
    
    private func ensureModelSelected() {
        if thread.selectedModel == nil || !availableModels.contains(thread.selectedModel!) {
            thread.selectedModel = defaultModelName == "" ? availableModels.first : defaultModelName
        }
    }
    
    private func sendMessageStream() {
        if isDraft {
            convertDraftToRegularThread()
        }
        
        currentInputMessage = ""
        thread.isThinking = true
        
        streamingTask = Task {
            do {
                ensureModelSelected()
                guard let selectedModel = thread.selectedModel, !selectedModel.isEmpty else {
                    throw NSError(domain: "ChatView", code: 1, userInfo: [NSLocalizedDescriptionKey: "No model selected"])
                }
                
                let ollamaService = OllamaService()
                let ollamaMessages = chronologicalMessages.map { message in
                    OllamaChatMessage(
                        role: message.isUser ? "user" : "assistant", 
                        content: message.text,
                        images: message.images != nil ? convertImagesToBase64(message.images!) : nil
                    )
                }
                let stream = ollamaService.streamConversation(model: selectedModel, messages: ollamaMessages)
                let assistantMessage = ChatMessage(text: "", isUser: false, timestamp: Date())
                
                await MainActor.run {
                    thread.messages.append(assistantMessage)
                    context.insert(assistantMessage)
                }
                
                for try await partialResponse in stream {
                    if Task.isCancelled {
                        break
                    }
                    
                    await MainActor.run {
                        assistantMessage.text += partialResponse
                        scrollProxy?.scrollTo(assistantMessage.id, anchor: .bottom)
                    }
                }
                
                if Task.isCancelled {
                    await MainActor.run {
                        thread.isThinking = false
                        isTextFieldFocused = true
                        streamingTask = nil
                    }
                    return
                }
                
                await MainActor.run {
                    thread.isThinking = false
                    if !thread.hasReceivedFirstMessage {
                        thread.hasReceivedFirstMessage = true
                        setThreadTitle()
                    }
                    isTextFieldFocused = true
                    streamingTask = nil
                }
            } catch {
                if !Task.isCancelled {
                    await handleError(error)
                } else {
                    await MainActor.run {
                        thread.isThinking = false
                        isTextFieldFocused = true
                    }
                }
                await MainActor.run {
                    streamingTask = nil
                }
            }
        }
    }
    
    private func convertDraftToRegularThread() {
        isDraft = false
        thread.createdAt = Date()
        context.insert(thread)
    }
    
    private func convertImagesToBase64(_ imageDataArray: [Data]) -> [String] {
        return imageDataArray.compactMap { imageData in
            // Since images are already pre-processed and compressed from ChatInputView,
            // we can just resize them for the server without heavy processing
            let resizedImageData = resizeImageEfficiently(imageData, targetSize: CGSize(width: 896, height: 896))
            return resizedImageData.base64EncodedString()
        }
    }
    
    private func resizeImageEfficiently(_ imageData: Data, targetSize: CGSize) -> Data {
        guard let nsImage = NSImage(data: imageData) else {
            return imageData // Return original if resizing fails
        }
        
        // Use more efficient resizing with better performance characteristics
        let resizedImage = NSImage(size: targetSize)
        resizedImage.lockFocus()
        nsImage.draw(in: NSRect(origin: .zero, size: targetSize), 
                    from: NSRect(origin: .zero, size: nsImage.size), 
                    operation: .sourceOver, 
                    fraction: 1.0, 
                    respectFlipped: false, 
                    hints: [.interpolation: NSImageInterpolation.high])
        resizedImage.unlockFocus()
        
        guard let tiffData = resizedImage.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let resizedData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
            return imageData // Return original if resizing fails
        }
        
        return resizedData
    }
    
    private func insertChatMessage() {
        if currentInputMessage.isEmpty && attachedImages.isEmpty {
            return
        }
        
        let newMessage = ChatMessage(
            text: currentInputMessage, 
            isUser: true, 
            timestamp: Date(),
            images: attachedImages.isEmpty ? nil : attachedImages
        )
        thread.messages.append(newMessage)
        context.insert(newMessage)
        
        // Clear attached images after sending
        attachedImages = []
        
        sendMessageStream()
    }
    
    private func retry(_ message: ChatMessage) {
        guard let index = chronologicalMessages.firstIndex(where: { $0.id == message.id }) else {
            return
        }
        
        let messagesToRemove = Array(chronologicalMessages[index...])
        for messageToRemove in messagesToRemove {
            if let messageIndex = thread.messages.firstIndex(where: { $0.id == messageToRemove.id }) {
                thread.messages.remove(at: messageIndex)
                context.delete(messageToRemove)
            }
        }
        
        sendMessageStream()
    }
    
    private func handleError(_ error: Error) async {
        await MainActor.run {
            shouldShowErrorAlert = true
            thread.isThinking = false
            
            let networkError = error as? URLError
            let defaultErrorMessage = "An unexpected error occurred while communicating with the Ollama API: \(error.localizedDescription)"
            
            if networkError == nil {
                errorMessage = defaultErrorMessage
            } else {
                switch networkError?.code {
                case .cannotConnectToHost:
                    errorMessage = "Unable to connect to the Ollama API. Please ensure that the Ollama server is running."
                case .timedOut:
                    errorMessage = "The request to Ollama API timed out. Please try again later."
                default:
                    errorMessage = defaultErrorMessage
                }
            }
        }
    }
    
    private func setThreadTitle() {
        Task {
            do {
                guard let selectedModel = thread.selectedModel, !selectedModel.isEmpty else {
                    throw NSError(domain: "ChatView", code: 1, userInfo: [NSLocalizedDescriptionKey: "No model selected"])
                }
                
                var ollamaMessages = chronologicalMessages.map { message in
                    OllamaChatMessage(
                        role: message.isUser ? "user" : "assistant", 
                        content: message.text,
                        images: message.images != nil ? convertImagesToBase64(message.images!) : nil
                    )
                }
                ollamaMessages.append(OllamaChatMessage(role: "user", content: titleSummaryPrompt, images: nil))
                
                let ollamaService = OllamaService()
                let summaryResponse = try await ollamaService.sendSingleMessage(model: selectedModel, messages: ollamaMessages)
                
                await MainActor.run {
                    setThreadTitle(summaryResponse)
                }
            } catch {
                print("Error summarizing thread: \(error.localizedDescription)")
            }
        }
    }
    
    private func stopGeneration() {
        streamingTask?.cancel()
        streamingTask = nil
        thread.isThinking = false
        isTextFieldFocused = true
    }
    
    private func setThreadTitle(_ summary: String) {
        thread.title = summary
        context.insert(thread)
    }
    
    private var chronologicalMessages: [ChatMessage] {
        thread.messages.sorted { $0.createdAt < $1.createdAt }
    }
}
