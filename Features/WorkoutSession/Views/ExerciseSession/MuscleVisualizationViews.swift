//
//  MuscleVisualizationViews.swift
//  WRKT
//
//  Muscle visualization components with SVG rendering
//

import SwiftUI
import SVGView
//import AppModels

private enum MusclesTheme {
    static let surface  = Color(red: 0.10, green: 0.10, blue: 0.10)
    static let border   = Color.white.opacity(0.10)
    static let headline = Color.white.opacity(0.65)
}

// MARK: - Exercise Muscles Section

struct ExerciseMusclesSection: View {
    let exercise: Exercise
    var focus: SVGHumanBodyView.Focus = .full

    private var primary: Set<String> { Set(exercise.primaryMuscles.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }) }
    private var secondary: Set<String> { Set(exercise.secondaryMuscles.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }) }
    private var tertiary: Set<String> { Set(exercise.tertiaryMuscles.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }) }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(MusclesTheme.surface)
            RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(MusclesTheme.border, lineWidth: 1)

            HStack(spacing: 12) {
                SVGHumanBodyView(side: .front, focus: focus, primary: primary, secondary: secondary, tertiary: tertiary)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(0.56, contentMode: .fit)
                SVGHumanBodyView(side: .back,  focus: focus, primary: primary, secondary: secondary, tertiary: tertiary)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(0.56, contentMode: .fit)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - SVG Human Body View

struct SVGHumanBodyView: View {
    enum Side  { case front, back }
    enum Focus { case full, upper, lower }

    var side: Side
    var focus: Focus = .full
    var primary: Set<String> = []
    var secondary: Set<String> = []
    var tertiary: Set<String> = []

    private var highlightKey: String {
        (primary.sorted().joined(separator: ",")) + "|" +
        (secondary.sorted().joined(separator: ",")) + "|" +
        (tertiary.sorted().joined(separator: ","))
    }

    private enum Heatmap {
        static let primaryName   = "mediumorchid"
        static let secondaryName = "orchid"
        static let tertiaryName  = "mediumpurple"
        static let primaryAlpha:   Double = 0.95
        static let secondaryAlpha: Double = 0.55
        static let tertiaryAlpha:  Double = 0.30
    }

    var body: some View {
        Group {
            if let url = Bundle.main.url(forResource: side == .front ? "torso" : "torso_back",
                                         withExtension: "svg") {
                let svg = SVGView(contentsOf: url)
                svg
                    .aspectRatio(contentMode: .fit)
                    .mask(maskForFocus())
                    .onAppear { DispatchQueue.main.async { applyHighlights(into: svg) } }
                    .onChange(of: highlightKey) { _ in DispatchQueue.main.async { applyHighlights(into: svg) } }
                    .onChange(of: side) { _ in DispatchQueue.main.async { applyHighlights(into: svg) } }
                    .onChange(of: focus) { _ in DispatchQueue.main.async { applyHighlights(into: svg) } }
            } else {
                Rectangle().fill(.secondary.opacity(0.15))
                    .overlay(Image(systemName: "exclamationmark.triangle").foregroundStyle(.secondary))
                    .aspectRatio(0.56, contentMode: .fit)
                    .mask(maskForFocus())
            }
        }
    }

    @ViewBuilder
    private func maskForFocus() -> some View {
        GeometryReader { geo in
            let size = geo.size
            let rect: CGRect = {
                switch focus {
                case .full:  return CGRect(origin: .zero, size: size)
                case .upper: return CGRect(x: 0, y: 0, width: size.width, height: size.height * 0.58)
                case .lower: return CGRect(x: 0, y: size.height * 0.42, width: size.width, height: size.height * 0.58)
                }
            }()
            Path { $0.addRect(rect) }.fill(Color.white)
        }
    }

    private func applyHighlights(into root: SVGView) {
        let pTokens = Array(primary).flatMap { MuscleLexicon.tokens(for: $0) }
        let sTokens = Array(secondary).flatMap { MuscleLexicon.tokens(for: $0) }
        let tTokens = Array(tertiary).flatMap { MuscleLexicon.tokens(for: $0) }

        let idx = MuscleIndex.shared
        var pIDs = Set(idx.ids(forClassTokens: pTokens, side: side))
        var sIDs = Set(idx.ids(forClassTokens: sTokens, side: side))
        var tIDs = Set(idx.ids(forClassTokens: tTokens, side: side))

        sIDs.subtract(pIDs)
        tIDs.subtract(pIDs); tIDs.subtract(sIDs)

        color(ids: Array(tIDs), in: root, colorName: Heatmap.tertiaryName, opacity: Heatmap.tertiaryAlpha)
        color(ids: Array(sIDs), in: root, colorName: Heatmap.secondaryName, opacity: Heatmap.secondaryAlpha)
        color(ids: Array(pIDs), in: root, colorName: Heatmap.primaryName,   opacity: Heatmap.primaryAlpha)
    }

    private func paint(_ node: SVGNode, colorName: String, targetOpacity: Double) {
        if let shape = node as? SVGShape {
            shape.fill = SVGColor.by(name: colorName)
            shape.opacity = targetOpacity
        } else if let group = node as? SVGGroup {
            group.opacity = max(group.opacity, targetOpacity)
            for child in group.contents { paint(child, colorName: colorName, targetOpacity: targetOpacity) }
        } else {
            node.opacity = max(node.opacity, targetOpacity)
        }
    }

    private func color(ids: [String], in root: SVGView, colorName: String, opacity: Double) {
        for id in ids { if let node = root.getNode(byId: id) { paint(node, colorName: colorName, targetOpacity: opacity) } }
    }
}

// MARK: - Muscle Lexicon

enum MuscleLexicon {
    static func tokens(for raw: String) -> [String] {
        let base = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var out: Set<String> = [base, base.replacingOccurrences(of: " ", with: "-"), singularize(base)]
        switch base {
        case "pectoralis major", "pectoralis-major", "chest", "pecs", "pectorals":
            out.formUnion(["pectoralis-major-clavicular","pectoralis-major","chest","pec"])
        case "pectoralis minor", "pectoralis-minor":
            out.formUnion(["pectoralis-minor","chest","pec"])
        case "triceps brachii", "triceps-brachii", "triceps":
            out.formUnion(["triceps","triceps-long","triceps-lateral","triceps-medial"])
        case "biceps brachii", "biceps-brachii":
            out.formUnion(["biceps-brachii-long","biceps-brachii-short","biceps"])
        case "biceps brachii long", "biceps-brachii-long":
            out.formUnion(["biceps-brachii-long","biceps"])
        case "biceps brachii short", "biceps-brachii-short":
            out.formUnion(["biceps-brachii-short","biceps"])
        case "biceps", "bicep":
            out.formUnion(["biceps","biceps-brachii-long","biceps-brachii-short"])
        case "brachialis": out.formUnion(["brachialis"])
        case "brachioradialis": out.formUnion(["brachioradialis"])
        case "forearm flexors", "forearm-flexors", "wrist flexors":
            out.formUnion(["forearm-flexors-1","forearm-flexors-2","forearm-flexors"])
        case "forearm extensors", "forearm-extensors", "wrist extensors":
            out.formUnion(["forearm-extensors","forearm-extensors-1","forearm-extensors-2","forearm-extensors-3"])
        case "supinator": out.formUnion(["supinator"])
        case "deltoid anterior", "anterior deltoid", "anterior deltoids", "deltoid-anterior", "front delts", "front delt":
            out.formUnion(["deltoid-anterior","deltoid","deltoids"])
        case "deltoid posterior", "posterior deltoid", "posterior deltoids", "rear delts", "rear delt", "deltoid-posterior":
            out.formUnion(["deltoid-posterior"])
        case "latissimus dorsi", "lat", "lats", "latissimus-dorsi":
            out.formUnion(["latissimus-dorsi","lats"])
        case "obliques", "external oblique", "internal oblique", "oblique":
            out.formUnion(["obliques"])
        case "rectus abdominis", "abs", "abdominals", "rectus-abdominis":
            out.formUnion(["rectus-abdominis","abs","abdominals"])
        case "serratus anterior", "serratus-anterior":
            out.formUnion(["serratus-anterior"])
        case "subscapularis": out.formUnion(["subscapularis"])
        case "trapezius upper", "upper traps", "trapezius-upper":
            out.formUnion(["trapezius-upper","trapezius","traps"])
        case "trapezius middle", "middle traps", "mid traps", "trapezius-middle":
            out.formUnion(["trapezius-middle"])
        case "trapezius lower", "lower traps", "trapezius-lower":
            out.formUnion(["trapezius-lower"])
        case "splenius", "splenius capitis", "splenius cervicis":
            out.formUnion(["splenius"])
        case "levator scapulae", "levator-scapulae":
            out.formUnion(["levator-scapulae"])
        case "rhomboid", "rhomboids", "rhomboid major", "rhomboid minor":
            out.formUnion(["rhomboid"])
        case "infraspinatus", "teres minor", "teres-minor", "infraspinatus-teres-minor":
            out.formUnion(["infraspinatus-teres-minor","infraspinatus","teres-minor"])
        case "supraspinatus": out.formUnion(["supraspinatus"])
        case "erector spinae", "erectors", "spinal erectors", "erector-spinae":
            out.formUnion(["erector-spinae"])
        case "quadratus lumborum", "quadratus-lumborum":
            out.formUnion(["quadratus-lumborum"])
        case "deep external rotators", "deep-external-rotators", "external rotators":
            out.formUnion(["deep-external-rotators"])
        case "quadriceps", "quads", "quadriceps femoris":
            out.formUnion(["quadriceps","quadriceps-1","quadriceps-2","quadriceps-3","quadriceps-4"])
        case "adductor magnus", "adductor-longus", "adductor longus",
             "adductor brevis", "adductor-brevis",
             "gracilis", "pectineus":
            out.formUnion(["adductors", "hip-adductors", "hip-adductors-1", "hip-adductors-2"])
        case "hip flexors", "hip-flexors": out.formUnion(["hip-flexors"])
        case "abductors", "abductor", "tfl": out.formUnion(["abductors"])
        case "gluteus maximus", "glute max", "gluteus-maximus":
            out.formUnion(["gluteus-maximus"])
        case "hamstrings", "hamstring", "posterior thigh", "posterior-thigh":
            out.formUnion(["hamstrings"])
        case "biceps femoris", "biceps-femoris":
            out.formUnion(["hamstrings","hamstring","biceps-femoris"])
        case "semitendinosus", "semi-tendinosus":
            out.formUnion(["hamstrings","semitendinosus"])
        case "semimembranosus", "semi-membranosus":
            out.formUnion(["hamstrings","semimembranosus"])
        case "gastrocnemius": out.formUnion(["gastrocnemius"])
        case "soleus": out.formUnion(["soleus"])
        case "tibialis anterior", "tibialis-anterior":
            out.formUnion(["tibialis-anterior"])
        default: break
        }
        return Array(out)
    }

    static func idCandidates(forTokens tokens: [String]) -> [String] {
        var ids = Set<String>()
        let sides = ["", "-l", "-r", "-L", "-R", "-left", "-right"]
        let planes = ["", "-front", "-back", "-anterior", "-posterior"]
        let copies = (0...20).map { "-\($0)" } + [""]
        for t in tokens {
            let base = t.trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased().replacingOccurrences(of: "_", with: "-")
                .replacingOccurrences(of: " ", with: "-")
            let singular = base.hasSuffix("s") ? String(base.dropLast()) : base
            let forms = Set([base, singular])
            for form in forms {
                for s in sides { for p in planes { for c in copies {
                    ids.insert("\(form)\(s)\(p)\(c)")
                    ids.insert("\(form)\(p)\(s)\(c)")
                }}}
            }
        }
        return Array(ids)
    }

    private static func singularize(_ s: String) -> String {
        if s.hasSuffix("s") { return String(s.dropLast()) }
        return s
    }
}
