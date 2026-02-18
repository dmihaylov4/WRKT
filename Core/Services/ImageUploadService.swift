import Foundation
import UIKit
import Supabase
import Combine

/// Service for uploading images to Supabase Storage
@MainActor
final class ImageUploadService: ObservableObject {
    private let client: SupabaseClient
    private let bucketName = "user-images"

    @Published var uploadProgress: Double = 0.0
    @Published var isUploading = false

    init(client: SupabaseClient = SupabaseClientWrapper.shared.client) {
        self.client = client
    }

    // MARK: - Upload Avatar

    /// Upload user avatar image
    func uploadAvatar(image: UIImage, userId: UUID) async throws -> String {
        // Compress and prepare image
        guard let imageData = prepareImage(image, maxDimension: 400) else {
            throw SupabaseError.serverError("Failed to prepare image")
        }

        // Generate file path: userId/avatar_timestamp.jpg
        // IMPORTANT: Use lowercase UUID to match auth.uid() in RLS policies
        let timestamp = Int(Date().timeIntervalSince1970)
        let fileName = "avatar_\(timestamp).jpg"
        let filePath = "\(userId.uuidString.lowercased())/\(fileName)"

        // Upload to Supabase Storage
        let publicURL = try await uploadToStorage(data: imageData, path: filePath)

        return publicURL
    }

    /// Upload profile picture (alias for uploadAvatar)
    func uploadProfilePicture(image: UIImage, userId: UUID) async throws -> String {
        try await uploadAvatar(image: image, userId: userId)
    }

    // MARK: - Upload Workout Images

    /// Upload multiple workout images with privacy settings
    /// - Parameters:
    ///   - images: Array of UIImages to upload
    ///   - userId: User ID for organizing files
    ///   - isPublic: Array of booleans indicating if each image is public (true) or private (false)
    /// - Returns: Array of PostImage objects with storage paths
    func uploadWorkoutImages(images: [UIImage], userId: UUID, isPublic: [Bool]) async throws -> [PostImage] {
        print("📤 [ImageUpload] Uploading \(images.count) images")
        print("  Privacy settings: \(isPublic.map { $0 ? "public" : "private" })")

        guard images.count == isPublic.count else {
            throw SupabaseError.serverError("Images and isPublic arrays must have same length")
        }

        var uploadedImages: [PostImage] = []

        for (index, image) in images.enumerated() {
            // Update progress
            await MainActor.run {
                uploadProgress = Double(index) / Double(images.count)
            }

            // Compress and prepare image
            guard let imageData = prepareImage(image, maxDimension: 1200) else {
                print("⚠️ Failed to prepare image \(index)")
                continue
            }

            let imageIsPublic = isPublic[index]

            // Generate file path: userId/workout_timestamp_index.jpg
            // IMPORTANT: Use lowercase UUID to match auth.uid() in RLS policies
            let timestamp = Int(Date().timeIntervalSince1970)
            let fileName = "workout_\(timestamp)_\(index).jpg"
            let filePath = "\(userId.uuidString.lowercased())/\(fileName)"

            // Choose bucket based on privacy setting
            let bucket = imageIsPublic ? "workout-images-public" : "workout-images-private"

            print("  📸 Uploading image \(index + 1)/\(images.count) to bucket: \(bucket)")
            print("    Path: \(filePath)")

            // Upload to appropriate Supabase Storage bucket
            do {
                let storagePath = try await uploadToWorkoutStorage(
                    data: imageData,
                    path: filePath,
                    bucket: bucket
                )

                print("    ✅ Uploaded successfully: \(storagePath)")

                let postImage = PostImage(
                    storagePath: storagePath,
                    isPublic: imageIsPublic
                )
                uploadedImages.append(postImage)
            } catch {
                // Continue with other images even if one fails
                print("    ❌ Failed to upload image \(index): \(error)")
            }
        }

        // Reset progress
        await MainActor.run {
            uploadProgress = 1.0
        }

        print("✅ [ImageUpload] Uploaded \(uploadedImages.count)/\(images.count) images successfully")
        return uploadedImages
    }

    /// Legacy method for backward compatibility - uploads all images as public
    func uploadWorkoutImagesLegacy(images: [UIImage], userId: UUID) async throws -> [String] {
        let isPublic = Array(repeating: true, count: images.count)
        let postImages = try await uploadWorkoutImages(images: images, userId: userId, isPublic: isPublic)

        // Convert to legacy URL format (for public images only)
        return postImages.compactMap { postImage in
            guard postImage.isPublic else { return nil }
            // Return public URL
            return try? client.storage
                .from(postImage.bucketName)
                .getPublicURL(path: postImage.filePath)
                .absoluteString
        }
    }

    // MARK: - Get Image URLs

    /// Get URL for a post image (public URL or signed URL for private images)
    /// - Parameters:
    ///   - image: PostImage object containing storage path and privacy settings
    ///   - currentUserId: ID of the currently logged-in user
    ///   - postOwnerId: ID of the user who owns the post
    /// - Returns: URL to display the image, or nil if user doesn't have access
    func getImageURL(for image: PostImage, currentUserId: UUID, postOwnerId: UUID) async throws -> URL? {
        print("🔍 [ImageUpload] Getting URL for image:")
        print("  - storagePath: \(image.storagePath)")
        print("  - isPublic: \(image.isPublic)")
        print("  - bucket: \(image.bucketName)")
        print("  - filePath: \(image.filePath)")
        print("  - currentUser: \(currentUserId)")
        print("  - postOwner: \(postOwnerId)")

        // Private images: Only owner can see them
        if image.isPrivate {
            guard currentUserId == postOwnerId else {
                print("  ❌ Private image - access denied (not owner)")
                return nil  // User doesn't have access to this private image
            }

            print("  🔒 Generating signed URL...")
            // Generate signed URL (expires in 1 hour)
            let signedURL = try await client.storage
                .from(image.bucketName)
                .createSignedURL(path: image.filePath, expiresIn: 3600)

            print("  ✅ Signed URL: \(signedURL)")
            return signedURL
        } else {
            print("  🌐 Generating public URL...")
            // Public images: Return permanent public URL
            let publicURL = try client.storage
                .from(image.bucketName)
                .getPublicURL(path: image.filePath)

            print("  ✅ Public URL: \(publicURL)")
            return publicURL
        }
    }

    /// Get URLs for multiple images at once (more efficient than calling getImageURL multiple times)
    func getImageURLs(for images: [PostImage], currentUserId: UUID, postOwnerId: UUID) async throws -> [URL] {
        var urls: [URL] = []

        for image in images {
            if let url = try await getImageURL(for: image, currentUserId: currentUserId, postOwnerId: postOwnerId) {
                urls.append(url)
            }
        }

        return urls
    }

    // MARK: - Delete Image

    /// Delete an image from storage
    func deleteImage(url: String) async throws {

        // Extract file path from URL
        // URL format: https://project.supabase.co/storage/v1/object/public/user-images/path/to/file.jpg
        guard let path = extractFilePath(from: url) else {
            throw SupabaseError.serverError("Invalid image URL")
        }

        try await client.storage
            .from(bucketName)
            .remove(paths: [path])

    }

    // MARK: - Private Helpers

    /// Prepare image for upload (compress, resize, convert to JPEG)
    private func prepareImage(_ image: UIImage, maxDimension: CGFloat) -> Data? {
        // Resize if needed
        let resizedImage: UIImage
        if image.size.width > maxDimension || image.size.height > maxDimension {
            resizedImage = resizeImage(image, maxDimension: maxDimension)
        } else {
            resizedImage = image
        }

        // Convert to JPEG with compression
        // Quality 0.8 gives good balance between file size and quality
        guard let jpegData = resizedImage.jpegData(compressionQuality: 0.8) else {
            return nil
        }

        let sizeInMB = Double(jpegData.count) / 1_000_000

        return jpegData
    }

    /// Resize image maintaining aspect ratio
    private func resizeImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let aspectRatio = size.width / size.height

        let newSize: CGSize
        if size.width > size.height {
            newSize = CGSize(width: maxDimension, height: maxDimension / aspectRatio)
        } else {
            newSize = CGSize(width: maxDimension * aspectRatio, height: maxDimension)
        }

        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resizedImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }

        return resizedImage
    }

    /// Upload data to Supabase Storage (legacy - for avatars)
    private func uploadToStorage(data: Data, path: String) async throws -> String {
        await MainActor.run {
            isUploading = true
        }
        defer {
            Task { @MainActor in
                isUploading = false
            }
        }

        // Upload file
        try await client.storage
            .from(bucketName)
            .upload(
                path: path,
                file: data,
                options: FileOptions(
                    contentType: "image/jpeg",
                    upsert: true
                )
            )

        // Get public URL
        let publicURL = try client.storage
            .from(bucketName)
            .getPublicURL(path: path)

        return publicURL.absoluteString
    }

    /// Upload data to workout storage bucket (public or private)
    /// - Returns: Full storage path including bucket prefix (e.g., "workout-images-public/userId/file.jpg")
    private func uploadToWorkoutStorage(data: Data, path: String, bucket: String) async throws -> String {
        await MainActor.run {
            isUploading = true
        }
        defer {
            Task { @MainActor in
                isUploading = false
            }
        }

        // Upload file to specified bucket
        try await client.storage
            .from(bucket)
            .upload(
                path: path,
                file: data,
                options: FileOptions(
                    contentType: "image/jpeg",
                    upsert: true
                )
            )

        // Return full storage path (bucket + path)
        return "\(bucket)/\(path)"
    }

    /// Extract file path from public URL
    private func extractFilePath(from url: String) -> String? {
        // URL format: https://project.supabase.co/storage/v1/object/public/user-images/path/to/file.jpg
        guard let range = url.range(of: "/\(bucketName)/") else {
            return nil
        }

        let startIndex = url.index(range.upperBound, offsetBy: 0)
        return String(url[startIndex...])
    }
}

/// Error types for image upload
extension SupabaseError {
    static func imageUploadFailed(_ message: String) -> SupabaseError {
        .serverError("Image upload failed: \(message)")
    }
}
