extends Node
## Static design data: the four word types, the enemy ladder with their
## weakness/resistance tables and signature skills, and the consumable items.

## Damage multipliers use these bands:
##   0.0        immune       (attack does nothing)
##   below 1.0  resisted
##   1.0        neutral
##   above 1.0  weakness
##   2.0+       critical hit
const IMMUNE := 0.0
const CRITICAL_AT := 2.0

const WORDS: Array = [
	{
		"id": "jargon",
		"name": "Corporate Jargon",
		"short": "JARGON",
		"cost": 12,
		"power": 26,
		"color": Color(0.45, 0.72, 0.95),
		"blurb": "Bury them in buzzwords.",
		"lines": [
			"Let's take this offline and circle back on your deliverables.",
			"We need to leverage synergies before the next sprint review.",
			"I'll action that once we've socialised the roadmap.",
		],
	},
	{
		"id": "direct",
		"name": "Direct Insult",
		"short": "DIRECT",
		"cost": 26,
		"power": 46,
		"color": Color(0.93, 0.42, 0.36),
		"blurb": "Say the quiet part out loud.",
		"lines": [
			"You are the reason this office needs a suggestion box.",
			"Your best work is the out-of-office reply.",
			"I've seen printers take more responsibility than you.",
		],
	},
	{
		"id": "passive",
		"name": "Passive-Aggressive",
		"short": "POLITE",
		"cost": 18,
		"power": 32,
		"color": Color(0.78, 0.66, 0.95),
		"blurb": "Perfectly polite. Absolutely lethal.",
		"lines": [
			"No rush at all - I only needed it last Tuesday.",
			"Thanks for finally looping me in on my own project.",
			"Just gently bumping this for the fourth time!",
		],
	},
	{
		"id": "logic",
		"name": "Logic & Facts",
		"short": "LOGIC",
		"cost": 20,
		"power": 38,
		"color": Color(0.55, 0.86, 0.6),
		"blurb": "Receipts, timestamps, paper trail.",
		"lines": [
			"Per the timestamp, you approved this yourself.",
			"The spec says otherwise, and I have it in writing.",
			"Here's the thread where you agreed to the deadline.",
		],
	},
]

## Enemy skills are resolved by id inside Battle.gd.
const ENEMIES: Array = [
	{
		"id": "rookie",
		"name": "The Rookie",
		"role": "Intern",
		"hp": 240,
		"coin_reward": 15,
		"sprite": "res://assets/characters/enemies/rookie.png",
		"scale": 0.86,
		"damage": [12, 20],
		"skill": "none",
		"skill_name": "",
		"mult": {"jargon": IMMUNE, "direct": 1.6, "passive": 1.0, "logic": 1.5},
		"intro": "A fresh graduate who nods at every buzzword and understands none.",
		"taunts": [
			"Sorry, is that an acronym?",
			"I'll ask my mentor about that!",
			"Wait, we had a deadline?",
		],
		"promotion": "Junior Staff",
	},
	{
		"id": "dodger",
		"name": "The Work-Dodger",
		"role": "Colleague",
		"hp": 320,
		"coin_reward": 20,
		"sprite": "res://assets/characters/enemies/dodger.png",
		"scale": 0.94,
		"damage": [14, 22],
		"skill": "pile_on",
		"skill_name": "Pile On",
		"mult": {"jargon": 1.0, "direct": 1.0, "passive": 0.6, "logic": 1.8},
		"intro": "Somehow always busy, never finished. Your inbox knows why.",
		"taunts": [
			"Could you take this one? I'm swamped.",
			"I thought YOU were handling that.",
			"Let's split it - you do it, I'll review.",
		],
		"promotion": "Senior Staff",
	},
	{
		"id": "senior",
		"name": "The Team Lead",
		"role": "Micromanager",
		"hp": 420,
		"coin_reward": 30,
		"sprite": "res://assets/characters/enemies/senior.png",
		"scale": 1.0,
		"damage": [18, 28],
		"skills": ["after_hours_ping", "urgent_no_brief"],
		"skill_name": "After-Hours Ping / Urgent, No Brief",
		## Chance per enemy turn to raise a shield instead of attacking or
		## using a skill; see Battle.gd's _roll_guard_stance()/_enemy_guarding.
		"guard_chance": 0.25,
		"mult": {"jargon": 1.8, "direct": 1.0, "passive": 1.1, "logic": 0.5},
		"intro": "Branded coffee cup in one hand, a KPI folder in the other, phone already buzzing.",
		"taunts": [
			"Just checking in on the check-in.",
			"Can we get eyes on this by EOD? Today's EOD.",
			"I left three comments on a doc you haven't opened yet.",
		],
		"defeat": "...I'll note this in your review. Actually - forget I said that.",
		"promotion": "Team Lead",
	},
	{
		"id": "hr",
		"name": "HR Compliance",
		"role": "Human Resources",
		"hp": 500,
		"coin_reward": 35,
		"sprite": "res://assets/characters/enemies/hr.png",
		"scale": 1.02,
		"damage": [20, 30],
		"skill": "silence",
		"skill_name": "Policy Citation",
		"mult": {"jargon": 1.0, "direct": 0.5, "passive": 1.0, "logic": 1.7},
		"intro": "Quotes the handbook like scripture. Section 4.2 is their favourite.",
		"taunts": [
			"That phrasing violates section 4.2.",
			"I'm documenting this conversation.",
			"Let's keep things professional, shall we?",
		],
		"promotion": "Manager",
	},
	{
		"id": "ceo",
		"name": "The CEO",
		"role": "Final Boss",
		"hp": 700,
		"coin_reward": 60,
		"sprite": "res://assets/characters/enemies/ceo.png",
		"scale": 1.12,
		"damage": [26, 38],
		"skill": "gaslight",
		"skill_name": "Gaslighting",
		"mult": {"jargon": 0.8, "direct": 0.2, "passive": 2.5, "logic": 0.9},
		"intro": "Shrugs off shouting. Cannot survive being handled politely.",
		"taunts": [
			"We're a family here. Families don't ask for raises.",
			"I never said that. You must be misremembering.",
			"Think of the equity!",
		],
		"promotion": "Director",
	},
]

## The eight food/drink ids double as the vending machine's stock in Shop.gd -
## each one is also a slot painted into assets/backgrounds/shop.png, so its id
## must stay in step with Shop.gd's FOOD_SLOTS keys. "headphones" isn't part of
## the machine art and gets its own row in the shop's Accessories panel.
const ITEMS: Dictionary = {
	"coffee": {
		"name": "Black Coffee",
		"blurb": "+45 Anger",
		"effect": "anger",
		"amount": 45,
		"price": 15,
		"icon": "res://assets/item/icon_coffee.png",
	},
	"energy_bar": {
		"name": "Energy Bar",
		"blurb": "+30 Anger",
		"effect": "anger",
		"amount": 30,
		"price": 12,
		"icon": "res://assets/item/icon_energy_bar.png",
	},
	"soda": {
		"name": "Cola",
		"blurb": "+50 Anger",
		"effect": "anger",
		"amount": 50,
		"price": 22,
		"icon": "res://assets/item/icon_soda.png",
	},
	"banana": {
		"name": "Banana",
		"blurb": "+20 Anger",
		"effect": "anger",
		"amount": 20,
		"price": 8,
		"icon": "res://assets/item/icon_banana.png",
	},
	"apple": {
		"name": "Apple",
		"blurb": "+35 Patience",
		"effect": "hp",
		"amount": 35,
		"price": 12,
		"icon": "res://assets/item/icon_apple.png",
	},
	"water": {
		"name": "Bottled Water",
		"blurb": "+30 Patience",
		"effect": "hp",
		"amount": 30,
		"price": 10,
		"icon": "res://assets/item/icon_water.png",
	},
	"noodles": {
		"name": "Instant Noodles",
		"blurb": "+80 Patience",
		"effect": "hp",
		"amount": 80,
		"price": 24,
		"icon": "res://assets/item/icon_noodles.png",
	},
	"sandwich": {
		"name": "Sandwich",
		"blurb": "+65 Patience",
		"effect": "hp",
		"amount": 65,
		"price": 20,
		"icon": "res://assets/item/icon_sandwich.png",
	},
	"headphones": {
		"name": "Noise-Cancelling Headphones",
		"blurb": "Halve the next hit",
		"effect": "guard",
		"amount": 1,
		"price": 35,
		"icon": "res://assets/item/headphone.png",
	},
}


func word_by_id(id: String) -> Dictionary:
	for w: Dictionary in WORDS:
		if w["id"] == id:
			return w
	return {}


func enemy_count() -> int:
	return ENEMIES.size()


func enemy_at(index: int) -> Dictionary:
	return ENEMIES[clampi(index, 0, ENEMIES.size() - 1)]


## Short label shown next to the damage number so the player learns the table.
func effectiveness_label(multiplier: float) -> String:
	if is_equal_approx(multiplier, IMMUNE):
		return "IMMUNE!"
	if multiplier >= CRITICAL_AT:
		return "CRITICAL!"
	if multiplier > 1.0:
		return "Effective!"
	if multiplier < 1.0:
		return "Resisted..."
	return ""


func effectiveness_color(multiplier: float) -> Color:
	if is_equal_approx(multiplier, IMMUNE):
		return Color(0.6, 0.6, 0.65)
	if multiplier >= CRITICAL_AT:
		return Color(1.0, 0.85, 0.3)
	if multiplier > 1.0:
		return Color(0.6, 1.0, 0.6)
	if multiplier < 1.0:
		return Color(0.75, 0.75, 0.8)
	return Color(1, 1, 1)
