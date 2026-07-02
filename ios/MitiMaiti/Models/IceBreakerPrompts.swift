import Foundation

// MARK: - Ice Breaker Category

enum IceBreakerCategory: String, CaseIterable {
    case fun = "fun"
    case deep = "deep"
    case flirty = "flirty"
    case sindhi = "sindhi"

    var displayName: String {
        switch self {
        case .fun:    return "Fun"
        case .deep:   return "Deep"
        case .flirty: return "Flirty"
        case .sindhi: return "Sindhi"
        }
    }

    var emoji: String {
        switch self {
        case .fun:    return "🎉"
        case .deep:   return "💭"
        case .flirty: return "😏"
        case .sindhi: return "🪔"
        }
    }
}

// MARK: - Ice Breaker Prompt

struct IceBreakerPrompt: Identifiable {
    let id: Int
    let text: String
    let category: IceBreakerCategory
}

// MARK: - Ice Breaker Prompts

enum IceBreakerPrompts {
    static let all: [IceBreakerPrompt] = [
        // Fun (17)
        IceBreakerPrompt(id: 1,  text: "What's your go-to Sindhi comfort food?",               category: .fun),
        IceBreakerPrompt(id: 2,  text: "Bollywood or Hollywood — pick one forever?",            category: .fun),
        IceBreakerPrompt(id: 3,  text: "What's the last thing that made you laugh out loud?",   category: .fun),
        IceBreakerPrompt(id: 4,  text: "If you could travel anywhere tomorrow, where would you go?", category: .fun),
        IceBreakerPrompt(id: 5,  text: "What's your unpopular food opinion?",                   category: .fun),
        IceBreakerPrompt(id: 6,  text: "What's the most spontaneous thing you've ever done?",   category: .fun),
        IceBreakerPrompt(id: 7,  text: "Dal pakwan or sai bhaji — and why?",                    category: .fun),
        IceBreakerPrompt(id: 8,  text: "What's your karaoke go-to song?",                       category: .fun),
        IceBreakerPrompt(id: 9,  text: "If you could have dinner with anyone, dead or alive?",  category: .fun),
        IceBreakerPrompt(id: 10, text: "What's your hidden talent nobody knows about?",         category: .fun),
        IceBreakerPrompt(id: 11, text: "Morning person or night owl?",                          category: .fun),
        IceBreakerPrompt(id: 12, text: "What show are you binge-watching right now?",           category: .fun),
        IceBreakerPrompt(id: 13, text: "Tea, coffee, or chai specifically?",                    category: .fun),
        IceBreakerPrompt(id: 14, text: "What's the weirdest food combo you secretly love?",     category: .fun),
        IceBreakerPrompt(id: 15, text: "If your life was a movie, what genre would it be?",     category: .fun),
        IceBreakerPrompt(id: 16, text: "What's your favorite festival memory growing up?",      category: .fun),
        IceBreakerPrompt(id: 17, text: "Dogs or cats — and this might be a dealbreaker?",       category: .fun),

        // Deep (17)
        IceBreakerPrompt(id: 18, text: "What does being Sindhi mean to you?",                           category: .deep),
        IceBreakerPrompt(id: 19, text: "What's a life goal you're working toward right now?",            category: .deep),
        IceBreakerPrompt(id: 20, text: "What's the best advice you've ever received?",                   category: .deep),
        IceBreakerPrompt(id: 21, text: "What's something you wish more people understood about you?",    category: .deep),
        IceBreakerPrompt(id: 22, text: "How do you stay connected to your Sindhi roots?",                category: .deep),
        IceBreakerPrompt(id: 23, text: "What's a value you'd never compromise on?",                      category: .deep),
        IceBreakerPrompt(id: 24, text: "What does your ideal weekend look like?",                        category: .deep),
        IceBreakerPrompt(id: 25, text: "What's the most important lesson your family taught you?",       category: .deep),
        IceBreakerPrompt(id: 26, text: "Where do you see yourself in 5 years?",                          category: .deep),
        IceBreakerPrompt(id: 27, text: "What's a tradition you want to pass on to your kids?",           category: .deep),
        IceBreakerPrompt(id: 28, text: "What's the bravest thing you've ever done?",                     category: .deep),
        IceBreakerPrompt(id: 29, text: "How do you handle conflict in relationships?",                   category: .deep),
        IceBreakerPrompt(id: 30, text: "What's something you're really proud of?",                       category: .deep),
        IceBreakerPrompt(id: 31, text: "What role does spirituality play in your life?",                  category: .deep),
        IceBreakerPrompt(id: 32, text: "What's a cause you care deeply about?",                          category: .deep),
        IceBreakerPrompt(id: 33, text: "What's the hardest thing you've overcome?",                      category: .deep),
        IceBreakerPrompt(id: 34, text: "What makes a house feel like home to you?",                      category: .deep),

        // Flirty (16)
        IceBreakerPrompt(id: 35, text: "What made you swipe right on me?",                                           category: .flirty),
        IceBreakerPrompt(id: 36, text: "What's your idea of a perfect first date?",                                  category: .flirty),
        IceBreakerPrompt(id: 37, text: "What's the most romantic thing someone's done for you?",                     category: .flirty),
        IceBreakerPrompt(id: 38, text: "Do you believe in love at first sight, or should I walk by again?",          category: .flirty),
        IceBreakerPrompt(id: 39, text: "What's your love language?",                                                 category: .flirty),
        IceBreakerPrompt(id: 40, text: "If we matched, where would you take me on our first date?",                  category: .flirty),
        IceBreakerPrompt(id: 41, text: "What's the quality you find most attractive in someone?",                    category: .flirty),
        IceBreakerPrompt(id: 42, text: "Beach sunset or city rooftop for a date night?",                             category: .flirty),
        IceBreakerPrompt(id: 43, text: "What song would you play to set the mood?",                                  category: .flirty),
        IceBreakerPrompt(id: 44, text: "Truth or dare — which do you usually pick?",                                 category: .flirty),
        IceBreakerPrompt(id: 45, text: "What's your signature move to impress someone?",                             category: .flirty),
        IceBreakerPrompt(id: 46, text: "Candlelight dinner or spontaneous adventure?",                               category: .flirty),
        IceBreakerPrompt(id: 47, text: "What's the cheesiest pickup line that actually worked on you?",              category: .flirty),
        IceBreakerPrompt(id: 48, text: "If you had to describe yourself in 3 emojis, which ones?",                   category: .flirty),
        IceBreakerPrompt(id: 49, text: "What's your definition of chemistry?",                                       category: .flirty),
        IceBreakerPrompt(id: 50, text: "Would you rather have a long phone call or a late-night walk?",              category: .flirty),
    ]

    /// Returns `count` random prompts drawn from mixed categories.
    static func random(count: Int = 3) -> [IceBreakerPrompt] {
        Array(all.shuffled().prefix(count))
    }

    /// Returns all prompts.
    static func getAll() -> [IceBreakerPrompt] { all }
}
