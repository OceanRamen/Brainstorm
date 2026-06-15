#ifndef RNG_HPP
#define RNG_HPP

#include <string>

struct ItemSource {
  static const std::string Shop;
  static const std::string Emperor;
  static const std::string High_Priestess;
  static const std::string Judgement;
  static const std::string Wraith;
  static const std::string Arcana_Pack;
  static const std::string Omen_Globe;
  static const std::string Celestial_Pack;
  static const std::string Spectral_Pack;
  static const std::string Standard_Pack;
  static const std::string Buffoon_Pack;
  static const std::string Vagabond;
  static const std::string Superposition;
  static const std::string _8_Ball;
  static const std::string Seance;
  static const std::string Sixth_Sense;
  static const std::string Top_Up;
  static const std::string Rare_Tag;
  static const std::string Uncommon_Tag;
  static const std::string Purple_Seal;
  static const std::string Soul;
  static const std::string Riff_Raff;
  static const std::string Cartomancer;
};

struct RandomType {
  static const std::string Joker_Common;
  static const std::string Joker_Uncommon;
  static const std::string Joker_Rare;
  static const std::string Joker_Legendary;
  static const std::string Joker_Rarity;
  static const std::string Joker_Edition;
  static const std::string Misprint;
  static const std::string Standard_Has_Enhancement;
  static const std::string Enhancement;
  static const std::string Card;
  static const std::string Standard_Edition;
  static const std::string Standard_Has_Seal;
  static const std::string Standard_Seal;
  static const std::string Shop_Pack;
  static const std::string Tarot;
  static const std::string Spectral;
  static const std::string Tags;
  static const std::string Shuffle_New_Round;
  static const std::string Card_Type;
  static const std::string Planet;
  static const std::string Lucky_Mult;
  static const std::string Lucky_Money;
  static const std::string Sigil;
  static const std::string Ouija;
  static const std::string Wheel_of_Fortune;
  static const std::string Gros_Michel;
  static const std::string Cavendish;
  static const std::string Voucher;
  static const std::string Voucher_Tag;
  static const std::string Orbital_Tag;
  static const std::string Soul;
  static const std::string Erratic;
  static const std::string Eternal; // Eternal jokers pre 1.0.1
  static const std::string Perishable;
  static const std::string Rental;
  static const std::string Eternal_Perishable;
  static const std::string Rental_Pack;
  static const std::string Eternal_Perishable_Pack;
  static const std::string Boss;
  static const std::string Omen_Globe;
};

#endif // RNG_HPP