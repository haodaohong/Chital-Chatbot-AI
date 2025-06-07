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
                                if let nsImage = NSImage(data: attachedImages[index]) {
                                    Image(nsImage: nsImage)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 60, height: 60)
                                        .cornerRadius(8)
                                        .clipped()
                                }
                                
                                VStack {
                                    HStack {
                                        Spacer()
                                        Button(action: {
                                            attachedImages.remove(at: index)
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
                    Image(systemName: "plus.circle")
                        .font(.title2)
                        .foregroundColor(isThinking || modelOptions.isEmpty ? .gray : .primary)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(isThinking || modelOptions.isEmpty)
                .help("Attach images")
                
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
                for url in urls {
                    if url.startAccessingSecurityScopedResource() {
                        defer { url.stopAccessingSecurityScopedResource() }
                        if let imageData = try? Data(contentsOf: url) {
                            attachedImages.append(imageData)
                        }
                    }
                }
                onImagesChanged(attachedImages)
            case .failure(let error):
                print("Failed to import images: \(error)")
            }
        }
    }
    
    private func handleDroppedImages(providers: [NSItemProvider]) {
        for provider in providers {
            if provider.canLoadObject(ofClass: NSImage.self) {
                provider.loadObject(ofClass: NSImage.self) { image, error in
                    if let nsImage = image as? NSImage,
                       let tiffData = nsImage.tiffRepresentation,
                       let bitmapRep = NSBitmapImageRep(data: tiffData),
                       let pngData = bitmapRep.representation(using: .png, properties: [:]) {
                        DispatchQueue.main.async {
                            attachedImages.append(pngData)
                            onImagesChanged(attachedImages)
                        }
                    }
                }
            }
        }
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
        onImagesChanged(attachedImages)
    }
}
