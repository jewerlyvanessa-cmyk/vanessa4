import 'package:flutter_test/flutter_test.dart';
import 'package:vanessa3/routes/app_routes.dart';
import 'package:vanessa3/routes/role_home_route.dart';

void main() {
  group('homeRouteForRole', () {
    test('maps known roles to module home routes', () {
      expect(homeRouteForRole('cs'), AppRoutes.cs);
      expect(homeRouteForRole('KASIR'), AppRoutes.kasir);
      expect(homeRouteForRole('superadmin'), AppRoutes.superadmin);
      expect(homeRouteForRole('admin_toko'), AppRoutes.adminToko);
      expect(homeRouteForRole('admin_workshop'), AppRoutes.adminWorkshop);
      expect(homeRouteForRole('admin_warehouse'), AppRoutes.adminWarehouse);
      expect(homeRouteForRole('tukang'), AppRoutes.tukang);
      expect(homeRouteForRole('manajer'), AppRoutes.manajer);
      expect(homeRouteForRole('owner'), AppRoutes.owner);
      expect(homeRouteForRole('stockist'), AppRoutes.stockist);
    });

    test('unknown role falls back to dashboard', () {
      expect(homeRouteForRole(''), AppRoutes.dashboard);
      expect(homeRouteForRole('guest'), AppRoutes.dashboard);
    });
  });
}
