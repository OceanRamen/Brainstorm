#ifndef SEED_HPP
#define SEED_HPP

#include <array>
#include <string>

// Seed helper class
// Caches hashing info recursively to save speed
// Because of that, also has an interesting order for seeds:
// <empty>, 1, 11, 111, ..., 11111111, 21111111, 31111111, ..., Z1111111,
// 2111111, 12111111, ..., ZZ111111, 211111, ..., ZZZZZZZZ
const std::string seedChars = "123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ";
const std::array<int, 128> charSeeds = {
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, 0,  1,  2,  3,  4,  5,  6,  7,
    8,  -1, -1, -1, -1, -1, -1, -1, 9,  10, 11, 12, 13, 14, 15, 16, 17, 18, 19,
    20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
};
const std::array<long long, 8> idCoeff = {
    66231629136, 1892332261, 54066636, 1544761, 44136, 1261, 36, 1};

struct Seed {
  // -1 is blank, 0 to 34 represent valid characters
  // To aid in hashing, stored right to left
  std::array<int, 8> seed;

  int length; 

  // The cache. Stored as [position in seed][length of string]
  std::array<std::array<double, 48>, 8> cache;

  Seed();
  Seed(std::string strSeed);
  Seed(long long id);

  std::string tostring();
  void debugprint();
  long long getID();

  void next();
  void next(int x);

  double pseudohash(int prefixLength);
};

#endif // SEED_HPP