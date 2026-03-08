//
//  AppSettings.swift
//  BioDataApp
//
//  Profile and API URL for the local TallyWell backend.
//

import Foundation

struct AppSettings {

    private static let heightKey = "TallyWellProfileHeightCm"
    private static let weightKey = "TallyWellProfileWeightKg"
    private static let genderKey = "TallyWellProfileGender"
    private static let ageKey = "TallyWellProfileAge"

    static var heightCm: Double {
        get {
            let v = UserDefaults.standard.double(forKey: heightKey)
            return v > 0 ? v : 170
        }
        set { UserDefaults.standard.set(newValue, forKey: heightKey) }
    }

    static var weightKg: Double {
        get {
            let v = UserDefaults.standard.double(forKey: weightKey)
            return v > 0 ? v : 70
        }
        set { UserDefaults.standard.set(newValue, forKey: weightKey) }
    }

    static var gender: String {
        get { UserDefaults.standard.string(forKey: genderKey) ?? "male" }
        set { UserDefaults.standard.set(newValue, forKey: genderKey) }
    }

    static var age: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: ageKey)
            return v > 0 ? v : 30
        }
        set { UserDefaults.standard.set(newValue, forKey: ageKey) }
    }

    static var profile: Profile {
        get {
            Profile(height_cm: heightCm, weight_kg: weightKg, gender: gender, age: age)
        }
        set {
            heightCm = newValue.height_cm
            weightKg = newValue.weight_kg
            gender = newValue.gender
            age = newValue.age
        }
    }

    /// True if user has set a valid profile (so we can call the API).
    static var hasProfile: Bool {
        heightCm > 0 && weightKg > 0 && age > 0
    }
}
