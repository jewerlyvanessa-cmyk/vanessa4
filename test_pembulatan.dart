import 'dart:developer' as developer;

void main() {
  double testPembulatan(double total) {
    final lastFourDigits = (total % 10000).floor();
    double pembulatan;
    if (lastFourDigits < 5000) {
      pembulatan = (5000 - lastFourDigits).toDouble();
    } else if (lastFourDigits == 5000) {
      pembulatan = 0.0; // No rounding if exactly 5000
    } else {
      pembulatan = (10000 - lastFourDigits).toDouble();
    }
    return total + pembulatan;
  }

  developer.log(
    'Test 1: 1294300 -> ${testPembulatan(1294300)} (expected: 1295000)',
  );
  developer.log(
    'Test 2: 1296700 -> ${testPembulatan(1296700)} (expected: 1300000)',
  );

  // Additional test cases
  developer.log(
    'Test 3: 1250000 -> ${testPembulatan(1250000)} (expected: 1255000 - round up to 5000)',
  );
  developer.log(
    'Test 4: 1256000 -> ${testPembulatan(1256000)} (expected: 1260000)',
  );
  developer.log(
    'Test 5: 1295000 -> ${testPembulatan(1295000)} (expected: 1295000 - no rounding for exactly 5000)',
  );
}
