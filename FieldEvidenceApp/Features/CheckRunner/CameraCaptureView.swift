import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct CameraCaptureView: UIViewControllerRepresentable {
    let onCapture: (Data) -> Void
    let onCancel: () -> Void
    let onFailure: () -> Void

    init(
        onCapture: @escaping (Data) -> Void,
        onCancel: @escaping () -> Void,
        onFailure: @escaping () -> Void
    ) {
        self.onCapture = onCapture
        self.onCancel = onCancel
        self.onFailure = onFailure
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onCapture: onCapture,
            onCancel: onCancel,
            onFailure: onFailure
        )
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.mediaTypes = [UTType.image.identifier]
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(
        _ uiViewController: UIImagePickerController,
        context: Context
    ) {}

    final class Coordinator: NSObject,
        UIImagePickerControllerDelegate,
        UINavigationControllerDelegate
    {
        private let onCapture: (Data) -> Void
        private let onCancel: () -> Void
        private let onFailure: () -> Void
        private var didFinish = false

        init(
            onCapture: @escaping (Data) -> Void,
            onCancel: @escaping () -> Void,
            onFailure: @escaping () -> Void
        ) {
            self.onCapture = onCapture
            self.onCancel = onCancel
            self.onFailure = onFailure
        }

        func imagePickerControllerDidCancel(
            _ picker: UIImagePickerController
        ) {
            guard !didFinish else { return }
            didFinish = true
            onCancel()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard !didFinish else { return }
            didFinish = true
            guard let image = info[.originalImage] as? UIImage,
                  let data = image.jpegData(compressionQuality: 1) else {
                onFailure()
                return
            }
            onCapture(data)
        }
    }
}
