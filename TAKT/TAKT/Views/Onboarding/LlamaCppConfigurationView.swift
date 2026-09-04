import AppKit
import SwiftUI

struct LlamaCppConfigurationView: View {
  @Binding var configuration: LlamaCppConfiguration
  let showsTitle: Bool

  init(configuration: Binding<LlamaCppConfiguration>, showsTitle: Bool = true) {
    _configuration = configuration
    self.showsTitle = showsTitle
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      if showsTitle {
        VStack(alignment: .leading, spacing: 4) {
          Text("llama.cpp konfigurieren")
            .font(.custom("Figtree", size: 16))
            .fontWeight(.semibold)
          Text("Diese Werte werden für den lokalen API-Endpunkt und den empfohlenen llama-server-Startbefehl verwendet.")
            .font(.custom("Figtree", size: 12))
            .foregroundColor(.black.opacity(0.6))
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      configurationTextField("Modellverzeichnis", text: $configuration.modelDirectory)
      configurationTextField("Hauptmodell (.gguf)", text: $configuration.modelFile)
      configurationTextField("Vision-Projektor (mmproj)", text: $configuration.mmprojFile)

      HStack(spacing: 12) {
        configurationTextField("Host", text: $configuration.host)
        VStack(alignment: .leading, spacing: 6) {
          fieldLabel("Port")
          Stepper(value: $configuration.port, in: 1...65535) {
            Text("\(configuration.port)")
              .font(.custom("Figtree", size: 13))
              .frame(minWidth: 54, alignment: .leading)
          }
        }
        .frame(width: 120, alignment: .leading)
      }

      HStack(spacing: 12) {
        numericStepper("Kontext", value: $configuration.contextSize, range: 1024...131072, step: 1024)
        numericStepper("Slots", value: $configuration.parallelSlots, range: 1...16, step: 1)
      }

      HStack(spacing: 12) {
        numericStepper("Batch", value: $configuration.batchSize, range: 64...4096, step: 64)
        numericStepper("UBatch", value: $configuration.ubatchSize, range: 32...2048, step: 32)
        numericStepper("Bildtokens min.", value: $configuration.imageMinTokens, range: 256...8192, step: 256)
      }

      VStack(alignment: .leading, spacing: 6) {
        fieldLabel("Startbefehl")
        Text(configuration.serverCommand)
          .font(.system(.caption, design: .monospaced))
          .foregroundColor(.black.opacity(0.78))
          .textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)
          .padding(10)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(Color.black.opacity(0.045))
          .overlay(Rectangle().stroke(Color.black.opacity(0.12), lineWidth: 1))
        Button("Startbefehl kopieren") {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(configuration.serverCommand, forType: .string)
        }
        .buttonStyle(.link)
        .font(.custom("Figtree", size: 12))
      }
    }
  }

  private func configurationTextField(
    _ title: String,
    text: Binding<String>
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      fieldLabel(title)
      TextField(title, text: text)
        .textFieldStyle(.roundedBorder)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func numericStepper(
    _ title: String,
    value: Binding<Int>,
    range: ClosedRange<Int>,
    step: Int
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      fieldLabel(title)
      Stepper(value: value, in: range, step: step) {
        Text("\(value.wrappedValue)")
          .font(.custom("Figtree", size: 13))
          .frame(minWidth: 60, alignment: .leading)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func fieldLabel(_ title: String) -> some View {
    Text(title)
      .font(.custom("Figtree", size: 12))
      .fontWeight(.semibold)
      .foregroundColor(.black.opacity(0.62))
  }
}
