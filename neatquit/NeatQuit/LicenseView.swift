import AppKit
import SwiftUI

struct LicenseView: View {
    @ObservedObject var manager: LicenseManager
    @State private var input = ""
    @State private var confirmDeactivate = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            if manager.hasPro {
                proSection
            } else {
                activationSection
            }
        }
        .padding(24)
        .frame(width: 460, height: 380, alignment: .topLeading)
        .alert(L10n.licenseDeactivateConfirmTitle, isPresented: $confirmDeactivate) {
            Button(L10n.cancel, role: .cancel) {}
            Button(L10n.licenseDeactivate, role: .destructive) {
                Task { await manager.deactivate() }
            }
        } message: {
            Text(L10n.licenseDeactivateConfirmMessage)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: manager.hasPro ? "checkmark.seal.fill" : "lock.shield")
                .font(.system(size: 34))
                .foregroundStyle(manager.hasPro ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(statusTitle)
                    .font(.title2.bold())
                Text(statusDetail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var proSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.licenseKeyLabel)
                    .font(.headline)
                Text(maskedKey)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }

            if let limit = manager.activationLimit {
                Text(L10n.licenseActivationCount(manager.activationCount ?? 0, limit))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button(L10n.licenseRefresh) {
                    Task { await manager.refresh(force: true) }
                }
                .disabled(manager.isWorking)

                Button(L10n.licenseDeactivate) {
                    confirmDeactivate = true
                }
                .disabled(manager.isWorking)

                if manager.isWorking {
                    ProgressView().controlSize(.small)
                }
            }

            if let error = manager.errorMessage {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
    }

    private var activationSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.licenseInputLabel)
                    .font(.headline)
                TextField(L10n.licenseInputPlaceholder, text: $input)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit { activate() }
                HStack(spacing: 10) {
                    Button(L10n.licenseActivate) { activate() }
                        .buttonStyle(.borderedProminent)
                        .disabled(manager.isWorking || LicenseManager.normalize(input).isEmpty)
                    Button(L10n.licensePaste) {
                        if let value = NSPasteboard.general.string(forType: .string) {
                            input = value.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                    .disabled(manager.isWorking)
                    if manager.isWorking {
                        ProgressView().controlSize(.small)
                    }
                }
            }

            if let error = manager.errorMessage {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.licensePurchaseTitle)
                    .font(.headline)
                Text(L10n.licensePurchaseDetail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button(L10n.licensePurchaseButton) {
                    NSWorkspace.shared.open(LicenseManager.purchaseURL)
                }
                Text(L10n.licensePurchaseNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusTitle: String {
        switch manager.tier {
        case .pro: return L10n.licenseProTitle
        case .trial(let days): return L10n.licenseTrialTitle(days)
        case .free: return L10n.licenseFreeTitle
        }
    }

    private var statusDetail: String {
        switch manager.tier {
        case .pro: return L10n.licenseProDetail
        case .trial: return L10n.licenseTrialDetail
        case .free: return L10n.licenseFreeDetail
        }
    }

    private var maskedKey: String {
        guard let key = manager.licenseKey else { return "—" }
        let parts = key.split(separator: "-")
        guard parts.count == 5 else { return key }
        return "\(parts[0])-•••••-•••••-•••••-\(parts[4])"
    }

    private func activate() {
        Task { await manager.activate(input: input) }
    }
}
