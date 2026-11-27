
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct AudioDocumentPicker: UIViewControllerRepresentable {
    var onCompletion: (Result<[URL], Error>) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCompletion: onCompletion)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.audio],
            asCopy: false
        )

        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator

        return picker
    }

    func updateUIViewController(
        _ controller: UIDocumentPickerViewController,
        context: Context
    ) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onCompletion: (Result<[URL], Error>) -> Void

        init(onCompletion: @escaping (Result<[URL], Error>) -> Void) {
            self.onCompletion = onCompletion
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            onCompletion(.success(urls))
        }

        func documentPickerWasCancelled(
            _ controller: UIDocumentPickerViewController
        ) {
            onCompletion(.success([]))
        }
    }
}
