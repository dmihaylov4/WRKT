//
//  ErrorView.swift
//  WRKT
//
//  Reusable error view with retry button
//

import SwiftUI

/// Standard error view with icon, message, and retry button
struct ErrorView: View {
    let error: UserFriendlyError
    let onRetry: (() -> Void)?

    init(error: UserFriendlyError, onRetry: (() -> Void)? = nil) {
        self.error = error
        self.onRetry = error.isRetryable ? onRetry : nil
    }

    var body: some View {
        VStack(spacing: 20) {
            // Error icon
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 50))
                .foregroundStyle(DS.Status.warning)

            // Title and message
            VStack(spacing: 8) {
                Text(error.title)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(DS.Semantic.textPrimary)

                Text(error.message)
                    .font(.body)
                    .foregroundStyle(DS.Semantic.textSecondary)
                    .multilineTextAlignment(.center)

                if let suggestion = error.suggestion {
                    Text(suggestion)
                        .font(.subheadline)
                        .foregroundStyle(DS.Semantic.textPrimary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 32)

            // Retry button
            if let onRetry = onRetry {
                Button {
                    Haptics.light()
                    onRetry()
                } label: {
                    Text("Try Again")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(DS.Semantic.brand)
                        .clipShape(Capsule())
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Inline error view (smaller, for banners)
struct InlineErrorView: View {
    let error: UserFriendlyError
    let onRetry: (() -> Void)?
    let onDismiss: (() -> Void)?

    init(
        error: UserFriendlyError,
        onRetry: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.error = error
        self.onRetry = error.isRetryable ? onRetry : nil
        self.onDismiss = onDismiss
    }

    var body: some View {
        HStack(spacing: 12) {
            // Error icon
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(DS.Status.warning)

            // Message
            VStack(alignment: .leading, spacing: 4) {
                Text(error.title)
                    .font(.subheadline.bold())
                    .foregroundStyle(DS.Semantic.textPrimary)

                Text(error.message)
                    .font(.caption)
                    .foregroundStyle(DS.Semantic.textSecondary)
            }

            Spacer()

            // Actions
            HStack(spacing: 8) {
                if let onRetry = onRetry {
                    Button {
                        Haptics.light()
                        onRetry()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.body.bold())
                            .foregroundStyle(DS.Semantic.brand)
                    }
                }

                if let onDismiss = onDismiss {
                    Button {
                        Haptics.light()
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.body)
                            .foregroundStyle(DS.Semantic.textSecondary)
                    }
                }
            }
        }
        .padding()
        .background(DS.Status.warningBg)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}

/// Compact error view (for list items)
struct CompactErrorView: View {
    let message: String
    let onRetry: (() -> Void)?

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(DS.Status.error)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(DS.Semantic.textSecondary)

            Spacer()

            if let onRetry = onRetry {
                Button("Retry") {
                    Haptics.light()
                    onRetry()
                }
                .font(.subheadline.bold())
                .foregroundStyle(DS.Semantic.brand)
            }
        }
        .padding()
        .background(DS.Semantic.fillSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Loading State View

/// View shown while retrying
struct RetryingView: View {
    let attemptNumber: Int
    let maxAttempts: Int

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(DS.Semantic.brand)

            VStack(spacing: 4) {
                Text("Retrying...")
                    .font(.headline)
                    .foregroundStyle(DS.Semantic.textPrimary)

                Text("Attempt \(attemptNumber) of \(maxAttempts)")
                    .font(.caption)
                    .foregroundStyle(DS.Semantic.textSecondary)
            }
        }
        .padding()
    }
}

// MARK: - Preview

#Preview("Full Error") {
    ErrorView(
        error: UserFriendlyError(
            title: "Can't Load Feed",
            message: "Please check your internet connection and try again.",
            suggestion: "Make sure you're connected to WiFi or cellular data.",
            isRetryable: true
        ),
        onRetry: {}
    )
}

#Preview("Inline Error") {
    InlineErrorView(
        error: UserFriendlyError(
            title: "Upload Failed",
            message: "We couldn't upload your image.",
            isRetryable: true
        ),
        onRetry: {},
        onDismiss: {}
    )
}

#Preview("Compact Error") {
    CompactErrorView(
        message: "Failed to load notifications",
        onRetry: {}
    )
}

#Preview("Retrying") {
    RetryingView(attemptNumber: 2, maxAttempts: 3)
}
