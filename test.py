import random
import os

class CardCounterTrainer:
    def __init__(self, num_decks=6):
        self.num_decks = num_decks
        self.running_count = 0
        self.true_count = 0
        self.cards_dealt = 0
        self.score = 0
        self.deck = self.create_shoe()

    def create_shoe(self):
        """Create a multi-deck shoe of cards"""
        cards = ['2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A']
        shoe = cards * 4 * self.num_decks  # 4 of each card per deck
        random.shuffle(shoe)
        return shoe

    def get_card_value(self, card):
        """Return Hi-Lo value for a card"""
        if card in ['2', '3', '4', '5', '6']:
            return 1
        elif card in ['10', 'J', 'Q', 'K', 'A']:
            return -1
        return 0

    def update_counts(self, card):
        """Update running and true counts"""
        self.running_count += self.get_card_value(card)
        self.cards_dealt += 1
        
        decks_remaining = (len(self.deck) - self.cards_dealt) / 52
        self.true_count = self.running_count / max(decks_remaining, 0.5)

    def practice_round(self):
        """Run a single practice round"""
        os.system('cls' if os.name == 'nt' else 'clear')
        print(f"Current Score: {self.score}")
        print("="*40)
        
        if not self.deck:
            print("Shoe is empty! Reshuffling...")
            self.deck = self.create_shoe()
            self.running_count = 0
            self.cards_dealt = 0
            
        card = self.deck.pop()
        self.update_counts(card)
        
        print(f"Card dealt: {card}")
        user_count = input("Enter running count: ")
        
        try:
            if int(user_count) == self.running_count:
                print("\n✅ Correct!")
                self.score += 1
            else:
                print(f"\n❌ Incorrect. Correct count: {self.running_count}")
            print(f"True count: {self.true_count:.2f}")
        except ValueError:
            print("\n⚠️ Please enter a valid number")
            
        input("\nPress Enter to continue...")

    def start_training(self):
        """Main training loop"""
        while True:
            self.practice_round()

if __name__ == "__main__":
    print("=== Blackjack Card Counting Trainer ===")
    print("Rules:")
    print("- +1 for 2-6")
    print("- 0 for 7-9")
    print("- -1 for 10/J/Q/K/A")
    print("- Keep track of the running count")
    print("- Type 'quit' to exit\n")
    
    trainer = CardCounterTrainer(num_decks=6)
    try:
        trainer.start_training()
    except KeyboardInterrupt:
        print("\nGoodbye! Final score:", trainer.score)