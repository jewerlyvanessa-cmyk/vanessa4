import 'dart:collection';

class CacheManager {
  final _cache = HashMap<String, dynamic>();

  void set(String key, dynamic value) {
    _cache[key] = value;
  }

  dynamic get(String key) {
    return _cache[key];
  }

  bool contains(String key) {
    return _cache.containsKey(key);
  }

  void clear() {
    _cache.clear();
  }
}
