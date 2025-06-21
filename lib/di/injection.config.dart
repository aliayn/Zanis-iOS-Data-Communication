// dart format width=80
// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// InjectableConfigGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:get_it/get_it.dart' as _i174;
import 'package:injectable/injectable.dart' as _i526;
import 'package:zanis_ios_data_communication/data/android_data_source.dart'
    as _i212;
import 'package:zanis_ios_data_communication/data/device_data_source.dart'
    as _i920;
import 'package:zanis_ios_data_communication/data/ios_data_source.dart'
    as _i500;
import 'package:zanis_ios_data_communication/data/platform_detector.dart'
    as _i217;
import 'package:zanis_ios_data_communication/data/vendor_android_data_source.dart'
    as _i151;
import 'package:zanis_ios_data_communication/home/cubit/home_cubit.dart'
    as _i1070;

extension GetItInjectableX on _i174.GetIt {
// initializes the registration of main-scope dependencies inside of GetIt
  _i174.GetIt init({
    String? environment,
    _i526.EnvironmentFilter? environmentFilter,
  }) {
    final gh = _i526.GetItHelper(
      this,
      environment,
      environmentFilter,
    );
    gh.singleton<_i212.AndroidDataSource>(() => _i212.AndroidDataSource());
    gh.singleton<_i217.PlatformDetector>(() => _i217.PlatformDetector());
    gh.singleton<_i500.IOSDataSource>(() => _i500.IOSDataSource());
    gh.singleton<_i151.VendorAndroidDataSource>(
        () => _i151.VendorAndroidDataSource());
    gh.singleton<_i920.DeviceDataSource>(() => _i920.DeviceDataSource(
          gh<_i217.PlatformDetector>(),
          gh<_i500.IOSDataSource>(),
          gh<_i212.AndroidDataSource>(),
          gh<_i151.VendorAndroidDataSource>(),
        ));
    gh.factory<_i1070.HomeCubit>(
        () => _i1070.HomeCubit(gh<_i500.IOSDataSource>()));
    return this;
  }
}
