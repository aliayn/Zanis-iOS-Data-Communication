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
import 'package:zanis_ios_data_communication/data/ios_data_source.dart'
    as _i500;
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
    gh.singleton<_i500.IOSDataSource>(() => _i500.IOSDataSource());
    gh.factory<_i1070.HomeCubit>(
        () => _i1070.HomeCubit(gh<_i500.IOSDataSource>()));
    return this;
  }
}
