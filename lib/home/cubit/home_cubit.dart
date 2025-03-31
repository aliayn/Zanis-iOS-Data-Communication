import 'package:bloc/bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:injectable/injectable.dart';
import 'package:zanis_ios_data_communication/data/ios_data_source.dart';

part 'home_state.dart';
part 'home_cubit.freezed.dart';

@injectable
class HomeCubit extends Cubit<HomeState> {
  final IOSDataSource _iosDataSource;
  HomeCubit(this._iosDataSource) : super(HomeState.initial()) {
    init();
  }

  void init() {
    emit(HomeState.initial());

    // Listen to data events
    _iosDataSource.dataStream.listen(
      (data) {
        emit(HomeState.data(data));
      },
      onError: (error) {
        emit(HomeState.error(error.toString()));
      },
    );

    // Listen to connection status
    _iosDataSource.connectionStream.listen(
      (isConnected) {
        emit(HomeState.connectionStatus(isConnected));
      },
      onError: (error) {
        emit(HomeState.error(error.toString()));
      },
    );

    // Listen to device info
    _iosDataSource.deviceInfoStream.listen(
      (deviceInfo) {
        emit(HomeState.deviceInfo(deviceInfo));
      },
      onError: (error) {
        emit(HomeState.error(error.toString()));
      },
    );
  }
}
