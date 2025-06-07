import SwiftUI

struct ChatInputView: View {
    @Binding var currentInputMessage: String
    @FocusState var isTextFieldFocused: Bool
    let isThinking: Bool
    let onSubmit: () -> Void
    let onStop: () -> Void
    
    @Binding var selectedModel: String
    let modelOptions: [String]
    
    @Binding var attachedImages: [Data]
    @State private var showImagePicker = false
    @State private var isProcessingImages = false
    @State private var thumbnailCache: [Data: NSImage] = [:] // Cache for thumbnails
    
    let onImagesChanged: ([Data]) -> Void
    
    @AppStorage("fontSize") private var fontSize = AppConstants.defaultFontSize
    
    var body: some View {
        VStack {
            HStack {
                Spacer()
                Picker(selection: $selectedModel, label: EmptyView()) {
                    ForEach(modelOptions, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .onChange(of: selectedModel) { _, _ in isTextFieldFocused = true }
                .buttonStyle(.borderless)
                .fixedSize()
                .disabled(modelOptions.isEmpty)
            }
            .padding(.trailing)
            
            if !attachedImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(attachedImages.indices, id: \.self) { index in
                            ZStack {
                                let imageData = attachedImages[index]
                                if let cachedImage = thumbnailCache[imageData] {
                                    Image(nsImage: cachedImage)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 60, height: 60)
                                        .cornerRadius(8)
                                        .clipped()
                                } else if let nsImage = NSImage(data: imageData) {
                                    Image(nsImage: nsImage)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 60, height: 60)
                                        .cornerRadius(8)
                                        .clipped()
                                        .onAppear {
                                            // Cache the thumbnail on first render
                                            thumbnailCache[imageData] = nsImage
                                        }
                                }
                                
                                VStack {
                                    HStack {
                                        Spacer()
                                        Button(action: {
                                            let imageData = attachedImages[index]
                                            attachedImages.remove(at: index)
                                            thumbnailCache.removeValue(forKey: imageData) // Clean up cache
                                            onImagesChanged(attachedImages)
                                        }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 16))
                                                .foregroundColor(.white)
                                                .background(Color.black.opacity(0.8))
                                                .clipShape(Circle())
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                        .offset(x: 0, y: 0)
                                    }
                                    Spacer()
                                }
                            }
                            .frame(width: 60, height: 60)
                        }
                    }
                    .padding(.horizontal)
                }
                .frame(height: 68)
            }
            
            HStack {
                Button(action: {
                    showImagePicker = true
                }) {
                    Image(systemName: isProcessingImages ? "clock" : "plus.circle")
                        .font(.title2)
                        .foregroundColor(isThinking || modelOptions.isEmpty || isProcessingImages ? .gray : .primary)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(isThinking || modelOptions.isEmpty || isProcessingImages)
                .help(isProcessingImages ? "Processing images..." : "Attach images")
                
                TextField(isThinking ? "Thinking..." : "How can I help you today?", text: $currentInputMessage, axis: .vertical)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: fontSize))
                    .lineLimit(10)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(20)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
                    )                .onSubmit(onSubmit)
                .disabled(isThinking || modelOptions.isEmpty)
                .focused($isTextFieldFocused)
                .onDrop(of: [.image], isTargeted: nil) { providers in
                    handleDroppedImages(providers: providers)
                    return true
                }
                
                if isThinking {
                    Button(action: onStop) {
                        Image(systemName: "stop.circle.fill")
                            .font(.title2)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Stop generation")
                }
            }
            .padding(.horizontal)
        }
        .fileImporter(
            isPresented: $showImagePicker,
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                isProcessingImages = true
                // Process images on background thread to avoid stuttering
                DispatchQueue.global(qos: .userInitiated).async {
                    var processedImages: [Data] = []
                    
                    for url in urls {
                        if url.startAccessingSecurityScopedResource() {
                            defer { url.stopAccessingSecurityScopedResource() }
                            
                            if let nsImage = NSImage(contentsOf: url),
                               let processedData = self.processImageForAttachment(nsImage) {
                                processedImages.append(processedData)
                            }
                        }
                    }
                    
                    DispatchQueue.main.async {
                        attachedImages.append(contentsOf: processedImages)
                        onImagesChanged(attachedImages)
                        isProcessingImages = false
                    }
                }
            case .failure(let error):
                print("Failed to import images: \(error)")
                isProcessingImages = false
            }
        }
    }
    
    private func handleDroppedImages(providers: [NSItemProvider]) {
        isProcessingImages = true
        var processedCount = 0
        let totalCount = providers.count
        
        for provider in providers {
            if provider.canLoadObject(ofClass: NSImage.self) {
                provider.loadObject(ofClass: NSImage.self) { image, error in
                    if let nsImage = image as? NSImage {
                        // Process image on background thread
                        DispatchQueue.global(qos: .userInitiated).async {
                            let processedData = self.processImageForAttachment(nsImage)
                            DispatchQueue.main.async {
                                if let data = processedData {
                                    attachedImages.append(data)
                                    onImagesChanged(attachedImages)
                                }
                                processedCount += 1
                                if processedCount >= totalCount {
                                    isProcessingImages = false
                                }
                            }
                        }
                    } else {
                        DispatchQueue.main.async {
                            processedCount += 1
                            if processedCount >= totalCount {
                                isProcessingImages = false
                            }
                        }
                    }
                }
            } else {
                processedCount += 1
                if processedCount >= totalCount {
                    isProcessingImages = false
                }
            }
        }
    }
    
    private func processImageForAttachment(_ nsImage: NSImage) -> Data? {
        // Resize image to reasonable preview size to reduce memory usage
        let maxDimension: CGFloat = 1024
        let originalSize = nsImage.size
        
        var targetSize = originalSize
        if originalSize.width > maxDimension || originalSize.height > maxDimension {
            let aspectRatio = originalSize.width / originalSize.height
            if originalSize.width > originalSize.height {
                targetSize = CGSize(width: maxDimension, height: maxDimension / aspectRatio)
            } else {
                targetSize = CGSize(width: maxDimension * aspectRatio, height: maxDimension)
            }
        }
        
        let resizedImage = NSImage(size: targetSize)
        resizedImage.lockFocus()
        nsImage.draw(in: NSRect(origin: .zero, size: targetSize))
        resizedImage.unlockFocus()
        
        guard let tiffData = resizedImage.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let compressedData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) else {
            return nil
        }
        
        return compressedData
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var currentInputMessage = ""
        @State private var selectedModel = "llama3.1"
        @State private var attachedImages: [Data] = []
        @FocusState private var isTextFieldFocused: Bool
        let modelOptions = ["llama3.1", "llama3.2"]
        
        var body: some View {
            ChatInputView(
                currentInputMessage: $currentInputMessage,
                isTextFieldFocused: _isTextFieldFocused,
                isThinking: false,
                onSubmit: {},
                onStop: {},
                selectedModel: $selectedModel,
                modelOptions: modelOptions,
                attachedImages: $attachedImages,
                onImagesChanged: { images in
                    attachedImages = images
                }
            )
            .frame(height: 100)
            .padding()
            .onAppear { isTextFieldFocused = true }
        }
    }
    
    return PreviewWrapper()
}

extension ChatInputView {
    func clearImages() {
        attachedImages.removeAll()
        thumbnailCache.removeAll() // Clear thumbnail cache as well
        onImagesChanged(attachedImages)
    }
}
