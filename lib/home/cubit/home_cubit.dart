import 'package:bloc/bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:injectable/injectable.dart';
import 'package:zanis_ios_data_communication/data/ios_data_source.dart';

part 'home_state.dart';
part 'home_cubit.freezed.dart';

@injectable
class HomeCubit extends Cubit<HomeState> {
  final IosDataSource _iosDataSource;
  HomeCubit(this._iosDataSource) : super(HomeState.initial()) {
    init();
  }

  void init() {
    final dataStream = _iosDataSource.stream;
    dataStream.listen((data) {
      final value = IOSDataAdapter.adaptData(data);
      emit(HomeState.data(value));
    }).onError((error) {
      emit(HomeState.error(error.toString()));
    });
  }
}
