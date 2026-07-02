package com.mitimaiti.app.models

data class IceBreakerPrompt(
    val id: Int,
    val text: String,
    val category: IceBreakerCategory
)

enum class IceBreakerCategory(val displayName: String, val emoji: String) {
    FUN("Fun", "🎉"),
    DEEP("Deep", "💭"),
    FLIRTY("Flirty", "😏"),
    SINDHI("Sindhi", "🪔")
}

object IceBreakerPrompts {
    private val all = listOf(
        // Fun (17)
        IceBreakerPrompt(1, "What's your go-to Sindhi comfort food?", IceBreakerCategory.FUN),
        IceBreakerPrompt(2, "Bollywood or Hollywood — pick one forever?", IceBreakerCategory.FUN),
        IceBreakerPrompt(3, "What's the last thing that made you laugh out loud?", IceBreakerCategory.FUN),
        IceBreakerPrompt(4, "If you could travel anywhere tomorrow, where would you go?", IceBreakerCategory.FUN),
        IceBreakerPrompt(5, "What's your unpopular food opinion?", IceBreakerCategory.FUN),
        IceBreakerPrompt(6, "What's the most spontaneous thing you've ever done?", IceBreakerCategory.FUN),
        IceBreakerPrompt(7, "Dal pakwan or sai bhaji — and why?", IceBreakerCategory.FUN),
        IceBreakerPrompt(8, "What's your karaoke go-to song?", IceBreakerCategory.FUN),
        IceBreakerPrompt(9, "If you could have dinner with anyone, dead or alive?", IceBreakerCategory.FUN),
        IceBreakerPrompt(10, "What's your hidden talent nobody knows about?", IceBreakerCategory.FUN),
        IceBreakerPrompt(11, "Morning person or night owl?", IceBreakerCategory.FUN),
        IceBreakerPrompt(12, "What show are you binge-watching right now?", IceBreakerCategory.FUN),
        IceBreakerPrompt(13, "Tea, coffee, or chai specifically?", IceBreakerCategory.FUN),
        IceBreakerPrompt(14, "What's the weirdest food combo you secretly love?", IceBreakerCategory.FUN),
        IceBreakerPrompt(15, "If your life was a movie, what genre would it be?", IceBreakerCategory.FUN),
        IceBreakerPrompt(16, "What's your favorite festival memory growing up?", IceBreakerCategory.FUN),
        IceBreakerPrompt(17, "Dogs or cats — and this might be a dealbreaker?", IceBreakerCategory.FUN),

        // Deep (17)
        IceBreakerPrompt(18, "What does being Sindhi mean to you?", IceBreakerCategory.DEEP),
        IceBreakerPrompt(19, "What's a life goal you're working toward right now?", IceBreakerCategory.DEEP),
        IceBreakerPrompt(20, "What's the best advice you've ever received?", IceBreakerCategory.DEEP),
        IceBreakerPrompt(21, "What's something you wish more people understood about you?", IceBreakerCategory.DEEP),
        IceBreakerPrompt(22, "How do you stay connected to your Sindhi roots?", IceBreakerCategory.DEEP),
        IceBreakerPrompt(23, "What's a value you'd never compromise on?", IceBreakerCategory.DEEP),
        IceBreakerPrompt(24, "What does your ideal weekend look like?", IceBreakerCategory.DEEP),
        IceBreakerPrompt(25, "What's the most important lesson your family taught you?", IceBreakerCategory.DEEP),
        IceBreakerPrompt(26, "Where do you see yourself in 5 years?", IceBreakerCategory.DEEP),
        IceBreakerPrompt(27, "What's a tradition you want to pass on to your kids?", IceBreakerCategory.DEEP),
        IceBreakerPrompt(28, "What's the bravest thing you've ever done?", IceBreakerCategory.DEEP),
        IceBreakerPrompt(29, "How do you handle conflict in relationships?", IceBreakerCategory.DEEP),
        IceBreakerPrompt(30, "What's something you're really proud of?", IceBreakerCategory.DEEP),
        IceBreakerPrompt(31, "What role does spirituality play in your life?", IceBreakerCategory.DEEP),
        IceBreakerPrompt(32, "What's a cause you care deeply about?", IceBreakerCategory.DEEP),
        IceBreakerPrompt(33, "What's the hardest thing you've overcome?", IceBreakerCategory.DEEP),
        IceBreakerPrompt(34, "What makes a house feel like home to you?", IceBreakerCategory.DEEP),

        // Flirty (16)
        IceBreakerPrompt(35, "What made you swipe right on me?", IceBreakerCategory.FLIRTY),
        IceBreakerPrompt(36, "What's your idea of a perfect first date?", IceBreakerCategory.FLIRTY),
        IceBreakerPrompt(37, "What's the most romantic thing someone's done for you?", IceBreakerCategory.FLIRTY),
        IceBreakerPrompt(38, "Do you believe in love at first sight, or should I walk by again?", IceBreakerCategory.FLIRTY),
        IceBreakerPrompt(39, "What's your love language?", IceBreakerCategory.FLIRTY),
        IceBreakerPrompt(40, "If we matched, where would you take me on our first date?", IceBreakerCategory.FLIRTY),
        IceBreakerPrompt(41, "What's the quality you find most attractive in someone?", IceBreakerCategory.FLIRTY),
        IceBreakerPrompt(42, "Beach sunset or city rooftop for a date night?", IceBreakerCategory.FLIRTY),
        IceBreakerPrompt(43, "What song would you play to set the mood?", IceBreakerCategory.FLIRTY),
        IceBreakerPrompt(44, "Truth or dare — which do you usually pick?", IceBreakerCategory.FLIRTY),
        IceBreakerPrompt(45, "What's your signature move to impress someone?", IceBreakerCategory.FLIRTY),
        IceBreakerPrompt(46, "Candlelight dinner or spontaneous adventure?", IceBreakerCategory.FLIRTY),
        IceBreakerPrompt(47, "What's the cheesiest pickup line that actually worked on you?", IceBreakerCategory.FLIRTY),
        IceBreakerPrompt(48, "If you had to describe yourself in 3 emojis, which ones?", IceBreakerCategory.FLIRTY),
        IceBreakerPrompt(49, "What's your definition of chemistry?", IceBreakerCategory.FLIRTY),
        IceBreakerPrompt(50, "Would you rather have a long phone call or a late-night walk?", IceBreakerCategory.FLIRTY)
    )

    /** Returns 2-3 random prompts from mixed categories */
    fun getRandomPrompts(count: Int = 3): List<IceBreakerPrompt> {
        return all.shuffled().take(count)
    }

    /** Returns all prompts */
    fun getAll(): List<IceBreakerPrompt> = all
}
