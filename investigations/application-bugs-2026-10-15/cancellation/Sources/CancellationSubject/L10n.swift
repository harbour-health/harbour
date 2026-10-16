import Foundation
import HarbourCore

enum L10n {
    static var isFrench: Bool { Bundle.main.preferredLocalizations.first?.hasPrefix("fr") == true }
    static var locale: Locale { Locale(identifier: isFrench ? "fr_CA" : "en_CA") }

    static func string(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: key, table: "Localizable")
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: locale, arguments: arguments)
    }

    static func date(_ value: Date, time: Bool = false) -> String {
        value.formatted(Date.FormatStyle(date: .abbreviated, time: time ? .shortened : .omitted).locale(locale))
    }

    static func readingValue(_ reading: Reading) -> String {
        isFrench ? reading.value.replacingOccurrences(of: ".", with: ",") : reading.value
    }

    static func medicineName(_ medicine: Medicine) -> String {
        guard Catalog.medicines.contains(where: { $0.id == medicine.id && $0.name == medicine.name }) else { return medicine.name }
        return string(medicine.name)
    }

    static func ingredientNames(_ ingredients: [String]) -> String {
        ingredients.map(string).joined(separator: ", ")
    }

    static func frequency(_ frequency: MedicationFrequency) -> String {
        format("%d per %@", frequency.count, string(frequency.period.rawValue))
    }

    static func doseTimes(_ times: [DoseTime]) -> String {
        times.map { time in
            let date = Calendar.current.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: .now) ?? .now
            return date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(locale))
        }.joined(separator: ", ")
    }
}
