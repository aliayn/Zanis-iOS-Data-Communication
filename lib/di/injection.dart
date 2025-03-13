

import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';

import 'injection.config.dart';

final GetIt _getIt = GetIt.instance;
T inject<T extends Object>() => _getIt.call<T>();

@injectableInit
void configureDependencies() => _getIt.init();