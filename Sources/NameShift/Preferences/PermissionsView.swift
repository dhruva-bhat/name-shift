import SwiftUI

/// First-run onboarding: explains each permission, shows live status, deep-links to Settings.
struct PermissionsView: View {
    @ObservedObject var permissions: PermissionCenter
    var onDone: () -> Void

    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Set up Name Shift").font(.title2.bold())
                Text("Select files in Finder, hold Shift, flick toward an action, release. These three permissions make that work.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(Permission.allCases) { permission in
                PermissionRow(permission: permission,
                              status: permissions.status[permission] ?? .unknown,
                              request: { permissions.request(permission) },
                              openSettings: { permissions.openSettings(permission) })
            }

            Text("Tip: if a permission shows as granted in System Settings but not here, remove Name Shift from that list and add it again — macOS ties grants to the app's code signature.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button(permissions.allGranted ? "Done" : "Continue Later", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 520)
        .onAppear { permissions.refresh() }
        .onReceive(poll) { _ in permissions.refresh() }
    }
}

private struct PermissionRow: View {
    let permission: Permission
    let status: PermissionStatus
    let request: () -> Void
    let openSettings: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: permission.symbol).font(.title2).frame(width: 30).foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(permission.title).font(.headline)
                    badge
                }
                Text(permission.explanation).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if status != .granted {
                VStack(alignment: .trailing, spacing: 4) {
                    Button("Grant…", action: request)
                    Button("Open Settings", action: openSettings).buttonStyle(.link).font(.caption)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
    }

    @ViewBuilder private var badge: some View {
        switch status {
        case .granted: Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .denied: Label("Not granted", systemImage: "xmark.circle.fill").foregroundStyle(.red)
        case .notDetermined: Label("Not asked yet", systemImage: "questionmark.circle").foregroundStyle(.orange)
        case .unknown: Label("Checking…", systemImage: "ellipsis.circle").foregroundStyle(.secondary)
        }
    }
}
