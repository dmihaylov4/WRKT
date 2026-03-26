//
//  PostDetailView.swift
//  WRKT
//
//  Detailed view of a workout post with comments
//

import SwiftUI
import Kingfisher
import Charts

struct PostDetailView: View {
    @Environment(\.dependencies) private var deps

    let post: PostWithAuthor

    @State private var viewModel: PostDetailViewModel?
    @State private var showingLikes = false
    @FocusState private var isCommentFieldFocused: Bool
    @State private var displayImageURLs: [URL] = []
    @State private var carouselPage: Int = 0

    private let imageUploadService = ImageUploadService()

    var body: some View {
        Group {
            if let viewModel = viewModel {
                content(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Post")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    isCommentFieldFocused = false
                }
                .fontWeight(.semibold)
            }
        }
        .task {
            if viewModel == nil {
                let vm = PostDetailViewModel(
                    post: post,
                    postRepository: deps.postRepository,
                    authService: deps.authService
                )
                viewModel = vm
                await vm.loadComments()
            }
            await loadImageURLs()
        }
    }

    @ViewBuilder
    private func content(viewModel: PostDetailViewModel) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Post Header
                    postHeader(viewModel: viewModel)

                    // Caption
                    if let caption = viewModel.post.post.caption, !caption.isEmpty {
                        Text(caption)
                            .font(.body)
                            .foregroundStyle(DS.Semantic.textPrimary)
                            .padding(.horizontal)
                    }

                    // Cardio: swipeable data carousel
                    // Strength: images + exercise details
                    if viewModel.post.post.workoutData.isCardioWorkout {
                        cardioCarousel(viewModel: viewModel)
                    } else {
                        strengthCarousel(viewModel: viewModel)
                    }

                    // Like/Comment counts
                    statsSection(viewModel: viewModel)

                    // Comments Section
                    commentsSection(viewModel: viewModel)
                }
                .padding(.bottom, 90)
            }
            .scrollDismissesKeyboard(.interactively)

            commentInput(viewModel: viewModel)
        }
        .padding(.bottom, 56) // lift content above custom tab bar (UITabBar.isHidden breaks safe area propagation)
    }

    private func postHeader(viewModel: PostDetailViewModel) -> some View {
        HStack(spacing: 12) {
            // Avatar (chamfered logo style)
            KFImage(URL(string: viewModel.post.author.avatarUrl ?? ""))
                .placeholder {
                    ChamferedRectangleAlt(.small)
                        .fill(DS.Semantic.brandSoft)
                        .overlay(
                            Text(viewModel.post.author.username.prefix(1).uppercased())
                                .font(.title3.bold())
                                .foregroundStyle(DS.Semantic.brand)
                        )
                }
                .fade(duration: 0.25)
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 44)
                .clipShape(ChamferedRectangleAlt(.small))

            // Username + Time
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.post.author.displayName ?? viewModel.post.author.username)
                    .font(.headline)
                    .foregroundStyle(DS.Semantic.textPrimary)

                HStack(spacing: 4) {
                    Text(viewModel.post.relativeTime)
                        .font(.caption)
                        .foregroundStyle(DS.Semantic.textSecondary)

                    Text("•")
                        .font(.caption)
                        .foregroundStyle(DS.Semantic.textSecondary)

                    Image(systemName: viewModel.post.post.visibility.icon)
                        .font(.caption)
                        .foregroundStyle(DS.Semantic.textSecondary)
                }
            }

            Spacer()
        }
        .padding(.horizontal)
    }

    private func imageCarousel(imageUrls: [String]) -> some View {
        TabView {
            ForEach(imageUrls, id: \.self) { urlString in
                KFImage(URL(string: urlString))
                    .placeholder {
                        Rectangle()
                            .fill(DS.Semantic.fillSubtle)
                            .overlay(ProgressView())
                    }
                    .fade(duration: 0.25)
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(height: 350)
        .tabViewStyle(.page(indexDisplayMode: imageUrls.count > 1 ? .always : .never))
    }

    // MARK: - Strength Carousel

    private func strengthCarousel(viewModel: PostDetailViewModel) -> some View {
        let workout = viewModel.post.post.workoutData
        let hasWatchData = workout.matchedHealthKitHeartRate != nil
            || workout.matchedHealthKitCalories != nil
        let pageCount = hasWatchData ? 3 : 2
        return VStack(spacing: 0) {
            TabView(selection: $carouselPage) {
                strengthSummaryPage(viewModel: viewModel).tag(0)
                strengthExercisePage(viewModel: viewModel).tag(1)
                if hasWatchData {
                    strengthWatchPage(viewModel: viewModel).tag(2)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 320)
            .padding(.horizontal)

            HStack(spacing: 5) {
                ForEach(0..<pageCount, id: \.self) { index in
                    Capsule()
                        .fill(index == carouselPage ? DS.tint : Color.secondary.opacity(0.3))
                        .frame(width: index == carouselPage ? 24 : 8, height: 3)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: carouselPage)
                }
            }
            .padding(.top, 10)
        }
        .onAppear { carouselPage = 0 }
    }

    // MARK: - Strength Page 1: Summary hero

    private func strengthSummaryPage(viewModel: PostDetailViewModel) -> some View {
        let post = viewModel.post.post
        let workout = post.workoutData
        return ZStack {
            // Background: first photo if available, else card with dumbbell watermark
            if let firstURL = displayImageURLs.first {
                KFImage(firstURL)
                    .resizable()
                    .scaledToFill()
                    .clipped()
            } else {
                ZStack {
                    DS.Semantic.card
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 90))
                        .foregroundStyle(DS.Semantic.brand.opacity(0.07))
                }
            }

            LinearGradient(
                colors: [.black.opacity(0.72), .clear, .black.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack {
                Spacer().frame(height: 90)

                // Stats row — shifted right
                HStack(alignment: .bottom, spacing: 0) {
                    if post.totalVolume > 0 {
                        VStack(spacing: 1) {
                            Text("VOLUME")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white.opacity(0.5))
                                .tracking(1.2)
                            Text(formatVolume(post.totalVolume))
                                .font(.system(size: 26, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            Text("KG")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white.opacity(0.65))
                                .tracking(1.5)
                        }
                        .frame(maxWidth: .infinity)
                        Rectangle().fill(.white.opacity(0.25)).frame(width: 1, height: 38)
                    }

                    VStack(spacing: 1) {
                        Text("EXERCISES")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white.opacity(0.5))
                            .tracking(1.2)
                        Text("\(post.exerciseCount)")
                            .font(.system(size: 26, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text("EX")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white.opacity(0.65))
                            .tracking(1.5)
                    }
                    .frame(maxWidth: .infinity)

                    Rectangle().fill(.white.opacity(0.25)).frame(width: 1, height: 38)

                    VStack(spacing: 1) {
                        Text("SETS")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white.opacity(0.5))
                            .tracking(1.2)
                        Text("\(post.totalSets)")
                            .font(.system(size: 26, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text("TOTAL")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white.opacity(0.65))
                            .tracking(1.5)
                    }
                    .frame(maxWidth: .infinity)

                    if post.duration != nil {
                        Rectangle().fill(.white.opacity(0.25)).frame(width: 1, height: 38)
                        VStack(spacing: 1) {
                            Text("DURATION")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white.opacity(0.5))
                                .tracking(1.2)
                            Text(post.durationFormatted)
                                .font(.system(size: 26, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.55)
                            Text("TIME")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white.opacity(0.65))
                                .tracking(1.5)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.leading, 32)
                .padding(.trailing, 12)

                Spacer()

                // Bottom: Apple Watch quick stats
                if workout.matchedHealthKitHeartRate != nil || workout.matchedHealthKitCalories != nil {
                    HStack(spacing: 14) {
                        if let hr = workout.matchedHealthKitHeartRate {
                            HStack(spacing: 4) {
                                Image(systemName: "heart.fill").font(.caption2).foregroundStyle(.red.opacity(0.9))
                                Text(String(format: "%.0f BPM", hr))
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundStyle(.white.opacity(0.9))
                        }
                        if let cal = workout.matchedHealthKitCalories {
                            HStack(spacing: 4) {
                                Image(systemName: "flame.fill").font(.caption2)
                                Text(String(format: "%.0f kcal", cal))
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundStyle(.white.opacity(0.9))
                        }
                        Spacer()
                    }
                    .padding(.bottom, 14)
                    .padding(.horizontal, 20)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Strength Page 2: Exercise list

    private func strengthExercisePage(viewModel: PostDetailViewModel) -> some View {
        let entries = viewModel.post.post.workoutData.entries
        return ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(entries) { entry in
                    strengthExerciseRow(entry: entry)
                }
            }
            .padding(14)
        }
        .background(DS.Semantic.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func strengthExerciseRow(entry: WorkoutEntry) -> some View {
        let totalReps = entry.sets.reduce(0) { $0 + $1.reps }
        let totalVolume = entry.sets.reduce(0.0) { $0 + Double($1.reps) * $1.weight }

        return VStack(alignment: .leading, spacing: 10) {
            // Exercise name
            Text(entry.exerciseName)
                .font(.subheadline.bold())
                .foregroundStyle(DS.Semantic.textPrimary)

            // Sets / Reps / Volume summary
            HStack(spacing: 16) {
                strengthStatItem(label: "Sets", value: "\(entry.sets.count)")
                strengthStatItem(label: "Reps", value: "\(totalReps)")
                if totalVolume > 0 {
                    strengthStatItem(label: "Volume", value: String(format: "%.0f kg", totalVolume))
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .background(DS.Semantic.fillSubtle)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Duration / Work / Rest (only when timing data available)
            if entry.totalDuration > 0 {
                HStack(spacing: 16) {
                    strengthStatItem(label: "Duration", value: entry.formattedTotalDuration)
                    strengthStatItem(label: "Work", value: entry.formattedWorkTime)
                    strengthStatItem(label: "Rest", value: entry.formattedRestTime)
                    Spacer(minLength: 0)
                }
                .padding(8)
                .background(DS.Semantic.fillSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Individual set rows
            VStack(spacing: 6) {
                ForEach(Array(entry.sets.enumerated()), id: \.offset) { index, set in
                    HStack(spacing: 10) {
                        // Number badge
                        Text("\(index + 1)")
                            .font(.caption.bold().monospacedDigit())
                            .foregroundStyle(.black)
                            .frame(width: 22, height: 22)
                            .background(set.tag.color, in: Circle())

                        // Set value + timing
                        VStack(alignment: .leading, spacing: 2) {
                            Text(set.displayValue)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(DS.Semantic.textPrimary)

                            if set.workDuration != nil || set.restAfterSeconds != nil {
                                HStack(spacing: 8) {
                                    if set.formattedWorkDuration != "—" {
                                        Text("Work: \(set.formattedWorkDuration)")
                                            .font(.caption2)
                                            .foregroundStyle(DS.Semantic.textSecondary)
                                    }
                                    if set.formattedRestDuration != "—" {
                                        Text("Rest: \(set.formattedRestDuration)")
                                            .font(.caption2)
                                            .foregroundStyle(DS.Semantic.textSecondary)
                                    }
                                }
                            }
                        }

                        Spacer()

                        // Tag badge
                        Text(set.tag.short)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(set.tag.color, in: Capsule())
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(DS.Semantic.fillSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(DS.Semantic.card)
        .clipShape(ChamferedRectangleAlt(.medium))
        .overlay(ChamferedRectangleAlt(.medium).stroke(DS.Semantic.border, lineWidth: 1))
    }

    private func strengthStatItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(DS.Semantic.textSecondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(DS.Semantic.textPrimary)
        }
    }

    // MARK: - Strength Page 3: Apple Watch biometrics (only shown when data exists)

    private func strengthWatchPage(viewModel: PostDetailViewModel) -> some View {
        let workout = viewModel.post.post.workoutData
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 8) {
                    Image(systemName: "applewatch")
                        .font(.title3)
                        .foregroundStyle(DS.Semantic.brand)
                    Text("Apple Watch")
                        .font(.headline.bold())
                        .foregroundStyle(DS.Semantic.textPrimary)
                }

                // BPM columns
                if workout.matchedHealthKitHeartRate != nil
                    || workout.matchedHealthKitMaxHeartRate != nil
                    || workout.matchedHealthKitMinHeartRate != nil {
                    HStack(spacing: 0) {
                        if let avg = workout.matchedHealthKitHeartRate {
                            bpmColumn(value: avg, label: "AVG BPM", color: DS.Semantic.brand)
                        }
                        if let max = workout.matchedHealthKitMaxHeartRate {
                            if workout.matchedHealthKitHeartRate != nil { bpmDivider() }
                            bpmColumn(value: max, label: "MAX BPM", color: DS.Semantic.textPrimary)
                        }
                        if let min = workout.matchedHealthKitMinHeartRate {
                            if workout.matchedHealthKitMaxHeartRate != nil { bpmDivider() }
                            bpmColumn(value: min, label: "MIN BPM", color: DS.Semantic.textSecondary)
                        }
                    }
                }

                // HR area chart
                if let samples = workout.matchedHealthKitHeartRateSamples, samples.count > 2,
                   let avgHR = workout.matchedHealthKitHeartRate,
                   let minHR = workout.matchedHealthKitMinHeartRate,
                   let maxHR = workout.matchedHealthKitMaxHeartRate {
                    strengthHRChart(
                        samples: samples,
                        avgHR: avgHR,
                        minHR: minHR,
                        maxHR: maxHR
                    )
                }

                // Calories
                if let calories = workout.matchedHealthKitCalories {
                    HStack(spacing: 14) {
                        Image(systemName: "flame.fill")
                            .font(.title2)
                            .foregroundStyle(DS.Semantic.brand)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(format: "%.0f", calories))
                                .font(.system(size: 32, weight: .heavy, design: .rounded))
                                .foregroundStyle(DS.Semantic.textPrimary)
                            Text("ACTIVE CALORIES")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(DS.Semantic.textSecondary)
                                .tracking(1.5)
                        }
                        Spacer()
                    }
                }
            }
            .padding(16)
        }
        .background(DS.Semantic.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func strengthHRChart(
        samples: [HeartRateSample],
        avgHR: Double,
        minHR: Double,
        maxHR: Double
    ) -> some View {
        let startTime = samples.first?.timestamp ?? Date()
        let dataPoints = samples.map { (time: $0.timestamp.timeIntervalSince(startTime), bpm: $0.bpm) }

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                // Min badge
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down").font(.caption2).foregroundStyle(.green)
                    Text("\(Int(minHR))")
                        .font(.caption.monospacedDigit().weight(.medium))
                        .foregroundStyle(DS.Semantic.textPrimary)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(.green.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))

                // Avg badge
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill").font(.caption2).foregroundStyle(.pink)
                    Text("\(Int(avgHR))")
                        .font(.caption.monospacedDigit().weight(.medium))
                        .foregroundStyle(DS.Semantic.textPrimary)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(.pink.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))

                // Max badge
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up").font(.caption2).foregroundStyle(.red)
                    Text("\(Int(maxHR))")
                        .font(.caption.monospacedDigit().weight(.medium))
                        .foregroundStyle(DS.Semantic.textPrimary)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(.red.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))

                Spacer()
            }

            Chart {
                ForEach(Array(dataPoints.enumerated()), id: \.offset) { _, point in
                    AreaMark(
                        x: .value("Time", point.time),
                        yStart: .value("Min", minHR - 10),
                        yEnd: .value("BPM", point.bpm)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.pink.opacity(0.4), .red.opacity(0.08)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("Time", point.time),
                        y: .value("BPM", point.bpm)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.pink, .red],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.catmullRom)
                }

                RuleMark(y: .value("Avg", avgHR))
                    .foregroundStyle(.pink.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("AVG")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.pink)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.5), in: Capsule())
                    }
            }
            .chartYScale(domain: (minHR - 10)...(maxHR + 10))
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { value in
                    if let seconds = value.as(Double.self) {
                        AxisValueLabel {
                            let m = Int(seconds) / 60
                            let s = Int(seconds) % 60
                            Text(m > 0 ? "\(m)m" : "\(s)s")
                                .font(.caption2)
                                .foregroundStyle(DS.Semantic.textSecondary)
                        }
                        AxisGridLine().foregroundStyle(DS.Semantic.border.opacity(0.4))
                    }
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisValueLabel {
                        if let v = value.as(Int.self) {
                            Text("\(v)")
                                .font(.caption2)
                                .foregroundStyle(DS.Semantic.textSecondary)
                        }
                    }
                    AxisGridLine().foregroundStyle(DS.Semantic.border.opacity(0.4))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 180)
        }
    }

    // MARK: - Cardio Carousel

    private func cardioCarousel(viewModel: PostDetailViewModel) -> some View {
        let workout = viewModel.post.post.workoutData

        // Determine which pages have content
        let isOutdoor = (workout.matchedHealthKitDistance ?? 0) > 0 || !displayImageURLs.isEmpty
        let hasHR = workout.matchedHealthKitHeartRate != nil
        let hasDynamics = workout.cardioAvgPower != nil || workout.cardioAvgCadence != nil
            || workout.cardioAvgStrideLength != nil || workout.cardioAvgGroundContactTime != nil
            || workout.cardioAvgVerticalOscillation != nil
        let hasZones = !(workout.cardioHRZones ?? []).isEmpty
        let hasSplits = !(workout.cardioSplits ?? []).isEmpty

        // Assign sequential page indices so dots and TabView stay in sync
        let hrIdx    = 1
        let dynIdx   = hrIdx   + (hasHR       ? 1 : 0)
        let zonesIdx = dynIdx  + (hasDynamics  ? 1 : 0)
        let splitsIdx = zonesIdx + (hasZones   ? 1 : 0)
        let pageCount = splitsIdx + (hasSplits ? 1 : 0)

        return VStack(spacing: 0) {
            TabView(selection: $carouselPage) {
                Group {
                    if isOutdoor {
                        cardioMapPage(workout: workout)
                    } else {
                        cardioSummaryHeroPage(workout: workout)
                    }
                }.tag(0)

                if hasHR {
                    cardioHeartRatePage(workout: workout, viewModel: viewModel).tag(hrIdx)
                }
                if hasDynamics {
                    cardioDynamicsPage(workout: workout).tag(dynIdx)
                }
                if hasZones {
                    cardioZonesPage(workout: workout, viewModel: viewModel).tag(zonesIdx)
                }
                if hasSplits {
                    cardioSplitsPage(workout: workout).tag(splitsIdx)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 320)
            .padding(.horizontal)

            // Line indicator (same design as SmartCardCarousel)
            HStack(spacing: 5) {
                ForEach(0..<pageCount, id: \.self) { index in
                    Capsule()
                        .fill(index == carouselPage ? DS.tint : Color.secondary.opacity(0.3))
                        .frame(width: index == carouselPage ? 24 : 8, height: 3)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: carouselPage)
                }
            }
            .padding(.top, 10)
        }
        .onAppear { carouselPage = 0 }
    }

    // MARK: - Carousel Page 0 (indoor): Summary hero when no route is available

    private func cardioSummaryHeroPage(workout: CompletedWorkout) -> some View {
        ZStack {
            DS.Semantic.card

            Image(systemName: workout.workoutIcon)
                .font(.system(size: 90))
                .foregroundStyle(DS.Semantic.brand.opacity(0.07))

            VStack(spacing: 16) {
                Text(workout.workoutTypeDisplayName.uppercased())
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(DS.Semantic.brand)
                    .tracking(2)

                if let calories = workout.matchedHealthKitCalories {
                    VStack(spacing: 2) {
                        Text(String(format: "%.0f", calories))
                            .font(.system(size: 52, weight: .heavy, design: .rounded))
                            .foregroundStyle(DS.Semantic.textPrimary)
                        Text("CALORIES")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(DS.Semantic.textSecondary)
                            .tracking(1.5)
                    }
                }

                HStack(spacing: 16) {
                    if let durationSec = workout.matchedHealthKitDuration {
                        cardioBigStat(value: formatSummaryDuration(durationSec), label: "DURATION")
                    }
                    if let avgHR = workout.matchedHealthKitHeartRate {
                        if workout.matchedHealthKitDuration != nil {
                            Rectangle().fill(DS.Semantic.border).frame(width: 1, height: 28)
                        }
                        cardioBigStat(value: String(format: "%.0f", avgHR), label: "AVG BPM")
                    }
                    if let maxHR = workout.matchedHealthKitMaxHeartRate {
                        Rectangle().fill(DS.Semantic.border).frame(width: 1, height: 28)
                        cardioBigStat(value: String(format: "%.0f", maxHR), label: "MAX BPM")
                    }
                }
            }
            .padding(16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func cardioBigStat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(DS.Semantic.textPrimary)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(DS.Semantic.textSecondary)
                .tracking(1)
        }
    }

    private func formatSummaryDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        return h > 0 ? String(format: "%dh %02dm", h, m) : "\(m)m"
    }

    // MARK: - Carousel Page 1: Route map with overlaid stats

    private func cardioMapPage(workout: CompletedWorkout) -> some View {
        ZStack {
            // Route map
            if let mapURL = displayImageURLs.first {
                KFImage(mapURL)
                    .placeholder { Rectangle().fill(DS.Semantic.fillSubtle) }
                    .fade(duration: 0.25)
                    .resizable()
                    .scaledToFill()
                    .clipped()
            } else {
                DS.Semantic.fillSubtle
            }

            // Gradient at top and bottom for legibility
            LinearGradient(
                colors: [.black.opacity(0.55), .clear, .black.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )

            // Pace + calories at top center, KM/TIME at bottom with labels above
            VStack {
                // Top center: pace + calories (small)
                if let distanceMeters = workout.matchedHealthKitDistance, distanceMeters > 0,
                   let durationSec = workout.matchedHealthKitDuration {
                    let pace = Double(durationSec) / (distanceMeters / 1000)
                    HStack(spacing: 16) {
                        HStack(spacing: 4) {
                            Image(systemName: "figure.run").font(.caption2)
                            Text("\(formatPace(pace)) /km")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(.white.opacity(0.92))

                        if let calories = workout.matchedHealthKitCalories {
                            HStack(spacing: 4) {
                                Image(systemName: "flame.fill").font(.caption2)
                                Text(String(format: "%.0f kcal", calories))
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundStyle(.white.opacity(0.92))
                        }
                    }
                    .padding(.top, 14)
                }

                Spacer()

                // Bottom: distance and time, label above each number
                if let distanceMeters = workout.matchedHealthKitDistance, distanceMeters > 0 {
                    HStack(alignment: .bottom, spacing: 0) {
                        VStack(spacing: 1) {
                            Text("DISTANCE")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white.opacity(0.5))
                                .tracking(1.5)
                            Text(String(format: "%.2f", distanceMeters / 1000))
                                .font(.system(size: 36, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                            Text("KM")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white.opacity(0.65))
                                .tracking(2)
                        }
                        .frame(maxWidth: .infinity)

                        if let durationSec = workout.matchedHealthKitDuration {
                            Rectangle()
                                .fill(.white.opacity(0.25))
                                .frame(width: 1, height: 46)

                            VStack(spacing: 1) {
                                Text("DURATION")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.5))
                                    .tracking(1.5)
                                Text(formatCardioDuration(durationSec))
                                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                                    .foregroundStyle(.white)
                                Text("TIME")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.65))
                                    .tracking(2)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.bottom, 16)
                    .padding(.horizontal, 20)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Carousel Page 2: Running dynamics

    private func cardioDynamicsPage(workout: CompletedWorkout) -> some View {
        RunningDynamicsGrid(
            avgPower: workout.cardioAvgPower,
            avgCadence: workout.cardioAvgCadence,
            avgStrideLength: workout.cardioAvgStrideLength,
            avgGroundContactTime: workout.cardioAvgGroundContactTime,
            avgVerticalOscillation: workout.cardioAvgVerticalOscillation
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Carousel Page 3: Heart rate numbers + time series

    private func cardioHeartRatePage(workout: CompletedWorkout, viewModel: PostDetailViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Heart Rate")
                        .font(.headline.bold())
                        .foregroundStyle(DS.Semantic.textPrimary)

                    Spacer()

                    if viewModel.canRefreshCardioData {
                        if viewModel.isRefreshingCardioData {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Button {
                                Task { await viewModel.refreshCardioData() }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.clockwise")
                                    Text(workout.cardioHRZones == nil ? "Load" : "Refresh")
                                }
                                .font(.caption)
                                .foregroundStyle(DS.Semantic.brand)
                            }
                        }
                    }
                }

                // Large inline BPM numbers
                if workout.matchedHealthKitHeartRate != nil
                    || workout.matchedHealthKitMaxHeartRate != nil
                    || workout.matchedHealthKitMinHeartRate != nil {
                    HStack(spacing: 0) {
                        if let avg = workout.matchedHealthKitHeartRate {
                            bpmColumn(value: avg, label: "AVG BPM", color: DS.Semantic.brand)
                        }
                        if let max = workout.matchedHealthKitMaxHeartRate {
                            if workout.matchedHealthKitHeartRate != nil {
                                bpmDivider()
                            }
                            bpmColumn(value: max, label: "MAX BPM", color: DS.Semantic.textPrimary)
                        }
                        if let min = workout.matchedHealthKitMinHeartRate {
                            if workout.matchedHealthKitMaxHeartRate != nil {
                                bpmDivider()
                            }
                            bpmColumn(value: min, label: "MIN BPM", color: DS.Semantic.textSecondary)
                        }
                    }
                } else {
                    Text("No heart rate data — swipe right to load")
                        .font(.subheadline)
                        .foregroundStyle(DS.Semantic.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                // HR over time chart
                if let samples = workout.matchedHealthKitHeartRateSamples, samples.count > 2 {
                    HRZoneChart(
                        zones: [],
                        samples: samples,
                        showZonesSection: false,
                        showTimeSeriesSection: true,
                        showCard: false
                    )
                }
            }
            .padding(16)
        }
        .background(DS.Semantic.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func bpmColumn(value: Double, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(String(format: "%.0f", value))
                .font(.system(size: 40, weight: .heavy, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(DS.Semantic.textSecondary)
                .tracking(1)
        }
        .frame(maxWidth: .infinity)
    }

    private func bpmDivider() -> some View {
        Rectangle()
            .fill(DS.Semantic.border)
            .frame(width: 1, height: 44)
    }

    // MARK: - Carousel Page 4: HR Zones

    private func cardioZonesPage(workout: CompletedWorkout, viewModel: PostDetailViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Spacer()
                    if viewModel.canRefreshCardioData {
                        if viewModel.isRefreshingCardioData {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Button {
                                Task { await viewModel.refreshCardioData() }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Refresh")
                                }
                                .font(.caption)
                                .foregroundStyle(DS.Semantic.brand)
                            }
                        }
                    }
                }

                HRZoneChart(
                    zones: workout.cardioHRZones ?? [],
                    samples: nil,
                    showZonesSection: true,
                    showTimeSeriesSection: false,
                    showCard: false
                )
            }
            .padding(16)
        }
        .background(DS.Semantic.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Carousel Page 5: Kilometer Splits

    private func cardioSplitsPage(workout: CompletedWorkout) -> some View {
        ScrollView {
            SplitsChart(splits: workout.cardioSplits ?? [], showCard: false)
                .padding(16)
        }
        .background(DS.Semantic.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func formatPace(_ secPerKm: Double) -> String {
        let minutes = Int(secPerKm) / 60
        let seconds = Int(secPerKm) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func formatCardioDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }

    private func statCard(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(DS.Semantic.brand)

            Text(value)
                .font(.headline)
                .foregroundStyle(DS.Semantic.textPrimary)

            Text(label)
                .font(.caption)
                .foregroundStyle(DS.Semantic.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(DS.Semantic.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func exerciseRow(entry: WorkoutEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(entry.exerciseName)
                .font(.subheadline.bold())
                .foregroundStyle(DS.Semantic.textPrimary)

            ForEach(Array(entry.sets.enumerated()), id: \.offset) { index, set in
                HStack {
                    Text("Set \(index + 1):")
                        .font(.caption)
                        .foregroundStyle(DS.Semantic.textSecondary)

                    if set.weight > 0 {
                        Text("\(set.weight.safeInt) kg × \(set.reps) reps")
                            .font(.caption)
                            .foregroundStyle(DS.Semantic.textPrimary)
                    } else {
                        Text("\(set.reps) reps")
                            .font(.caption)
                            .foregroundStyle(DS.Semantic.textPrimary)
                    }

                    Spacer()

                    if set.isCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(DS.Status.success)
                    }
                }
            }
        }
        .padding(12)
        .background(DS.Semantic.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func statsSection(viewModel: PostDetailViewModel) -> some View {
        HStack(spacing: 20) {
            // Like icon: toggles the like. Count: opens likers list.
            HStack(spacing: 6) {
                Button {
                    Task { await viewModel.toggleLike() }
                } label: {
                    Image(viewModel.post.isLikedByCurrentUser ? "tab-cardio" : "tab-cardio-inactive")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                }

                let displayCount = max(viewModel.post.post.likesCount, viewModel.post.isLikedByCurrentUser ? 1 : 0)
                if displayCount > 0 {
                    Button {
                        showingLikes = true
                    } label: {
                        Text("\(displayCount)")
                            .font(.subheadline.bold())
                            .foregroundStyle(DS.Semantic.textPrimary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("0")
                        .font(.subheadline.bold())
                        .foregroundStyle(DS.Semantic.textPrimary)
                }
            }

            // Comment count
            HStack(spacing: 6) {
                Image("tab-social-inactive")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)

                Text("\(viewModel.post.post.commentsCount)")
                    .font(.subheadline.bold())
                    .foregroundStyle(DS.Semantic.textPrimary)
            }

            Spacer()
        }
        .padding(.horizontal)
        .sheet(isPresented: $showingLikes) {
            LikesListView(postId: post.post.id, postRepository: deps.postRepository)
        }
    }

    private func commentsSection(viewModel: PostDetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if viewModel.isLoadingComments {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else if viewModel.comments.isEmpty {
                Text("No comments yet")
                    .font(.subheadline)
                    .foregroundStyle(DS.Semantic.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                ForEach(viewModel.comments) { comment in
                    CommentRow(
                        comment: comment,
                        isReply: false,
                        canDelete: comment.userId == deps.authService.currentUser?.id,
                        onDelete: {
                            Task { await viewModel.deleteComment(comment) }
                        },
                        onReply: {
                            viewModel.startReply(to: comment)
                            isCommentFieldFocused = true
                        }
                    )
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private func commentInput(viewModel: PostDetailViewModel) -> some View {
        VStack(spacing: 0) {
            // Mention autocomplete (above comment input)
            if !viewModel.mentionSuggestions.isEmpty {
                MentionAutocomplete(
                    suggestions: viewModel.mentionSuggestions,
                    onSelect: { user in
                        viewModel.insertMention(user)
                    }
                )
                .padding(.bottom, 8)
            }

            // Reply indicator (if replying to a comment)
            if let replyingTo = viewModel.replyingTo {
                HStack {
                    Text("Replying to @\(replyingTo.author?.username ?? "unknown")")
                        .font(.caption)
                        .foregroundStyle(DS.Semantic.textSecondary)

                    Spacer()

                    Button {
                        viewModel.cancelReply()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption)
                            .foregroundStyle(DS.Semantic.textSecondary)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(DS.Semantic.fillSubtle.opacity(0.5))
            }

            Divider()

            HStack(alignment: .bottom, spacing: 10) {
                TextField("Add a comment...", text: Binding(
                    get: { viewModel.commentText },
                    set: { newValue in
                        viewModel.commentText = newValue
                        viewModel.detectMentionQuery(in: newValue)
                    }
                ), axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .focused($isCommentFieldFocused)
                    .disabled(viewModel.isPostingComment)
                    .submitLabel(.return)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(DS.Semantic.fillSubtle)
                    )

                Button {
                    Task {
                        await viewModel.postComment()
                        isCommentFieldFocused = false
                    }
                } label: {
                    if viewModel.isPostingComment {
                        ProgressView()
                            .tint(DS.Semantic.brand)
                            .frame(width: 34, height: 34)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(
                                viewModel.commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? DS.Semantic.textSecondary
                                    : DS.Semantic.brand
                            )
                            .frame(width: 34, height: 34)
                    }
                }
                .disabled(viewModel.commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isPostingComment)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(DS.Semantic.card)
        }
    }

    private func formatVolume(_ volume: Double) -> String {
        if volume >= 1000 {
            return String(format: "%.1fk", volume / 1000)
        }
        return String(format: "%.0f", volume)
    }

    // MARK: - Load Image URLs

    private func loadImageURLs() async {
        guard let userId = deps.authService.currentUser?.id else { return }
        guard let images = post.post.images, !images.isEmpty else { return }

        do {
            let urls = try await imageUploadService.getImageURLs(
                for: images,
                currentUserId: userId,
                postOwnerId: post.post.userId
            )
            await MainActor.run {
                displayImageURLs = urls
            }
        } catch {
            print("⚠️ Failed to load image URLs: \(error)")
        }
    }
}

// MARK: - Comment Row Component

struct CommentRow: View {
    let comment: PostComment
    let isReply: Bool
    let canDelete: Bool
    let onDelete: () -> Void
    let onReply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            commentBody

            if let replies = comment.replies, !replies.isEmpty, !isReply {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(replies) { reply in
                        CommentRow(
                            comment: reply,
                            isReply: true,
                            canDelete: false,
                            onDelete: {},
                            onReply: {}
                        )
                        .padding(.leading, 34)
                        .padding(.vertical, 4)
                    }
                }
                .padding(.top, 6)
            }
        }
    }

    @ViewBuilder
    private var commentBody: some View {
        HStack(alignment: .top, spacing: 8) {
            avatar

            VStack(alignment: .leading, spacing: 2) {
                // Username outside bubble — naturally aligned with avatar top
                if let author = comment.author {
                    Text(author.username)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DS.Semantic.brand)
                }

                // Chamfered bubble (content only)
                MentionText(text: comment.content, mentions: comment.mentions)
                    .font(.subheadline)
                    .foregroundStyle(DS.Semantic.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        ChamferedRectangleAlt(.small)
                            .fill(isReply ? DS.Semantic.fillSubtle : DS.Semantic.card)
                    )

                // Time + Reply (outside bubble)
                HStack(spacing: 12) {
                    Text(relativeTime(for: comment.createdAt))
                        .font(.caption2)
                        .foregroundStyle(DS.Semantic.textSecondary)

                    if !isReply {
                        Button(action: onReply) {
                            Text("Reply")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(DS.Semantic.textSecondary)
                        }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.top, 2)
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            if canDelete {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            if !isReply {
                Button {
                    onReply()
                } label: {
                    Label("Reply", systemImage: "arrowshape.turn.up.left")
                }
            }
        }
    }

    @ViewBuilder
    private var avatar: some View {
        let size: CGFloat = isReply ? 24 : 30
        let chamfer: CGFloat = isReply ? 5 : 7
        if let author = comment.author {
            KFImage(URL(string: author.avatarUrl ?? ""))
                .placeholder {
                    ChamferedRectangleAlt(chamferSize: chamfer)
                        .fill(DS.Semantic.brandSoft)
                        .overlay(
                            Text(author.username.prefix(1).uppercased())
                                .font(.system(size: size * 0.4, weight: .bold))
                                .foregroundStyle(DS.Semantic.brand)
                        )
                }
                .fade(duration: 0.25)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(ChamferedRectangleAlt(chamferSize: chamfer))
        }
    }

    private func relativeTime(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

