import Foundation

/// Directory options for the searchable Basics pickers (Education, Occupation,
/// Religion). All allow a typed custom value via SearchableSelectField, so
/// these lists never block a real entry. Mirrors the Android
/// EDUCATION_OPTIONS / OCCUPATION_OPTIONS / RELIGION_OPTIONS lists.
enum BasicsOptions {
    static let education: [String] = [
        "High School", "Diploma", "Trade / Vocational", "Bachelor's Degree",
        "Master's Degree", "MBA", "PhD / Doctorate", "Professional Degree",
        "Some College", "Other",
    ]

    static let religion: [String] = [
        "Hindu", "Sikh", "Jain", "Muslim", "Christian", "Buddhist", "Parsi",
        "Spiritual", "Agnostic", "Atheist", "Prefer not to say", "Other",
    ]

    static let occupation: [String] = [
        "Business Owner", "Entrepreneur", "Doctor", "Engineer", "Software Developer",
        "Teacher", "Professor", "Lawyer", "Chartered Accountant", "Consultant",
        "Banker", "Finance Professional", "Designer", "Architect", "Marketing",
        "Sales", "Pharmacist", "Nurse", "Dentist", "Real Estate", "Trader",
        "Government Service", "Homemaker", "Student", "Retired", "Other",
    ]
}
