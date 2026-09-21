import Foundation

/// Gruppo muscolare: serve ad accorpare esercizi con nomi diversi tra schede diverse
/// (es. "Chest press" e "Pectoral machine" finiscono entrambi in Petto).
enum MuscleGroup: String, CaseIterable, Identifiable, Codable {
    case petto, schiena, spalle, bicipiti, tricipiti, gambe, glutei, addome, cardio, altro

    var id: String { rawValue }

    var label: String {
        switch self {
        case .petto: return "Petto"
        case .schiena: return "Schiena"
        case .spalle: return "Spalle"
        case .bicipiti: return "Bicipiti"
        case .tricipiti: return "Tricipiti"
        case .gambe: return "Gambe"
        case .glutei: return "Glutei"
        case .addome: return "Addome"
        case .cardio: return "Cardio"
        case .altro: return "Altro"
        }
    }

    var icon: String {
        switch self {
        case .petto: return "figure.strengthtraining.traditional"
        case .schiena: return "figure.rowing"
        case .spalle: return "figure.arms.open"
        case .bicipiti, .tricipiti: return "dumbbell.fill"
        case .gambe: return "figure.walk"
        case .glutei: return "figure.step.training"
        case .addome: return "figure.core.training"
        case .cardio: return "heart.fill"
        case .altro: return "circle.grid.2x2"
        }
    }

    var sortOrder: Int {
        MuscleGroup.allCases.firstIndex(of: self) ?? 0
    }

    /// Regole in ordine di priorità: la prima che corrisponde vince
    /// ("leg curl" deve finire in Gambe prima che "curl" lo mandi in Bicipiti).
    private static let rules: [(MuscleGroup, [String])] = [
        (.cardio, ["riscaldamento", "warm up", "warm-up", "warmup", "corsa", "cyclette", "tapis", "treadmill", "bike", "ellittica", "vogatore", "rower", "camminata", "defaticamento", "stretching", "corda", "salto", "skip", "cardio", "run"]),
        (.addome, ["crunch", "addom", "plank", "leg raise", "sit up", "sit-up", "situp", "russian", "abs", "core", "hollow", "mountain climber", "obliqu", "twist", "ab wheel", "ruota"]),
        (.gambe, ["leg curl", "leg extension", "leg press", "squat", "affond", "lunge", "stacco", "deadlift", "calf", "polpacc", "hack", "adduttor", "abduttor", "adductor", "step up", "bulgar", "pressa", "quadric", "femoral", "sissy", "good morning", "pistol"]),
        (.glutei, ["hip thrust", "glute", "glutei", "ponte", "kickback", "kick back", "abductor", "slancio"]),
        (.tricipiti, ["push down", "pushdown", "french", "tricip", "dip", "skull", "estensioni", "extension", "overhead"]),
        (.bicipiti, ["curl", "bicip", "chin", "hammer", "martello", "spider", "preacher", "scott"]),
        (.spalle, ["shoulder", "alzate", "military", "lento", "deltoid", "spalle", "arnold", "face pull", "mento", "upright", "lateral raise", "front raise", "rear delt"]),
        (.schiena, ["lat ", "lat", "pulley", "remator", "rowing", "row", "trazion", "pull up", "pull-up", "pullup", "pulldown", "pull down", "dorsal", "schiena", "lombar", "hyperextension", "iperestension", "shrug", "scrollate", "pullover"]),
        (.petto, ["chest", "pectoral", "petto", "pettoral", "panca", "bench", "croci", "fly", "push up", "push-up", "pushup", "piegament", "pec deck", "crossover"])
    ]

    /// Le parole chiave devono corrispondere all'inizio di una parola:
    /// "run" non deve scattare su "crunch", né "chin" su "machine".
    static func classify(_ name: String) -> MuscleGroup {
        let key = " " + name.normalizedKey
        for (group, keywords) in rules {
            for keyword in keywords where key.contains(" " + keyword.normalizedKey) {
                return group
            }
        }
        return .altro
    }
}
