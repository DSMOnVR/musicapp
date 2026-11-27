
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
            asCopy: true
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
        private var finished = false

        init(onCompletion: @escaping (Result<[URL], Error>) -> Void) {
            self.onCompletion = onCompletion
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            guard !finished else { return }
            finished = true

            controller.dismiss(animated: true) {
                self.onCompletion(.success(urls))
            }
        }

        func documentPickerWasCancelled(
            _ controller: UIDocumentPickerViewController
        ) {
            guard !finished else { return }
            finished = true

            onCompletion(.success([]))
        }
    }
}


/// Native iOS picker for .lrc and .txt files. It displays the system Open action.
struct LyricsDocumentPicker: UIViewControllerRepresentable {
    var onCompletion: (Result<URL, Error>) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCompletion: onCompletion)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let lrcType = UTType(filenameExtension: "lrc", conformingTo: .plainText) ?? .plainText
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.plainText, lrcType],
            asCopy: true
        )
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onCompletion: (Result<URL, Error>) -> Void
        private var finished = false

        init(onCompletion: @escaping (Result<URL, Error>) -> Void) {
            self.onCompletion = onCompletion
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard !finished else { return }
            finished = true
            guard let url = urls.first else {
                onCompletion(.failure(NSError(domain: "LyricsImport", code: 1, userInfo: [NSLocalizedDescriptionKey: "No file was selected."])))
                return
            }
            controller.dismiss(animated: true) {
                self.onCompletion(.success(url))
            }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            guard !finished else { return }
            finished = true
            onCompletion(.failure(CancellationError()))
        }
    }
}
